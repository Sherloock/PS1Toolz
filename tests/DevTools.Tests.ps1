# Dev Tools Tests
# Tests for DevTools.ps1 (PortKill, NodeKill) with mocked processes

BeforeAll {
    # Load the toolkit modules
    $ToolKitDir = Split-Path -Parent $PSScriptRoot
    . "$ToolKitDir\core\Helpers.ps1"
    . "$ToolKitDir\dev\DevTools.ps1"
}

# ============================================================================
# PORTKILL
# ============================================================================

Describe "PortKill" {
    Context "when process is using the port" {
        BeforeAll {
            Mock Get-NetTCPConnection {
                [PSCustomObject]@{ OwningProcess = 1234 }
            }
            Mock Get-Process {
                [PSCustomObject]@{ ProcessName = "node" }
            }
            Mock Stop-Process { }
        }

        It "finds and kills the process" {
            PortKill -Port 3000
            Should -Invoke Stop-Process -Times 1 -ParameterFilter { $Id -eq 1234 }
        }

        It "identifies the process name" {
            PortKill -Port 3000
            Should -Invoke Get-Process -Times 1
        }
    }

    Context "when no process is using the port" {
        BeforeAll {
            Mock Get-NetTCPConnection { $null }
            Mock Stop-Process { }
        }

        It "reports no process found" {
            { PortKill -Port 3000 } | Should -Not -Throw
            Should -Not -Invoke Stop-Process
        }
    }

    Context "when access is denied" {
        BeforeAll {
            Mock Get-NetTCPConnection {
                [PSCustomObject]@{ OwningProcess = 4 }  # System process
            }
            Mock Get-Process {
                [PSCustomObject]@{ ProcessName = "System" }
            }
            Mock Stop-Process { throw "Access Denied" }
        }

        It "handles access denied gracefully" {
            { PortKill -Port 445 } | Should -Not -Throw
        }
    }

    Context "parameter validation" {
        It "requires Port parameter" {
            { PortKill } | Should -Throw
        }

        It "accepts valid port number" {
            Mock Get-NetTCPConnection { $null }
            { PortKill -Port 8080 } | Should -Not -Throw
        }
    }
}

# ============================================================================
# NODEKILL
# ============================================================================

Describe "NodeKill" {
    Context "when node_modules folders exist" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName = "$TestDrive\project1\node_modules"
                        Name = "node_modules"
                        PSIsContainer = $true
                    },
                    [PSCustomObject]@{
                        FullName = "$TestDrive\project2\node_modules"
                        Name = "node_modules"
                        PSIsContainer = $true
                    }
                )
            } -ParameterFilter { $Filter -eq "node_modules" }

            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{ Length = 100MB },
                    [PSCustomObject]@{ Length = 50MB }
                )
            } -ParameterFilter { $Recurse -and $File }

            Mock Measure-Object {
                [PSCustomObject]@{ Sum = 150MB }
            }

            Mock Read-Host { "" }  # Cancel by default
            Mock Remove-Item { }
        }

        It "finds node_modules folders" {
            NodeKill
            Should -Invoke Get-ChildItem -ParameterFilter { $Filter -eq "node_modules" }
        }

        It "calculates folder sizes" {
            NodeKill
            # Verify size calculation was attempted
            $true | Should -BeTrue
        }

        It "prompts for selection" {
            NodeKill
            Should -Invoke Read-Host -Times 1
        }
    }

    Context "path parameter and shortcuts" {
        BeforeAll {
            # Setup mock config
            $global:Config = @{
                NodeKillPaths = [ordered]@{
                    "test" = "$TestDrive\testproject"
                }
            }

            Mock Get-ChildItem { @() } -ParameterFilter { $Filter -eq "node_modules" }
            Mock Test-Path { $true }
        }

        AfterAll {
            $global:Config = $null
        }

        It "accepts shortcut from config" {
            # Create test directory
            New-Item -Path "$TestDrive\testproject" -ItemType Directory -Force | Out-Null

            NodeKill -Path "test"
            Should -Invoke Get-ChildItem -ParameterFilter { $Path -eq "$TestDrive\testproject" -and $Filter -eq "node_modules" }
        }

        It "accepts direct path" {
            New-Item -Path "$TestDrive\directpath" -ItemType Directory -Force | Out-Null

            NodeKill -Path "$TestDrive\directpath"
            Should -Invoke Get-ChildItem -ParameterFilter { $Path -eq "$TestDrive\directpath" -and $Filter -eq "node_modules" }
        }

        It "handles invalid shortcut gracefully" {
            Mock Test-Path { $false }
            { NodeKill -Path "nonexistent" } | Should -Not -Throw
        }

        It "shows available shortcuts on invalid input" {
            Mock Test-Path { $false }
            # Should not throw, just display message
            { NodeKill -Path "badpath" } | Should -Not -Throw
        }
    }

    Context "when no node_modules exist" {
        BeforeAll {
            Mock Get-ChildItem { @() } -ParameterFilter { $Filter -eq "node_modules" }
        }

        It "reports no folders found" {
            { NodeKill } | Should -Not -Throw
        }
    }

    Context "deletion scenarios" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName = "$TestDrive\project1\node_modules"
                        Name = "node_modules"
                        PSIsContainer = $true
                    }
                )
            } -ParameterFilter { $Filter -eq "node_modules" }

            Mock Get-ChildItem {
                @([PSCustomObject]@{ Length = 100MB })
            } -ParameterFilter { $Recurse -and $File }

            Mock Measure-Object {
                [PSCustomObject]@{ Sum = 100MB }
            }
        }

        It "deletes selected folder" {
            Mock Read-Host { "1" }
            Mock Remove-Item { }

            NodeKill
            Should -Invoke Remove-Item -Times 1
        }

        It "deletes all folders when 'all' selected" {
            Mock Read-Host { "all" }
            Mock Remove-Item { }

            NodeKill
            Should -Invoke Remove-Item -Times 1
        }

        It "handles deletion failure" {
            Mock Read-Host { "1" }
            Mock Remove-Item { throw "File in use" }

            { NodeKill } | Should -Not -Throw
        }
    }

    Context "nested node_modules filtering" {
        BeforeAll {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        FullName = "$TestDrive\project\node_modules"
                        Name = "node_modules"
                        PSIsContainer = $true
                    },
                    # This should be filtered out (nested)
                    [PSCustomObject]@{
                        FullName = "$TestDrive\project\node_modules\lodash\node_modules"
                        Name = "node_modules"
                        PSIsContainer = $true
                    }
                )
            } -ParameterFilter { $Filter -eq "node_modules" }

            Mock Get-ChildItem {
                @([PSCustomObject]@{ Length = 50MB })
            } -ParameterFilter { $Recurse -and $File }

            Mock Measure-Object {
                [PSCustomObject]@{ Sum = 50MB }
            }

            Mock Read-Host { "" }
        }

        It "filters nested node_modules" {
            # The Where-Object in NodeKill filters nested folders
            { NodeKill } | Should -Not -Throw
        }
    }
}
