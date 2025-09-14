function Invoke-TerraformPlan {
    <#
    .SYNOPSIS
        Executes Terraform plan operation with comprehensive analysis and validation

    .DESCRIPTION
        Executes a Terraform plan with enterprise features including:
        - Resource change analysis and impact assessment
        - Cost estimation integration
        - Security compliance validation
        - Drift detection and reporting
        - Plan file management and storage
        - Parallel execution optimization

    .PARAMETER Path
        The path to the Terraform configuration directory

    .PARAMETER PlanFile
        Path to save the plan file for later apply operations

    .PARAMETER Target
        Specific resources to target for planning

    .PARAMETER Variables
        Terraform variables as hashtable or file path

    .PARAMETER VarFile
        Path to Terraform variables file (.tfvars)

    .PARAMETER Destroy
        Generate a destroy plan instead of create/update

    .PARAMETER Detailed
        Include detailed analysis in the output

    .EXAMPLE
        Invoke-TerraformPlan -Path "./infrastructure" -PlanFile "production.tfplan"
        Creates a plan file for production infrastructure

    .EXAMPLE
        Invoke-TerraformPlan -Path "./infrastructure" -Variables @{environment='dev'} -Detailed
        Creates a detailed plan with development variables

    .NOTES
        Author: Zealous Rock Research
        Module: ZRR.Terraform.Wrapper
        Requires: PowerShell 5.1+, Terraform CLI

    .LINK
        https://docs.zealousrock.dev/powershell/ZRR.Terraform.Wrapper/Invoke-TerraformPlan
    #>
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
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
            HelpMessage = "Path to save the plan file"
        )]
        [ValidateNotNullOrEmpty()]
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
            HelpMessage = "Generate a destroy plan"
        )]
        [switch]$Destroy,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Include detailed analysis in output"
        )]
        [switch]$Detailed
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Invoke-TerraformPlan function"

        # Validate prerequisites
        try {
            Test-TerraformPrerequisites
        }
        catch {
            Write-PSFMessage -Level Error -Message "Prerequisites validation failed: $_"
            throw
        }
    }

    process {
        Write-PSFMessage -Level Information -Message "Executing Terraform plan for path: $Path"

        try {
            $AbsolutePath = Resolve-Path -Path $Path -ErrorAction Stop

            if ($PSCmdlet.ShouldProcess($AbsolutePath.Path, "Execute Terraform plan")) {
                $StartTime = Get-Date

                # Build terraform plan command
                $PlanArgs = @('plan', '-input=false', '-no-color')

                # Add plan file output
                if ($PlanFile) {
                    $PlanFilePath = Join-Path -Path $AbsolutePath.Path -ChildPath $PlanFile
                    $PlanArgs += "-out=`"$PlanFilePath`""
                    Write-PSFMessage -Level Information -Message "Plan will be saved to: $PlanFilePath"
                }

                # Add destroy flag
                if ($Destroy) {
                    $PlanArgs += '-destroy'
                    Write-PSFMessage -Level Information -Message "Generating destroy plan"
                }

                # Add targets
                if ($Target) {
                    foreach ($TargetResource in $Target) {
                        $PlanArgs += "-target=$TargetResource"
                    }
                    Write-PSFMessage -Level Information -Message "Targeting resources: $($Target -join ', ')"
                }

                # Add variables file
                if ($VarFile) {
                    $VarFilePath = Resolve-Path -Path $VarFile -ErrorAction Stop
                    $PlanArgs += "-var-file=`"$($VarFilePath.Path)`""
                    Write-PSFMessage -Level Information -Message "Using variables file: $($VarFilePath.Path)"
                }

                # Add individual variables
                if ($Variables) {
                    foreach ($VarPair in $Variables.GetEnumerator()) {
                        $VarString = "$($VarPair.Key)=$($VarPair.Value)"
                        $PlanArgs += "-var=$VarString"
                    }
                    Write-PSFMessage -Level Verbose -Message "Added $($Variables.Count) variables"
                }

                # Execute terraform plan
                Write-PSFMessage -Level Information -Message "Executing: terraform $($PlanArgs -join ' ')"
                $PlanResult = Invoke-TerraformCommand -Command $PlanArgs -WorkingDirectory $AbsolutePath.Path

                # Parse and analyze plan output
                $PlanAnalysis = ConvertFrom-TerraformPlanOutput -PlanOutput $PlanResult.StandardOutput -Detailed:$Detailed

                $Result = [PSCustomObject]@{
                    Path = $AbsolutePath.Path
                    PlanFile = $PlanFile
                    Success = $PlanResult.ExitCode -eq 0
                    ExitCode = $PlanResult.ExitCode
                    ExecutionTime = (Get-Date) - $StartTime
                    ResourceChanges = $PlanAnalysis.ResourceChanges
                    Summary = $PlanAnalysis.Summary
                    Warnings = $PlanAnalysis.Warnings
                    Errors = if ($PlanResult.StandardError) { @($PlanResult.StandardError) } else { @() }
                    RawOutput = $PlanResult.StandardOutput
                    Timestamp = Get-Date
                }

                if ($Detailed) {
                    $Result | Add-Member -MemberType NoteProperty -Name 'DetailedAnalysis' -Value $PlanAnalysis.DetailedAnalysis
                    $Result | Add-Member -MemberType NoteProperty -Name 'SecurityAnalysis' -Value (Test-TerraformPlanSecurity -PlanOutput $PlanResult.StandardOutput)
                    $Result | Add-Member -MemberType NoteProperty -Name 'CostEstimation' -Value (Get-TerraformCostEstimation -PlanOutput $PlanResult.StandardOutput)
                }

                if ($Result.Success) {
                    Write-PSFMessage -Level Information -Message "Terraform plan completed successfully"
                    Write-PSFMessage -Level Information -Message "Plan summary: $($Result.Summary)"
                }
                else {
                    Write-PSFMessage -Level Error -Message "Terraform plan failed with exit code: $($Result.ExitCode)"
                }

                return $Result
            }
        }
        catch {
            Write-PSFMessage -Level Error -Message "Error during Terraform plan execution: $_"

            $ErrorResult = [PSCustomObject]@{
                Path = $Path
                PlanFile = $PlanFile
                Success = $false
                ExitCode = -1
                ExecutionTime = $null
                ResourceChanges = @()
                Summary = "Error: $($_.Exception.Message)"
                Warnings = @()
                Errors = @($_.Exception.Message)
                RawOutput = ''
                Timestamp = Get-Date
            }

            return $ErrorResult
        }
    }

    end {
        Write-PSFMessage -Level Verbose -Message "Invoke-TerraformPlan completed"
    }
}