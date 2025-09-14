function Get-EntrezDataRecord {
    <#
    .SYNOPSIS
        Retrieves complete data records from NCBI Entrez databases using EFetch utility

    .DESCRIPTION
        The Get-EntrezDataRecord function retrieves full data records for specified UIDs from NCBI Entrez databases.
        It supports all major databases, multiple output formats, and can return complete articles, sequences, or other data types.

    .PARAMETER Database
        Target NCBI database (e.g., 'pubmed', 'pmc', 'protein', 'nucleotide')

    .PARAMETER Id
        Array of unique identifiers to retrieve records for

    .PARAMETER RetMode
        Output format: 'xml', 'json', 'text', 'html', 'asn.1'

    .PARAMETER RetType
        Record type varies by database:
        - PubMed: 'abstract', 'citation', 'full', 'medline', 'uilist'
        - PMC: 'full', 'medline'
        - Protein/Nucleotide: 'fasta', 'gb', 'gp', 'seqid', 'acc'

    .PARAMETER Strand
        DNA strand to retrieve (1 for plus, 2 for minus) - applies to nucleotide sequences

    .PARAMETER SeqStart
        Starting sequence position (applies to sequence databases)

    .PARAMETER SeqStop
        Ending sequence position (applies to sequence databases)

    .PARAMETER Complexity
        Sequence complexity level (applies to sequence databases)

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

    .PARAMETER FullArticle
        Switch to retrieve complete article content when available

    .EXAMPLE
        Get-EntrezDataRecord -Database 'pubmed' -Id @('12345678') -RetMode 'xml' -RetType 'full'

        Retrieves full XML record for a PubMed article

    .EXAMPLE
        Get-EntrezDataRecord -Database 'protein' -Id @('NP_123456') -RetMode 'text' -RetType 'fasta'

        Retrieves protein sequence in FASTA format

    .EXAMPLE
        Get-EntrezDataRecord -Database 'pubmed' -Id @('12345678') -FullArticle

        Retrieves complete article with all available content

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
        NCBI API: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi
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
        [ValidateSet('xml', 'json', 'text', 'html', 'asn.1')]
        [string]$RetMode = 'xml',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RetType,

        [Parameter()]
        [ValidateSet(1, 2)]
        [int]$Strand,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SeqStart,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SeqStop,

        [Parameter()]
        [ValidateRange(0, 4)]
        [int]$Complexity,

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
        [string]$Email,

        [Parameter()]
        [switch]$FullArticle
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting EFetch request for database: $Database"

        # Set default RetType based on database if not specified
        if (-not $RetType) {
            switch ($Database.ToLower()) {
                'pubmed' { $RetType = if ($FullArticle) { 'full' } else { 'abstract' } }
                'pmc' { $RetType = if ($FullArticle) { 'full' } else { 'medline' } }
                'protein' { $RetType = 'fasta' }
                'nucleotide' { $RetType = 'fasta' }
                'nuccore' { $RetType = 'fasta' }
                default { $RetType = 'full' }
            }
        }

        # Override RetType for full article requests
        if ($FullArticle) {
            switch ($Database.ToLower()) {
                'pubmed' { $RetType = 'full' }
                'pmc' { $RetType = 'full' }
                default { $RetType = 'full' }
            }
        }

        Write-PSFMessage -Level Verbose -Message "Using RetType: $RetType for database: $Database"

        $results = @()
    }

    process {
        try {
            # Build parameters for EFetch request
            $params = @{
                db = $Database
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

            # Add sequence-specific parameters if provided
            if ($Strand) { $params['strand'] = $Strand }
            if ($SeqStart) { $params['seq_start'] = $SeqStart }
            if ($SeqStop) { $params['seq_stop'] = $SeqStop }
            if ($PSBoundParameters.ContainsKey('Complexity')) { $params['complexity'] = $Complexity }

            # Handle different parameter sets
            if ($PSCmdlet.ParameterSetName -eq 'ByIds') {
                # Process IDs in batches to respect API limits
                $idBatches = @()
                for ($i = 0; $i -lt $Id.Count; $i += $RetMax) {
                    $idBatches += ,@($Id[$i..([Math]::Min($i + $RetMax - 1, $Id.Count - 1))])
                }

                foreach ($batch in $idBatches) {
                    $params['id'] = $batch -join ','
                    $batchResult = Invoke-EntrezRequest -Utility 'efetch.fcgi' -Parameters $params -Raw

                    # Process results based on format and database
                    $processedResults = ConvertTo-StructuredData -RawData $batchResult -Database $Database -RetMode $RetMode -RetType $RetType -IdList $batch

                    $results += $processedResults

                    Write-PSFMessage -Level Verbose -Message "Retrieved records for $($batch.Count) IDs"

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

                $result = Invoke-EntrezRequest -Utility 'efetch.fcgi' -Parameters $params -Raw
                $processedResults = ConvertTo-StructuredData -RawData $result -Database $Database -RetMode $RetMode -RetType $RetType

                $results += $processedResults

                Write-PSFMessage -Level Verbose -Message "Retrieved records using session data (WebEnv: $WebEnv, QueryKey: $QueryKey)"
            }

            return $results
        }
        catch {
            $ErrorMessage = "Failed to retrieve data records: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}

function ConvertTo-StructuredData {
    <#
    .SYNOPSIS
        Private helper function to convert raw EFetch results into structured PowerShell objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $RawData,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$RetMode,

        [Parameter(Mandatory)]
        [string]$RetType,

        [Parameter()]
        [string[]]$IdList
    )

    $results = @()

    try {
        if ($RetMode -eq 'xml' -and $RawData) {
            # Handle XML data based on database
            switch ($Database.ToLower()) {
                'pubmed' {
                    if ($RawData.PubmedArticleSet) {
                        foreach ($article in $RawData.PubmedArticleSet.PubmedArticle) {
                            $results += [PSCustomObject]@{
                                Database = $Database
                                PMID = $article.MedlineCitation.PMID.InnerText
                                Title = $article.MedlineCitation.Article.ArticleTitle
                                Authors = ($article.MedlineCitation.Article.AuthorList.Author | ForEach-Object {
                                    if ($_.LastName -and $_.ForeName) {
                                        "$($_.LastName) $($_.ForeName)"
                                    } elseif ($_.CollectiveName) {
                                        $_.CollectiveName
                                    }
                                }) -join ', '
                                Journal = $article.MedlineCitation.Article.Journal.Title
                                PublicationDate = $article.MedlineCitation.Article.Journal.JournalIssue.PubDate.Year
                                Abstract = $article.MedlineCitation.Article.Abstract.AbstractText -join ' '
                                Keywords = ($article.MedlineCitation.KeywordList.Keyword -join ', ')
                                DOI = ($article.PubmedData.ArticleIdList.ArticleId | Where-Object { $_.IdType -eq 'doi' }).InnerText
                                RawData = $article
                                Retrieved = Get-Date
                            }
                        }
                    }
                }
                'pmc' {
                    # Handle PMC XML structure
                    $results += [PSCustomObject]@{
                        Database = $Database
                        RawData = $RawData
                        Retrieved = Get-Date
                    }
                }
                default {
                    # Generic XML handling
                    $results += [PSCustomObject]@{
                        Database = $Database
                        RawData = $RawData
                        Retrieved = Get-Date
                    }
                }
            }
        }
        elseif ($RetMode -eq 'text' -or $RetMode -eq 'html') {
            # Handle text/HTML format (common for sequences)
            if ($RetType -eq 'fasta' -and $RawData) {
                # Parse FASTA format
                $sequences = $RawData -split '(?=^>)' | Where-Object { $_ -match '^>' }
                foreach ($seq in $sequences) {
                    $lines = $seq -split "`n"
                    $header = $lines[0] -replace '^>', ''
                    $sequence = ($lines[1..($lines.Length-1)] -join '')

                    $results += [PSCustomObject]@{
                        Database = $Database
                        Header = $header
                        Sequence = $sequence
                        Length = $sequence.Length
                        RawData = $seq
                        Retrieved = Get-Date
                    }
                }
            }
            else {
                # Raw text data
                $results += [PSCustomObject]@{
                    Database = $Database
                    Content = $RawData
                    Retrieved = Get-Date
                }
            }
        }
        else {
            # Handle other formats or raw data
            $results += [PSCustomObject]@{
                Database = $Database
                RawData = $RawData
                Retrieved = Get-Date
            }
        }
    }
    catch {
        Write-PSFMessage -Level Warning -Message "Failed to parse structured data, returning raw result: $($_.Exception.Message)"
        $results += [PSCustomObject]@{
            Database = $Database
            RawData = $RawData
            Retrieved = Get-Date
            ParseError = $_.Exception.Message
        }
    }

    return $results
}