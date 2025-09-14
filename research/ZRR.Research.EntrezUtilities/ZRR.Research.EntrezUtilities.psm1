#Requires -Version 5.1

<#
.SYNOPSIS
    ZRR.Research.EntrezUtilities - NCBI Entrez Programming Utilities PowerShell Module

.DESCRIPTION
    Enterprise-grade PowerShell module for accessing NCBI Entrez Programming Utilities (E-utilities).
    Provides comprehensive API coverage for scientific research data retrieval with advanced logging,
    error handling, session management, and batch processing capabilities.

.NOTES
    Module: ZRR.Research.EntrezUtilities
    Author: Zealous Rock Research
    Version: 1.0.0
    Generated: 2025-09-13
#>

# Get the module path
$ModulePath = $PSScriptRoot

# Import configuration and logging
$Script:ModuleConfig = @{
    ModuleName = 'ZRR.Research.EntrezUtilities'
    ModulePath = $ModulePath
    LogLevel = 'Host'
    BaseUrl = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/'
    DefaultRetMax = 500
    MaxRetMax = 10000
    DefaultDatabase = 'pubmed'
    SessionData = @{
        WebEnv = $null
        QueryKey = $null
        Count = 0
        Database = $null
    }
    SupportedDatabases = @(
        'pubmed', 'pmc', 'protein', 'nucleotide', 'nuccore', 'nucgss', 'nucest',
        'gene', 'genome', 'biosystems', 'blastdbinfo', 'books', 'cdd', 'clinvar',
        'gap', 'gapplus', 'dbvar', 'epigenomics', 'gds', 'geoprofiles', 'homologene',
        'medgen', 'mesh', 'ncbisearch', 'nlmcatalog', 'omim', 'orgtrack', 'pmc',
        'popset', 'probe', 'proteinclusters', 'pcassay', 'biosample', 'bioproject',
        'pccompound', 'pcsubstance', 'seqannot', 'snp', 'sra', 'structure', 'taxonomy',
        'toolkit', 'toolkitall', 'toolkitbookgh', 'unigene'
    )
}

# Initialize logging using PSFramework
try {
    Import-Module PSFramework -Force -ErrorAction Stop

    # Create logs directory if it doesn't exist
    $LogDirectory = Join-Path $ModulePath 'Logs'
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    # Configure file logging
    $LogPath = Join-Path $LogDirectory 'ZRR.Research.EntrezUtilities.log'
    Set-PSFLoggingProvider -Name logfile -FilePath $LogPath -Enabled $true

    Write-PSFMessage -Level Host -Message "Loading ZRR.Research.EntrezUtilities module..."
}
catch {
    Write-Warning "Failed to initialize PSFramework logging: $_"
    Write-Host "Loading ZRR.Research.EntrezUtilities module..." -ForegroundColor Green
}

# Import private functions first
$PrivateFunctions = Get-ChildItem -Path "$ModulePath\Private\*.ps1" -Recurse -ErrorAction SilentlyContinue
foreach ($Function in $PrivateFunctions) {
    try {
        Write-PSFMessage -Level Verbose -Message "Importing private function: $($Function.Name)"
        . $Function.FullName
    }
    catch {
        $ErrorMsg = "Failed to import private function $($Function.Name): $_"
        Write-PSFMessage -Level Error -Message $ErrorMsg
        throw $ErrorMsg
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
        $ErrorMsg = "Failed to import public function $($Function.Name): $_"
        Write-PSFMessage -Level Error -Message $ErrorMsg
        throw $ErrorMsg
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
        $ErrorMsg = "Failed to import class $($Class.Name): $_"
        Write-PSFMessage -Level Error -Message $ErrorMsg
        throw $ErrorMsg
    }
}

# Create aliases for backward compatibility
New-Alias -Name 'Search-Entrez' -Value 'Search-EntrezDatabase' -Force
New-Alias -Name 'Get-EntrezSummary' -Value 'Get-EntrezDocumentSummary' -Force
New-Alias -Name 'Get-EntrezData' -Value 'Get-EntrezDataRecord' -Force

# Module cleanup function
$OnRemove = {
    Write-PSFMessage -Level Host -Message "Unloading ZRR.Research.EntrezUtilities module..."

    # Clear session data
    if ($Script:ModuleConfig.SessionData) {
        $Script:ModuleConfig.SessionData.WebEnv = $null
        $Script:ModuleConfig.SessionData.QueryKey = $null
        $Script:ModuleConfig.SessionData.Count = 0
        $Script:ModuleConfig.SessionData.Database = $null
    }

    # Remove aliases
    Remove-Alias -Name 'Search-Entrez' -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name 'Get-EntrezSummary' -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name 'Get-EntrezData' -Force -ErrorAction SilentlyContinue
}

# Register cleanup
$ExecutionContext.SessionState.Module.OnRemove += $OnRemove

# Export public functions
Export-ModuleMember -Function $ExportFunctions -Alias @('Search-Entrez', 'Get-EntrezSummary', 'Get-EntrezData')

$LoadedFunctionCount = $ExportFunctions.Count
Write-PSFMessage -Level Host -Message "ZRR.Research.EntrezUtilities module loaded successfully. Functions: $LoadedFunctionCount"

# Display available functions for user
if ($LoadedFunctionCount -gt 0) {
    Write-PSFMessage -Level Host -Message "Available functions: $($ExportFunctions -join ', ')"
}