function Get-EntrezDocumentSummary {
    <#
    .SYNOPSIS
        Retrieves document summaries from NCBI Entrez databases using ESummary utility

    .DESCRIPTION
        The Get-EntrezDocumentSummary function retrieves document summaries for specified UIDs from NCBI Entrez databases.
        It supports comprehensive field selection, multiple output formats, and batch processing for research workflows.

    .PARAMETER Database
        Target NCBI database (e.g., 'pubmed', 'pmc', 'protein', 'nucleotide')

    .PARAMETER Id
        Array of unique identifiers to retrieve summaries for

    .PARAMETER RetMode
        Output format: 'xml', 'json', 'text'

    .PARAMETER RetType
        Summary type: 'full', 'brief', 'core'

    .PARAMETER Version
        API version to use (default: '2.0')

    .PARAMETER WebEnv
        Web environment string from previous search

    .PARAMETER QueryKey
        Query key from previous search

    .PARAMETER RetStart
        Starting position in result set (0-based)

    .PARAMETER RetMax
        Maximum number of records to retrieve

    .PARAMETER Tool
        Tool name for API usage tracking

    .PARAMETER Email
        Email address for API usage tracking

    .EXAMPLE
        Get-EntrezDocumentSummary -Database 'pubmed' -Id @('12345678', '23456789') -RetMode 'json'

        Retrieves JSON summaries for specific PubMed articles

    .EXAMPLE
        Get-EntrezDocumentSummary -Database 'pubmed' -WebEnv $webenv -QueryKey 1 -RetMax 100 -RetType 'full'

        Retrieves full summaries using session data

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
        NCBI API: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIds')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({
            if ($_ -in $Script:ModuleConfig.SupportedDatabases) {
                $true
            } else {
                throw "Database '$_' is not supported. Supported databases: $($Script:ModuleConfig.SupportedDatabases -join ', ')"
            }
        })]
        [string]$Database,

        [Parameter(Mandatory, ParameterSetName = 'ByIds', ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'BySession')]
        [ValidateNotNullOrEmpty()]
        [string]$WebEnv,

        [Parameter(ParameterSetName = 'BySession')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$QueryKey,

        [Parameter()]
        [ValidateSet('xml', 'json', 'text')]
        [string]$RetMode = 'xml',

        [Parameter()]
        [ValidateSet('full', 'brief', 'core')]
        [string]$RetType = 'full',

        [Parameter()]
        [ValidateSet('1.0', '2.0')]
        [string]$Version = '2.0',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetStart = 0,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$RetMax = 500,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Tool = $Script:ModuleConfig.ModuleName,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
        [string]$Email
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting ESummary request for database: $Database"

        # Validate parameter combinations
        if ($PSCmdlet.ParameterSetName -eq 'BySession' -and (-not $WebEnv -or -not $QueryKey)) {
            throw "WebEnv and QueryKey are required when using session-based retrieval"
        }

        $results = @()
    }

    process {
        try {
            # Build parameters for ESummary request
            $params = @{
                db = $Database
                version = $Version
                retmode = $RetMode
                rettype = $RetType
                tool = $Tool
            }

            # Add email if provided or available in environment
            if ($Email) {
                $params['email'] = $Email
            } elseif ($env:NCBI_EMAIL) {
                $params['email'] = $env:NCBI_EMAIL
            }

            # Handle different parameter sets
            if ($PSCmdlet.ParameterSetName -eq 'ByIds') {
                # Process IDs in batches to respect API limits
                $idBatches = @()
                for ($i = 0; $i -lt $Id.Count; $i += $RetMax) {
                    $idBatches += ,@($Id[$i..([Math]::Min($i + $RetMax - 1, $Id.Count - 1))])
                }

                foreach ($batch in $idBatches) {
                    $params['id'] = $batch -join ','
                    $batchResult = Invoke-EntrezRequest -Utility 'esummary.fcgi' -Parameters $params
                    $results += $batchResult

                    Write-PSFMessage -Level Verbose -Message "Retrieved summaries for $($batch.Count) IDs"

                    # Rate limiting
                    if ($idBatches.Count -gt 1) {
                        Start-Sleep -Milliseconds 334  # ~3 requests per second
                    }
                }
            }
            else {
                # Session-based retrieval
                $params['WebEnv'] = $WebEnv
                $params['query_key'] = $QueryKey
                $params['retstart'] = $RetStart
                $params['retmax'] = $RetMax

                $result = Invoke-EntrezRequest -Utility 'esummary.fcgi' -Parameters $params
                $results += $result

                Write-PSFMessage -Level Verbose -Message "Retrieved summaries using session data (WebEnv: $WebEnv, QueryKey: $QueryKey)"
            }

            # Process and format results based on RetMode
            foreach ($result in $results) {
                if ($RetMode -eq 'json' -and $result) {
                    # Parse JSON and extract summaries
                    if ($result.result) {
                        foreach ($uid in $result.result.uids) {
                            Write-Output ([PSCustomObject]@{
                                Database = $Database
                                UID = $uid
                                Summary = $result.result.$uid
                                Retrieved = Get-Date
                            })
                        }
                    }
                }
                elseif ($RetMode -eq 'xml' -and $result) {
                    # Parse XML and extract summaries
                    if ($result.eSummaryResult) {
                        # Version 2.0 structure
                        if ($result.eSummaryResult.DocumentSummarySet) {
                            foreach ($docSum in $result.eSummaryResult.DocumentSummarySet.DocumentSummary) {
                                $summaryData = @{
                                    Title = $docSum.Title
                                    Abstract = $docSum | Select-Object -ExpandProperty Abstract -ErrorAction SilentlyContinue
                                    Authors = $docSum.Authors
                                    Journal = $docSum.Source
                                    PubDate = $docSum.PubDate
                                    DOI = $docSum | Select-Object -ExpandProperty DOI -ErrorAction SilentlyContinue
                                    PMID = $docSum.UID
                                }

                                # Add all other properties
                                foreach ($prop in $docSum.PSObject.Properties) {
                                    if ($prop.Name -notin @('uid', 'Title')) {
                                        $summaryData[$prop.Name] = $prop.Value
                                    }
                                }

                                Write-Output ([PSCustomObject]@{
                                    Database = $Database
                                    UID = $docSum.UID
                                    Summary = $summaryData
                                    Retrieved = Get-Date
                                })
                            }
                        }
                        # Version 1.0 structure (fallback)
                        elseif ($result.eSummaryResult.DocSum) {
                            foreach ($docSum in $result.eSummaryResult.DocSum) {
                                $summaryData = @{}
                                foreach ($item in $docSum.Item) {
                                    $summaryData[$item.Name] = $item.InnerText
                                }

                                Write-Output ([PSCustomObject]@{
                                    Database = $Database
                                    UID = $docSum.Id
                                    Summary = $summaryData
                                    Retrieved = Get-Date
                                })
                            }
                        }
                    }
                }
                else {
                    # Raw text or other formats
                    Write-Output ([PSCustomObject]@{
                        Database = $Database
                        RawResult = $result
                        Retrieved = Get-Date
                    })
                }
            }
        }
        catch {
            $ErrorMessage = "Failed to retrieve document summaries: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}