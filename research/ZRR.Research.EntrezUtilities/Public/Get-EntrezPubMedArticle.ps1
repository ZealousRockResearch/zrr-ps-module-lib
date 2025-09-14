function Get-EntrezPubMedArticle {
    <#
    .SYNOPSIS
        Specialized function for retrieving PubMed articles with enhanced parsing and formatting

    .DESCRIPTION
        The Get-EntrezPubMedArticle function provides specialized handling for PubMed database queries,
        offering enhanced article parsing, citation formatting, and comprehensive metadata extraction.
        Optimized for research workflows with options for full-text retrieval when available.

    .PARAMETER Id
        PubMed IDs (PMIDs) to retrieve articles for

    .PARAMETER RetMode
        Output format: 'xml', 'json', 'text'

    .PARAMETER IncludeFullText
        Attempt to retrieve full article text when available

    .PARAMETER IncludeCitations
        Include reference citations in the output

    .PARAMETER IncludeAbstract
        Include article abstract (default: true)

    .PARAMETER IncludeKeywords
        Include MeSH keywords and author keywords

    .PARAMETER IncludeAffiliations
        Include author affiliations

    .PARAMETER FormatCitation
        Format output as citation strings (APA, MLA, Chicago)

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
        Get-EntrezPubMedArticle -Id @('12345678', '23456789') -IncludeFullText

        Retrieves PubMed articles with full text when available

    .EXAMPLE
        Get-EntrezPubMedArticle -Id @('12345678') -FormatCitation 'APA' -IncludeAbstract

        Retrieves article formatted as APA citation with abstract

    .EXAMPLE
        Get-EntrezPubMedArticle -WebEnv $webenv -QueryKey 1 -RetMax 50 -IncludeKeywords -IncludeAffiliations

        Retrieves articles using session data with comprehensive metadata

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
        NCBI API: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIds')]
    [OutputType([PSCustomObject])]
    param(
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
        [switch]$IncludeFullText,

        [Parameter()]
        [switch]$IncludeCitations,

        [Parameter()]
        [bool]$IncludeAbstract = $true,

        [Parameter()]
        [switch]$IncludeKeywords,

        [Parameter()]
        [switch]$IncludeAffiliations,

        [Parameter()]
        [ValidateSet('APA', 'MLA', 'Chicago')]
        [string]$FormatCitation,

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
        Write-PSFMessage -Level Verbose -Message "Starting specialized PubMed article retrieval"

        # Determine RetType based on requirements
        $retType = if ($IncludeFullText) { 'full' } elseif ($IncludeAbstract) { 'abstract' } else { 'medline' }

        Write-PSFMessage -Level Verbose -Message "Using RetType: $retType for PubMed retrieval"
    }

    process {
        try {
            # Use Get-EntrezDataRecord for the base retrieval
            $baseParams = @{
                Database = 'pubmed'
                RetMode = $RetMode
                RetType = $retType
                Tool = $Tool
            }

            if ($Email) { $baseParams['Email'] = $Email }

            if ($PSCmdlet.ParameterSetName -eq 'ByIds') {
                $baseParams['Id'] = $Id
            } else {
                $baseParams['WebEnv'] = $WebEnv
                $baseParams['QueryKey'] = $QueryKey
                $baseParams['RetStart'] = $RetStart
                $baseParams['RetMax'] = $RetMax
            }

            # Get raw article data
            $rawArticles = Get-EntrezDataRecord @baseParams

            # Process each article with specialized PubMed parsing
            $processedArticles = @()
            foreach ($rawArticle in $rawArticles) {
                $processedArticle = ConvertTo-PubMedArticle -RawArticle $rawArticle -IncludeAffiliations:$IncludeAffiliations -IncludeKeywords:$IncludeKeywords -IncludeCitations:$IncludeCitations -FormatCitation $FormatCitation

                $processedArticles += $processedArticle
            }

            return $processedArticles
        }
        catch {
            $ErrorMessage = "Failed to retrieve PubMed articles: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}

function ConvertTo-PubMedArticle {
    <#
    .SYNOPSIS
        Private helper function to convert raw PubMed data into enhanced article objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $RawArticle,

        [Parameter()]
        [switch]$IncludeAffiliations,

        [Parameter()]
        [switch]$IncludeKeywords,

        [Parameter()]
        [switch]$IncludeCitations,

        [Parameter()]
        [string]$FormatCitation
    )

    try {
        if ($RawArticle.RawData -and $RawArticle.RawData.MedlineCitation) {
            $citation = $RawArticle.RawData.MedlineCitation
            $article = $citation.Article
            $pubmedData = $RawArticle.RawData.PubmedData

            # Extract basic article information
            $articleObj = [PSCustomObject]@{
                PMID = $citation.PMID.InnerText
                Title = $article.ArticleTitle
                Abstract = if ($article.Abstract) {
                    ($article.Abstract.AbstractText | ForEach-Object { $_.InnerText }) -join ' '
                } else { $null }
                Journal = @{
                    Title = $article.Journal.Title
                    ISOAbbreviation = $article.Journal.ISOAbbreviation
                    Volume = $article.Journal.JournalIssue.Volume
                    Issue = $article.Journal.JournalIssue.Issue
                    ISSN = $article.Journal.ISSN.InnerText
                    PublicationDate = Get-PublicationDate -PubDate $article.Journal.JournalIssue.PubDate
                }
                Authors = @()
                ArticleIds = @{}
                PublicationType = @($article.PublicationTypeList.PublicationType | ForEach-Object { $_.InnerText })
                Language = $article.Language
                Retrieved = Get-Date
                Database = 'PubMed'
            }

            # Extract authors with detailed information
            if ($article.AuthorList) {
                foreach ($author in $article.AuthorList.Author) {
                    $authorObj = @{
                        LastName = $author.LastName
                        ForeName = $author.ForeName
                        Initials = $author.Initials
                        CollectiveName = $author.CollectiveName
                    }

                    if ($IncludeAffiliations -and $author.AffiliationInfo) {
                        $authorObj['Affiliations'] = @($author.AffiliationInfo | ForEach-Object { $_.Affiliation })
                    }

                    $articleObj.Authors += $authorObj
                }
            }

            # Extract article IDs (DOI, PMC, etc.)
            if ($pubmedData.ArticleIdList) {
                foreach ($articleId in $pubmedData.ArticleIdList.ArticleId) {
                    $articleObj.ArticleIds[$articleId.IdType] = $articleId.InnerText
                }
            }

            # Extract keywords if requested
            if ($IncludeKeywords) {
                $articleObj | Add-Member -NotePropertyName 'Keywords' -NotePropertyValue @{
                    MeshHeadings = @()
                    AuthorKeywords = @()
                }

                if ($citation.MeshHeadingList) {
                    foreach ($meshHeading in $citation.MeshHeadingList.MeshHeading) {
                        $meshObj = @{
                            DescriptorName = $meshHeading.DescriptorName.InnerText
                            MajorTopic = $meshHeading.DescriptorName.MajorTopicYN -eq 'Y'
                            Qualifiers = @()
                        }

                        if ($meshHeading.QualifierName) {
                            foreach ($qualifier in $meshHeading.QualifierName) {
                                $meshObj.Qualifiers += @{
                                    Name = $qualifier.InnerText
                                    MajorTopic = $qualifier.MajorTopicYN -eq 'Y'
                                }
                            }
                        }

                        $articleObj.Keywords.MeshHeadings += $meshObj
                    }
                }

                if ($citation.KeywordList) {
                    $articleObj.Keywords.AuthorKeywords = @($citation.KeywordList.Keyword | ForEach-Object { $_.InnerText })
                }
            }

            # Extract citations if requested
            if ($IncludeCitations -and $citation.CommentsCorrectionsList) {
                $articleObj | Add-Member -NotePropertyName 'Citations' -NotePropertyValue @()
                foreach ($comment in $citation.CommentsCorrectionsList.CommentsCorrections) {
                    if ($comment.RefType -eq 'Cites') {
                        $articleObj.Citations += @{
                            PMID = $comment.PMID.InnerText
                            Citation = $comment.Note
                        }
                    }
                }
            }

            # Format citation if requested
            if ($FormatCitation) {
                $articleObj | Add-Member -NotePropertyName 'FormattedCitation' -NotePropertyValue (Format-PubMedCitation -Article $articleObj -Style $FormatCitation)
            }

            return $articleObj
        }
        else {
            # Return original article if parsing fails
            Write-PSFMessage -Level Warning -Message "Unable to parse PubMed article structure, returning original data"
            return $RawArticle
        }
    }
    catch {
        Write-PSFMessage -Level Warning -Message "Error parsing PubMed article: $($_.Exception.Message)"
        return $RawArticle
    }
}

function Get-PublicationDate {
    <#
    .SYNOPSIS
        Private helper to extract and format publication dates
    #>
    param($PubDate)

    if ($PubDate.Year) {
        $year = $PubDate.Year
        $month = if ($PubDate.Month) { $PubDate.Month } else { '01' }
        $day = if ($PubDate.Day) { $PubDate.Day } else { '01' }

        try {
            return [DateTime]::ParseExact("$year-$month-$day", 'yyyy-MM-dd', $null)
        }
        catch {
            return $PubDate.Year
        }
    }
    elseif ($PubDate.MedlineDate) {
        return $PubDate.MedlineDate
    }
    else {
        return $null
    }
}

function Format-PubMedCitation {
    <#
    .SYNOPSIS
        Private helper to format citations in various styles
    #>
    param(
        [Parameter(Mandatory)]
        $Article,

        [Parameter(Mandatory)]
        [string]$Style
    )

    $authors = ($Article.Authors | ForEach-Object {
        if ($_.LastName -and $_.ForeName) {
            switch ($Style) {
                'APA' { "$($_.LastName), $($_.Initials)" }
                'MLA' { "$($_.LastName), $($_.ForeName)" }
                'Chicago' { "$($_.ForeName) $($_.LastName)" }
            }
        }
        elseif ($_.CollectiveName) {
            $_.CollectiveName
        }
    }) -join ', '

    $journal = $Article.Journal.Title
    $year = if ($Article.Journal.PublicationDate -is [DateTime]) {
        $Article.Journal.PublicationDate.Year
    } else {
        $Article.Journal.PublicationDate
    }

    switch ($Style) {
        'APA' {
            "$authors ($year). $($Article.Title). $journal"
        }
        'MLA' {
            "$authors `"$($Article.Title).`" $journal, $year"
        }
        'Chicago' {
            "$authors `"$($Article.Title).`" $journal ($year)"
        }
    }
}