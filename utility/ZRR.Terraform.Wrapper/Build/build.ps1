<#
.SYNOPSIS
    Build script for ZRR.Terraform.Wrapper PowerShell module

.DESCRIPTION
    Comprehensive build script that handles:
    - Module validation and testing
    - Documentation generation
    - Code analysis and security scanning
    - Build artifact creation
    - Version management
    - Publishing preparation

.PARAMETER Task
    The build task to execute

.PARAMETER Version
    Override version for the build

.PARAMETER Configuration
    Build configuration (Debug, Release)

.PARAMETER OutputPath
    Output directory for build artifacts

.PARAMETER SkipTests
    Skip running tests during build

.PARAMETER Force
    Force build even if tests fail

.EXAMPLE
    .\build.ps1 -Task Build

    Performs a complete build with default settings

.EXAMPLE
    .\build.ps1 -Task Test -Configuration Debug

    Runs tests in debug configuration

.EXAMPLE
    .\build.ps1 -Task Publish -Version "1.0.1"

    Prepares module for publishing with specific version

.NOTES
    This script supports the following tasks:
    - Clean: Remove build artifacts
    - Restore: Install dependencies
    - Build: Compile and prepare module
    - Test: Run all tests
    - Package: Create distribution package
    - Publish: Prepare for PowerShell Gallery
    - All: Execute all tasks in sequence
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Clean', 'Restore', 'Build', 'Test', 'Package', 'Publish', 'All')]
    [string]$Task = 'All',

    [Parameter()]
    [string]$Version,

    [Parameter()]
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [Parameter()]
    [string]$OutputPath = './build',

    [Parameter()]
    [switch]$SkipTests,

    [Parameter()]
    [switch]$Force
)

# Build configuration
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Module information
$ModuleName = 'ZRR.Terraform.Wrapper'
$ModulePath = Split-Path $PSScriptRoot -Parent
$ManifestPath = Join-Path $ModulePath "$ModuleName.psd1"
$BuildPath = Resolve-Path $OutputPath -ErrorAction SilentlyContinue

# Create output directory if it doesn't exist
if (-not $BuildPath) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    $BuildPath = Resolve-Path $OutputPath
}

# Initialize build variables
$BuildVersion = $null
$BuildDate = Get-Date
$BuildLog = @()

function Write-BuildLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $Timestamp = Get-Date -Format 'HH:mm:ss'
    $LogEntry = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        'Info' { Write-Information $LogEntry }
        'Warning' { Write-Warning $LogEntry }
        'Error' { Write-Error $LogEntry }
        'Success' { Write-Host $LogEntry -ForegroundColor Green }
    }

    $Script:BuildLog += $LogEntry
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()

    Write-BuildLog "Checking build prerequisites..."

    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell 5.0 or higher is required"
    }
    Write-BuildLog "✓ PowerShell $($PSVersionTable.PSVersion)"

    # Check module manifest
    if (-not (Test-Path $ManifestPath)) {
        throw "Module manifest not found: $ManifestPath"
    }
    Write-BuildLog "✓ Module manifest found"

    # Check required modules
    $RequiredModules = @('Pester', 'PSScriptAnalyzer', 'PlatyPS')
    foreach ($Module in $RequiredModules) {
        if (-not (Get-Module $Module -ListAvailable)) {
            Write-BuildLog "Installing required module: $Module" -Level Warning
            Install-Module $Module -Force -Scope CurrentUser
        }
        Write-BuildLog "✓ $Module available"
    }

    Write-BuildLog "Prerequisites check completed" -Level Success
}

function Invoke-Clean {
    [CmdletBinding()]
    param()

    Write-BuildLog "Cleaning build artifacts..."

    $ItemsToClean = @(
        "$BuildPath\*",
        "$ModulePath\Logs\*.log",
        "$ModulePath\*.nupkg",
        "$ModulePath\TestResults.xml",
        "$ModulePath\coverage.xml"
    )

    foreach ($Item in $ItemsToClean) {
        if (Test-Path $Item) {
            Remove-Item $Item -Recurse -Force
            Write-BuildLog "Removed: $Item"
        }
    }

    Write-BuildLog "Clean completed" -Level Success
}

function Invoke-Restore {
    [CmdletBinding()]
    param()

    Write-BuildLog "Restoring dependencies..."

    # Set PSGallery as trusted
    if ((Get-PSRepository PSGallery).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Write-BuildLog "Set PSGallery as trusted repository"
    }

    # Install/Update required modules
    $Dependencies = @(
        @{ Name = 'Pester'; MinimumVersion = '5.0.0' },
        @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.21.0' },
        @{ Name = 'PlatyPS'; MinimumVersion = '0.14.0' }
    )

    foreach ($Dependency in $Dependencies) {
        $Module = Get-Module $Dependency.Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

        if (-not $Module -or $Module.Version -lt $Dependency.MinimumVersion) {
            Write-BuildLog "Installing $($Dependency.Name) >= $($Dependency.MinimumVersion)"
            Install-Module $Dependency.Name -Force -Scope CurrentUser -AllowClobber
        } else {
            Write-BuildLog "✓ $($Dependency.Name) $($Module.Version) is current"
        }
    }

    Write-BuildLog "Restore completed" -Level Success
}

function Invoke-ModuleBuild {
    [CmdletBinding()]
    param()

    Write-BuildLog "Building module..."

    # Import and validate module
    try {
        Import-Module $ManifestPath -Force -ErrorAction Stop
        $Module = Get-Module $ModuleName
        Write-BuildLog "✓ Module imported successfully"
        Write-BuildLog "  Name: $($Module.Name)"
        Write-BuildLog "  Version: $($Module.Version)"
        Write-BuildLog "  Functions: $($Module.ExportedFunctions.Count)"
        Write-BuildLog "  Aliases: $($Module.ExportedAliases.Count)"

        $Script:BuildVersion = $Module.Version
    }
    catch {
        throw "Failed to import module: $_"
    }

    # Validate module manifest
    try {
        $Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        Write-BuildLog "✓ Module manifest is valid"
    }
    catch {
        throw "Module manifest validation failed: $_"
    }

    # Run PSScriptAnalyzer
    Write-BuildLog "Running code analysis..."
    $AnalysisResults = Invoke-ScriptAnalyzer -Path $ModulePath -Recurse -Settings PSGallery

    if ($AnalysisResults) {
        $ErrorCount = ($AnalysisResults | Where-Object Severity -eq 'Error').Count
        $WarningCount = ($AnalysisResults | Where-Object Severity -eq 'Warning').Count
        $InfoCount = ($AnalysisResults | Where-Object Severity -eq 'Information').Count

        Write-BuildLog "Analysis results: $ErrorCount errors, $WarningCount warnings, $InfoCount info"

        if ($ErrorCount -gt 0) {
            $AnalysisResults | Where-Object Severity -eq 'Error' | ForEach-Object {
                Write-BuildLog "ERROR: $($_.RuleName) in $($_.ScriptName):$($_.Line) - $($_.Message)" -Level Error
            }

            if (-not $Force) {
                throw "Code analysis found $ErrorCount error(s). Use -Force to continue."
            }
        }

        if ($WarningCount -gt 0 -and $Configuration -eq 'Release') {
            $AnalysisResults | Where-Object Severity -eq 'Warning' | ForEach-Object {
                Write-BuildLog "WARNING: $($_.RuleName) in $($_.ScriptName):$($_.Line) - $($_.Message)" -Level Warning
            }
        }
    } else {
        Write-BuildLog "✓ No analysis issues found" -Level Success
    }

    # Generate documentation
    if ($Configuration -eq 'Release') {
        Write-BuildLog "Generating documentation..."
        try {
            $DocsPath = Join-Path $ModulePath 'Docs/Functions'
            if (-not (Test-Path $DocsPath)) {
                New-Item -Path $DocsPath -ItemType Directory -Force | Out-Null
            }

            New-MarkdownHelp -Module $ModuleName -OutputFolder $DocsPath -Force | Out-Null
            Write-BuildLog "✓ Function documentation generated"
        }
        catch {
            Write-BuildLog "Documentation generation failed: $_" -Level Warning
        }
    }

    Write-BuildLog "Build completed" -Level Success
}

function Invoke-ModuleTest {
    [CmdletBinding()]
    param()

    if ($SkipTests) {
        Write-BuildLog "Skipping tests as requested" -Level Warning
        return
    }

    Write-BuildLog "Running tests..."

    $TestPath = Join-Path $ModulePath 'Tests'
    if (-not (Test-Path $TestPath)) {
        Write-BuildLog "No tests found in $TestPath" -Level Warning
        return
    }

    # Configure Pester
    $PesterConfig = New-PesterConfiguration
    $PesterConfig.Run.Path = $TestPath
    $PesterConfig.Run.Exit = $false
    $PesterConfig.CodeCoverage.Enabled = $true
    $PesterConfig.CodeCoverage.Path = @(
        Join-Path $ModulePath 'Public/*.ps1',
        Join-Path $ModulePath 'Private/*.ps1'
    )
    $PesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'
    $PesterConfig.CodeCoverage.OutputPath = Join-Path $ModulePath 'coverage.xml'
    $PesterConfig.TestResult.Enabled = $true
    $PesterConfig.TestResult.OutputFormat = 'NUnitXml'
    $PesterConfig.TestResult.OutputPath = Join-Path $ModulePath 'TestResults.xml'
    $PesterConfig.Output.Verbosity = 'Detailed'

    # Run tests
    $TestResults = Invoke-Pester -Configuration $PesterConfig

    # Report results
    Write-BuildLog "Test Results:"
    Write-BuildLog "  Total: $($TestResults.TotalCount)"
    Write-BuildLog "  Passed: $($TestResults.PassedCount)" -Level Success
    Write-BuildLog "  Failed: $($TestResults.FailedCount)" -Level $(if ($TestResults.FailedCount -gt 0) { 'Error' } else { 'Info' })
    Write-BuildLog "  Skipped: $($TestResults.SkippedCount)" -Level $(if ($TestResults.SkippedCount -gt 0) { 'Warning' } else { 'Info' })

    if ($TestResults.CodeCoverage) {
        $Coverage = [math]::Round($TestResults.CodeCoverage.CoveragePercent, 2)
        Write-BuildLog "  Coverage: $Coverage%" -Level $(if ($Coverage -ge 80) { 'Success' } else { 'Warning' })
    }

    # Fail build if tests failed
    if ($TestResults.FailedCount -gt 0) {
        if ($Force) {
            Write-BuildLog "Tests failed but continuing due to -Force" -Level Warning
        } else {
            throw "Tests failed. $($TestResults.FailedCount) test(s) failed."
        }
    } else {
        Write-BuildLog "All tests passed" -Level Success
    }
}

function Invoke-Package {
    [CmdletBinding()]
    param()

    Write-BuildLog "Creating package..."

    $PackagePath = Join-Path $BuildPath $ModuleName
    if (Test-Path $PackagePath) {
        Remove-Item $PackagePath -Recurse -Force
    }
    New-Item -Path $PackagePath -ItemType Directory -Force | Out-Null

    # Files and directories to include in package
    $ItemsToPackage = @(
        "$ModuleName.psd1",
        "$ModuleName.psm1",
        'Public',
        'Private',
        'Classes',
        'Data',
        'Docs',
        'Examples'
    )

    foreach ($Item in $ItemsToPackage) {
        $SourcePath = Join-Path $ModulePath $Item
        if (Test-Path $SourcePath) {
            $DestPath = Join-Path $PackagePath $Item
            Copy-Item -Path $SourcePath -Destination $DestPath -Recurse -Force
            Write-BuildLog "Packaged: $Item"
        }
    }

    # Update version in manifest if specified
    if ($Version) {
        $ManifestDestPath = Join-Path $PackagePath "$ModuleName.psd1"
        $ManifestContent = Get-Content $ManifestDestPath -Raw
        $ManifestContent = $ManifestContent -replace "ModuleVersion\s*=\s*['\"][^'\"]*['\"]", "ModuleVersion = '$Version'"
        Set-Content -Path $ManifestDestPath -Value $ManifestContent
        Write-BuildLog "Updated version to $Version in packaged manifest"
        $Script:BuildVersion = $Version
    }

    # Create build info file
    $BuildInfo = @{
        ModuleName = $ModuleName
        Version = $Script:BuildVersion
        BuildDate = $BuildDate
        Configuration = $Configuration
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        BuildMachine = $env:COMPUTERNAME
        BuildUser = $env:USERNAME
    }

    $BuildInfoPath = Join-Path $PackagePath 'BuildInfo.json'
    $BuildInfo | ConvertTo-Json -Depth 3 | Set-Content -Path $BuildInfoPath
    Write-BuildLog "Created build info: $BuildInfoPath"

    # Create archive
    $ArchivePath = Join-Path $BuildPath "$ModuleName-$($Script:BuildVersion).zip"
    if (Test-Path $ArchivePath) {
        Remove-Item $ArchivePath -Force
    }

    Compress-Archive -Path $PackagePath -DestinationPath $ArchivePath -Force
    Write-BuildLog "Created archive: $ArchivePath"

    Write-BuildLog "Package created successfully" -Level Success
    return @{
        PackagePath = $PackagePath
        ArchivePath = $ArchivePath
        Version = $Script:BuildVersion
    }
}

function Invoke-PublishPrep {
    [CmdletBinding()]
    param()

    Write-BuildLog "Preparing for publishing..."

    # Validate for publishing
    $PackageResult = Invoke-Package

    # Run publish validation
    try {
        $ManifestPath = Join-Path $PackageResult.PackagePath "$ModuleName.psd1"
        $Manifest = Test-ModuleManifest -Path $ManifestPath

        # Check required metadata for PowerShell Gallery
        $RequiredFields = @('Author', 'Description', 'ProjectUri', 'Tags')
        foreach ($Field in $RequiredFields) {
            if (-not $Manifest.$Field) {
                Write-BuildLog "Missing required field for publishing: $Field" -Level Warning
            } else {
                Write-BuildLog "✓ $Field is present"
            }
        }

        # Validate tags count (PowerShell Gallery limit)
        if ($Manifest.Tags -and $Manifest.Tags.Count -gt 10) {
            throw "Too many tags for PowerShell Gallery. Maximum is 10, found $($Manifest.Tags.Count)"
        }

        Write-BuildLog "✓ Module is ready for publishing"
        Write-BuildLog "  Version: $($Manifest.Version)"
        Write-BuildLog "  Author: $($Manifest.Author)"
        Write-BuildLog "  Tags: $($Manifest.Tags -join ', ')"

        # Create publish script
        $PublishScript = @"
# Publish script for $ModuleName
# Generated: $(Get-Date)

# To publish to PowerShell Gallery:
# Publish-Module -Path '$($PackageResult.PackagePath)' -NuGetApiKey `$ApiKey -Repository PSGallery

# To test publishing:
# Publish-Module -Path '$($PackageResult.PackagePath)' -WhatIf -Repository PSGallery

Write-Host "Publishing $ModuleName version $($Manifest.Version)..."
Write-Host "Package path: $($PackageResult.PackagePath)"
Write-Host ""
Write-Host "To publish, run:"
Write-Host "  Publish-Module -Path '$($PackageResult.PackagePath)' -NuGetApiKey `$ApiKey"
Write-Host ""
"@

        $PublishScriptPath = Join-Path $BuildPath 'publish.ps1'
        Set-Content -Path $PublishScriptPath -Value $PublishScript
        Write-BuildLog "Created publish script: $PublishScriptPath"

        Write-BuildLog "Publish preparation completed" -Level Success
    }
    catch {
        throw "Publish validation failed: $_"
    }
}

function Save-BuildLog {
    [CmdletBinding()]
    param()

    $LogPath = Join-Path $BuildPath "build-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $Script:BuildLog | Set-Content -Path $LogPath
    Write-BuildLog "Build log saved to: $LogPath"
}

# Main build execution
try {
    Write-Host "=== ZRR.Terraform.Wrapper Build Script ===" -ForegroundColor Cyan
    Write-Host "Task: $Task" -ForegroundColor White
    Write-Host "Configuration: $Configuration" -ForegroundColor White
    Write-Host "Output: $BuildPath" -ForegroundColor White
    Write-Host "Module: $ModulePath" -ForegroundColor White
    Write-Host ""

    $StartTime = Get-Date

    # Execute tasks
    switch ($Task) {
        'Clean' {
            Test-Prerequisites
            Invoke-Clean
        }
        'Restore' {
            Test-Prerequisites
            Invoke-Restore
        }
        'Build' {
            Test-Prerequisites
            Invoke-ModuleBuild
        }
        'Test' {
            Test-Prerequisites
            Import-Module $ManifestPath -Force
            Invoke-ModuleTest
        }
        'Package' {
            Test-Prerequisites
            Invoke-ModuleBuild
            Invoke-ModuleTest
            Invoke-Package | Out-Null
        }
        'Publish' {
            Test-Prerequisites
            Invoke-ModuleBuild
            Invoke-ModuleTest
            Invoke-PublishPrep
        }
        'All' {
            Test-Prerequisites
            Invoke-Clean
            Invoke-Restore
            Invoke-ModuleBuild
            Invoke-ModuleTest
            Invoke-PublishPrep
        }
    }

    $Duration = ((Get-Date) - $StartTime).TotalSeconds
    Write-BuildLog "Build completed successfully in $([math]::Round($Duration, 2)) seconds" -Level Success

    Save-BuildLog
}
catch {
    $Duration = ((Get-Date) - $StartTime).TotalSeconds
    Write-BuildLog "Build failed after $([math]::Round($Duration, 2)) seconds: $_" -Level Error

    Save-BuildLog
    throw
}
finally {
    # Cleanup
    Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
}