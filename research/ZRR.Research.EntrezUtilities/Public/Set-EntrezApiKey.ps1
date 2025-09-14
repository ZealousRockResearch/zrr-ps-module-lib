function Set-EntrezApiKey {
    <#
    .SYNOPSIS
        Sets the NCBI API key for enhanced request limits and tracking

    .DESCRIPTION
        The Set-EntrezApiKey function configures the NCBI API key for the current session.
        API keys allow up to 10 requests per second instead of the default 3 per second limit.
        Keys are stored as environment variables and persist for the PowerShell session.

    .PARAMETER ApiKey
        Your NCBI API key (obtain from NCBI account settings)

    .PARAMETER Persist
        Store the API key persistently in user environment variables

    .PARAMETER Validate
        Validate the API key by making a test request

    .PARAMETER Remove
        Remove the currently stored API key

    .EXAMPLE
        Set-EntrezApiKey -ApiKey "your_api_key_here"

        Set API key for current session

    .EXAMPLE
        Set-EntrezApiKey -ApiKey "your_api_key_here" -Persist -Validate

        Set API key persistently and validate it works

    .EXAMPLE
        Set-EntrezApiKey -Remove

        Remove currently stored API key

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
        API Keys: https://ncbiinsights.ncbi.nlm.nih.gov/2017/11/02/new-api-keys-for-the-e-utilities/
    #>
    [CmdletBinding(DefaultParameterSetName = 'Set', SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Set', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-f0-9]{36}$')]
        [string]$ApiKey,

        [Parameter(ParameterSetName = 'Set')]
        [switch]$Persist,

        [Parameter(ParameterSetName = 'Set')]
        [switch]$Validate,

        [Parameter(ParameterSetName = 'Remove')]
        [switch]$Remove
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Managing NCBI API key configuration"
    }

    process {
        try {
            if ($Remove) {
                if ($PSCmdlet.ShouldProcess("NCBI API Key", "Remove")) {
                    # Remove from current session
                    $env:NCBI_API_KEY = $null

                    # Remove from persistent storage if it exists
                    if ($Persist) {
                        try {
                            [Environment]::SetEnvironmentVariable("NCBI_API_KEY", $null, [EnvironmentVariableTarget]::User)
                            Write-PSFMessage -Level Host -Message "NCBI API key removed from persistent storage"
                        }
                        catch {
                            Write-PSFMessage -Level Warning -Message "Failed to remove API key from persistent storage: $($_.Exception.Message)"
                        }
                    }

                    Write-PSFMessage -Level Host -Message "NCBI API key removed from current session"

                    return [PSCustomObject]@{
                        Status = 'Removed'
                        ApiKeySet = $false
                        Persistent = $false
                        Validated = $false
                    }
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess("NCBI API Key", "Set")) {
                    # Set for current session
                    $env:NCBI_API_KEY = $ApiKey
                    Write-PSFMessage -Level Verbose -Message "API key set for current session"

                    $result = [PSCustomObject]@{
                        Status = 'Set'
                        ApiKeySet = $true
                        Persistent = $false
                        Validated = $false
                        ValidationResult = $null
                    }

                    # Set persistently if requested
                    if ($Persist) {
                        try {
                            [Environment]::SetEnvironmentVariable("NCBI_API_KEY", $ApiKey, [EnvironmentVariableTarget]::User)
                            $result.Persistent = $true
                            Write-PSFMessage -Level Host -Message "NCBI API key stored persistently in user environment"
                        }
                        catch {
                            Write-PSFMessage -Level Warning -Message "Failed to store API key persistently: $($_.Exception.Message)"
                            $result.Status = 'PartiallySet'
                        }
                    }

                    # Validate API key if requested
                    if ($Validate) {
                        Write-PSFMessage -Level Verbose -Message "Validating API key with test request"

                        try {
                            $validationResult = Test-EntrezApiKey -ApiKey $ApiKey
                            $result.Validated = $validationResult.IsValid
                            $result.ValidationResult = $validationResult

                            if ($validationResult.IsValid) {
                                Write-PSFMessage -Level Host -Message "API key validated successfully - enhanced rate limits now active"
                            } else {
                                Write-PSFMessage -Level Warning -Message "API key validation failed: $($validationResult.ErrorMessage)"
                            }
                        }
                        catch {
                            Write-PSFMessage -Level Warning -Message "API key validation failed: $($_.Exception.Message)"
                            $result.ValidationResult = @{
                                IsValid = $false
                                ErrorMessage = $_.Exception.Message
                            }
                        }
                    }

                    Write-PSFMessage -Level Host -Message "NCBI API key configured successfully"
                    return $result
                }
            }
        }
        catch {
            $ErrorMessage = "Failed to configure NCBI API key: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}

function Test-EntrezApiKey {
    <#
    .SYNOPSIS
        Private helper function to validate NCBI API key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ApiKey
    )

    try {
        # Make a simple test request to validate the API key
        $testParams = @{
            db = 'pubmed'
            term = 'test'
            retmax = 1
            api_key = $ApiKey
        }

        Write-PSFMessage -Level Verbose -Message "Making validation request to NCBI"

        $response = Invoke-EntrezRequest -Utility 'esearch.fcgi' -Parameters $testParams

        if ($response.eSearchResult) {
            # Check if the response indicates successful API key usage
            return @{
                IsValid = $true
                ResponseTime = (Get-Date)
                Message = "API key validated successfully"
            }
        } else {
            return @{
                IsValid = $false
                ErrorMessage = "Invalid response from NCBI API"
            }
        }
    }
    catch {
        # Parse error to determine if it's API key related
        $errorMessage = $_.Exception.Message

        if ($errorMessage -match "API key|authentication|authorization") {
            return @{
                IsValid = $false
                ErrorMessage = "Invalid API key: $errorMessage"
            }
        } elseif ($errorMessage -match "rate limit|too many requests") {
            # Paradoxically, rate limiting might indicate the key is working but overwhelmed
            return @{
                IsValid = $true
                ErrorMessage = "API key appears valid but rate limited: $errorMessage"
                Message = "Consider reducing request frequency"
            }
        } else {
            return @{
                IsValid = $false
                ErrorMessage = "Validation failed: $errorMessage"
            }
        }
    }
}