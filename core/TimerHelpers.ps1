# Timer-specific helper functions
# Loaded after Helpers.ps1, before Timer.ps1

# ============================================================================
# ANSI COLORS
# ============================================================================

function Get-AnsiColors {
    <#
    .SYNOPSIS
        Returns a hashtable of ANSI color escape codes for console output.
    #>
    $esc = [char]27
    return @{
        Esc        = $esc
        Reset      = "$esc[0m"
        Bold       = "$esc[1m"
        Dim        = "$esc[2m"
        Cyan       = "$esc[36m"
        DarkCyan   = "$esc[36m"
        Green      = "$esc[32m"
        Yellow     = "$esc[33m"
        Red        = "$esc[31m"
        Magenta    = "$esc[35m"
        White      = "$esc[97m"
        Gray       = "$esc[90m"
        InvertCyan = "$esc[30;46m"  # Black text on cyan background
    }
}

# ============================================================================
# TIME FORMATTING
# ============================================================================

function Format-RemainingTime {
    <#
    .SYNOPSIS
        Formats a TimeSpan as HH:MM:SS string.
    .PARAMETER Remaining
        The TimeSpan to format.
    .RETURNS
        String in format "HH:MM:SS" or "00:00:00" if negative.
    #>
    param([TimeSpan]$Remaining)

    if ($Remaining.TotalSeconds -lt 0) {
        return "00:00:00"
    }
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$Remaining.Hours, $Remaining.Minutes, $Remaining.Seconds
}

# ============================================================================
# STATE HELPERS
# ============================================================================

function Get-TimerStateColor {
    <#
    .SYNOPSIS
        Returns the display color for a timer state.
    .PARAMETER State
        The timer state (Running, Paused, Completed, Lost).
    .PARAMETER Ansi
        If set, returns ANSI escape code instead of color name.
    #>
    param(
        [string]$State,
        [switch]$Ansi
    )

    $colorName = switch ($State) {
        'Running'   { 'Green' }
        'Completed' { 'DarkGray' }
        'Paused'    { 'Yellow' }
        'Lost'      { 'Red' }
        default     { 'Gray' }
    }

    if ($Ansi) {
        $colors = Get-AnsiColors
        $result = switch ($colorName) {
            'Green'    { $colors.Green }
            'DarkGray' { $colors.Gray }
            'Yellow'   { $colors.Yellow }
            'Red'      { $colors.Red }
            default    { $colors.Gray }
        }
        return $result
    }

    return $colorName
}

# ============================================================================
# PROGRESS CALCULATION
# ============================================================================

function Get-TimerProgress {
    <#
    .SYNOPSIS
        Calculates the progress percentage for a timer.
    .PARAMETER Timer
        The timer object with StartTime, EndTime, Seconds, and State.
    .RETURNS
        Double percentage (0-100), or -1 if not applicable.
    #>
    param([PSCustomObject]$Timer)

    if ($Timer.State -eq 'Completed') {
        return [double]100
    }

    if ($Timer.State -eq 'Paused') {
        # Calculate progress based on remaining seconds
        $remaining = if ($Timer.RemainingSeconds) { $Timer.RemainingSeconds } else { $Timer.Seconds }
        $elapsed = $Timer.Seconds - $remaining
        $percent = [math]::Min(100, [math]::Max(0, ($elapsed / $Timer.Seconds) * 100))
        return [double]$percent
    }

    if ($Timer.State -ne 'Running') {
        return [double]-1
    }

    $now = Get-Date
    $startTime = [DateTime]::Parse($Timer.StartTime)
    $elapsed = ($now - $startTime).TotalSeconds
    
    # Force double precision before division
    $percent = ([double]$elapsed / $Timer.Seconds) * 100
    $percent = [math]::Min(100.0, [math]::Max(0.0, $percent))

    return $percent
}

# ============================================================================
# TEXT HELPERS
# ============================================================================

function Get-TruncatedMessage {
    <#
    .SYNOPSIS
        Truncates a message to a maximum length with ellipsis.
    .PARAMETER Message
        The message to truncate.
    .PARAMETER MaxLength
        Maximum length (default 20).
    #>
    param(
        [string]$Message,
        [int]$MaxLength = 20
    )

    if ($Message.Length -gt $MaxLength) {
        return $Message.Substring(0, $MaxLength - 3) + "..."
    }
    return $Message
}

# ============================================================================
# PICKER OPTIONS BUILDER
# ============================================================================

function Get-TimerPickerOptions {
    <#
    .SYNOPSIS
        Builds options array for Show-MenuPicker from timer list.
    .PARAMETER Timers
        Array of timer objects.
    .PARAMETER FilterState
        Filter timers by state ('Running', 'Paused'). Null for all.
    .PARAMETER ShowRemaining
        Show remaining time in label.
    .PARAMETER IncludeAllOption
        Add "all" option at the end.
    .PARAMETER IncludeDoneOption
        Add "done" option (for completed/lost timers).
    .PARAMETER AllOptionLabel
        Custom label for the "all" option.
    .PARAMETER AllOptionColor
        Color for the "all" option.
    #>
    param(
        [array]$Timers,
        [string]$FilterState,
        [switch]$ShowRemaining,
        [switch]$IncludeAllOption,
        [switch]$IncludeDoneOption,
        [string]$AllOptionLabel,
        [string]$AllOptionColor = 'Yellow'
    )

    $options = @()

    # Filter timers if state specified
    $filteredTimers = $Timers
    if ($FilterState) {
        $filteredTimers = @($Timers | Where-Object { $_.State -eq $FilterState })
    }

    # Build individual timer options
    foreach ($t in $filteredTimers) {
        $color = Get-TimerStateColor -State $t.State

        # Build label
        if ($ShowRemaining) {
            if ($t.State -eq 'Running') {
                $remaining = ([DateTime]::Parse($t.EndTime) - (Get-Date))
                $remainingStr = Format-RemainingTime -Remaining $remaining
                $label = "[$($t.Id)] $($t.Message) - $remainingStr remaining"
            }
            elseif ($t.State -eq 'Paused') {
                $remaining = if ($t.RemainingSeconds) { $t.RemainingSeconds } else { $t.Seconds }
                $remainingStr = Format-Duration -Seconds $remaining
                $label = "[$($t.Id)] $($t.Message) - $remainingStr remaining"
            }
            else {
                $label = "[$($t.Id)] $($t.Message) ($($t.State))"
            }
        }
        else {
            $label = "[$($t.Id)] $($t.Message) ($($t.State))"
        }

        $options += @{
            Id    = $t.Id
            Label = $label
            Color = $color
        }
    }

    # Add "done" option if requested
    if ($IncludeDoneOption) {
        $doneCount = @($Timers | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Lost' }).Count
        if ($doneCount -gt 0) {
            $options += @{
                Id    = 'done'
                Label = "Remove all finished ($doneCount completed/lost)"
                Color = 'Cyan'
            }
        }
    }

    # Add "all" option if requested and multiple timers exist
    if ($IncludeAllOption -and $filteredTimers.Count -gt 1) {
        $label = if ($AllOptionLabel) { $AllOptionLabel } else { "All ($($filteredTimers.Count) total)" }
        $options += @{
            Id    = 'all'
            Label = $label
            Color = $AllOptionColor
        }
    }

    return $options
}
