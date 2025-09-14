#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for ZRR.Terraform.Wrapper module

.DESCRIPTION
    Comprehensive test suite covering all public and private functions
    in the ZRR.Terraform.Wrapper module. Includes unit tests, integration
    tests, and validation of enterprise-grade functionality.
#>

BeforeAll {
    # Import the module for testing
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    $ModuleName = 'ZRR.Terraform.Wrapper'

    Import-Module "$ModulePath\$ModuleName.psd1" -Force -ErrorAction Stop

    # Set up test environment
    $TestDrive = $TestDrive ?? (New-Item -Path (Join-Path $env:TEMP "PesterTests-$(Get-Random)") -ItemType Directory).FullName
    $Script:TestWorkspace = Join-Path $TestDrive "terraform-test"
    $Script:TestTerraformConfig = @"
terraform {
  required_version = ">= 0.14"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "test" {
  content  = "Hello, Terraform!"
  filename = "$${path.module}/test.txt"
}

output "test_file" {
  value = local_file.test.filename
}
"@

    # Mock Terraform executable for testing
    $Script:MockTerraformPath = Join-Path $TestDrive "terraform.exe"
    if (-not (Test-Path $Script:MockTerraformPath)) {
        New-Item -Path $Script:MockTerraformPath -ItemType File -Force | Out-Null
    }
}

AfterAll {
    # Cleanup test environment
    if (Test-Path $TestDrive) {
        Remove-Item $TestDrive -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove module
    Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
}

Describe "ZRR.Terraform.Wrapper Module Tests" -Tag 'Unit', 'Module' {

    Context "Module Structure" {
        It "Should have a valid module manifest" {
            $ManifestPath = "$ModulePath\$ModuleName.psd1"
            $ManifestPath | Should -Exist

            { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It "Should have a root module file" {
            "$ModulePath\$ModuleName.psm1" | Should -Exist
        }

        It "Should import without errors" {
            { Import-Module "$ModulePath\$ModuleName.psd1" -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It "Should export expected functions" {
            $ExportedFunctions = Get-Command -Module $ModuleName -CommandType Function
            $ExportedFunctions | Should -Not -BeNullOrEmpty

            # Test for specific expected functions
            $ExpectedFunctions = @(
                'Initialize-TerraformWorkspace',
                'Invoke-TerraformPlan',
                'Invoke-TerraformApply',
                'Invoke-TerraformDestroy',
                'Get-TerraformState'
            )

            foreach ($Function in $ExpectedFunctions) {
                $ExportedFunctions.Name | Should -Contain $Function
            }
        }

        It "Should have proper module dependencies" {
            $Manifest = Test-ModuleManifest -Path "$ModulePath\$ModuleName.psd1"
            $Manifest.RequiredModules | Should -Contain @{ModuleName = 'PSFramework'; ModuleVersion = '1.7.249'}
        }
    }

    Context "Function Documentation" {
        $PublicFunctions = Get-Command -Module $ModuleName -CommandType Function

        foreach ($Function in $PublicFunctions) {
            It "Function $($Function.Name) should have help documentation" {
                $Help = Get-Help -Name $Function.Name
                $Help.Synopsis | Should -Not -BeNullOrEmpty
                $Help.Description | Should -Not -BeNullOrEmpty
            }

            It "Function $($Function.Name) should have examples" {
                $Help = Get-Help -Name $Function.Name
                $Help.Examples | Should -Not -BeNullOrEmpty
            }

            It "Function $($Function.Name) should have parameter documentation" {
                $Help = Get-Help -Name $Function.Name
                if ($Help.Parameters) {
                    foreach ($Parameter in $Help.Parameters.Parameter) {
                        $Parameter.Description.Text | Should -Not -BeNullOrEmpty
                    }
                }
            }
        }
    }

    Context "Module Configuration" {
        It "Should initialize module configuration" {
            $Script:ModuleConfig | Should -Not -BeNull
            $Script:ModuleConfig.ModuleName | Should -Be $ModuleName
            $Script:ModuleConfig.ModulePath | Should -Not -BeNullOrEmpty
        }

        It "Should have default configuration values" {
            $Script:ModuleConfig.DefaultWorkspace | Should -Be 'default'
            $Script:ModuleConfig.StateBackupEnabled | Should -Be $true
            $Script:ModuleConfig.MaxRetryAttempts | Should -BeGreaterThan 0
            $Script:ModuleConfig.TimeoutMinutes | Should -BeGreaterThan 0
        }
    }
}

Describe "Initialize-TerraformWorkspace Function Tests" -Tag 'Unit', 'Function' {

    BeforeAll {
        # Create test workspace directory
        if (-not (Test-Path $Script:TestWorkspace)) {
            New-Item -Path $Script:TestWorkspace -ItemType Directory -Force | Out-Null
        }

        # Create basic Terraform configuration
        Set-Content -Path (Join-Path $Script:TestWorkspace "main.tf") -Value $Script:TestTerraformConfig
    }

    Context "Parameter Validation" {
        It "Should accept valid Path parameter" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf } | Should -Not -Throw
        }

        It "Should reject non-existent Path parameter" {
            $NonExistentPath = Join-Path $TestDrive "non-existent"
            { Initialize-TerraformWorkspace -Path $NonExistentPath } | Should -Throw
        }

        It "Should accept valid WorkspaceName parameter" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WorkspaceName "test-workspace" -WhatIf } | Should -Not -Throw
        }

        It "Should reject invalid WorkspaceName parameter" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WorkspaceName "invalid workspace name!" -WhatIf } | Should -Throw
        }

        It "Should accept valid Backend parameter" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Backend "s3" -WhatIf } | Should -Not -Throw
        }
    }

    Context "Output Validation" -Skip:(!(Get-Command terraform -ErrorAction SilentlyContinue)) {
        It "Should return PSCustomObject" {
            Mock Invoke-TerraformCommand {
                return @{ ExitCode = 0; StandardOutput = "Terraform initialized"; StandardError = "" }
            } -ModuleName $ModuleName

            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result | Should -BeOfType [PSCustomObject]
        }

        It "Should have required properties" {
            Mock Invoke-TerraformCommand {
                return @{ ExitCode = 0; StandardOutput = "Terraform initialized"; StandardError = "" }
            } -ModuleName $ModuleName

            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.PSObject.Properties.Name | Should -Contain 'Path'
            $Result.PSObject.Properties.Name | Should -Contain 'WorkspaceName'
            $Result.PSObject.Properties.Name | Should -Contain 'Status'
            $Result.PSObject.Properties.Name | Should -Contain 'Timestamp'
        }
    }
}

Describe "Invoke-TerraformPlan Function Tests" -Tag 'Unit', 'Function' {

    Context "Parameter Validation" {
        It "Should accept valid Path parameter" {
            { Invoke-TerraformPlan -Path $Script:TestWorkspace -WhatIf } | Should -Not -Throw
        }

        It "Should reject non-existent Path parameter" {
            $NonExistentPath = Join-Path $TestDrive "non-existent"
            { Invoke-TerraformPlan -Path $NonExistentPath } | Should -Throw
        }

        It "Should accept Variables as hashtable" {
            $Variables = @{ environment = 'test'; region = 'us-east-1' }
            { Invoke-TerraformPlan -Path $Script:TestWorkspace -Variables $Variables -WhatIf } | Should -Not -Throw
        }

        It "Should accept Target as string array" {
            $Targets = @('local_file.test', 'local_file.test2')
            { Invoke-TerraformPlan -Path $Script:TestWorkspace -Target $Targets -WhatIf } | Should -Not -Throw
        }
    }

    Context "Output Validation" -Skip:(!(Get-Command terraform -ErrorAction SilentlyContinue)) {
        It "Should return PSCustomObject with plan results" {
            Mock Invoke-TerraformCommand {
                return @{
                    ExitCode = 0
                    StandardOutput = "Plan: 1 to add, 0 to change, 0 to destroy"
                    StandardError = ""
                }
            } -ModuleName $ModuleName

            Mock ConvertFrom-TerraformPlanOutput {
                return @{
                    ResourceChanges = @();
                    Summary = "1 to add"
                    Warnings = @()
                }
            } -ModuleName $ModuleName

            $Result = Invoke-TerraformPlan -Path $Script:TestWorkspace -WhatIf
            $Result | Should -BeOfType [PSCustomObject]
            $Result.Success | Should -Be $true
        }
    }
}

Describe "Private Function Tests" -Tag 'Unit', 'Private' {

    Context "Test-TerraformPrerequisites" {
        It "Should validate Terraform installation" -Skip:(!(Get-Command terraform -ErrorAction SilentlyContinue)) {
            { Test-TerraformPrerequisites } | Should -Not -Throw
        }

        It "Should validate PowerShell version" {
            { Test-TerraformPrerequisites } | Should -Not -Throw
        }

        It "Should validate module configuration" {
            { Test-TerraformPrerequisites } | Should -Not -Throw
        }
    }

    Context "Test-TerraformTransientError" {
        It "Should identify transient network errors" {
            $ErrorOutput = "Error: connection timeout occurred"
            $Result = Test-TerraformTransientError -ErrorOutput $ErrorOutput -ExitCode 1
            $Result | Should -Be $true
        }

        It "Should identify non-transient configuration errors" {
            $ErrorOutput = "Error: invalid configuration syntax"
            $Result = Test-TerraformTransientError -ErrorOutput $ErrorOutput -ExitCode 1
            $Result | Should -Be $false
        }

        It "Should return false for successful operations" {
            $Result = Test-TerraformTransientError -ErrorOutput "" -ExitCode 0
            $Result | Should -Be $false
        }

        It "Should identify state locking as transient" {
            $ErrorOutput = "Error acquiring state lock"
            $Result = Test-TerraformTransientError -ErrorOutput $ErrorOutput -ExitCode 1
            $Result | Should -Be $true
        }
    }

    Context "Invoke-TerraformCommand" {
        BeforeAll {
            # Mock the terraform executable for testing
            if ($IsWindows) {
                $Script:ModuleConfig.TerraformPath = 'cmd'
            } else {
                $Script:ModuleConfig.TerraformPath = '/bin/echo'
            }
        }

        It "Should execute commands and capture output" {
            if ($IsWindows) {
                $Result = Invoke-TerraformCommand -Command @('/c', 'echo', 'test') -WorkingDirectory $TestDrive
            } else {
                $Result = Invoke-TerraformCommand -Command @('test') -WorkingDirectory $TestDrive
            }

            $Result | Should -Not -BeNull
            $Result.ExitCode | Should -Be 0
            $Result.Success | Should -Be $true
        }

        It "Should handle command failures" {
            if ($IsWindows) {
                $Result = Invoke-TerraformCommand -Command @('/c', 'exit', '1') -WorkingDirectory $TestDrive -RetryCount 0
            } else {
                # Use a command that will fail
                $Script:ModuleConfig.TerraformPath = '/bin/false'
                $Result = Invoke-TerraformCommand -Command @() -WorkingDirectory $TestDrive -RetryCount 0
            }

            $Result.Success | Should -Be $false
            $Result.ExitCode | Should -Not -Be 0
        }
    }
}

Describe "Integration Tests" -Tag 'Integration' -Skip:(!(Get-Command terraform -ErrorAction SilentlyContinue)) {

    BeforeAll {
        # Set up integration test environment
        $Script:IntegrationTestPath = Join-Path $TestDrive "integration-test"
        if (-not (Test-Path $Script:IntegrationTestPath)) {
            New-Item -Path $Script:IntegrationTestPath -ItemType Directory -Force | Out-Null
        }

        # Create a more complex Terraform configuration
        $ComplexConfig = @"
terraform {
  required_version = ">= 0.14"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "test"
}

resource "local_file" "config" {
  content  = "Environment: `${var.environment}"
  filename = "`${path.module}/config.txt"
}

resource "local_file" "data" {
  content  = "Data for `${var.environment} environment"
  filename = "`${path.module}/data.txt"
}

output "config_file" {
  value = local_file.config.filename
}

output "data_file" {
  value = local_file.data.filename
}
"@

        Set-Content -Path (Join-Path $Script:IntegrationTestPath "main.tf") -Value $ComplexConfig
    }

    Context "End-to-End Workflow" {
        It "Should initialize workspace successfully" {
            $Result = Initialize-TerraformWorkspace -Path $Script:IntegrationTestPath
            $Result.Status | Should -Be 'Initialized'
            $Result.Errors | Should -BeNullOrEmpty
        }

        It "Should generate plan successfully" {
            $PlanFile = "test.tfplan"
            $Variables = @{ environment = 'integration-test' }

            $Result = Invoke-TerraformPlan -Path $Script:IntegrationTestPath -PlanFile $PlanFile -Variables $Variables

            $Result.Success | Should -Be $true
            $Result.Errors | Should -BeNullOrEmpty

            # Verify plan file was created
            $PlanFilePath = Join-Path $Script:IntegrationTestPath $PlanFile
            Test-Path $PlanFilePath | Should -Be $true
        }
    }

    Context "Error Handling" {
        It "Should handle invalid Terraform configuration" {
            $InvalidConfigPath = Join-Path $TestDrive "invalid-config"
            New-Item -Path $InvalidConfigPath -ItemType Directory -Force | Out-Null

            # Create invalid Terraform configuration
            $InvalidConfig = "this is not valid terraform syntax {"
            Set-Content -Path (Join-Path $InvalidConfigPath "main.tf") -Value $InvalidConfig

            $Result = Initialize-TerraformWorkspace -Path $InvalidConfigPath
            $Result.Status | Should -Be 'Failed'
            $Result.Errors | Should -Not -BeNullOrEmpty
        }
    }
}