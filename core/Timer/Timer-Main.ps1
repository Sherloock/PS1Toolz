# Timer module - Main user-facing functions

function Show-TimerHelp {
    <#
    .SYNOPSIS
        Shows timer commands help dashboard.
    #>
    Write-Host ""
    Write-Host "  TIMER COMMANDS" -ForegroundColor Cyan
    Write-Host "  ==============" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "t <time>" -ForegroundColor Yellow -NoNewline
    Write-Host " [msg] [repeat]" -ForegroundColor Gray
    Write-Host "      Start a timer (simple or sequence pattern)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tpre" -ForegroundColor Yellow
    Write-Host "      Pick from preset sequences (Pomodoro, etc.)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tl" -ForegroundColor Yellow -NoNewline
    Write-Host " [-a] [-w]" -ForegroundColor Gray
    Write-Host "      List active timers (-a all, -w live watch)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tw" -ForegroundColor Yellow -NoNewline
    Write-Host " [id]" -ForegroundColor Gray
    Write-Host "      Watch timer with progress bar (picker if no id)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tp" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|all]" -ForegroundColor Gray
    Write-Host "      Pause timer (picker if no id)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tr" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|all]" -ForegroundColor Gray
    Write-Host "      Resume paused timer (picker if no id)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "td" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|done|all]" -ForegroundColor Gray
    Write-Host "      Remove timer (picker if no id)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Time formats: " -ForegroundColor DarkGray -NoNewline
    Write-Host "1h30m, 25m, 90s, 1h20m30s" -ForegroundColor White
    Write-Host ""
    Write-Host "  Simple examples:" -ForegroundColor DarkGray
    Write-Host "    t 25m                      " -ForegroundColor Gray -NoNewline
    Write-Host "# 25 min timer" -ForegroundColor DarkGray
    Write-Host "    t 30m Water                " -ForegroundColor Gray -NoNewline
    Write-Host "# With message" -ForegroundColor DarkGray
    Write-Host "    t 1h30m 'Stand up' 4       " -ForegroundColor Gray -NoNewline
    Write-Host "# Repeat 4x" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  SEQUENCE TIMERS" -ForegroundColor Cyan
    Write-Host "  ---------------" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Syntax: " -ForegroundColor DarkGray -NoNewline
    Write-Host "(duration label, duration label)xN" -ForegroundColor White
    Write-Host ""
    Write-Host "  Sequence examples:" -ForegroundColor DarkGray
    Write-Host "    t pomodoro                 " -ForegroundColor Gray -NoNewline
    Write-Host "# Use preset" -ForegroundColor DarkGray
    Write-Host "    t ""(25m work, 5m rest)x4"" " -ForegroundColor Gray -NoNewline
    Write-Host "# 4 cycles" -ForegroundColor DarkGray
    Write-Host "    t ""(50m focus, 10m break)x3, 30m 'long break'""" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Presets: " -ForegroundColor DarkGray -NoNewline
    Write-Host "pomodoro, pomodoro-short, pomodoro-long, 52-17, 90-20" -ForegroundColor White
    Write-Host ""
}

function Timer {
    <#
    .SYNOPSIS
        Starts a background timer with optional repeat. Use tl to view all timers.
    .PARAMETER Time
        Duration (e.g., 1h20m, 90s), sequence pattern (e.g., "(25m work, 5m rest)x4"),
        or preset name (e.g., "pomodoro"). Omit to see help.
    .PARAMETER Message
        Optional message to show when time is up (ignored for sequences).
    .PARAMETER Repeat
        Number of times to repeat the timer (e.g., -r 3 repeats 3 times total).
    .EXAMPLE
        t 25m
        t 30m Water
        t 1h30m 'Stand up' 4
        t pomodoro
        t "(25m work, 5m rest)x4"
    #>
    param(
        [Parameter(Position=0)][string]$Time,
        [Parameter(Position=1)][Alias('m')][string]$Message = "Time is up!",
        [Parameter(Position=2)][Alias('r')][int]$Repeat = 1
    )

    # Show help if no time provided
    if ([string]::IsNullOrEmpty($Time)) {
        Show-TimerHelp
        return
    }

    # Check if this is a sequence pattern or preset
    if (Test-TimerSequence -Pattern $Time) {
        Start-SequenceTimer -Pattern $Time
        return
    }

    # Simple timer mode
    $seconds = ConvertTo-Seconds -Time $Time

    if ($seconds -le 0) {
        Write-Host "Invalid time format. Use 1h20m, 90s, etc." -ForegroundColor Red
        return
    }

    if ($Repeat -lt 1) { $Repeat = 1 }

    # Generate unique ID
    $id = New-TimerId
    $now = Get-Date
    $endTime = $now.AddSeconds($seconds)

    # Create timer metadata
    $timer = [PSCustomObject]@{
        Id              = $id
        Duration        = $Time
        Seconds         = $seconds
        Message         = $Message
        StartTime       = $now.ToString('o')
        EndTime         = $endTime.ToString('o')
        RepeatTotal     = $Repeat
        RepeatRemaining = $Repeat - 1
        CurrentRun      = 1
        State           = 'Running'
        IsSequence      = $false
    }

    # Save to data file
    $timers = @(Get-TimerData)
    $timers += $timer
    Save-TimerData -Timers $timers

    # Start the job
    Start-TimerJob -Timer $timer

    # Display confirmation
    Write-Host ""
    Write-Host "  Timer started " -ForegroundColor Green -NoNewline
    Write-Host "[$id]" -ForegroundColor Cyan
    Write-Host "  Duration: " -ForegroundColor Gray -NoNewline
    Write-Host (Format-Duration -Seconds $seconds) -ForegroundColor White
    Write-Host "  Ends at:  " -ForegroundColor Gray -NoNewline
    Write-Host $endTime.ToString('HH:mm:ss') -ForegroundColor Yellow
    if ($Repeat -gt 1) {
        Write-Host "  Repeats:  " -ForegroundColor Gray -NoNewline
        Write-Host "$Repeat times" -ForegroundColor Magenta
    }
    Write-Host "  Message:  " -ForegroundColor Gray -NoNewline
    Write-Host $Message -ForegroundColor White
    Write-Host ""
}

function Start-SequenceTimer {
    <#
    .SYNOPSIS
        Starts a sequence-based timer (Pomodoro-style).
    .PARAMETER Pattern
        Sequence pattern string or preset name.
    #>
    param([string]$Pattern)

    $originalPattern = $Pattern
    if ($script:TimerPresets.ContainsKey($Pattern)) {
        $Pattern = $script:TimerPresets[$Pattern].Pattern
    }

    try {
        $phases = @(ConvertFrom-TimerSequence -Pattern $Pattern)
    }
    catch {
        Write-Host "`n  Invalid sequence pattern: $Pattern" -ForegroundColor Red
        Write-Host "  Example: (25m work, 5m rest)x4, 30m break`n" -ForegroundColor DarkGray
        return
    }

    if ($phases.Count -eq 0) {
        Write-Host "`n  No phases found in pattern: $Pattern" -ForegroundColor Red
        return
    }

    $summary = Get-SequenceSummary -Phases $phases
    $id = New-TimerId
    $now = Get-Date
    $timer = New-SequenceTimerFromPhases -Id $id -OriginalPattern $originalPattern -Phases $phases -Summary $summary -Now $now

    $timers = @(Get-TimerData)
    $timers += $timer
    Save-TimerData -Timers $timers
    Start-SequenceTimerJob -Timer $timer

    $firstPhase = $phases[0]
    $endTime = $now.AddSeconds($firstPhase.Seconds)
    Write-SequenceTimerConfirmation -Id $id -OriginalPattern $originalPattern -Summary $summary -PhaseCount $phases.Count -FirstPhase $firstPhase -EndTime $endTime
}

function TimerList {
    <#
    .SYNOPSIS
        Shows all background timers with detailed status.
    .PARAMETER All
        Include completed/stopped timers in the list.
    .PARAMETER Watch
        Live-updating display with countdown. Press any key to exit.
    #>
    param(
        [Alias('a')][switch]$All,
        [Alias('w')][switch]$Watch
    )

    if ($Watch) {
        Show-TimerListWatch -All:$All
        return
    }

    Show-TimerListOnce -All:$All -ShowCommands
}

function Show-TimerListOnce {
    <#
    .SYNOPSIS
        Internal function to display timer list once.
    #>
    param(
        [switch]$All,
        [switch]$ShowCommands
    )

    $timers = @(Sync-TimerData)

    if ($timers.Count -eq 0) {
        Write-Host "`n  No timers found." -ForegroundColor Gray
        Write-Host "  Use 't <time>' to create one.`n" -ForegroundColor DarkGray
        return $false
    }

    # Filter if not showing all
    if (-not $All) {
        $timers = @($timers | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Paused' })
    }

    if ($timers.Count -eq 0) {
        Write-Host "`n  No active timers." -ForegroundColor Gray
        Write-Host "  Use 'TimerList -a' to see all timers.`n" -ForegroundColor DarkGray
        return $false
    }

    # Count by state
    $running = @($timers | Where-Object { $_.State -eq 'Running' }).Count
    $paused = @($timers | Where-Object { $_.State -eq 'Paused' }).Count

    Write-Host ""
    Write-Host "  BACKGROUND TIMERS " -ForegroundColor Cyan -NoNewline
    Write-Host "($running running" -ForegroundColor Green -NoNewline
    if ($paused -gt 0) {
        Write-Host ", $paused paused" -ForegroundColor Yellow -NoNewline
    }
    Write-Host ")" -ForegroundColor Gray
    Write-Host "  =================" -ForegroundColor DarkCyan
    Write-Host ""

    # Column widths
    $colId = 5
    $colState = 10
    $colDuration = 11
    $colRemaining = 11
    $colProgress = 8
    $colEndsAt = 10
    $colPhase = 8

    # Header
    Write-Host "  " -NoNewline
    Write-Host ("{0,-$colId}" -f "ID") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colState}" -f "STATE") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colDuration}" -f "DURATION") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colRemaining}" -f "REMAINING") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colProgress}" -f "PROG") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colEndsAt}" -f "ENDS AT") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colPhase}" -f "PHASE") -ForegroundColor DarkGray -NoNewline
    Write-Host "MESSAGE" -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 83)) -ForegroundColor DarkGray

    $now = Get-Date
    foreach ($t in $timers) {
        $row = Get-TimerListRowDisplayData -Timer $t -Now $now
        Write-Host "  " -NoNewline
        Write-Host ("{0,-$colId}" -f $t.Id) -ForegroundColor Cyan -NoNewline
        Write-Host ("{0,-$colState}" -f $t.State) -ForegroundColor $row.StateColor -NoNewline
        Write-Host ("{0,-$colDuration}" -f $row.DurationStr) -ForegroundColor White -NoNewline
        Write-Host ("{0,-$colRemaining}" -f $row.RemainingStr) -ForegroundColor $row.RemainingColor -NoNewline
        Write-Host ("{0,-$colProgress}" -f $row.ProgressStr) -ForegroundColor $row.RemainingColor -NoNewline
        Write-Host ("{0,-$colEndsAt}" -f $row.EndsAtStr) -ForegroundColor $row.EndsColor -NoNewline
        Write-Host ("{0,-$colPhase}" -f $row.RepeatStr) -ForegroundColor $row.PhaseColor -NoNewline
        Write-Host $row.MsgDisplay -ForegroundColor Gray
    }

    Write-Host ""

    if ($ShowCommands) {
        Write-Host "  Pause " -ForegroundColor DarkGray -NoNewline
        Write-Host "tp <id>" -ForegroundColor White -NoNewline
        Write-Host " | Resume " -ForegroundColor DarkGray -NoNewline
        Write-Host "tr <id>" -ForegroundColor White -NoNewline
        Write-Host " | Delete " -ForegroundColor DarkGray -NoNewline
        Write-Host "td <id>" -ForegroundColor White -NoNewline
        Write-Host " | Watch " -ForegroundColor DarkGray -NoNewline
        Write-Host "tl -w" -ForegroundColor White
        Write-Host ""
    }

    return $true
}

function Show-TimerListWatch {
    <#
    .SYNOPSIS
        Live-updating timer list display. Press any key to exit.
    #>
    param(
        [switch]$All
    )

    $c = Get-AnsiColors
    [Console]::CursorVisible = $false
    $sw = [System.Diagnostics.Stopwatch]::new()

    try {
        $timers = @(Get-TimerData)

        while ($true) {
            $sw.Restart()
            $now = Get-Date

            $cacheResult = Get-TimerDataIfChanged
            if ($cacheResult.Changed) {
                $timers = @($cacheResult.Data)
            }

            $displayTimers = $timers
            if (-not $All) {
                $displayTimers = @($timers | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Paused' })
            }

            $sb = [System.Text.StringBuilder]::new()

            if ($displayTimers.Count -eq 0) {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("$($c.Gray)  No active timers.$($c.Reset)")
                Clear-Host
                [Console]::Write($sb.ToString())
                break
            }

            $running = @($displayTimers | Where-Object { $_.State -eq 'Running' }).Count
            $paused = @($displayTimers | Where-Object { $_.State -eq 'Paused' }).Count

            [void]$sb.AppendLine("")
            $pausedPart = if ($paused -gt 0) { "$($c.Yellow), $paused paused$($c.Reset)" } else { "" }
            [void]$sb.AppendLine("$($c.Cyan)  BACKGROUND TIMERS $($c.Green)($running running${pausedPart}$($c.Green))$($c.Reset)")
            [void]$sb.AppendLine("$($c.DarkCyan)  =====================$($c.Reset)")
            [void]$sb.AppendLine("")

            $colWidths = @{ Id = 5; State = 10; Duration = 11; Remaining = 11; Progress = 8; EndsAt = 10; Phase = 8 }
            $hdr = "  {0,-5}{1,-10}{2,-11}{3,-11}{4,-8}{5,-10}{6,-8}MESSAGE" -f "ID", "STATE", "DURATION", "REMAINING", "PROG", "ENDS AT", "PHASE"
            [void]$sb.AppendLine("$($c.Gray)$hdr$($c.Reset)")
            [void]$sb.AppendLine("$($c.Gray)  $("-" * 83)$($c.Reset)")
            foreach ($t in $displayTimers) {
                [void]$sb.AppendLine((Get-TimerListWatchRowLine -Timer $t -Now $now -Colors $c -ColWidths $colWidths))
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("$($c.Gray)  Press any key to exit watch mode...$($c.Reset)")
            Clear-Host
            [Console]::Write($sb.ToString())
            if (Wait-OneSecondOrKeyPress -Stopwatch $sw) {
                Write-Host ""
                return
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

function TimerPresets {
    <#
    .SYNOPSIS
        Shows interactive preset picker for common timer sequences.
    #>
    $options = @()
    foreach ($name in $script:TimerPresets.Keys | Sort-Object) {
        $preset = $script:TimerPresets[$name]
        $phases = ConvertFrom-TimerSequence -Pattern $preset.Pattern
        $summary = Get-SequenceSummary -Phases $phases

        $options += @{
            Id          = $name
            Label       = "$name - $($summary.TotalDuration) total ($($summary.PhaseCount) phases)"
            Description = $preset.Description
            Color       = 'White'
        }
    }

    $options += @{
        Id    = '_custom'
        Label = "[Enter custom sequence...]"
        Color = 'Cyan'
    }

    $selectedId = Show-MenuPicker -Title "SELECT TIMER PRESET" -Options $options -AllowCancel

    if (-not $selectedId) {
        return
    }

    if ($selectedId -eq '_custom') {
        Write-Host ""
        Write-Host "  Enter sequence pattern:" -ForegroundColor Cyan
        Write-Host "  Example: (25m work, 5m rest)x4, 30m break" -ForegroundColor DarkGray
        Write-Host ""
        $pattern = Read-Host "  Pattern"
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            return
        }
        Timer -Time $pattern
    }
    else {
        Timer -Time $selectedId
    }
}

function TimerWatch {
    <#
    .SYNOPSIS
        Watch a specific timer with live countdown and progress bar.
    .PARAMETER Id
        The timer ID to watch. If omitted and only one active timer exists, watches that one.
    #>
    param(
        [Parameter(Position=0)][string]$Id
    )

    $timers = @(Sync-TimerData)
    $result = Get-TimerForWatch -Timers $timers -Id $Id
    if ($result.Error) {
        if ($result.Error -eq 'NoActive') {
            Write-Host "`n  No active timers to watch." -ForegroundColor Gray
            Write-Host "  Use 't <time>' to create one.`n" -ForegroundColor DarkGray
        }
        elseif ($result.Error -eq 'NotFound') {
            Write-Host "`n  Timer '$($result.Id)' not found.`n" -ForegroundColor Red
        }
        elseif ($result.Error -eq 'NotRunning') {
            Write-Host "`n  Timer '$($result.Id)' is not running (state: $($result.State)).`n" -ForegroundColor Yellow
        }
        return
    }
    Show-TimerWatchDisplay -Timer $result.Timer
}

function Show-TimerWatchDisplay {
    <#
    .SYNOPSIS
        Internal function to display live timer watch with progress bar.
    #>
    param([PSCustomObject]$Timer)

    $c = Get-AnsiColors
    [Console]::CursorVisible = $false
    $sw = [System.Diagnostics.Stopwatch]::new()

    try {
        $totalSeconds = $Timer.Seconds
        $endTime = [DateTime]::Parse($Timer.EndTime)
        $currentTimer = $Timer

        while ($true) {
            $sw.Restart()
            $now = Get-Date

            $cacheResult = Get-TimerDataIfChanged
            if ($cacheResult.Changed) {
                $currentTimer = $cacheResult.Data | Where-Object { $_.Id -eq $Timer.Id }
                if ($currentTimer -and $currentTimer.EndTime) {
                    $endTime = [DateTime]::Parse($currentTimer.EndTime)
                }
            }

            if (-not $currentTimer -or $currentTimer.State -ne 'Running') {
                Clear-Host
                Write-Host ""
                Write-Host "  Timer [$($Timer.Id)] is no longer running." -ForegroundColor Yellow
                Write-Host ""
                break
            }

            $remaining = $endTime - $now
            $remainingSeconds = [math]::Max(0, $remaining.TotalSeconds)
            $percent = Get-TimerProgress -Timer $currentTimer

            if ($remainingSeconds -le 0) {
                Clear-Host
                $sb = Get-TimerWatchCompletedContent -Colors $c -Message $Timer.Message -TotalSeconds $totalSeconds -EndTime $endTime
                [Console]::Write($sb.ToString())
                break
            }

            $endsAtStr = $endTime.ToString('HH:mm:ss')
            $sb = Get-TimerWatchRunningContent -Colors $c -CurrentTimer $currentTimer -Timer $Timer -Percent $percent -Remaining $remaining -EndsAtFormatted $endsAtStr
            $phaseSb = Get-TimerWatchPhaseTimelineContent -Colors $c -CurrentTimer $currentTimer
            if ($phaseSb) {
                [void]$sb.Append($phaseSb.ToString())
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("$($c.Dim)  Press any key to exit watch mode...$($c.Reset)")
            Clear-Host
            [Console]::Write($sb.ToString())
            if (Wait-OneSecondOrKeyPress -Stopwatch $sw) {
                Write-Host ""
                return
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

function TimerPause {
    <#
    .SYNOPSIS
        Pauses a background timer. Shows picker if no ID specified.
    .PARAMETER Id
        The timer ID to pause. Use 'all' to pause all. Omit for picker.
    #>
    param(
        [Parameter(Position=0)][string]$Id
    )

    $timers = @(Get-TimerData)
    if ($timers.Count -eq 0) {
        Write-Host "`n  No timers to pause.`n" -ForegroundColor Gray
        return
    }

    if ([string]::IsNullOrEmpty($Id)) {
        $runningTimers = @($timers | Where-Object { $_.State -eq 'Running' })
        if ($runningTimers.Count -eq 0) {
            Write-Host "`n  No running timers to pause.`n" -ForegroundColor Gray
            return
        }
        $options = Get-TimerPickerOptions -Timers $runningTimers -FilterState 'Running' -ShowRemaining -IncludeAllOption -AllOptionLabel "Pause ALL running timers ($($runningTimers.Count) total)" -AllOptionColor 'Yellow'
        $selectedId = Show-MenuPicker -Title "SELECT TIMER TO PAUSE" -Options $options -AllowCancel
        if (-not $selectedId) { return }
        $Id = $selectedId
        $timers = @(Get-TimerData)
    }

    if ($Id -eq 'all') {
        $count = Invoke-PauseTimersBulk -Timers $timers
        Write-Host "`n  Paused $count timer(s).`n" -ForegroundColor Yellow
    }
    else {
        $remaining = Invoke-PauseSingleTimer -Timers $timers -Id $Id
        if ($remaining -eq $false) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
        }
        elseif ($null -eq $remaining) {
            Write-Host "`n  Timer '$Id' is not running.`n" -ForegroundColor Yellow
        }
        else {
            Write-Host "`n  Timer " -ForegroundColor Yellow -NoNewline
            Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
            Write-Host " paused. " -ForegroundColor Yellow -NoNewline
            Write-Host "($(Format-Duration -Seconds $remaining) remaining)`n" -ForegroundColor Gray
        }
    }
}

function TimerResume {
    <#
    .SYNOPSIS
        Resumes a paused or lost timer. Shows picker if no ID specified.
    #>
    param(
        [Parameter(Position=0)][string]$Id
    )

    $timers = @(Get-TimerData)
    if ($timers.Count -eq 0) {
        Write-Host "`n  No timers to resume.`n" -ForegroundColor Gray
        return
    }

    if ([string]::IsNullOrEmpty($Id)) {
        $resumableTimers = @($timers | Where-Object { $_.State -eq 'Paused' -or $_.State -eq 'Lost' })
        if ($resumableTimers.Count -eq 0) {
            Write-Host "`n  No paused or lost timers to resume.`n" -ForegroundColor Gray
            return
        }
        $options = Get-TimerPickerOptions -Timers $resumableTimers -ShowRemaining -IncludeAllOption -AllOptionLabel "Resume ALL resumable timers ($($resumableTimers.Count) total)" -AllOptionColor 'Green'
        $selectedId = Show-MenuPicker -Title "SELECT TIMER TO RESUME" -Options $options -AllowCancel
        if (-not $selectedId) { return }
        $Id = $selectedId
        $timers = @(Get-TimerData)
    }

    if ($Id -eq 'all') {
        $count = Invoke-ResumeTimersBulk -Timers $timers
        Write-Host "`n  Resumed $count timer(s).`n" -ForegroundColor Green
    }
    else {
        $result = Invoke-ResumeSingleTimer -Timers $timers -Id $Id
        if (-not $result.Found) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
        }
        elseif ($result.NoTime) {
            Write-Host "`n  Timer '$Id' has no time remaining.`n" -ForegroundColor Yellow
        }
        elseif (-not $result.CanResume) {
            Write-Host "`n  Timer '$Id' cannot be resumed.`n" -ForegroundColor Yellow
        }
        else {
            $action = if ($result.IsLost) { "restarted" } else { "resumed" }
            Write-Host "`n  Timer " -ForegroundColor Green -NoNewline
            Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
            Write-Host " $action. " -ForegroundColor Green -NoNewline
            Write-Host "Ends at $($result.NewEndTime.ToString('HH:mm:ss'))`n" -ForegroundColor Yellow
        }
    }
}

function TimerRemove {
    <#
    .SYNOPSIS
        Removes a timer from the list by ID, or clears all finished timers.
    .PARAMETER Id
        The timer ID to remove. Use 'all' to remove all, 'done' to remove completed/stopped only.
    #>
    param(
        [Parameter(Position=0)][string]$Id
    )

    $timers = @(Get-TimerData)
    if ($timers.Count -eq 0) {
        Write-Host "`n  No timers to remove.`n" -ForegroundColor Gray
        return
    }

    if ([string]::IsNullOrEmpty($Id)) {
        $timers = @(Sync-TimerData)
        if ($timers.Count -eq 0) {
            Write-Host "`n  No timers to remove.`n" -ForegroundColor Gray
            return
        }
        $options = Get-TimerPickerOptions -Timers $timers -IncludeDoneOption -IncludeAllOption -AllOptionLabel "Remove ALL timers ($($timers.Count) total)" -AllOptionColor 'Red'
        if ($timers.Count -eq 1) {
            $options += @{ Id = 'all'; Label = "Remove ALL timers ($($timers.Count) total)"; Color = 'Red' }
        }
        $selectedId = Show-MenuPicker -Title "SELECT TIMER TO REMOVE" -Options $options -AllowCancel
        if (-not $selectedId) { return }
        $Id = $selectedId
        $timers = @(Get-TimerData)
    }

    if ($Id -eq 'all') {
        Invoke-RemoveTimersBulk -Timers $timers -Mode 'all' | Out-Null
        Write-Host "`n  All timers removed.`n" -ForegroundColor Yellow
    }
    elseif ($Id -eq 'done') {
        $removed = Invoke-RemoveTimersBulk -Timers $timers -Mode 'done'
        Write-Host "`n  Removed $removed finished timer(s).`n" -ForegroundColor Yellow
    }
    else {
        $removed = Invoke-RemoveSingleTimer -Timers $timers -Id $Id
        if (-not $removed) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
        }
        else {
            Write-Host "`n  Timer " -ForegroundColor Yellow -NoNewline
            Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
            Write-Host " removed.`n" -ForegroundColor Yellow
        }
    }
}
