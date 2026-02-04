# Timer module - Display and formatting helpers

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
        InvertCyan = "$esc[30;46m"
    }
}

function Format-RemainingTime {
    <#
    .SYNOPSIS
        Formats a TimeSpan as HH:MM:SS string.
    #>
    param([TimeSpan]$Remaining)

    if ($Remaining.TotalSeconds -lt 0) {
        return "00:00:00"
    }
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$Remaining.Hours, $Remaining.Minutes, $Remaining.Seconds
}

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

function Get-TimerProgress {
    <#
    .SYNOPSIS
        Calculates the progress percentage for a timer.
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

    $percent = ([double]$elapsed / $Timer.Seconds) * 100
    $percent = [math]::Min(100.0, [math]::Max(0.0, $percent))

    return $percent
}

function Test-TimerIsActiveDisplay {
    <#
    .SYNOPSIS
        Returns whether the timer state should show remaining time and ends-at.
    #>
    param([string]$State)
    return ($State -eq 'Running' -or $State -eq 'Paused' -or $State -eq 'Lost')
}

function Get-TimerListRowColorsForState {
    <#
    .SYNOPSIS
        Returns remainingColor and endsColor for a timer state.
    #>
    param([string]$State)
    if ($State -eq 'Running') {
        return @{ RemainingColor = 'Yellow'; EndsColor = 'Green' }
    }
    if ($State -eq 'Lost') {
        return @{ RemainingColor = 'DarkRed'; EndsColor = 'DarkGray' }
    }
    if ($State -eq 'Paused') {
        return @{ RemainingColor = 'DarkYellow'; EndsColor = 'DarkGray' }
    }
    return @{ RemainingColor = 'DarkGray'; EndsColor = 'DarkGray' }
}

function Get-TimerListRowDisplayData {
    <#
    .SYNOPSIS
        Computes all display values for one timer list row.
    #>
    param(
        [PSCustomObject]$Timer,
        [DateTime]$Now
    )
    $endTime = [DateTime]::Parse($Timer.EndTime)
    $remaining = $endTime - $Now
    $remainingStr = Format-RemainingTime -Remaining $remaining
    $stateColor = Get-TimerStateColor -State $Timer.State

    if ($Timer.IsSequence) {
        $phaseNum = [int]$Timer.CurrentPhase + 1
        $repeatStr = "$phaseNum/$($Timer.TotalPhases)"
    }
    elseif ($Timer.RepeatTotal -gt 1) {
        $repeatStr = "$($Timer.CurrentRun)/$($Timer.RepeatTotal)"
    }
    else {
        $repeatStr = "-"
    }

    $msgSource = if ($Timer.IsSequence) { $Timer.PhaseLabel } else { $Timer.Message }
    $msgDisplay = Get-TruncatedMessage -Message $msgSource -MaxLength 20
    $durationStr = if ($Timer.IsSequence) { Format-Duration -Seconds $Timer.TotalSeconds } else { Format-Duration -Seconds $Timer.Seconds }

    $percent = Get-TimerProgress -Timer $Timer
    $progressStr = if ($percent -ge 0) { "{0:N0}%" -f $percent } else { "-" }

    $showActive = Test-TimerIsActiveDisplay -State $Timer.State
    if ($showActive) {
        if ($Timer.State -eq 'Running') {
            $endsAtStr = $endTime.ToString('HH:mm:ss')
        }
        else {
            $savedRemaining = if ($Timer.RemainingSeconds -and $Timer.RemainingSeconds -gt 0) { $Timer.RemainingSeconds } else { $Timer.Seconds }
            $remainingStr = Format-RemainingTime -Remaining ([TimeSpan]::FromSeconds($savedRemaining))
            $projectedEnd = $Now.AddSeconds($savedRemaining)
            $endsAtStr = $projectedEnd.ToString('HH:mm:ss')
            $elapsed = $Timer.Seconds - $savedRemaining
            $percent = if ($Timer.Seconds -gt 0) { ($elapsed / $Timer.Seconds) * 100 } else { 0 }
            $progressStr = "{0:N0}%" -f $percent
        }
        $colors = Get-TimerListRowColorsForState -State $Timer.State
        $remainingColor = $colors.RemainingColor
        $endsColor = $colors.EndsColor
    }
    else {
        $remainingStr = "-"
        $endsAtStr = "-"
        $remainingColor = 'DarkGray'
        $endsColor = 'DarkGray'
    }

    return @{
        RemainingStr   = $remainingStr
        ProgressStr   = $progressStr
        EndsAtStr     = $endsAtStr
        StateColor    = $stateColor
        RepeatStr     = $repeatStr
        MsgDisplay   = $msgDisplay
        DurationStr   = $durationStr
        ShowActive    = $showActive
        RemainingColor = $remainingColor
        EndsColor     = $endsColor
        PhaseColor    = if ($Timer.IsSequence) { 'Cyan' } else { 'Magenta' }
    }
}

function Get-TimerListWatchRowLine {
    <#
    .SYNOPSIS
        Builds one ANSI-colored line for the watch list display.
    #>
    param(
        [PSCustomObject]$Timer,
        [DateTime]$Now,
        [hashtable]$Colors,
        [hashtable]$ColWidths
    )
    $row = Get-TimerListRowDisplayData -Timer $Timer -Now $Now
    $stateColor = Get-TimerStateColor -State $Timer.State -Ansi
    $phaseColor = if ($Timer.IsSequence) { $Colors.Cyan } else { $Colors.Magenta }
    $id = $ColWidths.Id; $st = $ColWidths.State; $dur = $ColWidths.Duration
    $rem = $ColWidths.Remaining; $prog = $ColWidths.Progress; $end = $ColWidths.EndsAt; $ph = $ColWidths.Phase
    return "  $($Colors.Cyan){0,-$id}$($Colors.Reset)${stateColor}{1,-$st}$($Colors.Reset)$($Colors.White){2,-$dur}$($Colors.Reset)$($Colors.Yellow){3,-$rem}$($Colors.Reset)$($Colors.Green){4,-$prog}$($Colors.Reset)$($Colors.Green){5,-$end}$($Colors.Reset)${phaseColor}{6,-$ph}$($Colors.Reset)$($Colors.Gray){7}$($Colors.Reset)" -f $Timer.Id, $Timer.State, $row.DurationStr, $row.RemainingStr, $row.ProgressStr, $row.EndsAtStr, $row.RepeatStr, $row.MsgDisplay
}

function Wait-OneSecondOrKeyPress {
    <#
    .SYNOPSIS
        Waits until 1 second has elapsed since stopwatch start, or user presses a key.
    .RETURNS
        $true if key was pressed (caller should exit), $false to continue loop.
    #>
    param([System.Diagnostics.Stopwatch]$Stopwatch)
    $remainingMs = 1000 - $Stopwatch.ElapsedMilliseconds
    while ($remainingMs -gt 0) {
        if ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
            return $true
        }
        $sleepMs = [math]::Min(50, $remainingMs)
        Start-Sleep -Milliseconds $sleepMs
        $remainingMs = 1000 - $Stopwatch.ElapsedMilliseconds
    }
    return $false
}

function Get-TimerWatchCompletedContent {
    <#
    .SYNOPSIS
        Builds content for completed timer watch display.
    #>
    param(
        [hashtable]$Colors,
        [string]$Message,
        [int]$TotalSeconds,
        [DateTime]$EndTime
    )
    $barFull = [char]0x2588
    $barWidth = 40
    $fullBar = [string]$barFull * $barWidth
    $durStr = Format-Duration -Seconds $TotalSeconds
    $endStr = $EndTime.ToString('HH:mm:ss')
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($Colors.Green + $Colors.Bold + "  TIMER COMPLETED!" + $Colors.Reset)
    [void]$sb.AppendLine($Colors.Cyan + "  ==================" + $Colors.Reset)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($Colors.Gray + "  Message:  " + $Colors.White + $Message + $Colors.Reset)
    [void]$sb.AppendLine($Colors.Gray + "  Duration: " + $Colors.White + $durStr + $Colors.Reset)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("  " + $Colors.Green + $fullBar + $Colors.Reset + " " + $Colors.Bold + "100%" + $Colors.Reset)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($Colors.Green + "  Finished at " + $endStr + $Colors.Reset)
    [void]$sb.AppendLine("")
    return $sb
}

function Get-TimerWatchRunningContent {
    <#
    .SYNOPSIS
        Builds content for running timer watch display.
    #>
    param(
        [hashtable]$Colors,
        [PSCustomObject]$CurrentTimer,
        [PSCustomObject]$Timer,
        [double]$Percent,
        [TimeSpan]$Remaining,
        [string]$EndsAtFormatted
    )
    $barFull = [char]0x2588
    $barEmpty = [char]0x2591
    $barWidth = 40
    $filledCount = [int][math]::Floor(($Percent / 100) * $barWidth)
    $emptyCount = [int]($barWidth - $filledCount)
    $filledBar = [string]$barFull * $filledCount
    $emptyBar = [string]$barEmpty * $emptyCount
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $percentStr = $Percent.ToString("0.00", $inv) + "%"
    $remainingStr = Format-RemainingTime -Remaining $Remaining
    $c = $Colors
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("")
    $timerId = $Timer.Id
    if ($CurrentTimer.IsSequence) {
        $phaseNum = [int]$CurrentTimer.CurrentPhase + 1
        $phaseLabel = $CurrentTimer.PhaseLabel
        $seqTotal = Format-Duration -Seconds $CurrentTimer.TotalSeconds
        $seqPhaseDur = Format-Duration -Seconds $CurrentTimer.Seconds
        [void]$sb.AppendLine($c.Cyan + $c.Bold + "  SEQUENCE WATCH " + $c.White + "[" + $timerId + "]" + $c.Reset)
        [void]$sb.AppendLine($c.Cyan + "  =====================" + $c.Reset)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine($c.Gray + "  Pattern:  " + $c.White + $CurrentTimer.SequencePattern + $c.Reset)
        [void]$sb.AppendLine($c.Gray + "  Total:    " + $c.White + $seqTotal + $c.Reset)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine($c.Cyan + $c.Bold + "  Phase " + $phaseNum + "/" + $CurrentTimer.TotalPhases + ": " + $phaseLabel + $c.Reset)
        [void]$sb.AppendLine($c.Gray + "  Duration: " + $c.White + $seqPhaseDur + $c.Reset)
        [void]$sb.AppendLine($c.Gray + "  Ends at:  " + $c.Yellow + $EndsAtFormatted + $c.Reset)
    }
    else {
        [void]$sb.AppendLine($c.Cyan + $c.Bold + "  TIMER WATCH " + $c.White + "[" + $timerId + "]" + $c.Reset)
        [void]$sb.AppendLine($c.Cyan + "  ===================" + $c.Reset)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine($c.Gray + "  Message:  " + $c.White + $Timer.Message + $c.Reset)
        $msgDur = Format-Duration -Seconds $Timer.Seconds
        [void]$sb.AppendLine($c.Gray + "  Duration: " + $c.White + $msgDur + $c.Reset)
        [void]$sb.AppendLine($c.Gray + "  Ends at:  " + $c.Yellow + $EndsAtFormatted + $c.Reset)
        if ($Timer.RepeatTotal -gt 1) {
            $repStr = $CurrentTimer.CurrentRun.ToString() + "/" + $Timer.RepeatTotal.ToString()
            [void]$sb.AppendLine($c.Gray + "  Repeat:   " + $c.White + $repStr + $c.Reset)
        }
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("  " + $c.Green + $filledBar + $c.Gray + $emptyBar + $c.Reset + " " + $c.Bold + $percentStr + $c.Reset)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($c.Yellow + $c.Bold + "  Remaining: " + $remainingStr + $c.Reset)
    return $sb
}

function Get-TimerWatchPhaseTimelineContent {
    <#
    .SYNOPSIS
        Builds phase timeline content for sequence timer watch.
    #>
    param(
        [hashtable]$Colors,
        [PSCustomObject]$CurrentTimer
    )
    if (-not $CurrentTimer.IsSequence -or -not $CurrentTimer.Phases) {
        return $null
    }
    $c = $Colors
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($c.DarkCyan + "  Phases:" + $c.Reset)
    $phases = $CurrentTimer.Phases
    $maxShow = [math]::Min(6, $phases.Count)
    $startIdx = [math]::Max(0, [int]$CurrentTimer.CurrentPhase - 2)
    $endIdx = [math]::Min($phases.Count - 1, $startIdx + $maxShow - 1)
    for ($i = $startIdx; $i -le $endIdx; $i++) {
        $phase = $phases[$i]
        $pNum = $i + 1
        $marker = if ($i -eq [int]$CurrentTimer.CurrentPhase) { $c.Cyan + ">" } else { " " }
        $pColor = if ($i -lt [int]$CurrentTimer.CurrentPhase) { $c.Dim } elseif ($i -eq [int]$CurrentTimer.CurrentPhase) { $c.White } else { $c.Gray }
        $checkMark = if ($i -lt [int]$CurrentTimer.CurrentPhase) { $c.Green + "[OK]" } else { "    " }
        $phaseDur = Format-Duration -Seconds $phase.Seconds
        $line = "  " + $marker + " " + $checkMark + " " + $pColor + $pNum + ". " + $phase.Label + " (" + $phaseDur + ")" + $c.Reset
        [void]$sb.AppendLine($line)
    }
    if ($endIdx -lt $phases.Count - 1) {
        $moreCount = $phases.Count - $endIdx - 1
        $moreLine = $c.Dim + "    ... " + $moreCount + " more phases" + $c.Reset
        [void]$sb.AppendLine($moreLine)
    }
    return $sb
}
