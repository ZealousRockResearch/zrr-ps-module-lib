function Search-Entrez {
    <#
    .SYNOPSIS
        Unified search function for NCBI Entrez databases with flexible output options

    .DESCRIPTION
        Performs a search in NCBI databases and returns results with specified fields.
        Combines search and summary retrieval in a single operation with customizable output.

    .PARAMETER Query
        The search query/terms to search for

    .PARAMETER Database
        The NCBI database to search (default: pubmed)

    .PARAMETER MaxResults
        Maximum number of results to return (default: 20)

    .PARAMETER IncludeTitles
        Include article titles in results

    .PARAMETER IncludeSummary
        Include abstracts/summaries in results

    .PARAMETER IncludeFullDoc
        Include full document (when available via PMC)

    .PARAMETER IncludePublicationDate
        Include publication dates in results

    .PARAMETER IncludeAuthors
        Include author information in results

    .PARAMETER IncludeDOI
        Include DOI links in results

    .PARAMETER IncludeJournal
        Include journal information in results

    .PARAMETER IncludeAll
        Include all available fields (except FullDoc - must be explicitly requested)

    .PARAMETER OutputFormat
        Output format: 'Object' (default), 'Table', 'CSV', 'JSON'

    .PARAMETER ExportPath
        Path to export results (for CSV/JSON formats)

    .EXAMPLE
        Search-Entrez -Query "diabetes treatment" -IncludeTitles -IncludeSummary

        Searches for diabetes treatment and returns IDs, titles, and abstracts

    .EXAMPLE
        Search-Entrez -Query "COVID-19 vaccines" -IncludeAll -MaxResults 50

        Returns 50 results with all standard fields

    .EXAMPLE
        Search-Entrez -Query "cancer" -IncludeTitles -IncludeAuthors -OutputFormat CSV -ExportPath "results.csv"

        Searches and exports results to CSV file

    .NOTES
        Author: ZRR Research Module
        Full documents require PMC database access and may not be available for all articles
    #>
    [CmdletBinding(DefaultParameterSetName = 'Standard')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [Parameter()]
        [ValidateSet('pubmed', 'pmc', 'protein', 'nucleotide', 'gene', 'genome')]
        [string]$Database = 'pubmed',

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$MaxResults = 20,

        [Parameter(ParameterSetName = 'Standard')]
        [switch]$IncludeTitles,

        [Parameter(ParameterSetName = 'Standard')]
        [switch]$IncludeSummary,

        [Parameter(ParameterSetName = 'Standard')]
        [switch]$IncludeFullDoc,

        [Parameter(ParameterSetName = 'Standard')]
        [switch]$IncludePublicationDate,

        [Parameter(ParameterSetName = 'Standard')]
        [switch]$IncludeAuthors,

        [Parameter(ParameterSetName = 'Standard')]
        [switch]$IncludeDOI,

        [Parameter(ParameterSetName = 'Standard')]
        [switch]$IncludeJournal,

        [Parameter(ParameterSetName = 'All')]
        [switch]$IncludeAll,

        [Parameter()]
        [ValidateSet('Object', 'Table', 'CSV', 'JSON')]
        [string]$OutputFormat = 'Object',

        [Parameter()]
        [string]$ExportPath
    )

    begin {
        Write-Verbose "Starting unified Entrez search for: $Query"

        # Check if module functions are available
        $requiredFunctions = @('Search-EntrezDatabase', 'Get-EntrezDocumentSummary')
        foreach ($func in $requiredFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                throw "Required function '$func' not found. Ensure ZRR.Research.EntrezUtilities module is loaded."
            }
        }

        # Initialize session-level abstract cache if it doesn't exist
        if (-not $Script:AbstractCache) {
            $Script:AbstractCache = @{}
        }

        # Set field flags based on IncludeAll
        if ($IncludeAll) {
            $IncludeTitles = $true
            $IncludeSummary = $true
            $IncludePublicationDate = $true
            $IncludeAuthors = $true
            $IncludeDOI = $true
            $IncludeJournal = $true
            # Note: FullDoc is not included by default due to size/availability concerns
        }

        # Default to including ID and Title if nothing specified
        if (-not ($IncludeTitles -or $IncludeSummary -or $IncludeFullDoc -or
                 $IncludePublicationDate -or $IncludeAuthors -or $IncludeDOI -or $IncludeJournal)) {
            $IncludeTitles = $true
        }
    }

    process {
        try {
            # Step 1: Search for articles
            Write-Verbose "Searching $Database for: $Query"
            $searchResults = Search-EntrezDatabase -Database $Database -Term $Query -RetMax $MaxResults

            if (-not $searchResults -or -not $searchResults.eSearchResult.IdList.Id) {
                Write-Warning "No results found for query: $Query"
                return
            }

            $ids = $searchResults.eSearchResult.IdList.Id
            $totalFound = $searchResults.eSearchResult.Count
            Write-Verbose "Found $totalFound total results, retrieving $($ids.Count)"

            # Step 2: Get document summaries
            Write-Verbose "Retrieving document summaries..."
            $summaries = Get-EntrezDocumentSummary -Database $Database -Id $ids -RetMode 'xml'

            if (-not $summaries) {
                Write-Warning "Failed to retrieve summaries for the search results"
                return
            }

            # Step 3: Build custom objects with requested fields
            $results = foreach ($summary in $summaries) {
                $obj = [PSCustomObject]@{
                    ID = $summary.UID
                }

                if ($IncludeTitles) {
                    $obj | Add-Member -NotePropertyName 'Title' -NotePropertyValue $summary.Summary.Title
                }

                # Note: Summary/Abstract will be filled in via batch EFetch if IncludeSummary is true
                if ($IncludeSummary) {
                    # Placeholder - will be populated by batch abstract retrieval
                    $obj | Add-Member -NotePropertyName 'Summary' -NotePropertyValue $null
                }

                if ($IncludeAuthors) {
                    # Extract author names from XML structure
                    $authorList = @()
                    if ($summary.Summary.Authors) {
                        if ($summary.Summary.Authors.Author) {
                            foreach ($author in $summary.Summary.Authors.Author) {
                                if ($author.Name) {
                                    $authorList += $author.Name
                                } elseif ($author -is [string]) {
                                    $authorList += $author
                                }
                            }
                        }
                    }
                    $authors = if ($authorList.Count -gt 0) { $authorList -join '; ' } else { $null }
                    $obj | Add-Member -NotePropertyName 'Authors' -NotePropertyValue $authors
                }

                if ($IncludeJournal) {
                    $journal = $summary.Summary.Journal
                    if (-not $journal) {
                        $journal = $summary.Summary.Source
                    }
                    $obj | Add-Member -NotePropertyName 'Journal' -NotePropertyValue $journal
                }

                if ($IncludePublicationDate) {
                    $pubDate = $summary.Summary.PubDate
                    if (-not $pubDate -and $summary.Summary.EPubDate) {
                        $pubDate = $summary.Summary.EPubDate
                    }
                    $obj | Add-Member -NotePropertyName 'PublicationDate' -NotePropertyValue $pubDate
                }

                if ($IncludeDOI) {
                    # Extract DOI from ArticleIds
                    $doi = $null
                    if ($summary.Summary.ArticleIds) {
                        foreach ($articleId in $summary.Summary.ArticleIds.ArticleId) {
                            if ($articleId.IdType -eq 'doi') {
                                $doi = $articleId.Value
                                break
                            }
                        }
                    }

                    if ($doi) {
                        $doiUrl = "https://doi.org/$doi"
                        $obj | Add-Member -NotePropertyName 'DOI' -NotePropertyValue $doi
                        $obj | Add-Member -NotePropertyName 'DOI_URL' -NotePropertyValue $doiUrl
                    } else {
                        $obj | Add-Member -NotePropertyName 'DOI' -NotePropertyValue $null
                        $obj | Add-Member -NotePropertyName 'DOI_URL' -NotePropertyValue $null
                    }
                }

                if ($IncludeFullDoc) {
                    # For PMC database, all articles should have full text available
                    if ($Database -eq 'pmc') {
                        $pmcId = "PMC" + $summary.UID
                        $pmcUrl = "https://www.ncbi.nlm.nih.gov/pmc/articles/$pmcId/"
                        $obj | Add-Member -NotePropertyName 'FullDocURL' -NotePropertyValue $pmcUrl
                        $obj | Add-Member -NotePropertyName 'PMC_ID' -NotePropertyValue $pmcId
                    } else {
                        # For PubMed, check if PMC ID is available in ArticleIds
                        $pmcId = $null
                        if ($summary.Summary.ArticleIds) {
                            foreach ($articleId in $summary.Summary.ArticleIds.ArticleId) {
                                if ($articleId.IdType -eq 'pmc') {
                                    $pmcId = $articleId.Value
                                    break
                                }
                            }
                        }

                        if ($pmcId) {
                            $pmcUrl = "https://www.ncbi.nlm.nih.gov/pmc/articles/$pmcId/"
                            $obj | Add-Member -NotePropertyName 'FullDocURL' -NotePropertyValue $pmcUrl
                            $obj | Add-Member -NotePropertyName 'PMC_ID' -NotePropertyValue $pmcId
                        } else {
                            $obj | Add-Member -NotePropertyName 'FullDocURL' -NotePropertyValue "Not available in PMC"
                            $obj | Add-Member -NotePropertyName 'PMC_ID' -NotePropertyValue $null
                        }
                    }
                }

                # Add metadata
                $obj | Add-Member -NotePropertyName 'Database' -NotePropertyValue $Database
                $obj | Add-Member -NotePropertyName 'RetrievedDate' -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

                $obj
            }

            # Step 3.5: Batch retrieve abstracts if IncludeSummary is requested
            if ($IncludeSummary -and $results.Count -gt 0) {
                Write-Verbose "Retrieving abstracts for $($results.Count) articles..."

                try {
                    # Get all IDs for abstract retrieval
                    $allIds = $results | ForEach-Object { $_.ID }

                    # Check cache first and identify IDs that need fetching
                    $idsToFetch = @()
                    $cachedAbstracts = @{}

                    foreach ($id in $allIds) {
                        if ($Script:AbstractCache.ContainsKey($id)) {
                            $cachedAbstracts[$id] = $Script:AbstractCache[$id]
                            Write-Verbose "Using cached abstract for ID: $id"
                        } else {
                            $idsToFetch += $id
                        }
                    }

                    # Only fetch abstracts for IDs not in cache
                    $abstractMap = $cachedAbstracts.Clone()
                    if ($idsToFetch.Count -gt 0) {
                        Write-Verbose "Fetching abstracts for $($idsToFetch.Count) new articles..."
                        $abstractRecords = Get-EntrezDataRecord -Database $Database -Id $idsToFetch -RetType 'abstract' -RetMode 'text'

                        # Parse the concatenated batch response (EFetch returns all articles in one text block)
                        foreach ($record in $abstractRecords) {
                            # Split the content by article boundaries (each article starts with any number followed by period)
                            $articlePattern = '(?=^\d+\.\s+)'
                            $articles = [regex]::Split($record.Content, $articlePattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)

                            # Filter out empty entries
                            $articles = $articles | Where-Object { $_.Trim().Length -gt 0 }

                            Write-Verbose "Split batch response into $($articles.Count) articles"

                            foreach ($article in $articles) {
                                # Extract PMID from this article
                                if ($article -match 'PMID:\s*(\d+)') {
                                    $pmid = $matches[1]
                                    Write-Verbose "Processing PMID: $pmid"

                                    # Extract abstract text
                                    $lines = $article -split "`n"
                                    $abstractLines = @()
                                    $inAbstract = $false
                                    $authorInfoPassed = $false

                                    for ($i = 0; $i -lt $lines.Count; $i++) {
                                        $line = $lines[$i].Trim()

                                        if ([string]::IsNullOrWhiteSpace($line)) {
                                            continue
                                        }

                                        # Skip until we pass author information
                                        if ($line -match '^Author information:') {
                                            $authorInfoPassed = $true
                                            continue
                                        }

                                        # Skip author affiliation lines like (1)Department...
                                        if ($authorInfoPassed -and $line -match '^\(\d+\)') {
                                            continue
                                        }

                                        # Start collecting abstract after author info
                                        if ($authorInfoPassed -and -not $inAbstract -and $line.Length -gt 20) {
                                            $inAbstract = $true
                                        }

                                        # Stop at DOI, PMID, copyright, etc.
                                        if ($line -match '^(DOI:|PMID:|©|Conflict of interest|Keywords:)') {
                                            break
                                        }

                                        # Collect abstract content
                                        if ($inAbstract) {
                                            $abstractLines += $line
                                        }
                                    }

                                    if ($abstractLines.Count -gt 0) {
                                        $abstractText = ($abstractLines -join ' ').Trim()
                                        $abstractMap[$pmid] = $abstractText

                                        # Cache the abstract for future use
                                        $Script:AbstractCache[$pmid] = $abstractText
                                        Write-Verbose "Extracted abstract for PMID $pmid (${abstractText.Length} chars)"
                                    } else {
                                        Write-Verbose "No abstract found for PMID: $pmid"
                                    }
                                }
                            }
                        }
                    }

                    # Update results with abstracts
                    foreach ($result in $results) {
                        if ($abstractMap.ContainsKey($result.ID)) {
                            $result.Summary = $abstractMap[$result.ID]
                        } else {
                            $result.Summary = "Abstract not available"
                        }
                    }

                    Write-Verbose "Successfully retrieved abstracts for $($abstractMap.Keys.Count) articles"
                }
                catch {
                    Write-Warning "Failed to retrieve abstracts: $($_.Exception.Message)"
                    # Set all summaries to indicate failure
                    foreach ($result in $results) {
                        $result.Summary = "Abstract retrieval failed"
                    }
                }
            }

            # Step 4: Format and output results
            switch ($OutputFormat) {
                'Table' {
                    $results | Format-Table -AutoSize
                }

                'CSV' {
                    if ($ExportPath) {
                        $results | Export-Csv -Path $ExportPath -NoTypeInformation
                        Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
                    }
                    $results | ConvertTo-Csv -NoTypeInformation
                }

                'JSON' {
                    if ($ExportPath) {
                        $results | ConvertTo-Json -Depth 10 | Set-Content -Path $ExportPath
                        Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
                    }
                    $results | ConvertTo-Json -Depth 10
                }

                Default {
                    # Return as objects
                    $results
                }
            }

            # Display summary statistics
            Write-Verbose "Retrieved $($results.Count) of $totalFound total results"
            if ($totalFound -gt $MaxResults) {
                Write-Information "Note: Total available results ($totalFound) exceeds MaxResults ($MaxResults). Use -MaxResults to retrieve more." -InformationAction Continue
            }

        }
        catch {
            $errorMsg = "Search-Entrez failed: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw
        }
    }

    end {
        Write-Verbose "Search-Entrez completed"
    }
}