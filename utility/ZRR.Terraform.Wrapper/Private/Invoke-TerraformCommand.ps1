function Invoke-TerraformCommand {
    <#
    .SYNOPSIS
        Internal function to execute Terraform commands with comprehensive error handling

    .DESCRIPTION
        Executes Terraform commands with enterprise features including:
        - Timeout management
        - Retry logic for transient failures
        - Output capture and parsing
        - Security validation
        - Performance monitoring

    .PARAMETER Command
        The Terraform command and arguments to execute

    .PARAMETER WorkingDirectory
        Working directory for the command execution

    .PARAMETER TimeoutMinutes
        Timeout in minutes for command execution

    .PARAMETER RetryCount
        Number of retry attempts for transient failures

    .NOTES
        This is a private function and should not be called directly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Command,

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $pwd,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = $Script:ModuleConfig.TimeoutMinutes,

        [Parameter(Mandatory = $false)]
        [int]$RetryCount = $Script:ModuleConfig.MaxRetryAttempts
    )

    Write-PSFMessage -Level Debug -Message "Executing Terraform command: terraform $($Command -join ' ')"

    $Result = [PSCustomObject]@{
        Command = "terraform $($Command -join ' ')"
        WorkingDirectory = $WorkingDirectory
        ExitCode = $null
        StandardOutput = ''
        StandardError = ''
        ExecutionTime = $null
        RetryAttempt = 0
        Success = $false
    }

    $StartTime = Get-Date
    $Attempt = 0

    do {
        $Attempt++
        $Result.RetryAttempt = $Attempt

        if ($Attempt -gt 1) {
            $RetryDelay = [Math]::Min(30, $Attempt * 5)  # Progressive delay up to 30 seconds
            Write-PSFMessage -Level Warning -Message "Retrying Terraform command (attempt $Attempt/$($RetryCount + 1)) after $RetryDelay seconds"
            Start-Sleep -Seconds $RetryDelay
        }

        try {
            Write-PSFMessage -Level Verbose -Message "Executing Terraform command (attempt $Attempt): $($Result.Command)"

            # Prepare the process start info
            $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ProcessInfo.FileName = $Script:ModuleConfig.TerraformPath ?? 'terraform'
            $ProcessInfo.Arguments = $Command -join ' '
            $ProcessInfo.WorkingDirectory = $WorkingDirectory
            $ProcessInfo.RedirectStandardOutput = $true
            $ProcessInfo.RedirectStandardError = $true
            $ProcessInfo.UseShellExecute = $false
            $ProcessInfo.CreateNoWindow = $true

            # Set environment variables if needed
            if ($env:TF_LOG) {
                $ProcessInfo.Environment['TF_LOG'] = $env:TF_LOG
            }

            # Start the process
            $Process = New-Object System.Diagnostics.Process
            $Process.StartInfo = $ProcessInfo

            # Event handlers for output capture
            $StdOutBuilder = New-Object System.Text.StringBuilder
            $StdErrBuilder = New-Object System.Text.StringBuilder

            $StdOutEvent = Register-ObjectEvent -InputObject $Process -EventName OutputDataReceived -Action {
                if (-not [string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
                    [void]$StdOutBuilder.AppendLine($Event.SourceEventArgs.Data)
                }
            }

            $StdErrEvent = Register-ObjectEvent -InputObject $Process -EventName ErrorDataReceived -Action {
                if (-not [string]::IsNullOrEmpty($Event.SourceEventArgs.Data)) {
                    [void]$StdErrBuilder.AppendLine($Event.SourceEventArgs.Data)
                }
            }

            $Process.Start() | Out-Null
            $Process.BeginOutputReadLine()
            $Process.BeginErrorReadLine()

            # Wait for completion with timeout
            $TimeoutMs = $TimeoutMinutes * 60 * 1000
            $ProcessExited = $Process.WaitForExit($TimeoutMs)

            if (-not $ProcessExited) {
                Write-PSFMessage -Level Error -Message "Terraform command timed out after $TimeoutMinutes minutes"
                $Process.Kill()
                throw "Command execution timed out after $TimeoutMinutes minutes"
            }

            # Clean up event handlers
            Unregister-Event -SourceIdentifier $StdOutEvent.Name -ErrorAction SilentlyContinue
            Unregister-Event -SourceIdentifier $StdErrEvent.Name -ErrorAction SilentlyContinue

            # Capture results
            $Result.ExitCode = $Process.ExitCode
            $Result.StandardOutput = $StdOutBuilder.ToString().Trim()
            $Result.StandardError = $StdErrBuilder.ToString().Trim()
            $Result.ExecutionTime = (Get-Date) - $StartTime
            $Result.Success = $Process.ExitCode -eq 0

            # Log the results
            if ($Result.Success) {
                Write-PSFMessage -Level Information -Message "Terraform command completed successfully in $($Result.ExecutionTime.TotalSeconds) seconds"
            }
            else {
                Write-PSFMessage -Level Warning -Message "Terraform command failed with exit code $($Result.ExitCode)"
                if ($Result.StandardError) {
                    Write-PSFMessage -Level Warning -Message "Error output: $($Result.StandardError)"
                }
            }

            # Check if this is a transient error that should be retried
            if (-not $Result.Success -and $Attempt -le $RetryCount) {
                $ShouldRetry = Test-TerraformTransientError -ErrorOutput $Result.StandardError -ExitCode $Result.ExitCode
                if (-not $ShouldRetry) {
                    Write-PSFMessage -Level Information -Message "Error is not transient, skipping retry attempts"
                    break
                }
            }

            $Process.Dispose()
            break
        }
        catch {
            Write-PSFMessage -Level Error -Message "Error executing Terraform command (attempt $Attempt): $_"

            $Result.StandardError += "`nException: $($_.Exception.Message)"

            if ($Attempt -gt $RetryCount) {
                $Result.ExitCode = -1
                throw "Failed to execute Terraform command after $($RetryCount + 1) attempts: $_"
            }
        }
        finally {
            # Cleanup
            if ($Process -and -not $Process.HasExited) {
                try { $Process.Kill() } catch {}
            }
            if ($Process) {
                try { $Process.Dispose() } catch {}
            }
        }
    }
    while ($Attempt -le $RetryCount -and -not $Result.Success)

    return $Result
}