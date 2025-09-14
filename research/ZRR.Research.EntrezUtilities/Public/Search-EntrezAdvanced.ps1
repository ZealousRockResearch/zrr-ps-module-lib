function Search-EntrezAdvanced {
    <#
    .SYNOPSIS
        Advanced search function with comprehensive filtering and query building capabilities

    .DESCRIPTION
        The Search-EntrezAdvanced function provides sophisticated search capabilities across NCBI databases
        with advanced query construction, field-specific searching, date ranges, and result filtering.
        Supports complex boolean logic, MeSH terms, and database-specific search fields.

    .PARAMETER Database
        Target NCBI database for the search

    .PARAMETER Term
        Primary search term or query

    .PARAMETER Field
        Specific database field to search (e.g., 'title', 'author', 'journal', 'mesh')

    .PARAMETER AuthorFilter
        Filter results by author name(s)

    .PARAMETER JournalFilter
        Filter results by journal name(s)

    .PARAMETER DateFrom
        Start date for publication date range (YYYY/MM/DD)

    .PARAMETER DateTo
        End date for publication date range (YYYY/MM/DD)

    .PARAMETER MeshTerms
        Array of MeSH terms to include in search (PubMed only)

    .PARAMETER PublicationType
        Filter by publication type (e.g., 'Clinical Trial', 'Review', 'Meta-Analysis')

    .PARAMETER Language
        Filter by publication language

    .PARAMETER Species
        Filter by organism/species

    .PARAMETER BooleanOperator
        Boolean logic for combining terms ('AND', 'OR', 'NOT')

    .PARAMETER RetMax
        Maximum number of results to return

    .PARAMETER RetStart
        Starting position for results (0-based)

    .PARAMETER Sort
        Sort order for results ('relevance', 'pub_date', 'first_author', 'last_author', 'journal', 'title')

    .PARAMETER UseHistory
        Store results on history server for later use

    .PARAMETER Tool
        Tool name for API usage tracking

    .PARAMETER Email
        Email address for API usage tracking

    .PARAMETER BuildQueryOnly
        Return constructed query string without executing search

    .EXAMPLE
        Search-EntrezAdvanced -Database 'pubmed' -Term 'cancer' -AuthorFilter 'Smith J' -DateFrom '2020/01/01' -DateTo '2023/12/31'

        Advanced search for cancer articles by Smith J from 2020-2023

    .EXAMPLE
        Search-EntrezAdvanced -Database 'pubmed' -MeshTerms @('Neoplasms', 'Drug Therapy') -PublicationType 'Clinical Trial' -RetMax 100

        Search using MeSH terms for clinical trials

    .EXAMPLE
        Search-EntrezAdvanced -Database 'protein' -Term 'kinase' -Species 'Homo sapiens' -Sort 'relevance'

        Search for human kinase proteins sorted by relevance

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
        NCBI API: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi
    #>
    [CmdletBinding()]
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

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Term,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Field,

        [Parameter()]
        [string[]]$AuthorFilter,

        [Parameter()]
        [string[]]$JournalFilter,

        [Parameter()]
        [ValidatePattern('^\d{4}/\d{2}/\d{2}$')]
        [string]$DateFrom,

        [Parameter()]
        [ValidatePattern('^\d{4}/\d{2}/\d{2}$')]
        [string]$DateTo,

        [Parameter()]
        [string[]]$MeshTerms,

        [Parameter()]
        [ValidateSet('Clinical Trial', 'Review', 'Meta-Analysis', 'Systematic Review', 'Case Reports', 'Comparative Study', 'Randomized Controlled Trial', 'Observational Study')]
        [string[]]$PublicationType,

        [Parameter()]
        [ValidateSet('eng', 'fre', 'ger', 'spa', 'ita', 'jpn', 'rus', 'chi')]
        [string[]]$Language,

        [Parameter()]
        [string[]]$Species,

        [Parameter()]
        [ValidateSet('AND', 'OR', 'NOT')]
        [string]$BooleanOperator = 'AND',

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$RetMax = $Script:ModuleConfig.DefaultRetMax,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetStart = 0,

        [Parameter()]
        [ValidateSet('relevance', 'pub_date', 'first_author', 'last_author', 'journal', 'title')]
        [string]$Sort = 'relevance',

        [Parameter()]
        [switch]$UseHistory,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Tool = $Script:ModuleConfig.ModuleName,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
        [string]$Email,

        [Parameter()]
        [switch]$BuildQueryOnly
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting advanced search for database: $Database"
    }

    process {
        try {
            # Build advanced query
            $queryParts = @()

            # Primary term with field specification
            if ($Field) {
                $queryParts += "($Term[$Field])"
            } else {
                $queryParts += "($Term)"
            }

            # Author filters
            if ($AuthorFilter) {
                foreach ($author in $AuthorFilter) {
                    $queryParts += "($author[Author])"
                }
            }

            # Journal filters
            if ($JournalFilter) {
                foreach ($journal in $JournalFilter) {
                    $queryParts += "($journal[Journal])"
                }
            }

            # Date range
            if ($DateFrom -or $DateTo) {
                $dateQuery = Build-DateQuery -DateFrom $DateFrom -DateTo $DateTo
                if ($dateQuery) {
                    $queryParts += $dateQuery
                }
            }

            # MeSH terms (PubMed specific)
            if ($MeshTerms -and $Database -eq 'pubmed') {
                foreach ($meshTerm in $MeshTerms) {
                    $queryParts += "($meshTerm[MeSH Terms])"
                }
            }

            # Publication type
            if ($PublicationType) {
                foreach ($pubType in $PublicationType) {
                    $queryParts += "($pubType[Publication Type])"
                }
            }

            # Language
            if ($Language) {
                foreach ($lang in $Language) {
                    $queryParts += "($lang[Language])"
                }
            }

            # Species/Organism
            if ($Species) {
                foreach ($organism in $Species) {
                    if ($Database -eq 'pubmed') {
                        $queryParts += "($organism[MeSH Terms])"
                    } else {
                        $queryParts += "($organism[Organism])"
                    }
                }
            }

            # Combine query parts
            $finalQuery = $queryParts -join " $BooleanOperator "

            Write-PSFMessage -Level Verbose -Message "Constructed query: $finalQuery"

            # Return query only if requested
            if ($BuildQueryOnly) {
                return @{
                    Database = $Database
                    Query = $finalQuery
                    QueryParts = $queryParts
                    BooleanOperator = $BooleanOperator
                }
            }

            # Build search parameters
            $searchParams = @{
                db = $Database
                term = $finalQuery
                retmax = $RetMax
                retstart = $RetStart
                sort = $Sort
                tool = $Tool
            }

            # Add email if provided or available in environment
            if ($Email) {
                $searchParams['email'] = $Email
            } elseif ($env:NCBI_EMAIL) {
                $searchParams['email'] = $env:NCBI_EMAIL
            }

            # Add history server usage if requested
            if ($UseHistory) {
                $searchParams['usehistory'] = 'y'
            }

            # Execute search using base ESearch functionality
            $searchResult = Invoke-EntrezRequest -Utility 'esearch.fcgi' -Parameters $searchParams

            # Process and enhance results
            $processedResult = ConvertTo-AdvancedSearchResult -RawResult $searchResult -Database $Database -Query $finalQuery -Parameters $searchParams

            Write-PSFMessage -Level Verbose -Message "Advanced search completed. Found: $($processedResult.Count) results"

            return $processedResult
        }
        catch {
            $ErrorMessage = "Advanced Entrez search failed: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}

function Build-DateQuery {
    <#
    .SYNOPSIS
        Private helper function to build date range queries
    #>
    [CmdletBinding()]
    param(
        [string]$DateFrom,
        [string]$DateTo
    )

    if ($DateFrom -and $DateTo) {
        return "(""$DateFrom""[Date - Publication] : ""$DateTo""[Date - Publication])"
    }
    elseif ($DateFrom) {
        return "(""$DateFrom""[Date - Publication] : ""3000""[Date - Publication])"
    }
    elseif ($DateTo) {
        return "(""1900""[Date - Publication] : ""$DateTo""[Date - Publication])"
    }
    else {
        return $null
    }
}

function ConvertTo-AdvancedSearchResult {
    <#
    .SYNOPSIS
        Private helper function to convert raw search results into enhanced objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $RawResult,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    try {
        if ($RawResult.eSearchResult) {
            $searchResult = $RawResult.eSearchResult

            # Create enhanced result object
            $result = [PSCustomObject]@{
                Database = $Database
                Query = $Query
                Count = [int]$searchResult.Count
                RetMax = [int]$searchResult.RetMax
                RetStart = [int]$searchResult.RetStart
                IdList = @()
                TranslationSet = @()
                TranslationStack = @()
                WebEnv = $searchResult.WebEnv
                QueryKey = $searchResult.QueryKey
                SearchTime = Get-Date
                QueryTranslation = $null
                Warnings = @()
                Errors = @()
            }

            # Extract ID list
            if ($searchResult.IdList -and $searchResult.IdList.Id) {
                $result.IdList = @($searchResult.IdList.Id)
            }

            # Extract query translation information
            if ($searchResult.TranslationSet -and $searchResult.TranslationSet.Translation) {
                foreach ($translation in $searchResult.TranslationSet.Translation) {
                    $result.TranslationSet += @{
                        From = $translation.From
                        To = $translation.To
                    }
                }
            }

            # Extract query translation stack
            if ($searchResult.TranslationStack -and $searchResult.TranslationStack.TermSet) {
                foreach ($termSet in $searchResult.TranslationStack.TermSet) {
                    $result.TranslationStack += @{
                        Term = $termSet.Term
                        Field = $termSet.Field
                        Count = $termSet.Count
                        Explode = $termSet.Explode
                    }
                }
            }

            # Extract actual query used by NCBI
            if ($searchResult.QueryTranslation) {
                $result.QueryTranslation = $searchResult.QueryTranslation
            }

            # Extract warnings and errors
            if ($searchResult.WarningList -and $searchResult.WarningList.PhraseIgnored) {
                $result.Warnings += @($searchResult.WarningList.PhraseIgnored)
            }

            if ($searchResult.ErrorList -and $searchResult.ErrorList.PhraseNotFound) {
                $result.Errors += @($searchResult.ErrorList.PhraseNotFound)
            }

            # Update module session if history server was used
            if ($result.WebEnv -and $result.QueryKey) {
                $Script:ModuleConfig.SessionData.WebEnv = $result.WebEnv
                $Script:ModuleConfig.SessionData.QueryKey = $result.QueryKey
                $Script:ModuleConfig.SessionData.Count = $result.Count
                $Script:ModuleConfig.SessionData.Database = $Database

                Write-PSFMessage -Level Verbose -Message "Updated session data: WebEnv=$($result.WebEnv), QueryKey=$($result.QueryKey)"
            }

            # Add search metadata
            $result | Add-Member -NotePropertyName 'SearchMetadata' -NotePropertyValue @{
                ReturnedIds = $result.IdList.Count
                TotalAvailable = $result.Count
                HasMoreResults = ($result.RetStart + $result.RetMax) -lt $result.Count
                NextRetStart = if (($result.RetStart + $result.RetMax) -lt $result.Count) { $result.RetStart + $result.RetMax } else { $null }
                QueryComplexity = ($Query -split '\s+').Count
                UsedHistory = [bool]$result.WebEnv
            }

            return $result
        }
        else {
            # Fallback for unexpected response format
            return [PSCustomObject]@{
                Database = $Database
                Query = $Query
                RawResult = $RawResult
                SearchTime = Get-Date
                Error = "Unexpected response format"
            }
        }
    }
    catch {
        Write-PSFMessage -Level Warning -Message "Error processing advanced search result: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Database = $Database
            Query = $Query
            RawResult = $RawResult
            SearchTime = Get-Date
            ProcessingError = $_.Exception.Message
        }
    }
}