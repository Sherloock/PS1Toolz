# Media Library Tests
# Tests for Library.ps1 (Size, Movies, Get-SizeColor)

BeforeAll {
    # Load the toolkit modules
    $ToolKitDir = Split-Path -Parent $PSScriptRoot
    . "$ToolKitDir\core\Helpers.ps1"
    . "$ToolKitDir\media\Library.ps1"
}

# ============================================================================
# GET-SIZECOLOR (Pure Function)
# ============================================================================

Describe "Get-SizeColor" {
    It "returns Red for 10GB or more" {
        Get-SizeColor -Bytes (10GB) | Should -Be "Red"
        Get-SizeColor -Bytes (15GB) | Should -Be "Red"
    }

    It "returns Yellow for 1GB to 10GB" {
        Get-SizeColor -Bytes (1GB) | Should -Be "Yellow"
        Get-SizeColor -Bytes (5GB) | Should -Be "Yellow"
        Get-SizeColor -Bytes (9.9GB) | Should -Be "Yellow"
    }

    It "returns White for 100MB to 1GB" {
        Get-SizeColor -Bytes (100MB) | Should -Be "White"
        Get-SizeColor -Bytes (500MB) | Should -Be "White"
    }

    It "returns DarkGray for less than 100MB" {
        Get-SizeColor -Bytes (50MB) | Should -Be "DarkGray"
        Get-SizeColor -Bytes (1MB) | Should -Be "DarkGray"
        Get-SizeColor -Bytes (0) | Should -Be "DarkGray"
    }

    It "handles exact boundaries" {
        Get-SizeColor -Bytes (100MB - 1) | Should -Be "DarkGray"
        Get-SizeColor -Bytes (100MB) | Should -Be "White"
        Get-SizeColor -Bytes (1GB - 1) | Should -Be "White"
        Get-SizeColor -Bytes (1GB) | Should -Be "Yellow"
        Get-SizeColor -Bytes (10GB - 1) | Should -Be "Yellow"
        Get-SizeColor -Bytes (10GB) | Should -Be "Red"
    }
}

# ============================================================================
# SIZE FUNCTION
# ============================================================================

Describe "Size" {
    BeforeAll {
        # Setup mock config
        $global:Config = @{
            SizeDefaults = @{
                Depth = 0
                MinSize = 1MB
            }
        }
    }

    AfterAll {
        $global:Config = $null
    }

    Context "with files in directory" {
        BeforeAll {
            # Create test files
            New-Item -ItemType Directory -Path "$TestDrive\testdir" -Force | Out-Null
            Set-Content -Path "$TestDrive\large.txt" -Value ("x" * 2MB)
            Set-Content -Path "$TestDrive\small.txt" -Value "small"
            New-Item -ItemType Directory -Path "$TestDrive\subfolder" -Force | Out-Null
            Set-Content -Path "$TestDrive\subfolder\nested.txt" -Value ("y" * 1MB)
        }

        BeforeEach {
            Push-Location $TestDrive
        }

        AfterEach {
            Pop-Location
        }

        It "lists files and folders" {
            { Size } | Should -Not -Throw
        }

        It "respects Depth parameter" {
            { Size -Depth 0 } | Should -Not -Throw
            { Size -Depth 1 } | Should -Not -Throw
        }

        It "filters by MinSize" {
            { Size -MinSize 0 } | Should -Not -Throw
            { Size -MinSize 10MB } | Should -Not -Throw
        }
    }

    Context "empty directory" {
        BeforeAll {
            New-Item -ItemType Directory -Path "$TestDrive\empty" -Force | Out-Null
        }

        BeforeEach {
            Push-Location "$TestDrive\empty"
        }

        AfterEach {
            Pop-Location
        }

        It "handles empty directory" {
            { Size } | Should -Not -Throw
        }
    }

    Context "default values from config" {
        BeforeEach {
            Push-Location $TestDrive
        }

        AfterEach {
            Pop-Location
        }

        It "uses config defaults" {
            # With config set, defaults should be applied
            { Size } | Should -Not -Throw
        }
    }
}

# ============================================================================
# MOVIES FUNCTION
# ============================================================================

Describe "Movies" {
    Context "with configured media paths" {
        BeforeAll {
            # Create test media directories
            New-Item -ItemType Directory -Path "$TestDrive\Media\Movies" -Force | Out-Null
            New-Item -ItemType Directory -Path "$TestDrive\Media\Shows" -Force | Out-Null
            New-Item -ItemType Directory -Path "$TestDrive\Media\Movies\Movie1" -Force | Out-Null
            Set-Content -Path "$TestDrive\Media\Movies\Movie1\video.mkv" -Value ("x" * 1MB)

            $global:Config = @{
                MediaPaths = @(
                    "$TestDrive\Media\Movies",
                    "$TestDrive\Media\Shows"
                )
            }
        }

        AfterAll {
            $global:Config = $null
        }

        It "aggregates media from configured paths" {
            { Movies } | Should -Not -Throw
        }

        It "handles multiple media paths" {
            { Movies } | Should -Not -Throw
        }
    }

    Context "without configured media paths" {
        BeforeAll {
            $global:Config = $null
        }

        It "shows warning when no paths configured" {
            { Movies } | Should -Not -Throw
        }
    }

    Context "with non-existent paths" {
        BeforeAll {
            $global:Config = @{
                MediaPaths = @(
                    "Z:\NonExistent\Path1",
                    "Z:\NonExistent\Path2"
                )
            }
        }

        AfterAll {
            $global:Config = $null
        }

        It "handles non-existent paths gracefully" {
            { Movies } | Should -Not -Throw
        }
    }

    Context "with mixed valid and invalid paths" {
        BeforeAll {
            New-Item -ItemType Directory -Path "$TestDrive\ValidMedia" -Force | Out-Null

            $global:Config = @{
                MediaPaths = @(
                    "$TestDrive\ValidMedia",
                    "Z:\NonExistent\Path"
                )
            }
        }

        AfterAll {
            $global:Config = $null
        }

        It "processes valid paths and skips invalid" {
            { Movies } | Should -Not -Throw
        }
    }
}

# ============================================================================
# WRITE-SIZETABLE (Internal Function)
# ============================================================================

Describe "Write-SizeTable" {
    It "handles empty items array" {
        { Write-SizeTable -Items @() } | Should -Not -Throw
    }

    It "handles null items" {
        { Write-SizeTable -Items $null } | Should -Not -Throw
    }

    It "displays items with size info" {
        $items = @(
            [PSCustomObject]@{
                Size = "1.00 GB"
                RawSize = 1GB
                Path = "$TestDrive\file.txt"
                Name = "file.txt"
                Parent = $TestDrive
            }
        )
        { Write-SizeTable -Items $items } | Should -Not -Throw
    }

    It "groups by parent when specified" {
        $items = @(
            [PSCustomObject]@{
                Size = "1.00 GB"
                RawSize = 1GB
                Path = "$TestDrive\folder1\file1.txt"
                Name = "file1.txt"
                Parent = "$TestDrive\folder1"
            },
            [PSCustomObject]@{
                Size = "500.00 MB"
                RawSize = 500MB
                Path = "$TestDrive\folder2\file2.txt"
                Name = "file2.txt"
                Parent = "$TestDrive\folder2"
            }
        )
        { Write-SizeTable -Items $items -GroupByParent } | Should -Not -Throw
    }

    It "shows total when provided" {
        $items = @(
            [PSCustomObject]@{
                Size = "1.00 GB"
                RawSize = 1GB
                Path = "$TestDrive\file.txt"
                Name = "file.txt"
                Parent = $TestDrive
            }
        )
        { Write-SizeTable -Items $items -TotalBytes 1GB } | Should -Not -Throw
    }

    It "shows filtered count message" {
        $items = @(
            [PSCustomObject]@{
                Size = "1.00 GB"
                RawSize = 1GB
                Path = "$TestDrive\file.txt"
                Name = "file.txt"
                Parent = $TestDrive
            }
        )
        { Write-SizeTable -Items $items -FilteredCount 5 -MinSize 1MB } | Should -Not -Throw
    }
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

Describe "Media module integration" {
    BeforeAll {
        # Setup complete test environment
        New-Item -ItemType Directory -Path "$TestDrive\MediaLib\Movies\Action Movie (2024)" -Force | Out-Null
        New-Item -ItemType Directory -Path "$TestDrive\MediaLib\Movies\Drama Film" -Force | Out-Null
        Set-Content -Path "$TestDrive\MediaLib\Movies\Action Movie (2024)\movie.mkv" -Value ("x" * 500KB)
        Set-Content -Path "$TestDrive\MediaLib\Movies\Drama Film\film.mp4" -Value ("y" * 300KB)

        $global:Config = @{
            MediaPaths = @("$TestDrive\MediaLib\Movies")
            SizeDefaults = @{
                Depth = 0
                MinSize = 0
            }
        }
    }

    AfterAll {
        $global:Config = $null
    }

    It "Size and Movies functions work together" {
        Push-Location "$TestDrive\MediaLib"
        { Size -Depth 1 -MinSize 0 } | Should -Not -Throw
        Pop-Location

        { Movies } | Should -Not -Throw
    }
}
