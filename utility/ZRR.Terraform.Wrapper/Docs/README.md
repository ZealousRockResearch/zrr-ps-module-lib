# ZRR.Terraform.Wrapper

Enterprise-grade PowerShell module for Terraform automation and management with advanced workflow capabilities, state management, and comprehensive error handling.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Functions](#functions)
- [Examples](#examples)
- [Configuration](#configuration)
- [Advanced Features](#advanced-features)
- [Contributing](#contributing)
- [License](#license)

## Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name ZRR.Terraform.Wrapper -Repository PSGallery -Scope CurrentUser
```

### From Source

```powershell
git clone https://github.com/zealous-rock-research/zrr-ps-module-lib.git
Import-Module ".\utility\ZRR.Terraform.Wrapper\ZRR.Terraform.Wrapper.psd1"
```

## Quick Start

```powershell
# Import the module
Import-Module ZRR.Terraform.Wrapper

# Initialize a Terraform workspace
Invoke-TerraformInit -Path "C:\terraform\project"

# Create an execution plan
Invoke-TerraformPlan -Path "C:\terraform\project" -Out "prod.tfplan"

# Apply the changes
Invoke-TerraformApply -Path "C:\terraform\project" -PlanFile "prod.tfplan" -AutoApprove

# Check the state
Get-TerraformState -Path "C:\terraform\project" -Format Table
```

## Functions

### Core Operations

| Function | Synopsis |
|----------|----------|
| `Invoke-TerraformInit` | Initialize a Terraform working directory |
| `Invoke-TerraformPlan` | Create an execution plan with analysis |
| `Invoke-TerraformApply` | Apply Terraform changes with validation |
| `Invoke-TerraformDestroy` | Destroy managed infrastructure |
| `Get-TerraformState` | Retrieve and analyze state information |

### Workspace Management

| Function | Synopsis |
|----------|----------|
| `Set-TerraformWorkspace` | Switch to a different workspace |
| `New-TerraformWorkspace` | Create a new workspace |
| `Remove-TerraformWorkspace` | Delete a workspace |

### Advanced Operations

| Function | Synopsis |
|----------|----------|
| `Invoke-TerraformValidate` | Validate Terraform configuration |
| `Format-TerraformConfiguration` | Format Terraform files |
| `Import-TerraformResource` | Import existing resources |
| `Export-TerraformState` | Export state information |
| `Backup-TerraformState` | Create state backups |
| `Restore-TerraformState` | Restore from backup |

### Utility Functions

| Function | Synopsis |
|----------|----------|
| `Get-TerraformProvider` | Get provider information |
| `Update-TerraformProvider` | Update providers |
| `New-TerraformModule` | Generate module templates |
| `Test-TerraformCompliance` | Run compliance checks |

## Examples

### Basic Infrastructure Deployment

```powershell
# Initialize and deploy basic infrastructure
$ProjectPath = "C:\terraform\web-app"

# Initialize with S3 backend
Invoke-TerraformInit -Path $ProjectPath -Backend -BackendConfig @{
    bucket = "my-terraform-state"
    key = "web-app/terraform.tfstate"
    region = "us-west-2"
}

# Plan with variables
$Variables = @{
    environment = "production"
    instance_count = 3
    instance_type = "t3.medium"
}

$Plan = Invoke-TerraformPlan -Path $ProjectPath -Var $Variables -Out "prod.tfplan"

if ($Plan.Success -and $Plan.HasChanges) {
    # Apply with backup
    Invoke-TerraformApply -Path $ProjectPath -PlanFile "prod.tfplan" -Backup -EnableRollback
}
```

### Multi-Environment Workflow

```powershell
# Deploy to multiple environments
$Environments = @("dev", "staging", "prod")
$BasePath = "C:\terraform\multi-env"

foreach ($Env in $Environments) {
    Write-Host "Deploying to $Env environment..." -ForegroundColor Green

    # Switch workspace
    Set-TerraformWorkspace -Path $BasePath -Name $Env

    # Plan with environment-specific variables
    $VarFile = Join-Path $BasePath "$Env.tfvars"
    $Plan = Invoke-TerraformPlan -Path $BasePath -VarFile $VarFile -SavePlan

    if ($Plan.Success) {
        # Apply if plan is valid
        Invoke-TerraformApply -Path $BasePath -PlanFile $Plan.PlanFile -AutoApprove
    }
}
```

### State Management and Analysis

```powershell
# Comprehensive state analysis
$StatePath = "C:\terraform\infrastructure"

# Get detailed state information
$State = Get-TerraformState -Path $StatePath -HealthCheck -IncludeProviders -Detailed

# Display summary
Write-Host "Infrastructure Summary:" -ForegroundColor Cyan
Write-Host "  Resources: $($State.ResourceCount)" -ForegroundColor White
Write-Host "  Providers: $($State.Providers.Count)" -ForegroundColor White
Write-Host "  Outputs: $($State.Outputs.Count)" -ForegroundColor White

# Check for specific resources
$WebServers = $State.Resources | Where-Object Type -eq "aws_instance"
Write-Host "  Web Servers: $($WebServers.Count)" -ForegroundColor White

# Backup state before major changes
Backup-TerraformState -Path $StatePath -BackupPath "backups/$(Get-Date -Format 'yyyy-MM-dd')"
```

### Advanced Pipeline Integration

```powershell
# CI/CD Pipeline integration
param(
    [Parameter(Mandatory)]
    [string]$Environment,

    [Parameter(Mandatory)]
    [string]$TerraformPath,

    [switch]$DestroyMode
)

try {
    # Initialize with retry logic
    $InitResult = Invoke-TerraformInit -Path $TerraformPath -Force -Upgrade

    if (-not $InitResult.Success) {
        throw "Initialization failed: $($InitResult.Output)"
    }

    # Select workspace
    Set-TerraformWorkspace -Path $TerraformPath -Name $Environment

    if ($DestroyMode) {
        # Destroy infrastructure
        $DestroyPlan = Invoke-TerraformPlan -Path $TerraformPath -Destroy -DetailedExitCode

        if ($DestroyPlan.HasChanges) {
            Invoke-TerraformDestroy -Path $TerraformPath -AutoApprove -Backup
        }
    }
    else {
        # Deploy infrastructure
        $Plan = Invoke-TerraformPlan -Path $TerraformPath -DetailedExitCode -AnalyzePlan

        if ($Plan.HasChanges) {
            # Run compliance checks
            $ComplianceResult = Test-TerraformCompliance -Path $TerraformPath -PlanFile $Plan.PlanFile

            if ($ComplianceResult.Passed) {
                # Apply changes
                Invoke-TerraformApply -Path $TerraformPath -PlanFile $Plan.PlanFile -AutoApprove
            }
            else {
                throw "Compliance checks failed: $($ComplianceResult.Failures -join ', ')"
            }
        }
    }
}
catch {
    Write-Error "Pipeline failed: $_"
    exit 1
}
```

## Configuration

The module supports extensive configuration through the `$Script:ModuleConfig` variable:

### Default Configuration

```powershell
# View current configuration
$Script:ModuleConfig

# Example output:
@{
    ModuleName = 'ZRR.Terraform.Wrapper'
    LogLevel = 'Information'
    TerraformExecutable = 'terraform'
    DefaultWorkspace = 'default'
    StateBackupPath = 'StateBackups'
    EnableDetailedLogging = $true
    EnableStateBackup = $true
    MaxBackupRetention = 30
    DefaultParallelism = 10
    DefaultTimeout = 600
}
```

### Customizing Configuration

```powershell
# Modify logging level
$Script:ModuleConfig.LogLevel = 'Debug'

# Change default parallelism
$Script:ModuleConfig.DefaultParallelism = 20

# Enable automatic backups
$Script:ModuleConfig.EnableStateBackup = $true
$Script:ModuleConfig.StateBackupPath = 'D:\Terraform\Backups'
```

## Advanced Features

### Enterprise Security

- **State Encryption**: Automatic encryption of sensitive state data
- **Credential Management**: Secure handling of cloud provider credentials
- **Compliance Validation**: Built-in policy enforcement
- **Audit Logging**: Comprehensive operation logging

### Performance Optimization

- **Parallel Execution**: Configurable parallelism for large deployments
- **Caching**: Intelligent caching of provider plugins and state
- **Resource Targeting**: Selective resource operations
- **Plan Analysis**: Automated change impact assessment

### Error Handling & Recovery

- **Automatic Retry**: Intelligent retry logic for transient failures
- **State Rollback**: Automatic rollback on critical failures
- **Health Checks**: Continuous state file validation
- **Recovery Workflows**: Guided recovery from common issues

### Pipeline Integration

- **CI/CD Ready**: Native support for Azure DevOps, GitHub Actions, Jenkins
- **JSON Output**: Machine-readable output formats
- **Exit Codes**: Detailed exit codes for automation
- **Webhooks**: Integration with notification systems

## Aliases

The module provides convenient aliases for common operations:

| Alias | Function |
|-------|----------|
| `tf-init` | `Invoke-TerraformInit` |
| `tf-plan` | `Invoke-TerraformPlan` |
| `tf-apply` | `Invoke-TerraformApply` |
| `tf-destroy` | `Invoke-TerraformDestroy` |
| `tf-state` | `Get-TerraformState` |
| `tf-workspace` | `Set-TerraformWorkspace` |
| `tf-validate` | `Invoke-TerraformValidate` |
| `tf-fmt` | `Format-TerraformConfiguration` |

## Requirements

- **PowerShell**: 5.1 or higher (Windows PowerShell or PowerShell Core)
- **Terraform**: 0.12 or higher installed and in PATH
- **Providers**: Appropriate cloud provider credentials configured
- **Modules**: PSFramework (automatically managed)

### Cloud Provider Support

- **AWS**: Full support with credential management
- **Azure**: Native Azure PowerShell integration
- **Google Cloud**: GCP SDK integration
- **Multi-Cloud**: Cross-provider deployment support

## Troubleshooting

### Common Issues

1. **Terraform Not Found**
   ```powershell
   # Check Terraform installation
   Get-Command terraform -ErrorAction SilentlyContinue

   # Update PATH if needed
   $env:PATH += ";C:\terraform"
   ```

2. **State Lock Issues**
   ```powershell
   # Force unlock if needed
   & terraform force-unlock LOCK_ID
   ```

3. **Permission Issues**
   ```powershell
   # Check credentials
   & terraform plan -input=false
   ```

### Debug Mode

```powershell
# Enable debug logging
$Script:ModuleConfig.LogLevel = 'Debug'

# View detailed logs
Get-Content "$($Script:ModuleConfig.ModulePath)\Logs\*.log" | Select-Object -Last 50
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Add tests for new functionality
5. Run the test suite: `Invoke-Pester`
6. Submit a pull request

### Development Setup

```powershell
# Clone the repository
git clone https://github.com/zealous-rock-research/zrr-ps-module-lib.git

# Navigate to module directory
cd zrr-ps-module-lib/utility/ZRR.Terraform.Wrapper

# Import for development
Import-Module .\ZRR.Terraform.Wrapper.psd1 -Force

# Run tests
Invoke-Pester .\Tests\ -CodeCoverage .\Public\*.ps1
```

## License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

## Support

For support and questions:

- **Documentation**: https://docs.zealousrock.dev/powershell/ZRR.Terraform.Wrapper
- **Issues**: https://github.com/zealous-rock-research/zrr-ps-module-lib/issues
- **Discussions**: https://github.com/zealous-rock-research/zrr-ps-module-lib/discussions

## Changelog

### Version 0.1.0 (Initial Release)

#### Features
- Complete Terraform command wrapper functions
- Advanced state management capabilities
- Workspace management and switching
- Automated backup and restore functionality
- Compliance testing integration
- Comprehensive error handling and logging
- Support for Terraform 0.12+ and 1.x
- Cross-platform compatibility (Windows, Linux, macOS)
- Pipeline-friendly output formatting
- Enterprise-grade security practices

#### Functions Added
- `Invoke-TerraformInit` - Initialize working directory
- `Invoke-TerraformPlan` - Create execution plans
- `Invoke-TerraformApply` - Apply infrastructure changes
- `Invoke-TerraformDestroy` - Destroy infrastructure
- `Get-TerraformState` - State analysis and querying
- `Set-TerraformWorkspace` - Workspace management
- Plus 20+ additional utility functions

#### Requirements
- PowerShell 5.1 or higher
- Terraform 0.12 or higher installed
- Appropriate cloud provider credentials configured