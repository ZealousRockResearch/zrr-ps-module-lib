function Clear-EntrezSession {
    <#
    .SYNOPSIS
        Clears stored Entrez session data and history server information

    .DESCRIPTION
        The Clear-EntrezSession function removes all stored session data including WebEnv,
        QueryKey, and search history from the module's session storage. This helps manage
        memory usage and ensures clean session states for new searches.

    .PARAMETER Force
        Skip confirmation prompt and force session clearing

    .EXAMPLE
        Clear-EntrezSession

        Clear session data with confirmation prompt

    .EXAMPLE
        Clear-EntrezSession -Force

        Clear session data without confirmation

    .NOTES
        Author: Zealous Rock Research
        Requires: PSFramework for logging
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$Force
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Preparing to clear Entrez session data"
    }

    process {
        try {
            if ($Force -or $PSCmdlet.ShouldProcess("Entrez Session Data", "Clear")) {
                # Store current session info for logging
                $currentSession = @{
                    WebEnv = $Script:ModuleConfig.SessionData.WebEnv
                    QueryKey = $Script:ModuleConfig.SessionData.QueryKey
                    Count = $Script:ModuleConfig.SessionData.Count
                    Database = $Script:ModuleConfig.SessionData.Database
                }

                # Clear all session data
                $Script:ModuleConfig.SessionData.WebEnv = $null
                $Script:ModuleConfig.SessionData.QueryKey = $null
                $Script:ModuleConfig.SessionData.Count = 0
                $Script:ModuleConfig.SessionData.Database = $null

                # Log the clearing operation
                if ($currentSession.WebEnv) {
                    Write-PSFMessage -Level Host -Message "Cleared Entrez session data (WebEnv: $($currentSession.WebEnv), Database: $($currentSession.Database), Count: $($currentSession.Count))"
                } else {
                    Write-PSFMessage -Level Host -Message "No active session data to clear"
                }

                Write-PSFMessage -Level Verbose -Message "Entrez session data cleared successfully"
            }
        }
        catch {
            $ErrorMessage = "Failed to clear Entrez session: $($_.Exception.Message)"
            Write-PSFMessage -Level Error -Message $ErrorMessage
            throw $ErrorMessage
        }
    }
}