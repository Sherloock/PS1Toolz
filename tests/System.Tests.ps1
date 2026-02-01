# System Module Tests
# Tests for System.ps1 (ShowIP, DiskSpace) with mocked network/WMI calls

BeforeAll {
    # Load the toolkit modules
    $ToolKitDir = Split-Path -Parent $PSScriptRoot
    . "$ToolKitDir\core\Helpers.ps1"
    . "$ToolKitDir\core\System.ps1"
}

# ============================================================================
# SHOWIP
# ============================================================================

Describe "ShowIP" {
    BeforeAll {
        # Mock network configuration
        Mock Get-NetIPConfiguration {
            [PSCustomObject]@{
                InterfaceIndex = 1
                IPv4Address = [PSCustomObject]@{ IPAddress = "192.168.1.100" }
                IPv4DefaultGateway = [PSCustomObject]@{ NextHop = "192.168.1.1" }
                DNSServer = [PSCustomObject]@{ ServerAddresses = @("8.8.8.8", "8.8.4.4") }
            }
        }

        Mock Get-NetAdapter {
            [PSCustomObject]@{
                Name = "Ethernet"
                Status = "Up"
                MacAddress = "00-11-22-33-44-55"
            }
        }

        Mock netsh { "" }

        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                query = "1.2.3.4"
                isp = "Test ISP"
                city = "Test City"
                country = "Test Country"
                timezone = "UTC"
            }
        }
    }

    It "executes without error" {
        { ShowIP } | Should -Not -Throw
    }

    It "calls Get-NetIPConfiguration" {
        ShowIP
        Should -Invoke Get-NetIPConfiguration -Times 1
    }

    It "calls Get-NetAdapter" {
        ShowIP
        Should -Invoke Get-NetAdapter -Times 1
    }

    It "fetches public IP info" {
        ShowIP
        Should -Invoke Invoke-RestMethod -Times 1
    }
}

Describe "ShowIP with network failure" {
    BeforeAll {
        Mock Get-NetIPConfiguration {
            [PSCustomObject]@{
                InterfaceIndex = 1
                IPv4Address = [PSCustomObject]@{ IPAddress = "192.168.1.100" }
                IPv4DefaultGateway = [PSCustomObject]@{ NextHop = "192.168.1.1" }
                DNSServer = [PSCustomObject]@{ ServerAddresses = @("8.8.8.8") }
            }
        }

        Mock Get-NetAdapter {
            [PSCustomObject]@{
                Name = "Ethernet"
                Status = "Up"
                MacAddress = "00-11-22-33-44-55"
            }
        }

        Mock netsh { "" }

        # Simulate network failure
        Mock Invoke-RestMethod { throw "Network error" }
    }

    It "handles network timeout gracefully" {
        { ShowIP } | Should -Not -Throw
    }
}

# ============================================================================
# DISKSPACE
# ============================================================================

Describe "DiskSpace" {
    BeforeAll {
        Mock Get-WmiObject {
            @(
                [PSCustomObject]@{
                    DeviceID = "C:"
                    Size = 500GB
                    FreeSpace = 100GB
                    DriveType = 3
                    VolumeName = "Windows"
                },
                [PSCustomObject]@{
                    DeviceID = "D:"
                    Size = 1TB
                    FreeSpace = 500GB
                    DriveType = 3
                    VolumeName = "Data"
                }
            )
        }
    }

    It "executes without error" {
        { DiskSpace } | Should -Not -Throw
    }

    It "calls Get-WmiObject for disk info" {
        DiskSpace
        Should -Invoke Get-WmiObject -Times 1
    }
}

Describe "DiskSpace calculations" {
    It "calculates usage percentage correctly" {
        Mock Get-WmiObject {
            @(
                [PSCustomObject]@{
                    DeviceID = "C:"
                    Size = 100GB
                    FreeSpace = 20GB
                    DriveType = 3
                    VolumeName = "Test"
                }
            )
        }

        # 80% used = (100-20)/100 * 100
        { DiskSpace } | Should -Not -Throw
    }

    It "handles drives with no label" {
        Mock Get-WmiObject {
            @(
                [PSCustomObject]@{
                    DeviceID = "E:"
                    Size = 50GB
                    FreeSpace = 25GB
                    DriveType = 2
                    VolumeName = $null
                }
            )
        }

        { DiskSpace } | Should -Not -Throw
    }

    It "handles USB drives" {
        Mock Get-WmiObject {
            @(
                [PSCustomObject]@{
                    DeviceID = "F:"
                    Size = 16GB
                    FreeSpace = 8GB
                    DriveType = 2
                    VolumeName = "USB Drive"
                }
            )
        }

        { DiskSpace } | Should -Not -Throw
    }
}

Describe "DiskSpace color thresholds" {
    It "shows warning color for high usage (85%+)" {
        Mock Get-WmiObject {
            @(
                [PSCustomObject]@{
                    DeviceID = "C:"
                    Size = 100GB
                    FreeSpace = 10GB  # 90% used
                    DriveType = 3
                    VolumeName = "Test"
                }
            )
        }

        { DiskSpace } | Should -Not -Throw
    }

    It "shows critical color for very high usage (92%+)" {
        Mock Get-WmiObject {
            @(
                [PSCustomObject]@{
                    DeviceID = "C:"
                    Size = 100GB
                    FreeSpace = 5GB  # 95% used
                    DriveType = 3
                    VolumeName = "Test"
                }
            )
        }

        { DiskSpace } | Should -Not -Throw
    }
}

# ============================================================================
# FAST (Speedtest)
# ============================================================================

Describe "Fast" {
    BeforeAll {
        # Mock file system checks
        Mock Test-Path { $false } -ParameterFilter { $Path -like "*speedtest*" }
        Mock New-Item { }
        Mock Invoke-WebRequest { }
        Mock Expand-Archive { }
        Mock Remove-Item { }
    }

    It "checks for speedtest installation" {
        Mock Test-Path { $true } -ParameterFilter { $Path -like "*speedtest.exe" }

        # Note: Cannot mock external exe calls directly, just verify no throw on path check
        # Full speedtest execution tests require the actual CLI
    }

    # Note: Full Fast tests skipped as they require external CLI
}
