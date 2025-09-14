<#
.SYNOPSIS
    Complete enterprise Terraform workflow with ZRR.Terraform.Wrapper

.DESCRIPTION
    Demonstrates a complete enterprise workflow including:
    - Multi-environment deployment
    - State management and backup
    - Compliance validation
    - Error handling and rollback
    - Performance monitoring
    - Pipeline integration

.PARAMETER Environment
    Target environment (dev, staging, prod)

.PARAMETER TerraformPath
    Path to Terraform configuration

.PARAMETER Action
    Action to perform (plan, apply, destroy)

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\CompleteWorkflow.ps1 -Environment "prod" -TerraformPath "C:\terraform\webapp" -Action "apply"

    Deploys the webapp to production environment

.EXAMPLE
    .\CompleteWorkflow.ps1 -Environment "dev" -TerraformPath "C:\terraform\webapp" -Action "destroy" -Force

    Destroys the dev environment without confirmation

.NOTES
    This example demonstrates enterprise best practices for Terraform automation
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$TerraformPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('plan', 'apply', 'destroy')]
    [string]$Action,

    [switch]$Force
)

# Import required modules
Import-Module ZRR.Terraform.Wrapper -Force -ErrorAction Stop

# Set up logging and configuration
$LogPath = Join-Path $env:TEMP "terraform-workflow-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogPath

try {
    Write-Host "=== ZRR Terraform Enterprise Workflow ===" -ForegroundColor Cyan
    Write-Host "Environment: $Environment" -ForegroundColor White
    Write-Host "Path: $TerraformPath" -ForegroundColor White
    Write-Host "Action: $Action" -ForegroundColor White
    Write-Host "Timestamp: $(Get-Date)" -ForegroundColor White
    Write-Host ""

    # Step 1: Environment validation and setup
    Write-Host "Step 1: Environment Validation" -ForegroundColor Yellow
    Write-Host "================================" -ForegroundColor Yellow

    # Validate Terraform installation
    try {
        $TerraformVersion = & terraform version -json | ConvertFrom-Json
        Write-Host "✓ Terraform version: $($TerraformVersion.terraform_version)" -ForegroundColor Green
    }
    catch {
        throw "Terraform is not installed or not in PATH"
    }

    # Validate environment-specific configuration
    $VarFile = Join-Path $TerraformPath "$Environment.tfvars"
    if (-not (Test-Path $VarFile)) {
        throw "Environment variable file not found: $VarFile"
    }
    Write-Host "✓ Environment variables file found: $VarFile" -ForegroundColor Green

    # Step 2: Initialize Terraform workspace
    Write-Host "`nStep 2: Initialize Terraform Workspace" -ForegroundColor Yellow
    Write-Host "=======================================" -ForegroundColor Yellow

    $InitParams = @{
        Path = $TerraformPath
        Backend = $true
        Upgrade = $true
        Force = $true
    }

    # Add environment-specific backend configuration
    switch ($Environment) {
        'prod' {
            $InitParams.BackendConfig = @{
                bucket = "company-terraform-state-prod"
                key = "webapp/prod/terraform.tfstate"
                region = "us-west-2"
                encrypt = $true
                dynamodb_table = "terraform-state-lock"
            }
        }
        'staging' {
            $InitParams.BackendConfig = @{
                bucket = "company-terraform-state-staging"
                key = "webapp/staging/terraform.tfstate"
                region = "us-west-2"
                encrypt = $true
                dynamodb_table = "terraform-state-lock"
            }
        }
        'dev' {
            $InitParams.BackendConfig = @{
                bucket = "company-terraform-state-dev"
                key = "webapp/dev/terraform.tfstate"
                region = "us-west-2"
                encrypt = $true
            }
        }
    }

    $InitResult = Invoke-TerraformInit @InitParams

    if (-not $InitResult.Success) {
        throw "Terraform initialization failed: $($InitResult.Output)"
    }

    Write-Host "✓ Terraform initialized successfully" -ForegroundColor Green
    Write-Host "  Duration: $($InitResult.Duration)s" -ForegroundColor Gray

    # Step 3: Workspace management
    Write-Host "`nStep 3: Workspace Management" -ForegroundColor Yellow
    Write-Host "=============================" -ForegroundColor Yellow

    try {
        # Create workspace if it doesn't exist
        $WorkspaceResult = New-TerraformWorkspace -Path $TerraformPath -Name $Environment -ErrorAction SilentlyContinue
        if ($WorkspaceResult) {
            Write-Host "✓ Created workspace: $Environment" -ForegroundColor Green
        }

        # Switch to the target workspace
        $SwitchResult = Set-TerraformWorkspace -Path $TerraformPath -Name $Environment
        Write-Host "✓ Switched to workspace: $Environment" -ForegroundColor Green
    }
    catch {
        Write-Warning "Workspace management error: $_"
    }

    # Step 4: State backup (for production)
    if ($Environment -eq 'prod' -and $Action -in @('apply', 'destroy')) {
        Write-Host "`nStep 4: State Backup" -ForegroundColor Yellow
        Write-Host "====================" -ForegroundColor Yellow

        $BackupPath = "backups/$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss')-$Environment.tfstate"
        $BackupResult = Backup-TerraformState -Path $TerraformPath -BackupPath $BackupPath

        if ($BackupResult.Success) {
            Write-Host "✓ State backup created: $($BackupResult.BackupPath)" -ForegroundColor Green
        }
        else {
            Write-Warning "State backup failed: $($BackupResult.Error)"
        }
    }

    # Step 5: Plan generation and analysis
    Write-Host "`nStep 5: Plan Generation and Analysis" -ForegroundColor Yellow
    Write-Host "=====================================" -ForegroundColor Yellow

    $PlanParams = @{
        Path = $TerraformPath
        VarFile = @($VarFile)
        DetailedExitCode = $true
        AnalyzePlan = $true
        SavePlan = $true
    }

    if ($Action -eq 'destroy') {
        $PlanParams.Destroy = $true
    }

    $PlanResult = Invoke-TerraformPlan @PlanParams

    if (-not $PlanResult.Success) {
        throw "Plan generation failed: $($PlanResult.Output)"
    }

    Write-Host "✓ Plan generated successfully" -ForegroundColor Green
    Write-Host "  Status: $($PlanResult.Status)" -ForegroundColor Gray
    Write-Host "  Duration: $($PlanResult.Duration)s" -ForegroundColor Gray

    if ($PlanResult.HasChanges) {
        Write-Host "  Changes detected:" -ForegroundColor Yellow
        if ($PlanResult.Analysis) {
            Write-Host "    $($PlanResult.Analysis.Summary)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  No changes detected" -ForegroundColor Green
        if ($Action -eq 'plan') {
            Write-Host "`n✓ Plan completed - no changes required" -ForegroundColor Green
            return
        }
    }

    # Step 6: Compliance and security validation
    Write-Host "`nStep 6: Compliance and Security Validation" -ForegroundColor Yellow
    Write-Host "===========================================" -ForegroundColor Yellow

    if ($PlanResult.PlanFile -and (Test-Path $PlanResult.PlanFile)) {
        try {
            $ComplianceResult = Test-TerraformCompliance -Path $TerraformPath -PlanFile $PlanResult.PlanFile

            if ($ComplianceResult.Passed) {
                Write-Host "✓ All compliance checks passed" -ForegroundColor Green
            }
            else {
                Write-Warning "Compliance issues detected:"
                $ComplianceResult.Failures | ForEach-Object {
                    Write-Host "  × $_" -ForegroundColor Red
                }

                if ($Environment -eq 'prod' -and -not $Force) {
                    throw "Compliance validation failed for production environment"
                }
            }
        }
        catch {
            Write-Warning "Compliance validation error: $_"
        }
    }

    # Step 7: Cost estimation (if available)
    Write-Host "`nStep 7: Cost Estimation" -ForegroundColor Yellow
    Write-Host "========================" -ForegroundColor Yellow

    if ($PlanResult.Analysis -and $PlanResult.Analysis.CostEstimation) {
        $CostInfo = $PlanResult.Analysis.CostEstimation
        Write-Host "  Estimated monthly cost: `$$($CostInfo.MonthlyEstimate)" -ForegroundColor Cyan
        Write-Host "  Cost change: `$$($CostInfo.CostDelta)" -ForegroundColor Cyan
    }
    else {
        Write-Host "  Cost estimation not available" -ForegroundColor Gray
    }

    # Step 8: Confirmation and execution
    if ($Action -eq 'plan') {
        Write-Host "`n✓ Plan completed successfully" -ForegroundColor Green
        Write-Host "Plan file saved to: $($PlanResult.PlanFile)" -ForegroundColor Gray
        return
    }

    Write-Host "`nStep 8: Execution Confirmation" -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow

    if (-not $Force) {
        $ConfirmMessage = if ($Action -eq 'destroy') {
            "This will DESTROY resources in $Environment environment. Are you sure?"
        } else {
            "Apply changes to $Environment environment?"
        }

        $Confirmation = Read-Host "$ConfirmMessage (yes/no)"
        if ($Confirmation -notin @('yes', 'y')) {
            Write-Host "Operation cancelled by user" -ForegroundColor Yellow
            return
        }
    }

    # Step 9: Execute the action
    Write-Host "`nStep 9: Execute $($Action.ToUpper())" -ForegroundColor Yellow
    Write-Host "========================" -ForegroundColor Yellow

    if ($Action -eq 'apply') {
        $ExecuteParams = @{
            Path = $TerraformPath
            PlanFile = $PlanResult.PlanFile
            AutoApprove = $true
            Backup = ($Environment -eq 'prod')
            EnableRollback = ($Environment -eq 'prod')
            Detailed = $true
        }

        $ExecuteResult = Invoke-TerraformApply @ExecuteParams
    }
    elseif ($Action -eq 'destroy') {
        $ExecuteParams = @{
            Path = $TerraformPath
            AutoApprove = $true
            Backup = ($Environment -eq 'prod')
            Force = $Force
        }

        $ExecuteResult = Invoke-TerraformDestroy @ExecuteParams
    }

    if (-not $ExecuteResult.Success) {
        throw "$Action failed: $($ExecuteResult.Output)"
    }

    Write-Host "✓ $($Action.ToUpper()) completed successfully" -ForegroundColor Green
    Write-Host "  Duration: $($ExecuteResult.Duration)s" -ForegroundColor Gray

    if ($ExecuteResult.ResourceChanges) {
        Write-Host "  Resources affected: $($ExecuteResult.ResourceChanges.Count)" -ForegroundColor Gray
    }

    # Step 10: Post-execution validation
    Write-Host "`nStep 10: Post-Execution Validation" -ForegroundColor Yellow
    Write-Host "===================================" -ForegroundColor Yellow

    if ($Action -eq 'apply') {
        # Verify deployment by checking outputs
        $StateResult = Get-TerraformState -Path $TerraformPath -Format JSON

        if ($StateResult.Success -and $StateResult.Outputs) {
            Write-Host "✓ Deployment validation:" -ForegroundColor Green

            $StateResult.Outputs.PSObject.Properties | ForEach-Object {
                $OutputName = $_.Name
                $OutputValue = $_.Value.value
                Write-Host "  $OutputName = $OutputValue" -ForegroundColor Gray
            }
        }

        # Health check for production
        if ($Environment -eq 'prod') {
            Write-Host "`nRunning production health checks..." -ForegroundColor Yellow

            $HealthResult = Get-TerraformState -Path $TerraformPath -HealthCheck

            if ($HealthResult.HealthCheck.IsValid) {
                Write-Host "✓ Production health check passed" -ForegroundColor Green
            }
            else {
                Write-Warning "Production health check issues detected:"
                $HealthResult.HealthCheck.Issues | ForEach-Object {
                    Write-Host "  × $_" -ForegroundColor Red
                }
            }
        }
    }

    # Step 11: Cleanup and reporting
    Write-Host "`nStep 11: Cleanup and Reporting" -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow

    # Archive plan file if it exists
    if ($PlanResult.PlanFile -and (Test-Path $PlanResult.PlanFile)) {
        $ArchivePath = "archives/$(Get-Date -Format 'yyyy-MM-dd')"
        if (-not (Test-Path $ArchivePath)) {
            New-Item -Path $ArchivePath -ItemType Directory -Force | Out-Null
        }

        $ArchivedPlan = Join-Path $ArchivePath "$(Get-Date -Format 'HH-mm-ss')-$Environment-$Action.tfplan"
        Move-Item -Path $PlanResult.PlanFile -Destination $ArchivedPlan -Force
        Write-Host "✓ Plan archived to: $ArchivedPlan" -ForegroundColor Green
    }

    # Generate summary report
    $SummaryReport = @{
        Timestamp = Get-Date
        Environment = $Environment
        Action = $Action
        Success = $true
        Duration = if ($ExecuteResult) { $ExecuteResult.Duration } else { $PlanResult.Duration }
        ResourceChanges = if ($ExecuteResult) { $ExecuteResult.ResourceChanges.Count } else { 0 }
        BackupCreated = if ($BackupResult) { $BackupResult.Success } else { $false }
        CompliancePassed = if ($ComplianceResult) { $ComplianceResult.Passed } else { $null }
        LogPath = $LogPath
    }

    $ReportPath = "reports/workflow-summary-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').json"
    $ReportDir = Split-Path $ReportPath -Parent

    if (-not (Test-Path $ReportDir)) {
        New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null
    }

    $SummaryReport | ConvertTo-Json -Depth 3 | Set-Content -Path $ReportPath
    Write-Host "✓ Summary report saved to: $ReportPath" -ForegroundColor Green

    Write-Host "`n=== Workflow Completed Successfully ===" -ForegroundColor Green
    Write-Host "Total execution time: $((Get-Date) - (Get-Date $SummaryReport.Timestamp))` seconds" -ForegroundColor White
}
catch {
    Write-Host "`n=== Workflow Failed ===" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red

    # Create failure report
    $FailureReport = @{
        Timestamp = Get-Date
        Environment = $Environment
        Action = $Action
        Success = $false
        Error = $_.Exception.Message
        LogPath = $LogPath
    }

    $FailureReportPath = "reports/workflow-failure-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').json"
    $FailureReportDir = Split-Path $FailureReportPath -Parent

    if (-not (Test-Path $FailureReportDir)) {
        New-Item -Path $FailureReportDir -ItemType Directory -Force | Out-Null
    }

    $FailureReport | ConvertTo-Json -Depth 3 | Set-Content -Path $FailureReportPath
    Write-Host "Failure report saved to: $FailureReportPath" -ForegroundColor Yellow

    # Attempt rollback for production failures
    if ($Environment -eq 'prod' -and $Action -eq 'apply' -and $BackupResult -and $BackupResult.Success) {
        Write-Host "`nAttempting automatic rollback..." -ForegroundColor Yellow

        try {
            $RollbackResult = Restore-TerraformState -Path $TerraformPath -BackupPath $BackupResult.BackupPath -Force
            if ($RollbackResult.Success) {
                Write-Host "✓ Automatic rollback completed" -ForegroundColor Green
            } else {
                Write-Host "× Automatic rollback failed: $($RollbackResult.Error)" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "× Automatic rollback failed: $_" -ForegroundColor Red
        }
    }

    throw
}
finally {
    Stop-Transcript
    Write-Host "`nComplete log saved to: $LogPath" -ForegroundColor Gray
}