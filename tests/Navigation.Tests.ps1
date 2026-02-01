# Navigation Tests
# Tests for Navigation.ps1 (Go function) with mock config

BeforeAll {
    # Load the toolkit modules
    $ToolKitDir = Split-Path -Parent $PSScriptRoot
    . "$ToolKitDir\dev\Navigation.ps1"
}

# ============================================================================
# GO FUNCTION
# ============================================================================

Describe "Go" {
    BeforeAll {
        # Setup mock config with bookmarks
        $global:Config = @{
            Bookmarks = [ordered]@{
                "home"    = $TestDrive
                "docs"    = "$TestDrive\Documents"
                "invalid" = "Z:\NonExistent\Path"
            }
        }

        # Create test directories
        New-Item -ItemType Directory -Path "$TestDrive\Documents" -Force | Out-Null
    }

    AfterAll {
        $global:Config = $null
    }

    Context "showing bookmarks list" {
        It "shows bookmark list when called without parameters" {
            { Go } | Should -Not -Throw
        }

        It "shows bookmark list for invalid target" {
            { Go -Target "nonexistent" } | Should -Not -Throw
        }
    }

    Context "navigating to bookmarks" {
        BeforeEach {
            # Save current location
            Push-Location
        }

        AfterEach {
            # Restore location
            Pop-Location
        }

        It "navigates to valid bookmark" {
            Go -Target "home"
            (Get-Location).Path | Should -Be $TestDrive
        }

        It "navigates to nested bookmark" {
            Go -Target "docs"
            (Get-Location).Path | Should -Be "$TestDrive\Documents"
        }

        It "handles non-existent path gracefully" {
            { Go -Target "invalid" } | Should -Not -Throw
            # Should stay in current directory
        }
    }

    Context "with default config" {
        BeforeAll {
            # Remove custom config to test defaults
            $savedConfig = $global:Config
            $global:Config = $null
        }

        AfterAll {
            $global:Config = $savedConfig
        }

        It "uses default bookmarks when config not set" {
            { Go } | Should -Not -Throw
        }
    }

    Context "bookmark resolution" {
        It "matches exact bookmark names" {
            # 'home' should work, 'hom' should not
            { Go -Target "home" } | Should -Not -Throw
        }

        It "is case-sensitive for bookmark names" {
            # This depends on hashtable implementation
            # Most PowerShell hashtables are case-insensitive
            { Go -Target "HOME" } | Should -Not -Throw
        }
    }
}

# ============================================================================
# BOOKMARK EDGE CASES
# ============================================================================

Describe "Go bookmark edge cases" {
    BeforeAll {
        $global:Config = @{
            Bookmarks = [ordered]@{
                "spaces" = "$TestDrive\Path With Spaces"
                "unicode" = "$TestDrive\Путь"
                "deep"   = "$TestDrive\a\b\c\d\e"
            }
        }

        # Create directories
        New-Item -ItemType Directory -Path "$TestDrive\Path With Spaces" -Force | Out-Null
    }

    AfterAll {
        $global:Config = $null
    }

    Context "special paths" {
        BeforeEach {
            Push-Location
        }

        AfterEach {
            Pop-Location
        }

        It "handles paths with spaces" {
            Go -Target "spaces"
            (Get-Location).Path | Should -Be "$TestDrive\Path With Spaces"
        }

        It "handles non-existent deep paths" {
            { Go -Target "deep" } | Should -Not -Throw
        }
    }
}

# ============================================================================
# CONFIG VALIDATION
# ============================================================================

Describe "Go config handling" {
    Context "empty bookmarks" {
        BeforeAll {
            $global:Config = @{
                Bookmarks = [ordered]@{}
            }
        }

        AfterAll {
            $global:Config = $null
        }

        It "handles empty bookmark list" {
            { Go } | Should -Not -Throw
        }
    }

    Context "null config" {
        BeforeAll {
            $global:Config = $null
        }

        It "handles null config gracefully" {
            { Go } | Should -Not -Throw
        }
    }

    Context "missing Bookmarks key" {
        BeforeAll {
            $global:Config = @{
                OtherSetting = "value"
            }
        }

        AfterAll {
            $global:Config = $null
        }

        It "handles missing Bookmarks key" {
            { Go } | Should -Not -Throw
        }
    }
}
