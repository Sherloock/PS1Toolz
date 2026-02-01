# Core Helper Functions Tests
# Tests for Helpers.ps1 and TimerHelpers.ps1

BeforeAll {
    # Load the toolkit modules
    $ToolKitDir = Split-Path -Parent $PSScriptRoot
    . "$ToolKitDir\core\Helpers.ps1"
    . "$ToolKitDir\core\TimerHelpers.ps1"
}

# ============================================================================
# HELPERS.PS1 - Size Helpers
# ============================================================================

Describe "Get-ReadableSize" {
    It "formats gigabytes" {
        Get-ReadableSize -Bytes 2147483648 | Should -Be "2.00 GB"
    }
    It "formats megabytes" {
        Get-ReadableSize -Bytes 5242880 | Should -Be "5.00 MB"
    }
    It "formats kilobytes" {
        Get-ReadableSize -Bytes 2048 | Should -Be "2.00 KB"
    }
    It "formats bytes" {
        Get-ReadableSize -Bytes 500 | Should -Be "500 B"
    }
    It "handles zero bytes" {
        Get-ReadableSize -Bytes 0 | Should -Be "0 B"
    }
    It "handles exact GB boundary" {
        Get-ReadableSize -Bytes 1073741824 | Should -Be "1.00 GB"
    }
    It "handles exact MB boundary" {
        Get-ReadableSize -Bytes 1048576 | Should -Be "1.00 MB"
    }
    It "handles exact KB boundary" {
        Get-ReadableSize -Bytes 1024 | Should -Be "1.00 KB"
    }
}

# ============================================================================
# HELPERS.PS1 - Timer Helpers
# ============================================================================

Describe "ConvertTo-Seconds" {
    It "converts hours" {
        ConvertTo-Seconds "2h" | Should -Be 7200
    }
    It "converts minutes" {
        ConvertTo-Seconds "30m" | Should -Be 1800
    }
    It "converts seconds" {
        ConvertTo-Seconds "45s" | Should -Be 45
    }
    It "converts hours and minutes" {
        ConvertTo-Seconds "1h30m" | Should -Be 5400
    }
    It "converts all units combined" {
        ConvertTo-Seconds "1h30m45s" | Should -Be 5445
    }
    It "converts pure number as seconds" {
        ConvertTo-Seconds "300" | Should -Be 300
    }
    It "returns 0 for invalid input" {
        ConvertTo-Seconds "abc" | Should -Be 0
    }
    It "returns 0 for empty string" {
        ConvertTo-Seconds "" | Should -Be 0
    }
    It "handles large values" {
        ConvertTo-Seconds "24h" | Should -Be 86400
    }
}

Describe "Format-Duration" {
    It "formats hours minutes seconds" {
        Format-Duration -Seconds 5445 | Should -Be "1h 30m 45s"
    }
    It "formats hours and minutes only" {
        Format-Duration -Seconds 5400 | Should -Be "1h 30m"
    }
    It "formats hours only" {
        Format-Duration -Seconds 7200 | Should -Be "2h"
    }
    It "formats minutes only" {
        Format-Duration -Seconds 1800 | Should -Be "30m"
    }
    It "formats seconds only" {
        Format-Duration -Seconds 45 | Should -Be "45s"
    }
    It "formats zero as 0s" {
        Format-Duration -Seconds 0 | Should -Be "0s"
    }
    It "formats minutes and seconds" {
        Format-Duration -Seconds 125 | Should -Be "2m 5s"
    }
}

Describe "New-TimerId" {
    BeforeAll {
        # Use TestDrive for isolated file operations
        $script:TimerDataFile = "$TestDrive\ps-timers.json"
    }

    It "returns '1' when no timers exist" {
        if (Test-Path $script:TimerDataFile) { Remove-Item $script:TimerDataFile }
        New-TimerId | Should -Be "1"
    }

    It "returns next sequential ID" {
        $testTimers = @(
            @{ Id = "1"; State = "Completed" },
            @{ Id = "2"; State = "Running" }
        )
        ConvertTo-Json $testTimers | Set-Content $script:TimerDataFile
        New-TimerId | Should -Be "3"
    }

    It "handles gaps in IDs" {
        $testTimers = @(
            @{ Id = "1"; State = "Completed" },
            @{ Id = "5"; State = "Running" }
        )
        ConvertTo-Json $testTimers | Set-Content $script:TimerDataFile
        New-TimerId | Should -Be "6"
    }
}

Describe "Get-TimerData" {
    BeforeAll {
        $script:TimerDataFile = "$TestDrive\ps-timers.json"
    }

    It "returns empty array when file does not exist" {
        if (Test-Path $script:TimerDataFile) { Remove-Item $script:TimerDataFile }
        $result = Get-TimerData
        $result | Should -BeNullOrEmpty
    }

    It "loads timers from JSON file" {
        $testTimers = @(
            @{ Id = "1"; Message = "Test"; State = "Running" }
        )
        ConvertTo-Json $testTimers | Set-Content $script:TimerDataFile
        $result = @(Get-TimerData)
        $result.Count | Should -Be 1
        $result[0].Id | Should -Be "1"
    }

    It "returns empty array for corrupted JSON" {
        "not valid json" | Set-Content $script:TimerDataFile
        $result = Get-TimerData
        $result | Should -BeNullOrEmpty
    }
}

Describe "Save-TimerData" {
    BeforeAll {
        $script:TimerDataFile = "$TestDrive\ps-timers.json"
    }

    It "saves timers to JSON file" {
        $testTimers = @(
            [PSCustomObject]@{
                Id = "1"
                Duration = "5m"
                Seconds = 300
                Message = "Test"
                StartTime = (Get-Date).ToString('o')
                EndTime = (Get-Date).AddSeconds(300).ToString('o')
                RepeatTotal = 1
                RepeatRemaining = 0
                CurrentRun = 1
                State = "Running"
            }
        )
        Save-TimerData -Timers $testTimers
        Test-Path $script:TimerDataFile | Should -BeTrue
        $loaded = Get-Content $script:TimerDataFile | ConvertFrom-Json
        $loaded.Id | Should -Be "1"
    }

    It "removes file when saving empty array" {
        "existing content" | Set-Content $script:TimerDataFile
        Save-TimerData -Timers @()
        Test-Path $script:TimerDataFile | Should -BeFalse
    }
}

# ============================================================================
# TIMERHELPERS.PS1 - ANSI Colors
# ============================================================================

Describe "Get-AnsiColors" {
    It "returns hashtable with expected keys" {
        $colors = Get-AnsiColors
        $colors | Should -BeOfType [hashtable]
        $colors.Keys | Should -Contain "Reset"
        $colors.Keys | Should -Contain "Cyan"
        $colors.Keys | Should -Contain "Green"
        $colors.Keys | Should -Contain "Yellow"
        $colors.Keys | Should -Contain "Red"
    }

    It "returns ANSI escape sequences" {
        $colors = Get-AnsiColors
        $colors.Reset | Should -Match '\x1b\['
    }
}

# ============================================================================
# TIMERHELPERS.PS1 - Time Formatting
# ============================================================================

Describe "Format-RemainingTime" {
    It "formats positive TimeSpan as HH:MM:SS" {
        $ts = [TimeSpan]::FromSeconds(3661)  # 1h 1m 1s
        Format-RemainingTime -Remaining $ts | Should -Be "01:01:01"
    }

    It "formats zero TimeSpan" {
        $ts = [TimeSpan]::Zero
        Format-RemainingTime -Remaining $ts | Should -Be "00:00:00"
    }

    It "returns 00:00:00 for negative TimeSpan" {
        $ts = [TimeSpan]::FromSeconds(-100)
        Format-RemainingTime -Remaining $ts | Should -Be "00:00:00"
    }

    It "handles hours correctly" {
        $ts = [TimeSpan]::FromHours(2)
        Format-RemainingTime -Remaining $ts | Should -Be "02:00:00"
    }

    It "handles minutes correctly" {
        $ts = [TimeSpan]::FromMinutes(45)
        Format-RemainingTime -Remaining $ts | Should -Be "00:45:00"
    }
}

# ============================================================================
# TIMERHELPERS.PS1 - State Helpers
# ============================================================================

Describe "Get-TimerStateColor" {
    It "returns Green for Running state" {
        Get-TimerStateColor -State "Running" | Should -Be "Green"
    }

    It "returns Yellow for Paused state" {
        Get-TimerStateColor -State "Paused" | Should -Be "Yellow"
    }

    It "returns DarkGray for Completed state" {
        Get-TimerStateColor -State "Completed" | Should -Be "DarkGray"
    }

    It "returns Red for Lost state" {
        Get-TimerStateColor -State "Lost" | Should -Be "Red"
    }

    It "returns Gray for unknown state" {
        Get-TimerStateColor -State "Unknown" | Should -Be "Gray"
    }

    It "returns ANSI code when -Ansi switch is used" {
        $result = Get-TimerStateColor -State "Running" -Ansi
        $result | Should -Match '\x1b\['
    }
}

# ============================================================================
# TIMERHELPERS.PS1 - Progress Calculation
# ============================================================================

Describe "Get-TimerProgress" {
    It "returns 100 for Completed timer" {
        $timer = [PSCustomObject]@{ State = "Completed" }
        Get-TimerProgress -Timer $timer | Should -Be 100
    }

    It "calculates progress for Paused timer" {
        $timer = [PSCustomObject]@{
            State = "Paused"
            Seconds = 100
            RemainingSeconds = 25
        }
        Get-TimerProgress -Timer $timer | Should -Be 75
    }

    It "returns -1 for non-applicable state" {
        $timer = [PSCustomObject]@{ State = "Lost" }
        Get-TimerProgress -Timer $timer | Should -Be -1
    }

    It "calculates progress for Running timer" {
        $now = Get-Date
        $timer = [PSCustomObject]@{
            State = "Running"
            Seconds = 100
            StartTime = $now.AddSeconds(-50).ToString('o')
            EndTime = $now.AddSeconds(50).ToString('o')
        }
        $progress = Get-TimerProgress -Timer $timer
        $progress | Should -BeGreaterOrEqual 45
        $progress | Should -BeLessOrEqual 55
    }
}

# ============================================================================
# TIMERHELPERS.PS1 - Text Helpers
# ============================================================================

Describe "Get-TruncatedMessage" {
    It "returns message unchanged if within limit" {
        Get-TruncatedMessage -Message "Short" -MaxLength 20 | Should -Be "Short"
    }

    It "truncates long message with ellipsis" {
        $result = Get-TruncatedMessage -Message "This is a very long message" -MaxLength 15
        $result | Should -Be "This is a ve..."
        $result.Length | Should -Be 15
    }

    It "handles exact length" {
        Get-TruncatedMessage -Message "Exactly20Characters!" -MaxLength 20 | Should -Be "Exactly20Characters!"
    }

    It "uses default MaxLength of 20" {
        $result = Get-TruncatedMessage -Message "This is definitely longer than twenty chars"
        $result.Length | Should -Be 20
    }
}
