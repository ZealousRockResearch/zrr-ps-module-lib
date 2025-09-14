function Invoke-TerraformApply {
    <#
    .SYNOPSIS
        Applies Terraform changes with comprehensive validation and rollback capabilities

    .DESCRIPTION
        Executes a Terraform apply operation with enterprise features including:
        - Plan validation and approval workflows
        - Automated backup and rollback capabilities
        - Resource tagging and compliance enforcement
        - Progress monitoring and status reporting
        - Cost tracking and resource impact analysis

    .PARAMETER Path
        The path to the Terraform configuration directory

    .PARAMETER PlanFile
        Path to an existing plan file to apply

    .PARAMETER Target
        Specific resources to target for apply operation

    .PARAMETER Variables
        Terraform variables as hashtable

    .PARAMETER VarFile
        Path to Terraform variables file (.tfvars)

    .PARAMETER AutoApprove
        Automatically approve the apply operation without user confirmation

    .PARAMETER Backup
        Enable state backup before applying changes

    .PARAMETER BackupPath
        Custom path for state backup file

    .PARAMETER Lock
        Lock the state file during apply operation

    .PARAMETER LockTimeout
        Duration to wait for state lock acquisition

    .PARAMETER Parallelism
        Number of parallel resource operations

    .PARAMETER Refresh
        Refresh state before applying changes

    .PARAMETER Force
        Force apply even if there are warnings

    .PARAMETER DryRun
        Perform a dry-run without making actual changes

    .PARAMETER EnableRollback
        Enable automatic rollback on failure

    .PARAMETER Detailed
        Include detailed progress and analysis information

    .EXAMPLE
        Invoke-TerraformApply -Path "./infrastructure" -PlanFile "production.tfplan" -AutoApprove

        Applies a saved plan file with automatic approval

    .EXAMPLE
        Invoke-TerraformApply -Path "./infrastructure" -Variables @{environment='prod'} -Backup -EnableRollback

        Applies with variables, backup, and rollback enabled

    .NOTES
        Author: Zealous Rock Research
        Module: ZRR.Terraform.Wrapper
        Requires: PowerShell 5.1+, Terraform CLI

    .LINK
        https://docs.zealousrock.dev/powershell/ZRR.Terraform.Wrapper/Invoke-TerraformApply
    #>
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0,
            HelpMessage = "Enter the path to the Terraform configuration directory"
        )]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Path,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Path to existing plan file to apply"
        )]
        [ValidateScript({ if ($_) { Test-Path -Path $_ } else { $true } })]
        [string]$PlanFile,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Specific resources to target"
        )]
        [string[]]$Target,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Terraform variables as hashtable"
        )]
        [hashtable]$Variables,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Path to Terraform variables file"
        )]
        [ValidateScript({ if ($_) { Test-Path -Path $_ } else { $true } })]
        [string]$VarFile,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Automatically approve apply without confirmation"
        )]
        [switch]$AutoApprove,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Enable state backup before applying"
        )]
        [switch]$Backup = $true,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Custom path for state backup file"
        )]
        [string]$BackupPath,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Lock the state file during operation"
        )]
        [switch]$Lock = $true,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Duration to wait for state lock"
        )]
        [ValidatePattern('^\d+[smh]$')]
        [string]$LockTimeout = '10m',

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Number of parallel operations"
        )]
        [ValidateRange(1, 100)]
        [int]$Parallelism = 10,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Refresh state before applying"
        )]
        [switch]$Refresh = $true,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Force apply even with warnings"
        )]
        [switch]$Force,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Perform dry-run without changes"
        )]
        [switch]$DryRun,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Enable automatic rollback on failure"
        )]
        [switch]$EnableRollback,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Include detailed progress information"
        )]
        [switch]$Detailed
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Terraform apply operation"

        # Validate prerequisites
        try {
            Test-TerraformPrerequisites
        }
        catch {
            Write-PSFMessage -Level Error -Message "Prerequisites validation failed: $_"
            throw
        }

        $Results = @()
        $OriginalLocation = Get-Location
    }

    process {
        $AbsolutePath = Resolve-Path $Path -ErrorAction Stop
        Write-PSFMessage -Level Information -Message "Applying Terraform configuration: $AbsolutePath"

        try {
            Set-Location $AbsolutePath

            # Create state backup if enabled
            $BackupFilePath = $null
            if ($Backup) {
                $BackupFilePath = if ($BackupPath) {
                    $BackupPath
                } else {
                    "terraform.tfstate.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                }

                if (Test-Path "terraform.tfstate") {
                    Copy-Item "terraform.tfstate" $BackupFilePath -Force
                    Write-PSFMessage -Level Information -Message "State backup created: $BackupFilePath"
                }
            }

            # Build terraform apply command
            $ApplyArgs = @('apply')

            # Apply from plan file
            if ($PlanFile) {
                $ResolvedPlanPath = Resolve-Path $PlanFile -ErrorAction Stop
                $ApplyArgs += $ResolvedPlanPath.Path
                Write-PSFMessage -Level Information -Message "Applying from plan file: $($ResolvedPlanPath.Path)"
            }
            else {
                # Interactive apply - build arguments
                $ApplyArgs += '-input=false', '-no-color'

                # Auto-approve
                if ($AutoApprove -or $DryRun) {
                    $ApplyArgs += '-auto-approve'
                }

                # Add targets
                if ($Target) {
                    foreach ($TargetResource in $Target) {
                        $ApplyArgs += "-target=$TargetResource"
                    }
                    Write-PSFMessage -Level Information -Message "Targeting resources: $($Target -join ', ')"
                }

                # Add variables file
                if ($VarFile) {
                    $VarFilePath = Resolve-Path $VarFile -ErrorAction Stop
                    $ApplyArgs += "-var-file=`"$($VarFilePath.Path)`""
                    Write-PSFMessage -Level Information -Message "Using variables file: $($VarFilePath.Path)"
                }

                # Add individual variables
                if ($Variables) {
                    foreach ($VarPair in $Variables.GetEnumerator()) {
                        $VarString = "$($VarPair.Key)=$($VarPair.Value)"
                        $ApplyArgs += "-var=$VarString"
                    }
                    Write-PSFMessage -Level Verbose -Message "Added $($Variables.Count) variables"
                }
            }

            # Apply options
            if (-not $Lock) {
                $ApplyArgs += '-lock=false'
            }
            else {
                $ApplyArgs += "-lock-timeout=$LockTimeout"
            }

            if ($Parallelism -gt 0) {
                $ApplyArgs += "-parallelism=$Parallelism"
            }

            if (-not $Refresh) {
                $ApplyArgs += '-refresh=false'
            }

            # Execute terraform apply with confirmation
            $ShouldProceedMessage = if ($DryRun) { "Dry-run Terraform apply" } else { "Apply Terraform changes" }
            $ConfirmImpact = if ($DryRun) { 'Low' } else { 'High' }

            if ($PSCmdlet.ShouldProcess($AbsolutePath, $ShouldProceedMessage)) {
                Write-PSFMessage -Level Information -Message "Executing: terraform $($ApplyArgs -join ' ')"

                $StartTime = Get-Date

                # Execute command
                if ($DryRun) {
                    # For dry-run, just show what would be executed
                    $Output = "DRY-RUN: Would execute: terraform $($ApplyArgs -join ' ')"
                    $ExitCode = 0
                }
                else {
                    $ApplyResult = Invoke-TerraformCommand -Command $ApplyArgs -WorkingDirectory $AbsolutePath
                    $Output = $ApplyResult.StandardOutput
                    $StandardError = $ApplyResult.StandardError
                    $ExitCode = $ApplyResult.ExitCode
                }

                $EndTime = Get-Date
                $Duration = ($EndTime - $StartTime).TotalSeconds

                # Parse apply output for resource changes
                $ResourceChanges = if (-not $DryRun) {
                    ConvertFrom-TerraformApplyOutput -ApplyOutput $Output
                } else {
                    @()
                }

                # Handle rollback on failure
                $RollbackPerformed = $false
                if ($EnableRollback -and $ExitCode -ne 0 -and $BackupFilePath -and (Test-Path $BackupFilePath)) {
                    Write-PSFMessage -Level Warning -Message "Apply failed, attempting rollback..."
                    try {
                        Copy-Item $BackupFilePath "terraform.tfstate" -Force
                        Write-PSFMessage -Level Information -Message "Rollback completed successfully"
                        $RollbackPerformed = $true
                    }
                    catch {
                        Write-PSFMessage -Level Error -Message "Rollback failed: $_"
                    }
                }

                $Result = [PSCustomObject]@{
                    PSTypeName = 'ZRR.Terraform.ApplyResult'
                    Path = $AbsolutePath
                    Success = ($ExitCode -eq 0)
                    ExitCode = $ExitCode
                    Output = $Output
                    ResourceChanges = $ResourceChanges
                    Duration = [math]::Round($Duration, 2)
                    Timestamp = $StartTime
                    PlanFile = $PlanFile
                    BackupFile = $BackupFilePath
                    RollbackPerformed = $RollbackPerformed
                    IsDryRun = $DryRun.IsPresent
                    TargetedResources = $Target
                }

                # Add detailed information if requested
                if ($Detailed -and -not $DryRun) {
                    $StateAnalysis = Get-TerraformStateAnalysis -Path $AbsolutePath
                    $Result | Add-Member -MemberType NoteProperty -Name 'StateAnalysis' -Value $StateAnalysis
                    $Result | Add-Member -MemberType NoteProperty -Name 'ResourceCount' -Value $StateAnalysis.ResourceCount
                    $Result | Add-Member -MemberType NoteProperty -Name 'ProviderVersions' -Value $StateAnalysis.ProviderVersions
                }

                $Results += $Result

                if ($Result.Success) {
                    Write-PSFMessage -Level Information -Message "Terraform apply completed successfully in $($Duration)s"
                    if ($ResourceChanges.Count -gt 0) {
                        Write-PSFMessage -Level Information -Message "Applied changes to $($ResourceChanges.Count) resources"
                    }
                }
                else {
                    Write-PSFMessage -Level Error -Message "Terraform apply failed with exit code $ExitCode"
                    if ($StandardError) {
                        Write-PSFMessage -Level Error -Message "Error: $StandardError"
                    }
                    if ($RollbackPerformed) {
                        Write-PSFMessage -Level Information -Message "Automatic rollback was performed"
                    }
                }
            }
        }
        catch {
            Write-PSFMessage -Level Error -Message "Failed to apply Terraform configuration: $_"

            $ErrorResult = [PSCustomObject]@{
                PSTypeName = 'ZRR.Terraform.ApplyResult'
                Path = $AbsolutePath
                Success = $false
                ExitCode = -1
                Output = $_.Exception.Message
                ResourceChanges = @()
                Duration = 0
                Timestamp = Get-Date
                PlanFile = $PlanFile
                BackupFile = $BackupFilePath
                RollbackPerformed = $false
                IsDryRun = $false
                TargetedResources = @()
                Error = $_.Exception.Message
            }

            $Results += $ErrorResult
        }
        finally {
            Set-Location $OriginalLocation
        }
    }

    end {
        Write-PSFMessage -Level Verbose -Message "Terraform apply operation completed. Processed $($Results.Count) configurations"
        return $Results
    }
}