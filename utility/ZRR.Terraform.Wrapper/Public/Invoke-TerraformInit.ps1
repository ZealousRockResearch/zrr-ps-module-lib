function Invoke-TerraformInit {
    <#
    .SYNOPSIS
        Initializes a Terraform working directory with advanced configuration options

    .DESCRIPTION
        Initializes a Terraform configuration with support for backend configuration,
        plugin management, workspace selection, and comprehensive error handling.

    .PARAMETER Path
        The path to the Terraform configuration directory

    .PARAMETER Backend
        Enable or disable backend configuration during initialization

    .PARAMETER BackendConfig
        Hashtable of backend configuration key-value pairs

    .PARAMETER PluginDir
        Directory containing Terraform plugins

    .PARAMETER Upgrade
        Allow provider plugin upgrades during initialization

    .PARAMETER GetPlugins
        Download and install provider plugins

    .PARAMETER VerifyPlugins
        Verify downloaded plugins against checksums

    .PARAMETER Force
        Force initialization even if already initialized

    .PARAMETER Reconfigure
        Reconfigure the backend ignoring any saved configuration

    .PARAMETER MigrateState
        Migrate existing state when reconfiguring backend

    .PARAMETER LockTimeout
        Duration to retry state lock acquisition

    .PARAMETER Workspace
        Terraform workspace to select after initialization

    .PARAMETER AdditionalArgs
        Additional arguments to pass to terraform init

    .EXAMPLE
        Invoke-TerraformInit -Path "C:\terraform\project"

        Initializes a Terraform configuration with default settings

    .EXAMPLE
        Invoke-TerraformInit -Path ".\terraform" -Backend -BackendConfig @{
            bucket = "my-terraform-state"
            key = "prod/terraform.tfstate"
            region = "us-west-2"
        }

        Initializes with S3 backend configuration

    .EXAMPLE
        Invoke-TerraformInit -Path ".\terraform" -Upgrade -Force -Workspace "production"

        Forces initialization with plugin upgrades and selects production workspace

    .NOTES
        Author: Zealous Rock Research
        Module: ZRR.Terraform.Wrapper
        Requires: PowerShell 5.1+, Terraform 0.12+

    .LINK
        https://docs.zealousrock.dev/powershell/ZRR.Terraform.Wrapper/Invoke-TerraformInit
    #>
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
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
            Mandatory = $false,
            HelpMessage = "Enable backend configuration"
        )]
        [switch]$Backend = $true,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Backend configuration key-value pairs"
        )]
        [hashtable]$BackendConfig = @{},

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Directory containing Terraform plugins"
        )]
        [ValidateScript({
            if (-not $_ -or (Test-Path $_ -PathType Container)) { return $true }
            throw "Plugin directory '$_' does not exist"
        })]
        [string]$PluginDir,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Allow provider plugin upgrades"
        )]
        [switch]$Upgrade,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Download and install provider plugins"
        )]
        [switch]$GetPlugins = $true,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Verify downloaded plugins against checksums"
        )]
        [switch]$VerifyPlugins = $true,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Force initialization even if already initialized"
        )]
        [switch]$Force,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Reconfigure the backend ignoring saved configuration"
        )]
        [switch]$Reconfigure,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Migrate existing state when reconfiguring backend"
        )]
        [switch]$MigrateState,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Duration to retry state lock acquisition (e.g., '10m')"
        )]
        [ValidatePattern('^\d+[smh]$')]
        [string]$LockTimeout = '10m',

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Terraform workspace to select after initialization"
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Workspace,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Additional arguments to pass to terraform init"
        )]
        [string[]]$AdditionalArgs = @()
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Terraform initialization"

        # Validate prerequisites
        if (-not (Test-TerraformPrerequisites)) {
            throw "Terraform prerequisites validation failed"
        }

        $Results = @()
        $OriginalLocation = Get-Location
    }

    process {
        $AbsolutePath = Resolve-Path $Path -ErrorAction Stop
        Write-PSFMessage -Level Information -Message "Initializing Terraform in directory: $AbsolutePath"

        try {
            Set-Location $AbsolutePath

            # Build terraform init command
            $InitArgs = @('init')

            # Backend configuration
            if (-not $Backend) {
                $InitArgs += '-backend=false'
            }
            elseif ($BackendConfig.Count -gt 0) {
                foreach ($key in $BackendConfig.Keys) {
                    $InitArgs += "-backend-config=$key=$($BackendConfig[$key])"
                }
            }

            # Plugin management
            if ($PluginDir) {
                $InitArgs += "-plugin-dir=$PluginDir"
            }

            if ($Upgrade) {
                $InitArgs += '-upgrade'
            }

            if (-not $GetPlugins) {
                $InitArgs += '-get-plugins=false'
            }

            if (-not $VerifyPlugins) {
                $InitArgs += '-verify-plugins=false'
            }

            # Initialization options
            if ($Force) {
                $InitArgs += '-force-copy'
            }

            if ($Reconfigure) {
                $InitArgs += '-reconfigure'
            }

            if ($MigrateState) {
                $InitArgs += '-migrate-state'
            }

            # Lock timeout
            $InitArgs += "-lock-timeout=$LockTimeout"

            # Additional arguments
            if ($AdditionalArgs.Count -gt 0) {
                $InitArgs += $AdditionalArgs
            }

            # Execute terraform init
            if ($PSCmdlet.ShouldProcess($AbsolutePath, "terraform init $($InitArgs -join ' ')")) {
                Write-PSFMessage -Level Verbose -Message "Executing: terraform $($InitArgs -join ' ')"

                $StartTime = Get-Date
                $Output = & terraform @InitArgs 2>&1
                $EndTime = Get-Date
                $Duration = ($EndTime - $StartTime).TotalSeconds
                $ExitCode = $LASTEXITCODE

                # Process workspace selection if specified
                if ($Workspace -and $ExitCode -eq 0) {
                    Write-PSFMessage -Level Information -Message "Selecting workspace: $Workspace"
                    $WorkspaceResult = & terraform workspace select $Workspace 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-PSFMessage -Level Warning -Message "Workspace selection failed: $($WorkspaceResult -join "`n")"
                    }
                }

                $Result = [PSCustomObject]@{
                    PSTypeName = 'ZRR.Terraform.InitResult'
                    Path = $AbsolutePath
                    Success = ($ExitCode -eq 0)
                    ExitCode = $ExitCode
                    Output = $Output -join "`n"
                    Duration = [math]::Round($Duration, 2)
                    Timestamp = $StartTime
                    BackendConfigured = $Backend
                    WorkspaceSelected = if ($Workspace) { $Workspace } else { $null }
                    PluginsUpgraded = $Upgrade.IsPresent
                }

                $Results += $Result

                if ($ExitCode -eq 0) {
                    Write-PSFMessage -Level Information -Message "Terraform initialization completed successfully in $($Duration)s"
                }
                else {
                    Write-PSFMessage -Level Error -Message "Terraform initialization failed with exit code $ExitCode"
                    Write-PSFMessage -Level Error -Message "Output: $($Output -join "`n")"
                }
            }
        }
        catch {
            Write-PSFMessage -Level Error -Message "Failed to initialize Terraform: $_"

            $ErrorResult = [PSCustomObject]@{
                PSTypeName = 'ZRR.Terraform.InitResult'
                Path = $AbsolutePath
                Success = $false
                ExitCode = -1
                Output = $_.Exception.Message
                Duration = 0
                Timestamp = Get-Date
                BackendConfigured = $false
                WorkspaceSelected = $null
                PluginsUpgraded = $false
                Error = $_.Exception.Message
            }

            $Results += $ErrorResult
        }
        finally {
            Set-Location $OriginalLocation
        }
    }

    end {
        Write-PSFMessage -Level Verbose -Message "Terraform initialization completed. Processed $($Results.Count) configurations"
        return $Results
    }
}