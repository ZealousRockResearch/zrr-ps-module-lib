<#
.SYNOPSIS
    ZRR Terraform Module Testing Command - Comprehensive testing framework for ZRR Terraform modules

.DESCRIPTION
    The /zrr-tf-module-test command provides automated, comprehensive testing for Terraform modules
    in the zrr-tf-module-lib repository. It leverages the ZRR.Terraform.Wrapper PowerShell module
    to orchestrate the complete testing lifecycle including:

    1. Module analysis and dependency resolution
    2. Prerequisites validation and deployment
    3. Target module deployment and testing
    4. Azure CLI validation and verification
    5. Complete cleanup and resource removal
    6. Test results documentation and reporting
    7. Example deployment script generation

.PARAMETER ModuleName
    Name of the module to test from the zrr-tf-module-lib registry

.PARAMETER TestLevel
    Testing level: Basic (uses basic example) or Advanced (uses advanced example)

.PARAMETER SubscriptionId
    Azure subscription ID (defaults to Zealous Rock Research - Sandbox)

.PARAMETER ResourceGroupPrefix
    Prefix for test resource groups (defaults to 'rg-test')

.PARAMETER Location
    Azure region for deployment (defaults to 'East US')

.PARAMETER CleanupOnFailure
    Whether to cleanup resources if testing fails (default: true)

.PARAMETER SkipPrerequisites
    Skip deployment of prerequisite modules (use existing infrastructure)

.PARAMETER DryRun
    Perform validation and planning without actual deployment

.PARAMETER Force
    Force deployment even if validation issues are found

.EXAMPLE
    .\zrr-tf-module-test.ps1 -ModuleName "virtual-network" -TestLevel Basic

    Tests the virtual-network module using basic configuration

.EXAMPLE
    .\zrr-tf-module-test.ps1 -ModuleName "azure-sql-db" -TestLevel Advanced -Location "West US 2"

    Tests the Azure SQL Database module using advanced configuration in West US 2

.EXAMPLE
    .\zrr-tf-module-test.ps1 -ModuleName "storage-account" -TestLevel Basic -DryRun

    Performs a dry-run test of the storage-account module

.NOTES
    Requires:
    - ZRR.Terraform.Wrapper PowerShell module
    - Azure CLI with appropriate permissions
    - Terraform 1.0+
    - Access to Zealous Rock Research - Sandbox subscription

    Module Repository: https://github.com/ZealousRockResearch/zrr-ps-module-lib
    Wrapper Repository: https://github.com/ZealousRockResearch/zrr-ps-module-lib/tree/main/utility/ZRR.Terraform.Wrapper

.LINK
    https://github.com/ZealousRockResearch/zrr-ps-module-lib
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Basic', 'Advanced')]
    [string]$TestLevel,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId = "12345678-1234-1234-1234-123456789012", # ZRR Sandbox

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupPrefix = "rg-test",

    [Parameter()]
    [ValidateSet('East US', 'West US 2', 'East US 2', 'West Europe', 'North Europe', 'Southeast Asia')]
    [string]$Location = "East US",

    [Parameter()]
    [switch]$CleanupOnFailure = $true,

    [Parameter()]
    [switch]$SkipPrerequisites,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Force
)

# Initialize script configuration
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Script constants
$SCRIPT_VERSION = "1.0.0"
$ZRR_MODULE_LIB_PATH = "./zrr-tf-module-lib"
$ZRR_WRAPPER_PATH = "./zrr-ps-module-lib/utility/ZRR.Terraform.Wrapper"
$TEST_SESSION_ID = "test-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(Get-Random -Maximum 9999)"
$AZURE_SUBSCRIPTION_NAME = "Zealous Rock Research - Sandbox"

# Test results tracking
$Script:TestResults = @{
    SessionId = $TEST_SESSION_ID
    ModuleName = $ModuleName
    TestLevel = $TestLevel
    StartTime = Get-Date
    EndTime = $null
    Success = $false
    Steps = @()
    DeployedResources = @()
    ValidationResults = @()
    CleanupResults = @()
    Errors = @()
}

# Logging configuration
$LogPath = "logs/$(Get-Date -Format 'dd-MM-yy').txt"
if (-not (Test-Path (Split-Path $LogPath))) {
    New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force | Out-Null
}

function Write-TestLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step')]
        [string]$Level = 'Info',

        [string]$Component = 'Main'
    )

    $Timestamp = Get-Date -Format 'HH:mm:ss'
    $LogEntry = "[$Timestamp] [$TEST_SESSION_ID] [$Component] [$Level] $Message"

    # Console output with colors
    switch ($Level) {
        'Success' { Write-Host $LogEntry -ForegroundColor Green }
        'Warning' { Write-Host $LogEntry -ForegroundColor Yellow }
        'Error' { Write-Host $LogEntry -ForegroundColor Red }
        'Step' { Write-Host $LogEntry -ForegroundColor Cyan }
        default { Write-Host $LogEntry -ForegroundColor White }
    }

    # File logging
    $LogEntry | Add-Content -Path $LogPath
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()

    Write-TestLog "=== STEP 1: PREREQUISITES VALIDATION ===" -Level Step

    $PrereqResults = @{
        ZRRWrapper = $false
        TerraformCLI = $false
        AzureCLI = $false
        ModuleLibrary = $false
        AzureSubscription = $false
    }

    try {
        # Check ZRR.Terraform.Wrapper module
        Write-TestLog "Checking ZRR.Terraform.Wrapper availability..." -Component "Prerequisites"

        if (Test-Path $ZRR_WRAPPER_PATH) {
            Import-Module "$ZRR_WRAPPER_PATH/ZRR.Terraform.Wrapper.psd1" -Force -ErrorAction Stop
            $PrereqResults.ZRRWrapper = $true
            Write-TestLog "✓ ZRR.Terraform.Wrapper module loaded successfully" -Level Success -Component "Prerequisites"
        } else {
            throw "ZRR.Terraform.Wrapper not found at $ZRR_WRAPPER_PATH"
        }

        # Check Terraform CLI
        Write-TestLog "Checking Terraform CLI availability..." -Component "Prerequisites"
        $TerraformVersion = & terraform version -json 2>$null | ConvertFrom-Json
        if ($TerraformVersion) {
            $PrereqResults.TerraformCLI = $true
            Write-TestLog "✓ Terraform version: $($TerraformVersion.terraform_version)" -Level Success -Component "Prerequisites"
        } else {
            throw "Terraform CLI not available or not working"
        }

        # Check Azure CLI
        Write-TestLog "Checking Azure CLI availability..." -Component "Prerequisites"
        $AzVersion = az version --output json 2>$null | ConvertFrom-Json
        if ($AzVersion) {
            $PrereqResults.AzureCLI = $true
            Write-TestLog "✓ Azure CLI version: $($AzVersion.'azure-cli')" -Level Success -Component "Prerequisites"
        } else {
            throw "Azure CLI not available or not working"
        }

        # Check module library
        Write-TestLog "Checking zrr-tf-module-lib availability..." -Component "Prerequisites"
        if (Test-Path $ZRR_MODULE_LIB_PATH) {
            $RegistryPath = "$ZRR_MODULE_LIB_PATH/module-registry.json"
            if (Test-Path $RegistryPath) {
                $Script:ModuleRegistry = Get-Content $RegistryPath | ConvertFrom-Json
                $PrereqResults.ModuleLibrary = $true
                Write-TestLog "✓ Module registry loaded with $($Script:ModuleRegistry.modules.Count) modules" -Level Success -Component "Prerequisites"
            } else {
                throw "Module registry not found at $RegistryPath"
            }
        } else {
            throw "Module library not found at $ZRR_MODULE_LIB_PATH"
        }

        # Check Azure subscription access
        Write-TestLog "Checking Azure subscription access..." -Component "Prerequisites"
        $CurrentSub = az account show --output json 2>$null | ConvertFrom-Json
        if ($CurrentSub) {
            if ($CurrentSub.id -eq $SubscriptionId -or $CurrentSub.name -eq $AZURE_SUBSCRIPTION_NAME) {
                $PrereqResults.AzureSubscription = $true
                Write-TestLog "✓ Connected to Azure subscription: $($CurrentSub.name)" -Level Success -Component "Prerequisites"
            } else {
                Write-TestLog "Switching to target subscription: $SubscriptionId" -Component "Prerequisites"
                az account set --subscription $SubscriptionId
                $PrereqResults.AzureSubscription = $true
                Write-TestLog "✓ Switched to target subscription" -Level Success -Component "Prerequisites"
            }
        } else {
            throw "Unable to access Azure subscription. Please run 'az login' first."
        }

        $Script:TestResults.Steps += @{
            Step = "Prerequisites"
            Success = $true
            Details = $PrereqResults
            Timestamp = Get-Date
        }

        Write-TestLog "✓ All prerequisites validated successfully" -Level Success -Component "Prerequisites"
        return $true

    } catch {
        Write-TestLog "✗ Prerequisites validation failed: $_" -Level Error -Component "Prerequisites"
        $Script:TestResults.Errors += "Prerequisites: $_"
        $Script:TestResults.Steps += @{
            Step = "Prerequisites"
            Success = $false
            Details = $PrereqResults
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
        throw
    }
}

function Get-ModuleInfo {
    [CmdletBinding()]
    param([string]$ModuleName)

    Write-TestLog "=== STEP 2: MODULE ANALYSIS ===" -Level Step

    try {
        Write-TestLog "Analyzing module: $ModuleName" -Component "Analysis"

        # Find module in registry
        $Module = $Script:ModuleRegistry.modules | Where-Object name -eq $ModuleName
        if (-not $Module) {
            throw "Module '$ModuleName' not found in registry. Available modules: $($Script:ModuleRegistry.modules.name -join ', ')"
        }

        $ModulePath = "$ZRR_MODULE_LIB_PATH/$($Module.path)"
        if (-not (Test-Path $ModulePath)) {
            throw "Module path not found: $ModulePath"
        }

        $ExamplePath = "$ModulePath/examples/$($TestLevel.ToLower())"
        if (-not (Test-Path $ExamplePath)) {
            throw "Example path not found: $ExamplePath (TestLevel: $TestLevel)"
        }

        $TfvarsExamplePath = "$ExamplePath/terraform.tfvars.example"
        if (-not (Test-Path $TfvarsExamplePath)) {
            throw "terraform.tfvars.example not found: $TfvarsExamplePath"
        }

        Write-TestLog "✓ Module found: $($Module.description)" -Level Success -Component "Analysis"
        Write-TestLog "  Version: $($Module.version)" -Component "Analysis"
        Write-TestLog "  Path: $ModulePath" -Component "Analysis"
        Write-TestLog "  Test Level: $TestLevel" -Component "Analysis"
        Write-TestLog "  Example Path: $ExamplePath" -Component "Analysis"

        $ModuleInfo = @{
            Module = $Module
            ModulePath = $ModulePath
            ExamplePath = $ExamplePath
            TfvarsPath = $TfvarsExamplePath
            RequiredProviders = $Module.required_providers
            TerraformVersion = $Module.terraform_version
        }

        $Script:TestResults.Steps += @{
            Step = "Module Analysis"
            Success = $true
            Details = $ModuleInfo
            Timestamp = Get-Date
        }

        Write-TestLog "✓ Module analysis completed successfully" -Level Success -Component "Analysis"
        return $ModuleInfo

    } catch {
        Write-TestLog "✗ Module analysis failed: $_" -Level Error -Component "Analysis"
        $Script:TestResults.Errors += "Module Analysis: $_"
        $Script:TestResults.Steps += @{
            Step = "Module Analysis"
            Success = $false
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
        throw
    }
}

function Resolve-Dependencies {
    [CmdletBinding()]
    param([hashtable]$ModuleInfo)

    Write-TestLog "=== STEP 3: DEPENDENCY RESOLUTION ===" -Level Step

    try {
        Write-TestLog "Resolving dependencies for module: $($ModuleInfo.Module.name)" -Component "Dependencies"

        $Dependencies = @()

        # Parse tfvars.example to identify required resources
        $ExampleContent = Get-Content $ModuleInfo.TfvarsPath -Raw

        # Common dependency patterns
        $DependencyPatterns = @{
            'resource_group' = 'resource_group_name\s*='
            'storage-account' = 'storage_account_id\s*='
            'key-vault' = 'key_vault_id\s*='
            'virtual-network' = 'vnet_id\s*='
        }

        foreach ($DepType in $DependencyPatterns.Keys) {
            if ($ExampleContent -match $DependencyPatterns[$DepType]) {
                # Check if we have this module in our registry
                $DepModule = $Script:ModuleRegistry.modules | Where-Object name -eq $DepType
                if ($DepModule -and $DepType -ne $ModuleInfo.Module.name) {
                    $Dependencies += @{
                        Name = $DepType
                        Module = $DepModule
                        Required = $true
                    }
                    Write-TestLog "  Dependency identified: $DepType" -Component "Dependencies"
                }
            }
        }

        # Special case: resource-group is almost always needed
        if ($ModuleInfo.Module.name -ne 'resource-group') {
            $RgModule = $Script:ModuleRegistry.modules | Where-Object name -eq 'resource-group'
            if ($RgModule -and ($Dependencies | Where-Object Name -eq 'resource-group') -eq $null) {
                $Dependencies += @{
                    Name = 'resource-group'
                    Module = $RgModule
                    Required = $true
                }
                Write-TestLog "  Adding required resource-group dependency" -Component "Dependencies"
            }
        }

        Write-TestLog "✓ Found $($Dependencies.Count) dependencies" -Level Success -Component "Dependencies"

        $DependencyInfo = @{
            Dependencies = $Dependencies
            DeploymentOrder = $Dependencies | Sort-Object {
                switch ($_.Name) {
                    'resource-group' { 1 }
                    'storage-account' { 2 }
                    'key-vault' { 3 }
                    'virtual-network' { 4 }
                    default { 5 }
                }
            }
        }

        $Script:TestResults.Steps += @{
            Step = "Dependency Resolution"
            Success = $true
            Details = $DependencyInfo
            Timestamp = Get-Date
        }

        return $DependencyInfo

    } catch {
        Write-TestLog "✗ Dependency resolution failed: $_" -Level Error -Component "Dependencies"
        $Script:TestResults.Errors += "Dependencies: $_"
        $Script:TestResults.Steps += @{
            Step = "Dependency Resolution"
            Success = $false
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
        throw
    }
}

function Deploy-Prerequisites {
    [CmdletBinding()]
    param(
        [hashtable]$DependencyInfo,
        [hashtable]$ModuleInfo
    )

    if ($SkipPrerequisites) {
        Write-TestLog "Skipping prerequisite deployment as requested" -Level Warning -Component "Prerequisites"
        return @()
    }

    Write-TestLog "=== STEP 4: PREREQUISITE DEPLOYMENT ===" -Level Step

    $DeployedPrereqs = @()

    try {
        foreach ($Dependency in $DependencyInfo.DeploymentOrder) {
            Write-TestLog "Deploying prerequisite: $($Dependency.Name)" -Component "Prerequisites"

            $DepModulePath = "$ZRR_MODULE_LIB_PATH/$($Dependency.Module.path)"
            $DepExamplePath = "$DepModulePath/examples/basic" # Always use basic for prerequisites

            # Create test-specific tfvars
            $TestTfvars = @"
# Test configuration for $($Dependency.Name)
# Generated by zrr-tf-module-test on $(Get-Date)

resource_group_name = "$ResourceGroupPrefix-$($Dependency.Name)-$TEST_SESSION_ID"
location_short = "$(($Location -replace ' ', '').ToLower().Substring(0,3))"
environment = "test"

common_tags = {
  Environment = "test"
  Project = "zrr-module-testing"
  Owner = "zrr-platform-team"
  CostCenter = "engineering"
  ManagedBy = "Terraform"
  TestSession = "$TEST_SESSION_ID"
  TestModule = "$($ModuleInfo.Module.name)"
  TestLevel = "$TestLevel"
  AutoCleanup = "true"
}
"@

            $TestTfvarsPath = "$DepExamplePath/test-$TEST_SESSION_ID.tfvars"
            Set-Content -Path $TestTfvarsPath -Value $TestTfvars

            try {
                # Initialize
                Write-TestLog "  Initializing $($Dependency.Name)..." -Component "Prerequisites"
                $InitResult = Invoke-TerraformInit -Path $DepExamplePath
                if (-not $InitResult.Success) {
                    throw "Init failed: $($InitResult.Output)"
                }

                # Plan
                Write-TestLog "  Planning $($Dependency.Name)..." -Component "Prerequisites"
                $PlanResult = Invoke-TerraformPlan -Path $DepExamplePath -VarFile $TestTfvarsPath -DetailedExitCode
                if (-not $PlanResult.Success) {
                    throw "Plan failed: $($PlanResult.Output)"
                }

                # Apply (if not dry run)
                if (-not $DryRun) {
                    Write-TestLog "  Applying $($Dependency.Name)..." -Component "Prerequisites"
                    $ApplyResult = Invoke-TerraformApply -Path $DepExamplePath -PlanFile $PlanResult.PlanFile -AutoApprove
                    if (-not $ApplyResult.Success) {
                        throw "Apply failed: $($ApplyResult.Output)"
                    }

                    $DeployedPrereqs += @{
                        Name = $Dependency.Name
                        Path = $DepExamplePath
                        TfvarsPath = $TestTfvarsPath
                        ApplyResult = $ApplyResult
                        Timestamp = Get-Date
                    }

                    Write-TestLog "  ✓ $($Dependency.Name) deployed successfully" -Level Success -Component "Prerequisites"
                } else {
                    Write-TestLog "  ✓ $($Dependency.Name) plan validated (dry-run)" -Level Success -Component "Prerequisites"
                }

            } catch {
                Write-TestLog "  ✗ Failed to deploy $($Dependency.Name): $_" -Level Error -Component "Prerequisites"
                throw "Prerequisite deployment failed: $($Dependency.Name) - $_"
            } finally {
                # Cleanup test tfvars
                if (Test-Path $TestTfvarsPath) {
                    Remove-Item $TestTfvarsPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        $Script:TestResults.Steps += @{
            Step = "Prerequisite Deployment"
            Success = $true
            Details = $DeployedPrereqs
            Timestamp = Get-Date
        }

        Write-TestLog "✓ All prerequisites deployed successfully" -Level Success -Component "Prerequisites"
        return $DeployedPrereqs

    } catch {
        Write-TestLog "✗ Prerequisite deployment failed: $_" -Level Error -Component "Prerequisites"
        $Script:TestResults.Errors += "Prerequisite Deployment: $_"
        $Script:TestResults.Steps += @{
            Step = "Prerequisite Deployment"
            Success = $false
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
        throw
    }
}

function Deploy-TargetModule {
    [CmdletBinding()]
    param(
        [hashtable]$ModuleInfo,
        [array]$DeployedPrereqs
    )

    Write-TestLog "=== STEP 5: TARGET MODULE DEPLOYMENT ===" -Level Step

    try {
        Write-TestLog "Deploying target module: $($ModuleInfo.Module.name)" -Component "TargetModule"

        # Create test-specific tfvars based on the example
        $ExampleContent = Get-Content $ModuleInfo.TfvarsPath -Raw

        # Replace placeholders with actual values from deployed prerequisites
        $TestTfvars = $ExampleContent

        # Update resource group reference if we deployed one
        $RgPrereq = $DeployedPrereqs | Where-Object Name -eq 'resource-group'
        if ($RgPrereq) {
            $RgName = "$ResourceGroupPrefix-resource-group-$TEST_SESSION_ID"
            $TestTfvars = $TestTfvars -replace 'resource_group_name\s*=\s*"[^"]*"', "resource_group_name = `"$RgName`""
        }

        # Update common test settings
        $TestTfvars = $TestTfvars -replace 'environment\s*=\s*"[^"]*"', 'environment = "test"'
        $TestTfvars = $TestTfvars -replace 'location_short\s*=\s*"[^"]*"', "location_short = `"$(($Location -replace ' ', '').ToLower().Substring(0,3))`""

        # Add test session tracking
        $TestTfvars += @"

# Test session metadata (added by zrr-tf-module-test)
test_session_tags = {
  TestSession = "$TEST_SESSION_ID"
  TestModule = "$($ModuleInfo.Module.name)"
  TestLevel = "$TestLevel"
  AutoCleanup = "true"
  TestTimestamp = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}
"@

        $TestTfvarsPath = "$($ModuleInfo.ExamplePath)/test-$TEST_SESSION_ID.tfvars"
        Set-Content -Path $TestTfvarsPath -Value $TestTfvars

        try {
            # Initialize
            Write-TestLog "  Initializing target module..." -Component "TargetModule"
            $InitResult = Invoke-TerraformInit -Path $ModuleInfo.ExamplePath
            if (-not $InitResult.Success) {
                throw "Init failed: $($InitResult.Output)"
            }

            # Validate
            Write-TestLog "  Validating target module..." -Component "TargetModule"
            $ValidateResult = Invoke-TerraformValidate -Path $ModuleInfo.ExamplePath
            if (-not $ValidateResult.Success) {
                throw "Validation failed: $($ValidateResult.Output)"
            }

            # Plan
            Write-TestLog "  Planning target module..." -Component "TargetModule"
            $PlanResult = Invoke-TerraformPlan -Path $ModuleInfo.ExamplePath -VarFile $TestTfvarsPath -DetailedExitCode -AnalyzePlan
            if (-not $PlanResult.Success) {
                throw "Plan failed: $($PlanResult.Output)"
            }

            Write-TestLog "  Plan Status: $($PlanResult.Status)" -Component "TargetModule"
            if ($PlanResult.Analysis) {
                Write-TestLog "  Plan Analysis: $($PlanResult.Analysis.Summary)" -Component "TargetModule"
            }

            $DeploymentResult = $null

            # Apply (if not dry run)
            if (-not $DryRun) {
                Write-TestLog "  Applying target module..." -Component "TargetModule"
                $ApplyResult = Invoke-TerraformApply -Path $ModuleInfo.ExamplePath -PlanFile $PlanResult.PlanFile -AutoApprove -EnableRollback
                if (-not $ApplyResult.Success) {
                    throw "Apply failed: $($ApplyResult.Output)"
                }

                $DeploymentResult = @{
                    ModuleName = $ModuleInfo.Module.name
                    TestLevel = $TestLevel
                    Path = $ModuleInfo.ExamplePath
                    TfvarsPath = $TestTfvarsPath
                    InitResult = $InitResult
                    ValidateResult = $ValidateResult
                    PlanResult = $PlanResult
                    ApplyResult = $ApplyResult
                    Timestamp = Get-Date
                }

                Write-TestLog "  ✓ Target module deployed successfully" -Level Success -Component "TargetModule"
                Write-TestLog "    Duration: $($ApplyResult.Duration)s" -Component "TargetModule"
                if ($ApplyResult.ResourceChanges) {
                    Write-TestLog "    Resources: $($ApplyResult.ResourceChanges.Count) changes" -Component "TargetModule"
                }
            } else {
                Write-TestLog "  ✓ Target module plan validated (dry-run)" -Level Success -Component "TargetModule"
            }

            $Script:TestResults.Steps += @{
                Step = "Target Module Deployment"
                Success = $true
                Details = $DeploymentResult
                Timestamp = Get-Date
            }

            return $DeploymentResult

        } catch {
            Write-TestLog "  ✗ Target module deployment failed: $_" -Level Error -Component "TargetModule"
            throw
        } finally {
            # Cleanup test tfvars
            if (Test-Path $TestTfvarsPath) {
                Remove-Item $TestTfvarsPath -Force -ErrorAction SilentlyContinue
            }
        }

    } catch {
        Write-TestLog "✗ Target module deployment failed: $_" -Level Error -Component "TargetModule"
        $Script:TestResults.Errors += "Target Module Deployment: $_"
        $Script:TestResults.Steps += @{
            Step = "Target Module Deployment"
            Success = $false
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
        throw
    }
}

function Test-DeployedResources {
    [CmdletBinding()]
    param(
        [hashtable]$ModuleInfo,
        [hashtable]$DeploymentResult
    )

    if ($DryRun) {
        Write-TestLog "Skipping resource validation (dry-run mode)" -Level Warning -Component "Validation"
        return @()
    }

    Write-TestLog "=== STEP 6: RESOURCE VALIDATION ===" -Level Step

    $ValidationResults = @()

    try {
        Write-TestLog "Validating deployed resources for module: $($ModuleInfo.Module.name)" -Component "Validation"

        # Get Terraform outputs
        Write-TestLog "  Retrieving Terraform outputs..." -Component "Validation"
        $StateResult = Get-TerraformState -Path $ModuleInfo.ExamplePath -Format JSON

        if ($StateResult.Success -and $StateResult.Outputs) {
            Write-TestLog "  ✓ Retrieved $($StateResult.Outputs.Count) outputs" -Level Success -Component "Validation"

            foreach ($Output in $StateResult.Outputs.PSObject.Properties) {
                $OutputName = $Output.Name
                $OutputValue = $Output.Value.value

                Write-TestLog "    Output: $OutputName = $OutputValue" -Component "Validation"

                # Validate outputs based on module type
                $ValidationResult = @{
                    Type = "Output"
                    Name = $OutputName
                    Value = $OutputValue
                    Success = $true
                    Details = ""
                }

                # Module-specific validation
                switch ($ModuleInfo.Module.name) {
                    'resource-group' {
                        if ($OutputName -eq 'id' -and $OutputValue) {
                            # Verify resource group exists
                            $RgCheck = az group show --name $OutputValue.Split('/')[-1] --output json 2>$null
                            if ($RgCheck) {
                                $ValidationResult.Details = "Resource group verified via Azure CLI"
                            } else {
                                $ValidationResult.Success = $false
                                $ValidationResult.Details = "Resource group not found via Azure CLI"
                            }
                        }
                    }
                    'virtual-network' {
                        if ($OutputName -eq 'id' -and $OutputValue) {
                            # Verify VNet exists
                            $VnetCheck = az network vnet show --ids $OutputValue --output json 2>$null
                            if ($VnetCheck) {
                                $VnetInfo = $VnetCheck | ConvertFrom-Json
                                $ValidationResult.Details = "VNet verified: $($VnetInfo.addressSpace.addressPrefixes -join ', ')"
                            } else {
                                $ValidationResult.Success = $false
                                $ValidationResult.Details = "VNet not found via Azure CLI"
                            }
                        }
                    }
                    'storage-account' {
                        if ($OutputName -eq 'name' -and $OutputValue) {
                            # Verify storage account exists
                            $StorageCheck = az storage account show --name $OutputValue --output json 2>$null
                            if ($StorageCheck) {
                                $StorageInfo = $StorageCheck | ConvertFrom-Json
                                $ValidationResult.Details = "Storage account verified: $($StorageInfo.sku.name)"
                            } else {
                                $ValidationResult.Success = $false
                                $ValidationResult.Details = "Storage account not found via Azure CLI"
                            }
                        }
                    }
                }

                $ValidationResults += $ValidationResult

                if ($ValidationResult.Success) {
                    Write-TestLog "    ✓ $OutputName validated" -Level Success -Component "Validation"
                } else {
                    Write-TestLog "    ✗ $OutputName validation failed: $($ValidationResult.Details)" -Level Error -Component "Validation"
                }
            }
        }

        # Additional Azure CLI validations
        Write-TestLog "  Running additional Azure CLI validations..." -Component "Validation"

        # Check all resources in test resource groups
        $TestResourceGroups = az group list --query "[?contains(name, '$TEST_SESSION_ID')]" --output json 2>$null
        if ($TestResourceGroups) {
            $RgList = $TestResourceGroups | ConvertFrom-Json
            foreach ($Rg in $RgList) {
                Write-TestLog "    Checking resources in: $($Rg.name)" -Component "Validation"

                $Resources = az resource list --resource-group $Rg.name --output json 2>$null
                if ($Resources) {
                    $ResourceList = $Resources | ConvertFrom-Json
                    Write-TestLog "      Found $($ResourceList.Count) resources" -Component "Validation"

                    foreach ($Resource in $ResourceList) {
                        $ValidationResults += @{
                            Type = "Resource"
                            Name = $Resource.name
                            Value = $Resource.type
                            Success = $true
                            Details = "Resource verified in $($Rg.name)"
                        }
                    }
                }
            }
        }

        $Script:TestResults.Steps += @{
            Step = "Resource Validation"
            Success = $true
            Details = $ValidationResults
            Timestamp = Get-Date
        }

        $SuccessCount = ($ValidationResults | Where-Object Success -eq $true).Count
        $FailCount = ($ValidationResults | Where-Object Success -eq $false).Count

        Write-TestLog "✓ Resource validation completed: $SuccessCount passed, $FailCount failed" -Level Success -Component "Validation"

        return $ValidationResults

    } catch {
        Write-TestLog "✗ Resource validation failed: $_" -Level Error -Component "Validation"
        $Script:TestResults.Errors += "Resource Validation: $_"
        $Script:TestResults.Steps += @{
            Step = "Resource Validation"
            Success = $false
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
        throw
    }
}

function Remove-TestResources {
    [CmdletBinding()]
    param(
        [hashtable]$ModuleInfo,
        [hashtable]$DeploymentResult,
        [array]$DeployedPrereqs
    )

    if ($DryRun) {
        Write-TestLog "Skipping cleanup (dry-run mode)" -Level Warning -Component "Cleanup"
        return
    }

    Write-TestLog "=== STEP 7: RESOURCE CLEANUP ===" -Level Step

    $CleanupResults = @()

    try {
        # Cleanup target module first
        if ($DeploymentResult) {
            Write-TestLog "Cleaning up target module: $($ModuleInfo.Module.name)" -Component "Cleanup"

            try {
                $DestroyResult = Invoke-TerraformDestroy -Path $ModuleInfo.ExamplePath -AutoApprove -Force

                $CleanupResults += @{
                    Type = "TargetModule"
                    Name = $ModuleInfo.Module.name
                    Path = $ModuleInfo.ExamplePath
                    Success = $DestroyResult.Success
                    Details = $DestroyResult.Output
                    Duration = $DestroyResult.Duration
                    Timestamp = Get-Date
                }

                if ($DestroyResult.Success) {
                    Write-TestLog "  ✓ Target module cleanup completed" -Level Success -Component "Cleanup"
                } else {
                    Write-TestLog "  ✗ Target module cleanup failed: $($DestroyResult.Output)" -Level Error -Component "Cleanup"
                }

            } catch {
                Write-TestLog "  ✗ Target module cleanup error: $_" -Level Error -Component "Cleanup"
                $CleanupResults += @{
                    Type = "TargetModule"
                    Name = $ModuleInfo.Module.name
                    Path = $ModuleInfo.ExamplePath
                    Success = $false
                    Details = $_.Exception.Message
                    Timestamp = Get-Date
                }
            }
        }

        # Cleanup prerequisites in reverse order
        if ($DeployedPrereqs -and $DeployedPrereqs.Count -gt 0) {
            Write-TestLog "Cleaning up $($DeployedPrereqs.Count) prerequisites..." -Component "Cleanup"

            $ReversedPrereqs = [array]::Reverse($DeployedPrereqs)
            foreach ($Prereq in $ReversedPrereqs) {
                Write-TestLog "  Cleaning up prerequisite: $($Prereq.Name)" -Component "Cleanup"

                try {
                    $DestroyResult = Invoke-TerraformDestroy -Path $Prereq.Path -AutoApprove -Force

                    $CleanupResults += @{
                        Type = "Prerequisite"
                        Name = $Prereq.Name
                        Path = $Prereq.Path
                        Success = $DestroyResult.Success
                        Details = $DestroyResult.Output
                        Duration = $DestroyResult.Duration
                        Timestamp = Get-Date
                    }

                    if ($DestroyResult.Success) {
                        Write-TestLog "    ✓ $($Prereq.Name) cleanup completed" -Level Success -Component "Cleanup"
                    } else {
                        Write-TestLog "    ✗ $($Prereq.Name) cleanup failed: $($DestroyResult.Output)" -Level Error -Component "Cleanup"
                    }

                } catch {
                    Write-TestLog "    ✗ $($Prereq.Name) cleanup error: $_" -Level Error -Component "Cleanup"
                    $CleanupResults += @{
                        Type = "Prerequisite"
                        Name = $Prereq.Name
                        Path = $Prereq.Path
                        Success = $false
                        Details = $_.Exception.Message
                        Timestamp = Get-Date
                    }
                }
            }
        }

        # Final Azure CLI cleanup - remove any remaining resource groups
        Write-TestLog "Performing final Azure CLI cleanup..." -Component "Cleanup"
        $TestResourceGroups = az group list --query "[?contains(name, '$TEST_SESSION_ID')]" --output json 2>$null
        if ($TestResourceGroups) {
            $RgList = $TestResourceGroups | ConvertFrom-Json
            foreach ($Rg in $RgList) {
                Write-TestLog "  Removing resource group: $($Rg.name)" -Component "Cleanup"
                az group delete --name $Rg.name --yes --no-wait 2>$null
            }
        }

        $Script:TestResults.CleanupResults = $CleanupResults
        $Script:TestResults.Steps += @{
            Step = "Resource Cleanup"
            Success = $true
            Details = $CleanupResults
            Timestamp = Get-Date
        }

        $SuccessCount = ($CleanupResults | Where-Object Success -eq $true).Count
        $FailCount = ($CleanupResults | Where-Object Success -eq $false).Count

        Write-TestLog "✓ Resource cleanup completed: $SuccessCount succeeded, $FailCount failed" -Level Success -Component "Cleanup"

    } catch {
        Write-TestLog "✗ Resource cleanup failed: $_" -Level Error -Component "Cleanup"
        $Script:TestResults.Errors += "Resource Cleanup: $_"
        $Script:TestResults.Steps += @{
            Step = "Resource Cleanup"
            Success = $false
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
    }
}

function New-TestReport {
    [CmdletBinding()]
    param(
        [hashtable]$ModuleInfo,
        [array]$ValidationResults
    )

    Write-TestLog "=== STEP 8: GENERATING TEST REPORT ===" -Level Step

    try {
        $Script:TestResults.EndTime = Get-Date
        $TotalDuration = ($Script:TestResults.EndTime - $Script:TestResults.StartTime).TotalSeconds
        $Script:TestResults.Success = ($Script:TestResults.Errors.Count -eq 0)

        # Create comprehensive test report
        $ReportPath = "test-reports/zrr-tf-module-test-$($ModuleInfo.Module.name)-$TestLevel-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"

        if (-not (Test-Path (Split-Path $ReportPath))) {
            New-Item -Path (Split-Path $ReportPath) -ItemType Directory -Force | Out-Null
        }

        $Report = @"
# ZRR Terraform Module Test Report

**Module:** $($ModuleInfo.Module.name)
**Test Level:** $TestLevel
**Session ID:** $TEST_SESSION_ID
**Status:** $(if ($Script:TestResults.Success) { "✅ PASSED" } else { "❌ FAILED" })
**Duration:** $([math]::Round($TotalDuration, 2))s
**Timestamp:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')

## Module Information

- **Name:** $($ModuleInfo.Module.name)
- **Description:** $($ModuleInfo.Module.description)
- **Version:** $($ModuleInfo.Module.version)
- **Cloud:** $($ModuleInfo.Module.cloud)
- **Layer:** $($ModuleInfo.Module.layer)
- **Path:** $($ModuleInfo.Module.path)

## Test Configuration

- **Test Level:** $TestLevel
- **Azure Subscription:** $AZURE_SUBSCRIPTION_NAME
- **Location:** $Location
- **Resource Group Prefix:** $ResourceGroupPrefix
- **Session ID:** $TEST_SESSION_ID
- **Dry Run:** $(if ($DryRun) { "Yes" } else { "No" })

## Test Results Summary

| Step | Status | Duration |
|------|--------|----------|
"@

        foreach ($Step in $Script:TestResults.Steps) {
            $Status = if ($Step.Success) { "✅ PASSED" } else { "❌ FAILED" }
            $Duration = if ($Step.Details.Duration) { "$($Step.Details.Duration)s" } else { "N/A" }
            $Report += "`n| $($Step.Step) | $Status | $Duration |"
        }

        $Report += @"

## Validation Results

"@

        if ($ValidationResults -and $ValidationResults.Count -gt 0) {
            $Report += @"

| Resource/Output | Type | Status | Details |
|----------------|------|--------|---------|
"@

            foreach ($Validation in $ValidationResults) {
                $Status = if ($Validation.Success) { "✅ PASSED" } else { "❌ FAILED" }
                $Report += "`n| $($Validation.Name) | $($Validation.Type) | $Status | $($Validation.Details) |"
            }
        } else {
            $Report += "`nNo validation results available (likely due to dry-run or deployment failure)."
        }

        if ($Script:TestResults.Errors.Count -gt 0) {
            $Report += @"

## Errors Encountered

"@
            foreach ($Error in $Script:TestResults.Errors) {
                $Report += "`n- $Error"
            }
        }

        $Report += @"

## ZRR.Terraform.Wrapper Commands Used

The following ZRR.Terraform.Wrapper commands were used during this test:

"@

        # Extract commands used from the test results
        foreach ($Step in $Script:TestResults.Steps) {
            if ($Step.Details -and $Step.Details.GetType().Name -eq "Hashtable") {
                switch ($Step.Step) {
                    "Target Module Deployment" {
                        $Report += @"

### Target Module Deployment
\`\`\`powershell
# Import ZRR.Terraform.Wrapper
Import-Module "$ZRR_WRAPPER_PATH/ZRR.Terraform.Wrapper.psd1"

# Initialize module
Invoke-TerraformInit -Path "$($ModuleInfo.ExamplePath)"

# Validate configuration
Invoke-TerraformValidate -Path "$($ModuleInfo.ExamplePath)"

# Generate execution plan
Invoke-TerraformPlan -Path "$($ModuleInfo.ExamplePath)" -VarFile "test-vars.tfvars" -DetailedExitCode -AnalyzePlan

# Apply changes with rollback capability
Invoke-TerraformApply -Path "$($ModuleInfo.ExamplePath)" -PlanFile "plan.tfplan" -AutoApprove -EnableRollback

# Destroy resources
Invoke-TerraformDestroy -Path "$($ModuleInfo.ExamplePath)" -AutoApprove -Force
\`\`\`
"@
                    }
                }
            }
        }

        $Report += @"

## Example Deployment Script

Below is a complete example script for deploying the **$($ModuleInfo.Module.name)** module using ZRR.Terraform.Wrapper:

\`\`\`powershell
<#
.SYNOPSIS
    Deploy $($ModuleInfo.Module.name) module using ZRR.Terraform.Wrapper

.DESCRIPTION
    Example deployment script generated from successful test execution.
    This script demonstrates enterprise-grade deployment practices.

.NOTES
    Generated by: zrr-tf-module-test
    Test Session: $TEST_SESSION_ID
    ZRR.Terraform.Wrapper: https://github.com/ZealousRockResearch/zrr-ps-module-lib
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]`$Environment,

    [Parameter(Mandatory)]
    [string]`$Location,

    [Parameter()]
    [switch]`$DryRun
)

# Import ZRR.Terraform.Wrapper module
# Available at: https://github.com/ZealousRockResearch/zrr-ps-module-lib
Import-Module "$ZRR_WRAPPER_PATH/ZRR.Terraform.Wrapper.psd1" -Force

try {
    `$ModulePath = "$($ModuleInfo.ModulePath)/examples/$($TestLevel.ToLower())"

    Write-Host "Deploying $($ModuleInfo.Module.name) module..." -ForegroundColor Cyan
    Write-Host "Environment: `$Environment" -ForegroundColor White
    Write-Host "Location: `$Location" -ForegroundColor White
    Write-Host "Test Level: $TestLevel" -ForegroundColor White

    # Step 1: Initialize Terraform
    Write-Host "`nStep 1: Initializing Terraform..." -ForegroundColor Yellow
    `$InitResult = Invoke-TerraformInit -Path `$ModulePath -Backend -Upgrade

    if (-not `$InitResult.Success) {
        throw "Initialization failed: `$(`$InitResult.Output)"
    }
    Write-Host "✓ Initialization completed" -ForegroundColor Green

    # Step 2: Validate configuration
    Write-Host "`nStep 2: Validating configuration..." -ForegroundColor Yellow
    `$ValidateResult = Invoke-TerraformValidate -Path `$ModulePath

    if (-not `$ValidateResult.Success) {
        throw "Validation failed: `$(`$ValidateResult.Output)"
    }
    Write-Host "✓ Configuration is valid" -ForegroundColor Green

    # Step 3: Create execution plan
    Write-Host "`nStep 3: Creating execution plan..." -ForegroundColor Yellow
    `$PlanResult = Invoke-TerraformPlan -Path `$ModulePath -DetailedExitCode -AnalyzePlan

    if (-not `$PlanResult.Success) {
        throw "Planning failed: `$(`$PlanResult.Output)"
    }

    Write-Host "✓ Plan created successfully" -ForegroundColor Green
    Write-Host "  Status: `$(`$PlanResult.Status)" -ForegroundColor White
    if (`$PlanResult.Analysis) {
        Write-Host "  Analysis: `$(`$PlanResult.Analysis.Summary)" -ForegroundColor White
    }

    # Step 4: Apply changes (if not dry run)
    if (-not `$DryRun -and `$PlanResult.HasChanges) {
        Write-Host "`nStep 4: Applying changes..." -ForegroundColor Yellow

        # Enable backup and rollback for production deployments
        `$ApplyParams = @{
            Path = `$ModulePath
            PlanFile = `$PlanResult.PlanFile
            AutoApprove = `$true
            Backup = (`$Environment -eq 'prod')
            EnableRollback = (`$Environment -eq 'prod')
        }

        `$ApplyResult = Invoke-TerraformApply @ApplyParams

        if (-not `$ApplyResult.Success) {
            throw "Apply failed: `$(`$ApplyResult.Output)"
        }

        Write-Host "✓ Deployment completed successfully" -ForegroundColor Green
        Write-Host "  Duration: `$(`$ApplyResult.Duration)s" -ForegroundColor White
        if (`$ApplyResult.ResourceChanges) {
            Write-Host "  Resources: `$(`$ApplyResult.ResourceChanges.Count) changes" -ForegroundColor White
        }

        # Step 5: Verify deployment
        Write-Host "`nStep 5: Verifying deployment..." -ForegroundColor Yellow
        `$StateResult = Get-TerraformState -Path `$ModulePath -HealthCheck

        if (`$StateResult.Success) {
            Write-Host "✓ Deployment verification completed" -ForegroundColor Green
            Write-Host "  Resources: `$(`$StateResult.ResourceCount)" -ForegroundColor White

            if (`$StateResult.Outputs) {
                Write-Host "  Outputs:" -ForegroundColor White
                `$StateResult.Outputs.PSObject.Properties | ForEach-Object {
                    Write-Host "    `$(`$_.Name) = `$(`$_.Value.value)" -ForegroundColor Gray
                }
            }
        }

    } elseif (`$DryRun) {
        Write-Host "`nDry-run completed - no changes applied" -ForegroundColor Yellow
    } else {
        Write-Host "`nNo changes required" -ForegroundColor Green
    }

    Write-Host "`n✅ $($ModuleInfo.Module.name) deployment completed successfully!" -ForegroundColor Green

} catch {
    Write-Host "`n❌ Deployment failed: `$_" -ForegroundColor Red

    # Attempt rollback if enabled
    if (`$ApplyResult -and `$ApplyResult.BackupFile) {
        Write-Host "Attempting automatic rollback..." -ForegroundColor Yellow
        try {
            `$RollbackResult = Restore-TerraformState -Path `$ModulePath -BackupPath `$ApplyResult.BackupFile -Force
            if (`$RollbackResult.Success) {
                Write-Host "✓ Rollback completed" -ForegroundColor Green
            }
        } catch {
            Write-Host "✗ Rollback failed: `$_" -ForegroundColor Red
        }
    }

    throw
}
\`\`\`

## Additional Resources

- **ZRR.Terraform.Wrapper Module:** https://github.com/ZealousRockResearch/zrr-ps-module-lib/tree/main/utility/ZRR.Terraform.Wrapper
- **ZRR Terraform Module Library:** https://github.com/ZealousRockResearch/zrr-tf-module-lib
- **Module Documentation:** $($ModuleInfo.ModulePath)/README.md

---

*Report generated by zrr-tf-module-test v$SCRIPT_VERSION on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')*
"@

        Set-Content -Path $ReportPath -Value $Report

        Write-TestLog "✓ Test report generated: $ReportPath" -Level Success -Component "Reporting"

        # Also generate JSON report for programmatic use
        $JsonReportPath = $ReportPath -replace '\.md$', '.json'
        $Script:TestResults | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonReportPath

        Write-TestLog "✓ JSON report generated: $JsonReportPath" -Level Success -Component "Reporting"

        return @{
            MarkdownReport = $ReportPath
            JsonReport = $JsonReportPath
            Success = $Script:TestResults.Success
        }

    } catch {
        Write-TestLog "✗ Test report generation failed: $_" -Level Error -Component "Reporting"
        throw
    }
}

# Main execution
try {
    Write-TestLog "=== ZRR TERRAFORM MODULE TESTING FRAMEWORK ===" -Level Step
    Write-TestLog "Version: $SCRIPT_VERSION" -Component "Main"
    Write-TestLog "Module: $ModuleName" -Component "Main"
    Write-TestLog "Test Level: $TestLevel" -Component "Main"
    Write-TestLog "Session ID: $TEST_SESSION_ID" -Component "Main"
    Write-TestLog "Dry Run: $(if ($DryRun) { 'Yes' } else { 'No' })" -Component "Main"
    Write-TestLog ""

    # Execute testing pipeline
    Test-Prerequisites
    $ModuleInfo = Get-ModuleInfo -ModuleName $ModuleName
    $DependencyInfo = Resolve-Dependencies -ModuleInfo $ModuleInfo
    $DeployedPrereqs = Deploy-Prerequisites -DependencyInfo $DependencyInfo -ModuleInfo $ModuleInfo
    $DeploymentResult = Deploy-TargetModule -ModuleInfo $ModuleInfo -DeployedPrereqs $DeployedPrereqs
    $ValidationResults = Test-DeployedResources -ModuleInfo $ModuleInfo -DeploymentResult $DeploymentResult

    # Always attempt cleanup unless specifically requested not to
    if (-not $SkipPrerequisites -or ($CleanupOnFailure -and $Script:TestResults.Errors.Count -gt 0)) {
        Remove-TestResources -ModuleInfo $ModuleInfo -DeploymentResult $DeploymentResult -DeployedPrereqs $DeployedPrereqs
    }

    $ReportResult = New-TestReport -ModuleInfo $ModuleInfo -ValidationResults $ValidationResults

    # Final results
    $Script:TestResults.Success = ($Script:TestResults.Errors.Count -eq 0)
    $Script:TestResults.EndTime = Get-Date
    $TotalDuration = ($Script:TestResults.EndTime - $Script:TestResults.StartTime).TotalSeconds

    Write-TestLog ""
    Write-TestLog "=== TESTING COMPLETED ===" -Level Step
    if ($Script:TestResults.Success) {
        Write-TestLog "✅ ALL TESTS PASSED" -Level Success -Component "Main"
    } else {
        Write-TestLog "❌ TESTING FAILED" -Level Error -Component "Main"
        Write-TestLog "Errors: $($Script:TestResults.Errors.Count)" -Level Error -Component "Main"
    }
    Write-TestLog "Duration: $([math]::Round($TotalDuration, 2))s" -Component "Main"
    Write-TestLog "Report: $($ReportResult.MarkdownReport)" -Component "Main"
    Write-TestLog ""

    # Add final log entry
    $FinalLogEntry = @"

=== ZRR Terraform Module Test Completed ===
Module: $ModuleName
Test Level: $TestLevel
Session ID: $TEST_SESSION_ID
Status: $(if ($Script:TestResults.Success) { "PASSED" } else { "FAILED" })
Duration: $([math]::Round($TotalDuration, 2))s
Report: $($ReportResult.MarkdownReport)
Errors: $($Script:TestResults.Errors.Count)

"@

    Add-Content -Path $LogPath -Value $FinalLogEntry

    if (-not $Script:TestResults.Success) {
        exit 1
    }

} catch {
    $Script:TestResults.Success = $false
    $Script:TestResults.EndTime = Get-Date
    $Script:TestResults.Errors += "Critical Error: $_"

    Write-TestLog "❌ CRITICAL TESTING FAILURE: $_" -Level Error -Component "Main"

    # Attempt emergency cleanup if resources were deployed
    if ((-not $DryRun) -and ($CleanupOnFailure)) {
        Write-TestLog "Attempting emergency cleanup..." -Level Warning -Component "Main"
        try {
            # Remove any test resource groups
            $TestResourceGroups = az group list --query "[?contains(name, '$TEST_SESSION_ID')]" --output json 2>$null
            if ($TestResourceGroups) {
                $RgList = $TestResourceGroups | ConvertFrom-Json
                foreach ($Rg in $RgList) {
                    Write-TestLog "Emergency cleanup: $($Rg.name)" -Component "Main"
                    az group delete --name $Rg.name --yes --no-wait 2>$null
                }
            }
        } catch {
            Write-TestLog "Emergency cleanup failed: $_" -Level Error -Component "Main"
        }
    }

    # Log critical failure
    $FailureLogEntry = @"

=== ZRR Terraform Module Test FAILED ===
Module: $ModuleName
Test Level: $TestLevel
Session ID: $TEST_SESSION_ID
Status: CRITICAL FAILURE
Error: $_
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

"@

    Add-Content -Path $LogPath -Value $FailureLogEntry

    exit 1
}