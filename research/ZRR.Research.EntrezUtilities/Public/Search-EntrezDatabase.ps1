function Search-EntrezDatabase {
    <#
    .SYNOPSIS
        Searches NCBI Entrez databases using the ESearch E-utility

    .DESCRIPTION
        Performs searches in specified NCBI Entrez databases and optionally stores
        results in the history server for subsequent operations. Supports advanced
        search features including date filtering, field-specific searches, and sorting.

    .PARAMETER Term
        The search query term or expression

    .PARAMETER Database
        The Entrez database to search (default: pubmed)

    .PARAMETER RetMax
        Maximum number of records to return (default: 20)

    .PARAMETER RetStart
        Sequential number of the first record to retrieve (default: 0)

    .PARAMETER UseHistory
        Store results on history server for subsequent batch operations

    .EXAMPLE
        Search-EntrezDatabase -Database pubmed -Term "cancer treatment" -RetMax 100 -UseHistory
        Searches PubMed for "cancer treatment" and stores results in history server

    .NOTES
        Author: Zealous Rock Research
        Module: ZRR.Research.EntrezUtilities
        Requires: PowerShell 5.1+

    .LINK
        https://docs.zealousrock.dev/powershell/ZRR.Research.EntrezUtilities/Search-EntrezDatabase
    #>
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0,
            HelpMessage = "Enter the search term or query expression"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Term,

        [Parameter(HelpMessage = "Specify the Entrez database to search")]
        [string]$Database = $Script:ModuleConfig.DefaultDatabase,

        [Parameter(HelpMessage = "Maximum number of records to return")]
        [ValidateRange(1, 10000)]
        [int]$RetMax = 20,

        [Parameter(HelpMessage = "Starting record number for retrieval")]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetStart = 0,

        [Parameter(HelpMessage = "Store results in history server for batch operations")]
        [switch]$UseHistory
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Entrez database search for term: $Term"
    }

    process {
        try {
            # Initialize search parameters
            $SearchParams = @{
                db = $Database
                term = $Term
                retmax = $RetMax
                retstart = $RetStart
                retmode = 'xml'
            }

            if ($UseHistory) {
                $SearchParams['usehistory'] = 'y'
            }

            $Response = Invoke-EntrezRequest -Utility 'esearch.fcgi' -Parameters $SearchParams

            # Update session data if using history
            if ($UseHistory -and $Response.eSearchResult) {
                $Script:ModuleConfig.SessionData.WebEnv = $Response.eSearchResult.WebEnv
                $Script:ModuleConfig.SessionData.QueryKey = $Response.eSearchResult.QueryKey
                $Script:ModuleConfig.SessionData.Count = [int]$Response.eSearchResult.Count
                $Script:ModuleConfig.SessionData.Database = $Database

                Write-PSFMessage -Level Host -Message "Search results stored in history server"
            }

            # Add custom type name
            if ($Response) {
                $Response.PSObject.TypeNames.Insert(0, 'ZRR.Research.EntrezUtilities.SearchResult')
            }

            return $Response
        }
        catch {
            $ErrorMessage = "Search failed for term '$Term' in database '$Database': $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }

    end {
        Write-PSFMessage -Level Verbose -Message "Search-EntrezDatabase completed"
    }
}