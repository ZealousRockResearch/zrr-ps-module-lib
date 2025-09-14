#Requires -Version 5.1

<#
.SYNOPSIS
    ZRR.Terraform.Wrapper - Enterprise-grade Terraform workflow automation and management wrapper

.DESCRIPTION
    Provides advanced Terraform workflow automation with enterprise features including:
    - Intelligent workspace management and state isolation
    - Advanced pipeline integration with CI/CD systems
    - Comprehensive error handling and rollback capabilities
    - Cross-platform deployment automation
    - State management with backup and recovery
    - Provider lifecycle management
    - Security-focused variable handling
    - Performance monitoring and optimization

.NOTES
    Module: ZRR.Terraform.Wrapper
    Author: Zealous Rock Research
    Version: 0.1.0
    Generated: 2025-09-13
#>

# Get the module path
$ModulePath = $PSScriptRoot

# Import configuration and logging
$Script:ModuleConfig = @{
    ModuleName = 'ZRR.Terraform.Wrapper'
    ModulePath = $ModulePath
    LogLevel = 'Information'
    TerraformPath = $null
    DefaultWorkspace = 'default'
    StateBackupEnabled = $true
    MaxRetryAttempts = 3
    TimeoutMinutes = 30
    PipelineIntegration = @{
        Enabled = $false
        Provider = $null
        ApiEndpoint = $null
    }
    Security = @{
        RequireStateEncryption = $true
        AllowDestructiveOperations = $false
        ValidateProviderSignatures = $true
    }
    Performance = @{
        EnableParallelism = $true
        MaxParallelOperations = 10
        CacheEnabled = $true
        CacheTTLMinutes = 15
    }
}

# Initialize logging
if (-not (Get-Module -Name PSFramework -ErrorAction SilentlyContinue)) {
    try {
        Import-Module PSFramework -Force -ErrorAction Stop
        Set-PSFLoggingProvider -Name logfile -FilePath "$ModulePath\Logs\ZRR.Terraform.Wrapper.log" -Enabled $true
    }
    catch {
        Write-Warning "PSFramework module not found. Using basic logging..."
        # Fallback to basic logging
        function Write-PSFMessage {
            param(
                [string]$Level,
                [string]$Message
            )
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logMessage = "[$timestamp] [$Level] $Message"

            switch ($Level) {
                'Error' { Write-Error $logMessage }
                'Warning' { Write-Warning $logMessage }
                'Verbose' { Write-Verbose $logMessage -Verbose }
                'Debug' { Write-Debug $logMessage }
                default { Write-Information $logMessage -InformationAction Continue }
            }
        }
    }
}

Write-PSFMessage -Level Host -Message "Loading ZRR.Terraform.Wrapper module..."

# Import private functions first
$PrivateFunctions = Get-ChildItem -Path "$ModulePath\Private\*.ps1" -Recurse -ErrorAction SilentlyContinue
foreach ($Function in $PrivateFunctions) {
    try {
        Write-PSFMessage -Level Verbose -Message "Importing private function: $($Function.Name)"
        . $Function.FullName
    }
    catch {
        Write-PSFMessage -Level Error -Message "Failed to import private function $($Function.Name): $_"
        throw
    }
}

# Import public functions and create exports list
$PublicFunctions = Get-ChildItem -Path "$ModulePath\Public\*.ps1" -ErrorAction SilentlyContinue
$ExportFunctions = @()

foreach ($Function in $PublicFunctions) {
    try {
        Write-PSFMessage -Level Verbose -Message "Importing public function: $($Function.Name)"
        . $Function.FullName
        $ExportFunctions += $Function.BaseName
    }
    catch {
        Write-PSFMessage -Level Error -Message "Failed to import public function $($Function.Name): $_"
        throw
    }
}

# Import classes if they exist
$ClassFiles = Get-ChildItem -Path "$ModulePath\Classes\*.ps1" -ErrorAction SilentlyContinue
foreach ($Class in $ClassFiles) {
    try {
        Write-PSFMessage -Level Verbose -Message "Importing class: $($Class.Name)"
        . $Class.FullName
    }
    catch {
        Write-PSFMessage -Level Error -Message "Failed to import class $($Class.Name): $_"
        throw
    }
}

# Initialize Terraform path detection
try {
    $TerraformExecutable = Get-Command terraform -ErrorAction SilentlyContinue
    if ($TerraformExecutable) {
        $Script:ModuleConfig.TerraformPath = $TerraformExecutable.Source
        Write-PSFMessage -Level Information -Message "Terraform detected at: $($Script:ModuleConfig.TerraformPath)"
    }
    else {
        Write-PSFMessage -Level Warning -Message "Terraform executable not found in PATH. Please ensure Terraform is installed."
    }
}
catch {
    Write-PSFMessage -Level Warning -Message "Error detecting Terraform installation: $_"
}

# Initialize workspace cache
$Script:WorkspaceCache = @{}
$Script:StateCache = @{}
$Script:ProviderCache = @{}

# Module cleanup function
$OnRemove = {
    Write-PSFMessage -Level Host -Message "Unloading ZRR.Terraform.Wrapper module..."

    # Clear caches
    $Script:WorkspaceCache.Clear()
    $Script:StateCache.Clear()
    $Script:ProviderCache.Clear()

    # Close any open file handles
    if ($Script:LogFileHandle) {
        $Script:LogFileHandle.Close()
        $Script:LogFileHandle.Dispose()
    }
}
$ExecutionContext.SessionState.Module.OnRemove += $OnRemove

# Define aliases
Set-Alias -Name 'tf-init' -Value 'Invoke-TerraformInit' -Scope Global
Set-Alias -Name 'tf-plan' -Value 'Invoke-TerraformPlan' -Scope Global
Set-Alias -Name 'tf-apply' -Value 'Invoke-TerraformApply' -Scope Global
Set-Alias -Name 'tf-destroy' -Value 'Invoke-TerraformDestroy' -Scope Global
Set-Alias -Name 'tf-state' -Value 'Get-TerraformState' -Scope Global
Set-Alias -Name 'tf-workspace' -Value 'Set-TerraformWorkspace' -Scope Global
Set-Alias -Name 'tf-validate' -Value 'Invoke-TerraformValidate' -Scope Global
Set-Alias -Name 'tf-fmt' -Value 'Format-TerraformConfiguration' -Scope Global
Set-Alias -Name 'tf-refresh' -Value 'Invoke-TerraformRefresh' -Scope Global
Set-Alias -Name 'tf-import' -Value 'Import-TerraformResource' -Scope Global

# Export public functions and aliases
Export-ModuleMember -Function $ExportFunctions -Alias @(
    'tf-init', 'tf-plan', 'tf-apply', 'tf-destroy', 'tf-state',
    'tf-workspace', 'tf-validate', 'tf-fmt', 'tf-refresh', 'tf-import'
)

Write-PSFMessage -Level Host -Message "ZRR.Terraform.Wrapper module loaded successfully. Functions: $($ExportFunctions -join ', ')"