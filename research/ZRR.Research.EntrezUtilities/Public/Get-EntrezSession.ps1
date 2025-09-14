function Get-EntrezSession {
    <#
    .SYNOPSIS
        Retrieves current Entrez session information and configuration

    .DESCRIPTION
        The Get-EntrezSession function displays current session data including WebEnv,
        QueryKey, search history, API key status, and module configuration details.
        Useful for debugging and session management.

    .PARAMETER IncludeConfig
        Include detailed module configuration information

    .PARAMETER IncludeApiKeyStatus
        Include API key configuration status (without revealing the key)

    .PARAMETER IncludeStatistics
        Include session usage statistics

    .EXAMPLE
        Get-EntrezSession

        Display basic session information

    .EXAMPLE
        Get-EntrezSession -IncludeConfig -IncludeApiKeyStatus -IncludeStatistics

        Display comprehensive session and configuration details

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$IncludeConfig,

        [Parameter()]
        [switch]$IncludeApiKeyStatus,

        [Parameter()]
        [switch]$IncludeStatistics
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Retrieving Entrez session information"
    }

    process {
        try {
            # Build basic session information
            $sessionInfo = [PSCustomObject]@{
                SessionActive = [bool]$Script:ModuleConfig.SessionData.WebEnv
                WebEnv = $Script:ModuleConfig.SessionData.WebEnv
                QueryKey = $Script:ModuleConfig.SessionData.QueryKey
                ResultCount = $Script:ModuleConfig.SessionData.Count
                CurrentDatabase = $Script:ModuleConfig.SessionData.Database
                ModuleVersion = '0.1.0'
                LoadedFunctions = (Get-Module ZRR.Research.EntrezUtilities).ExportedFunctions.Count
                SessionStartTime = $null  # Would need to track this separately
            }

            # Add API key status if requested
            if ($IncludeApiKeyStatus) {
                $apiKeyStatus = @{
                    ApiKeyConfigured = [bool]$env:NCBI_API_KEY
                    ApiKeyLength = if ($env:NCBI_API_KEY) { $env:NCBI_API_KEY.Length } else { 0 }
                    EmailConfigured = [bool]$env:NCBI_EMAIL
                    EnhancedRateLimits = [bool]$env:NCBI_API_KEY
                    EstimatedRateLimit = if ($env:NCBI_API_KEY) { '10 requests/second' } else { '3 requests/second' }
                }

                $sessionInfo | Add-Member -NotePropertyName 'ApiConfiguration' -NotePropertyValue $apiKeyStatus
            }

            # Add module configuration if requested
            if ($IncludeConfig) {
                $configInfo = @{
                    ModuleName = $Script:ModuleConfig.ModuleName
                    ModulePath = $Script:ModuleConfig.ModulePath
                    LogLevel = $Script:ModuleConfig.LogLevel
                    BaseUrl = $Script:ModuleConfig.BaseUrl
                    DefaultRetMax = $Script:ModuleConfig.DefaultRetMax
                    MaxRetMax = $Script:ModuleConfig.MaxRetMax
                    DefaultDatabase = $Script:ModuleConfig.DefaultDatabase
                    SupportedDatabaseCount = $Script:ModuleConfig.SupportedDatabases.Count
                    SupportedDatabases = $Script:ModuleConfig.SupportedDatabases
                }

                $sessionInfo | Add-Member -NotePropertyName 'ModuleConfiguration' -NotePropertyValue $configInfo
            }

            # Add usage statistics if requested
            if ($IncludeStatistics) {
                $statisticsInfo = @{
                    # These would need to be tracked throughout the session
                    TotalSearches = 0  # Would need session tracking
                    TotalRecordsRetrieved = 0  # Would need session tracking
                    DatabasesUsed = @()  # Would need session tracking
                    SessionDuration = $null  # Would need session start time
                    LastActivity = Get-Date
                    MemoryUsage = @{
                        WorkingSet = [Math]::Round((Get-Process -Id $PID).WorkingSet / 1MB, 2)
                        PrivateMemory = [Math]::Round((Get-Process -Id $PID).PrivateMemorySize / 1MB, 2)
                    }
                }

                $sessionInfo | Add-Member -NotePropertyName 'SessionStatistics' -NotePropertyValue $statisticsInfo
            }

            # Add session recommendations
            $recommendations = @()

            if (-not $env:NCBI_API_KEY) {
                $recommendations += "Consider setting an API key with Set-EntrezApiKey for enhanced rate limits"
            }

            if (-not $env:NCBI_EMAIL) {
                $recommendations += "Consider setting NCBI_EMAIL environment variable for better API compliance"
            }

            if ($Script:ModuleConfig.SessionData.WebEnv -and $Script:ModuleConfig.SessionData.Count -gt 1000) {
                $recommendations += "Large result set in session - consider using batch processing for retrievals"
            }

            if ($recommendations.Count -gt 0) {
                $sessionInfo | Add-Member -NotePropertyName 'Recommendations' -NotePropertyValue $recommendations
            }

            Write-PSFMessage -Level Verbose -Message "Session information retrieved successfully"

            return $sessionInfo
        }
        catch {
            $ErrorMessage = "Failed to retrieve session information: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}