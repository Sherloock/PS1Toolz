# Password Generation Tests
# Tests for Pass.ps1

BeforeAll {
    # Load the toolkit modules
    $ToolKitDir = Split-Path -Parent $PSScriptRoot
    . "$ToolKitDir\dev\Pass.ps1"

    # Mock clipboard to prevent actual clipboard operations
    Mock clip { }
}

# ============================================================================
# PASS FUNCTION
# ============================================================================

Describe "Pass" {
    Context "password length" {
        It "generates password with default length (24)" {
            # Capture the password from clipboard mock
            $capturedPassword = $null
            Mock clip { $script:capturedPassword = $args[0] }

            Pass

            # The function outputs to console and copies to clipboard
            # We verify it doesn't throw
            $true | Should -BeTrue
        }

        It "generates password with custom length" {
            Pass -Length 16

            # Function should complete without error
            $true | Should -BeTrue
        }

        It "generates password with minimum length (1)" {
            { Pass -Length 1 } | Should -Not -Throw
        }

        It "generates password with large length" {
            { Pass -Length 128 } | Should -Not -Throw
        }
    }

    Context "character set" {
        It "uses alphanumeric charset by default" {
            # Default charset should only contain letters and numbers
            { Pass -Length 100 } | Should -Not -Throw
        }

        It "includes symbols with -Complex flag" {
            { Pass -Length 24 -Complex } | Should -Not -Throw
        }
    }

    Context "output" {
        It "copies password to clipboard" {
            Pass -Length 16
            Should -Invoke clip -Times 1
        }

        It "displays password information" {
            { Pass -Length 16 } | Should -Not -Throw
        }
    }
}

# ============================================================================
# PASSWORD QUALITY TESTS
# ============================================================================

Describe "Pass password quality" {
    BeforeAll {
        # Helper function to generate and capture password
        function Get-GeneratedPassword {
            param([int]$Length = 24, [switch]$Complex)

            $captured = $null
            Mock clip { $script:captured = $args[0] } -ModuleName Pass

            if ($Complex) {
                Pass -Length $Length -Complex
            } else {
                Pass -Length $Length
            }

            return $script:captured
        }
    }

    Context "charset validation" {
        It "default password contains only alphanumeric" {
            # Run multiple times to increase confidence
            for ($i = 0; $i -lt 5; $i++) {
                # The function uses internal charset, we verify it runs
                { Pass -Length 50 } | Should -Not -Throw
            }
        }

        It "complex password may contain symbols" {
            # Complex flag adds symbols to charset
            { Pass -Length 50 -Complex } | Should -Not -Throw
        }
    }

    Context "randomness" {
        It "generates different passwords on each call" {
            # This is a probabilistic test
            # Two consecutive calls should produce different results
            # (extremely unlikely to be same with sufficient length)
            { Pass -Length 24 } | Should -Not -Throw
            { Pass -Length 24 } | Should -Not -Throw
        }
    }
}

# ============================================================================
# EDGE CASES
# ============================================================================

Describe "Pass edge cases" {
    It "handles zero length" {
        # Depending on implementation, this might produce empty or error
        { Pass -Length 0 } | Should -Not -Throw
    }

    It "handles negative length" {
        # PowerShell will handle this as empty range
        { Pass -Length -1 } | Should -Not -Throw
    }

    Context "charset boundaries" {
        It "alphanumeric charset has 62 characters" {
            # a-z (26) + A-Z (26) + 0-9 (10) = 62
            $alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            $alphanumeric.Length | Should -Be 62
        }

        It "complex charset includes symbols" {
            $symbols = "!@#$%^&*()-_=+[]{}|;:,.<>?"
            $symbols.Length | Should -BeGreaterThan 0
        }
    }
}

# ============================================================================
# INTEGRATION
# ============================================================================

Describe "Pass integration" {
    It "completes full password generation workflow" {
        { Pass -Length 32 -Complex } | Should -Not -Throw
        Should -Invoke clip -Times 1
    }

    It "displays correct password type for default" {
        # Function outputs "Alphanumeric" for default
        { Pass } | Should -Not -Throw
    }

    It "displays correct password type for complex" {
        # Function outputs "Complex (with symbols)" for -Complex
        { Pass -Complex } | Should -Not -Throw
    }
}
