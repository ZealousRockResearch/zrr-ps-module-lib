function Get-TerraformState {
    <#
    .SYNOPSIS
        Retrieves and analyzes Terraform state information with advanced filtering

    .DESCRIPTION
        Provides comprehensive Terraform state analysis including resource inventory,
        provider information, output values, and state file health checks.

    .PARAMETER Path
        The path to the Terraform configuration directory

    .PARAMETER Resource
        Specific resource address to query

    .PARAMETER OutputName
        Specific output value to retrieve

    .PARAMETER ShowSensitive
        Include sensitive values in output (use with caution)

    .PARAMETER Format
        Output format: Table, List, JSON, or Raw

    .PARAMETER IncludeProviders
        Include provider information in the analysis

    .PARAMETER HealthCheck
        Perform state file health and consistency checks

    .PARAMETER Detailed
        Include detailed resource attributes and metadata

    .EXAMPLE
        Get-TerraformState -Path "C:\terraform\project"

        Retrieves basic state information for the project

    .EXAMPLE
        Get-TerraformState -Path ".\terraform" -Resource "aws_instance.web" -Detailed

        Gets detailed information for a specific resource

    .EXAMPLE
        Get-TerraformState -Path ".\terraform" -Format JSON -HealthCheck

        Outputs state in JSON format with health check

    .NOTES
        Author: Zealous Rock Research
        Module: ZRR.Terraform.Wrapper
        Requires: PowerShell 5.1+, Terraform 0.12+

    .LINK
        https://docs.zealousrock.dev/powershell/ZRR.Terraform.Wrapper/Get-TerraformState
    #>
    [CmdletBinding(DefaultParameterSetName = 'General')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0,
            HelpMessage = "Path to the Terraform configuration directory"
        )]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (Test-Path $_ -PathType Container) { return $true }
            throw "Directory path '$_' does not exist"
        })]
        [string]$Path = (Get-Location),

        [Parameter(
            ParameterSetName = 'Resource',
            Mandatory = $false,
            HelpMessage = "Specific resource address to query"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Resource,

        [Parameter(
            ParameterSetName = 'Output',
            Mandatory = $false,
            HelpMessage = "Specific output value to retrieve"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$OutputName,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Include sensitive values in output"
        )]
        [switch]$ShowSensitive,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Output format"
        )]
        [ValidateSet('Table', 'List', 'JSON', 'Raw')]
        [string]$Format = 'Table',

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Include provider information"
        )]
        [switch]$IncludeProviders,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Perform state health checks"
        )]
        [switch]$HealthCheck,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Include detailed resource information"
        )]
        [switch]$Detailed
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Terraform state retrieval"

        if (-not (Test-TerraformPrerequisites)) {
            throw "Terraform prerequisites validation failed"
        }

        $Results = @()
        $OriginalLocation = Get-Location
    }

    process {
        $AbsolutePath = Resolve-Path $Path -ErrorAction Stop
        Write-PSFMessage -Level Information -Message "Retrieving Terraform state from: $AbsolutePath"

        try {
            Set-Location $AbsolutePath

            # Check if state file exists
            $StateFile = Join-Path $AbsolutePath "terraform.tfstate"
            if (-not (Test-Path $StateFile)) {
                Write-PSFMessage -Level Warning -Message "No state file found. Run 'terraform init' and 'terraform apply' first."
                return [PSCustomObject]@{
                    PSTypeName = 'ZRR.Terraform.StateResult'
                    Path = $AbsolutePath
                    StateExists = $false
                    Resources = @()
                    Outputs = @{}
                    Providers = @()
                    ResourceCount = 0
                    Message = "No state file found"
                }
            }

            # Retrieve state information based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'Resource' {
                    Write-PSFMessage -Level Information -Message "Querying specific resource: $Resource"
                    $StateOutput = & terraform state show $Resource 2>&1
                    $ExitCode = $LASTEXITCODE
                }
                'Output' {
                    Write-PSFMessage -Level Information -Message "Querying output: $OutputName"
                    $StateArgs = @('output')
                    if ($ShowSensitive) { $StateArgs += '-raw' }
                    $StateArgs += $OutputName
                    $StateOutput = & terraform @StateArgs 2>&1
                    $ExitCode = $LASTEXITCODE
                }
                default {
                    Write-PSFMessage -Level Information -Message "Retrieving general state information"
                    # Get state list
                    $StateListOutput = & terraform state list 2>&1
                    $StateListExitCode = $LASTEXITCODE

                    # Get outputs
                    $OutputsArgs = @('output', '-json')
                    if ($ShowSensitive) { $OutputsArgs += '-sensitive' }
                    $OutputsJson = & terraform @OutputsArgs 2>&1
                    $OutputsExitCode = $LASTEXITCODE

                    $StateOutput = $StateListOutput
                    $ExitCode = $StateListExitCode
                }
            }

            if ($ExitCode -eq 0) {
                # Parse state information
                $Resources = @()
                $Outputs = @{}
                $Providers = @()

                if ($PSCmdlet.ParameterSetName -eq 'General') {
                    # Parse resource list
                    if ($StateListExitCode -eq 0) {
                        $Resources = $StateListOutput | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
                            $ResourceAddress = $_.Trim()
                            $ResourceParts = $ResourceAddress -split '\.'

                            [PSCustomObject]@{
                                Address = $ResourceAddress
                                Type = if ($ResourceParts.Count -ge 2) { $ResourceParts[0] } else { 'Unknown' }
                                Name = if ($ResourceParts.Count -ge 2) { $ResourceParts[1] } else { $ResourceAddress }
                                Provider = if ($ResourceParts[0] -match '^([^_]+)_') { $Matches[1] } else { 'Unknown' }
                            }
                        }

                        # Get detailed resource information if requested
                        if ($Detailed -and $Resources.Count -gt 0) {
                            Write-PSFMessage -Level Information -Message "Retrieving detailed resource information..."
                            foreach ($Resource in $Resources) {
                                try {
                                    $ResourceDetails = & terraform state show $Resource.Address 2>&1
                                    if ($LASTEXITCODE -eq 0) {
                                        $Resource | Add-Member -MemberType NoteProperty -Name 'Details' -Value ($ResourceDetails -join "`n")
                                    }
                                }
                                catch {
                                    Write-PSFMessage -Level Warning -Message "Failed to get details for resource: $($Resource.Address)"
                                }
                            }
                        }
                    }

                    # Parse outputs
                    if ($OutputsExitCode -eq 0 -and $OutputsJson) {
                        try {
                            $OutputsHash = $OutputsJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                            $Outputs = $OutputsHash
                        }
                        catch {
                            Write-PSFMessage -Level Warning -Message "Failed to parse outputs JSON: $_"
                        }
                    }

                    # Get provider information if requested
                    if ($IncludeProviders) {
                        Write-PSFMessage -Level Information -Message "Retrieving provider information..."
                        $ProvidersOutput = & terraform providers 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $Providers = $ProvidersOutput | Where-Object { $_ -match '└─|├─' } | ForEach-Object {
                                $ProviderLine = $_ -replace '└─|├─|\s+', ''
                                if ($ProviderLine -match '^(.+?)\s+(.+)$') {
                                    [PSCustomObject]@{
                                        Name = $Matches[1]
                                        Version = $Matches[2]
                                    }
                                }
                            }
                        }
                    }
                }

                # Perform health check if requested
                $HealthCheckResults = $null
                if ($HealthCheck) {
                    Write-PSFMessage -Level Information -Message "Performing state health check..."
                    $HealthCheckResults = @{
                        StateFileSize = (Get-Item $StateFile).Length
                        LastModified = (Get-Item $StateFile).LastWriteTime
                        IsValid = $true
                        Issues = @()
                    }

                    # Check for common issues
                    if ($Resources.Count -eq 0 -and (Test-Path $StateFile)) {
                        $HealthCheckResults.Issues += "State file exists but contains no resources"
                        $HealthCheckResults.IsValid = $false
                    }

                    # Validate state file format
                    try {
                        $StateContent = Get-Content $StateFile -Raw | ConvertFrom-Json
                        if (-not $StateContent.version) {
                            $HealthCheckResults.Issues += "State file missing version information"
                        }
                    }
                    catch {
                        $HealthCheckResults.Issues += "State file is not valid JSON: $_"
                        $HealthCheckResults.IsValid = $false
                    }
                }

                # Create result object
                $Result = [PSCustomObject]@{
                    PSTypeName = 'ZRR.Terraform.StateResult'
                    Path = $AbsolutePath
                    StateExists = $true
                    Resources = $Resources
                    ResourceCount = $Resources.Count
                    Outputs = $Outputs
                    Providers = $Providers
                    HealthCheck = $HealthCheckResults
                    Timestamp = Get-Date
                    Format = $Format
                }

                # Handle specific resource query
                if ($PSCmdlet.ParameterSetName -eq 'Resource') {
                    $Result | Add-Member -MemberType NoteProperty -Name 'ResourceDetails' -Value ($StateOutput -join "`n")
                }

                # Handle specific output query
                if ($PSCmdlet.ParameterSetName -eq 'Output') {
                    $Result | Add-Member -MemberType NoteProperty -Name 'OutputValue' -Value ($StateOutput -join "`n")
                }

                $Results += $Result

                Write-PSFMessage -Level Information -Message "Successfully retrieved state information. Found $($Resources.Count) resources."
            }
            else {
                Write-PSFMessage -Level Error -Message "Failed to retrieve state information. Exit code: $ExitCode"
                Write-PSFMessage -Level Error -Message "Output: $($StateOutput -join "`n")"

                $ErrorResult = [PSCustomObject]@{
                    PSTypeName = 'ZRR.Terraform.StateResult'
                    Path = $AbsolutePath
                    StateExists = (Test-Path $StateFile)
                    Resources = @()
                    ResourceCount = 0
                    Outputs = @{}
                    Providers = @()
                    HealthCheck = $null
                    Timestamp = Get-Date
                    Error = $StateOutput -join "`n"
                }

                $Results += $ErrorResult
            }
        }
        catch {
            Write-PSFMessage -Level Error -Message "Failed to retrieve Terraform state: $_"

            $ErrorResult = [PSCustomObject]@{
                PSTypeName = 'ZRR.Terraform.StateResult'
                Path = $AbsolutePath
                StateExists = $false
                Resources = @()
                ResourceCount = 0
                Outputs = @{}
                Providers = @()
                HealthCheck = $null
                Timestamp = Get-Date
                Error = $_.Exception.Message
            }

            $Results += $ErrorResult
        }
        finally {
            Set-Location $OriginalLocation
        }
    }

    end {
        Write-PSFMessage -Level Verbose -Message "Terraform state retrieval completed. Processed $($Results.Count) configurations"
        return $Results
    }
}