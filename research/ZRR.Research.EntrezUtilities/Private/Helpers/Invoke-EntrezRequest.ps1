function Invoke-EntrezRequest {
    <#
    .SYNOPSIS
        Internal function to make HTTP requests to NCBI Entrez E-utilities

    .DESCRIPTION
        Handles all HTTP communication with the NCBI Entrez API, including parameter
        encoding, API key injection, and response parsing.

    .PARAMETER Utility
        The E-utility endpoint (e.g., 'esearch.fcgi', 'esummary.fcgi')

    .PARAMETER Parameters
        Hashtable of parameters to send with the request

    .PARAMETER Method
        HTTP method to use (GET or POST)

    .PARAMETER Raw
        Return raw response without XML parsing

    .NOTES
        This is a private function and should not be called directly.
        Uses PSFramework for logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Utility,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Parameters,

        [Parameter()]
        [ValidateSet('GET', 'POST')]
        [string]$Method = 'GET',

        [Parameter()]
        [switch]$Raw
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Entrez request to $Utility"
    }

    process {
        try {
            $uri = $Script:ModuleConfig.BaseUrl + $Utility

            # Add API key if available
            if ($env:NCBI_API_KEY) {
                $Parameters['api_key'] = $env:NCBI_API_KEY
            }

            # Build query string for GET or prepare body for POST
            if ($Method -eq 'GET') {
                $queryString = ($Parameters.GetEnumerator() | ForEach-Object {
                    "$($_.Key)=$([System.Uri]::EscapeDataString($_.Value))"
                }) -join '&'
                $uri = "$uri`?$queryString"

                $response = Invoke-RestMethod -Uri $uri -Method GET -ErrorAction Stop
            }
            else {
                $response = Invoke-RestMethod -Uri $uri -Method POST -Body $Parameters -ErrorAction Stop
            }

            if ($Raw) {
                return $response
            }

            # Parse XML response if applicable
            if ($response -is [string] -and $response -match '^<') {
                try {
                    [xml]$xmlResponse = $response
                    return $xmlResponse
                }
                catch {
                    return $response
                }
            }

            return $response
        }
        catch {
            $ErrorMessage = "Entrez request to $Utility failed: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}