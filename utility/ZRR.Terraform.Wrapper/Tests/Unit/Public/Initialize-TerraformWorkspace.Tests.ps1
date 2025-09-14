#Requires -Module Pester

<#
.SYNOPSIS
    Unit tests for Initialize-TerraformWorkspace function

.DESCRIPTION
    Comprehensive unit tests covering all aspects of the Initialize-TerraformWorkspace
    function including parameter validation, error handling, and output validation.
#>

BeforeAll {
    # Import the module for testing
    $ModulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    $ModuleName = 'ZRR.Terraform.Wrapper'

    Import-Module "$ModulePath\$ModuleName.psd1" -Force -ErrorAction Stop

    # Set up test environment
    $Script:TestWorkspace = Join-Path $TestDrive "terraform-workspace-test"
    New-Item -Path $Script:TestWorkspace -ItemType Directory -Force | Out-Null

    # Create basic Terraform configuration
    $TerraformConfig = @"
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
  content  = "test content"
  filename = "$${path.module}/test.txt"
}
"@

    Set-Content -Path (Join-Path $Script:TestWorkspace "main.tf") -Value $TerraformConfig
}

Describe "Initialize-TerraformWorkspace Parameter Validation" -Tag 'Unit', 'ParameterValidation' {

    Context "Path Parameter" {
        It "Should accept valid directory path" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf } | Should -Not -Throw
        }

        It "Should reject empty path" {
            { Initialize-TerraformWorkspace -Path "" } | Should -Throw
        }

        It "Should reject null path" {
            { Initialize-TerraformWorkspace -Path $null } | Should -Throw
        }

        It "Should reject non-existent directory" {
            $NonExistentPath = Join-Path $TestDrive "does-not-exist"
            { Initialize-TerraformWorkspace -Path $NonExistentPath } | Should -Throw
        }

        It "Should reject file path instead of directory" {
            $FilePath = Join-Path $Script:TestWorkspace "main.tf"
            { Initialize-TerraformWorkspace -Path $FilePath } | Should -Throw
        }

        It "Should accept path from pipeline" {
            { $Script:TestWorkspace | Initialize-TerraformWorkspace -WhatIf } | Should -Not -Throw
        }

        It "Should accept path via alias" {
            { Initialize-TerraformWorkspace -Directory $Script:TestWorkspace -WhatIf } | Should -Not -Throw
            { Initialize-TerraformWorkspace -ConfigPath $Script:TestWorkspace -WhatIf } | Should -Not -Throw
        }
    }

    Context "Backend Parameter" {
        It "Should accept valid backend types" {
            $ValidBackends = @('local', 's3', 'azurerm', 'gcs', 'consul', 'etcdv3', 'http')

            foreach ($Backend in $ValidBackends) {
                { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Backend $Backend -WhatIf } | Should -Not -Throw
            }
        }

        It "Should reject invalid backend type" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Backend "invalid-backend" -WhatIf } | Should -Throw
        }

        It "Should default to 'local' backend" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.Backend | Should -Be 'local'
        }
    }

    Context "WorkspaceName Parameter" {
        It "Should accept valid workspace names" {
            $ValidNames = @('dev', 'staging', 'production', 'test-env', 'env_1', 'env.2')

            foreach ($Name in $ValidNames) {
                { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WorkspaceName $Name -WhatIf } | Should -Not -Throw
            }
        }

        It "Should reject invalid workspace names" {
            $InvalidNames = @('', ' ', 'name with spaces', 'name!@#$%', 'name/with/slashes')

            foreach ($Name in $InvalidNames) {
                { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WorkspaceName $Name -WhatIf } | Should -Throw
            }
        }

        It "Should reject workspace name longer than 50 characters" {
            $LongName = 'a' * 51
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WorkspaceName $LongName -WhatIf } | Should -Throw
        }

        It "Should use default workspace when not specified" {
            Mock Get-Variable { @{ Value = @{ DefaultWorkspace = 'default' } } } -ParameterFilter { $Name -eq 'ModuleConfig' -and $Scope -eq 'Script' }

            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.WorkspaceName | Should -Be 'default'
        }
    }

    Context "Switch Parameters" {
        It "Should accept Force switch" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Force -WhatIf } | Should -Not -Throw
        }

        It "Should accept Upgrade switch" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Upgrade -WhatIf } | Should -Not -Throw
        }

        It "Should accept both Force and Upgrade switches" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Force -Upgrade -WhatIf } | Should -Not -Throw
        }
    }

    Context "ProviderLockFile Parameter" {
        It "Should accept valid file path" {
            $LockFile = Join-Path $Script:TestWorkspace ".terraform.lock.hcl"
            New-Item -Path $LockFile -ItemType File -Force | Out-Null

            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -ProviderLockFile $LockFile -WhatIf } | Should -Not -Throw
        }

        It "Should reject non-existent file" {
            $NonExistentFile = Join-Path $Script:TestWorkspace "does-not-exist.hcl"
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -ProviderLockFile $NonExistentFile -WhatIf } | Should -Throw
        }

        It "Should accept empty string (optional parameter)" {
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -ProviderLockFile "" -WhatIf } | Should -Not -Throw
        }
    }
}

Describe "Initialize-TerraformWorkspace Output Validation" -Tag 'Unit', 'OutputValidation' {

    Context "Return Object Structure" {
        BeforeEach {
            Mock Test-TerraformPrerequisites { } -ModuleName $ModuleName
            Mock Invoke-TerraformCommand {
                return @{
                    ExitCode = 0
                    StandardOutput = "Terraform has been successfully initialized!"
                    StandardError = ""
                }
            } -ModuleName $ModuleName
            Mock Set-TerraformWorkspace {
                return @{ Success = $true; Error = $null }
            } -ModuleName $ModuleName
            Mock Get-TerraformProviderInfo { return @() } -ModuleName $ModuleName
            Mock Get-TerraformModuleInfo { return @() } -ModuleName $ModuleName
        }

        It "Should return PSCustomObject" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result | Should -BeOfType [PSCustomObject]
        }

        It "Should have all required properties" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf

            $ExpectedProperties = @(
                'Path', 'WorkspaceName', 'Backend', 'Status',
                'InitializationTime', 'Providers', 'Modules',
                'Warnings', 'Errors', 'Timestamp'
            )

            foreach ($Property in $ExpectedProperties) {
                $Result.PSObject.Properties.Name | Should -Contain $Property
            }
        }

        It "Should have correct property types" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf

            $Result.Path | Should -BeOfType [string]
            $Result.WorkspaceName | Should -BeOfType [string]
            $Result.Backend | Should -BeOfType [string]
            $Result.Status | Should -BeOfType [string]
            $Result.Providers | Should -BeOfType [array]
            $Result.Modules | Should -BeOfType [array]
            $Result.Warnings | Should -BeOfType [array]
            $Result.Errors | Should -BeOfType [array]
            $Result.Timestamp | Should -BeOfType [DateTime]
        }
    }

    Context "Success Scenarios" {
        BeforeEach {
            Mock Test-TerraformPrerequisites { } -ModuleName $ModuleName
            Mock Invoke-TerraformCommand {
                return @{
                    ExitCode = 0
                    StandardOutput = "Terraform has been successfully initialized!"
                    StandardError = ""
                }
            } -ModuleName $ModuleName
            Mock Set-TerraformWorkspace {
                return @{ Success = $true; Error = $null }
            } -ModuleName $ModuleName
            Mock Get-TerraformProviderInfo {
                return @(
                    @{ Name = 'local'; Version = '2.2.3'; Source = 'hashicorp/local' }
                )
            } -ModuleName $ModuleName
            Mock Get-TerraformModuleInfo { return @() } -ModuleName $ModuleName
        }

        It "Should set status to 'Initialized' on success" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.Status | Should -Be 'Initialized'
        }

        It "Should have empty errors array on success" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.Errors | Should -BeNullOrEmpty
        }

        It "Should populate providers information" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.Providers | Should -Not -BeNullOrEmpty
            $Result.Providers[0].Name | Should -Be 'local'
        }

        It "Should record initialization time" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.InitializationTime | Should -Not -BeNull
            $Result.InitializationTime | Should -BeOfType [TimeSpan]
        }
    }

    Context "Failure Scenarios" {
        BeforeEach {
            Mock Test-TerraformPrerequisites { } -ModuleName $ModuleName
            Mock Invoke-TerraformCommand {
                return @{
                    ExitCode = 1
                    StandardOutput = ""
                    StandardError = "Error: Failed to initialize Terraform"
                }
            } -ModuleName $ModuleName
        }

        It "Should set status to 'Failed' on command failure" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.Status | Should -Be 'Failed'
        }

        It "Should populate errors array on failure" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result.Errors | Should -Not -BeNullOrEmpty
            $Result.Errors[0] | Should -Match "initialization failed"
        }

        It "Should handle prerequisite validation failure" {
            Mock Test-TerraformPrerequisites {
                throw "Terraform not found"
            } -ModuleName $ModuleName

            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf } | Should -Throw "Prerequisites validation failed"
        }
    }
}

Describe "Initialize-TerraformWorkspace Functional Behavior" -Tag 'Unit', 'Functional' {

    Context "ShouldProcess Integration" {
        BeforeEach {
            Mock Test-TerraformPrerequisites { } -ModuleName $ModuleName
            Mock Invoke-TerraformCommand {
                return @{
                    ExitCode = 0
                    StandardOutput = "Terraform initialized"
                    StandardError = ""
                }
            } -ModuleName $ModuleName
        }

        It "Should support WhatIf parameter" {
            $Result = Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WhatIf
            $Result | Should -Not -BeNull

            # Verify that terraform command was not actually called in WhatIf mode
            Assert-MockCalled Invoke-TerraformCommand -Times 0 -ModuleName $ModuleName
        }

        It "Should prompt for confirmation with Confirm parameter" {
            # This test would require interactive input simulation
            # For now, we'll test that the function accepts the parameter
            { Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Confirm:$false } | Should -Not -Throw
        }
    }

    Context "Force and Upgrade Behavior" {
        BeforeEach {
            Mock Test-TerraformPrerequisites { } -ModuleName $ModuleName
        }

        It "Should include reconfigure flag when Force is specified" {
            Mock Invoke-TerraformCommand {
                param($Command)
                $Command | Should -Contain '-reconfigure'
                return @{ ExitCode = 0; StandardOutput = ""; StandardError = "" }
            } -ModuleName $ModuleName

            Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Force -Confirm:$false
        }

        It "Should include upgrade flag when Upgrade is specified" {
            Mock Invoke-TerraformCommand {
                param($Command)
                $Command | Should -Contain '-upgrade'
                return @{ ExitCode = 0; StandardOutput = ""; StandardError = "" }
            } -ModuleName $ModuleName

            Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Upgrade -Confirm:$false
        }

        It "Should include both flags when both are specified" {
            Mock Invoke-TerraformCommand {
                param($Command)
                $Command | Should -Contain '-reconfigure'
                $Command | Should -Contain '-upgrade'
                return @{ ExitCode = 0; StandardOutput = ""; StandardError = "" }
            } -ModuleName $ModuleName

            Initialize-TerraformWorkspace -Path $Script:TestWorkspace -Force -Upgrade -Confirm:$false
        }
    }

    Context "Workspace Cache Management" {
        BeforeEach {
            Mock Test-TerraformPrerequisites { } -ModuleName $ModuleName
            Mock Invoke-TerraformCommand {
                return @{ ExitCode = 0; StandardOutput = ""; StandardError = "" }
            } -ModuleName $ModuleName
            Mock Set-TerraformWorkspace {
                return @{ Success = $true; Error = $null }
            } -ModuleName $ModuleName
            Mock Get-TerraformProviderInfo { return @() } -ModuleName $ModuleName
            Mock Get-TerraformModuleInfo { return @() } -ModuleName $ModuleName

            # Reset workspace cache
            $Script:WorkspaceCache = @{}
        }

        It "Should update workspace cache on successful initialization" {
            Initialize-TerraformWorkspace -Path $Script:TestWorkspace -WorkspaceName "test-cache" -Confirm:$false

            $Script:WorkspaceCache | Should -Not -BeNull
            $Script:WorkspaceCache["test-cache"] | Should -Not -BeNull
            $Script:WorkspaceCache["test-cache"].Status | Should -Be 'Active'
        }
    }
}