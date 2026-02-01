# Timer and countdown utilities
# Helper functions are in Helpers.ps1 (loaded first by loader.ps1)

# ============================================================================
# TIMER HELP DASHBOARD
# ============================================================================

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
    Write-Host "      Start a background timer with optional message & repeat" -ForegroundColor DarkGray
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
    Write-Host "  Examples:" -ForegroundColor DarkGray
    Write-Host "    t 25m                      " -ForegroundColor Gray -NoNewline
    Write-Host "# Simple 25 min timer" -ForegroundColor DarkGray
    Write-Host "    t 30m Water                " -ForegroundColor Gray -NoNewline
    Write-Host "# Hydration reminder" -ForegroundColor DarkGray
    Write-Host "    t 1h30m 'Stand up' 4       " -ForegroundColor Gray -NoNewline
    Write-Host "# Repeat 4 times" -ForegroundColor DarkGray
    Write-Host "    t 45m -m 'Meeting' -r 2    " -ForegroundColor Gray -NoNewline
    Write-Host "# Named params" -ForegroundColor DarkGray
    Write-Host "    t 8h Lunch                 " -ForegroundColor Gray -NoNewline
    Write-Host "# End of workday" -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================================
# TIMER FUNCTIONS
# ============================================================================

function Timer {
    <#
    .SYNOPSIS
        Starts a background timer with optional repeat. Use tl to view all timers.
    .PARAMETER Time
        The duration (e.g., 1h20m, 90s, 10m, 3h). Omit to see help.
    .PARAMETER Message
        Optional message to show when time is up.
    .PARAMETER Repeat
        Number of times to repeat the timer (e.g., -r 3 repeats 3 times total).
    .EXAMPLE
        t 25m
        t 30m Water
        t 1h30m 'Stand up' 4
        t 45m -m 'Meeting' -r 2
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
    $colRepeat = 8

    # Header
    Write-Host "  " -NoNewline
    Write-Host ("{0,-$colId}" -f "ID") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colState}" -f "STATE") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colDuration}" -f "DURATION") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colRemaining}" -f "REMAINING") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colProgress}" -f "PROG") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colEndsAt}" -f "ENDS AT") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colRepeat}" -f "REPEAT") -ForegroundColor DarkGray -NoNewline
    Write-Host "MESSAGE" -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 83)) -ForegroundColor DarkGray

    foreach ($t in $timers) {
        $now = Get-Date
        $endTime = [DateTime]::Parse($t.EndTime)

        # Calculate remaining time
        $remaining = $endTime - $now
        $remainingStr = Format-RemainingTime -Remaining $remaining

        # State color
        $stateColor = Get-TimerStateColor -State $t.State

        # Repeat info
        $repeatStr = if ($t.RepeatTotal -gt 1) { "$($t.CurrentRun)/$($t.RepeatTotal)" } else { "-" }

        # Truncate message
        $msgDisplay = Get-TruncatedMessage -Message $t.Message -MaxLength 20

        # Duration formatted
        $durationStr = Format-Duration -Seconds $t.Seconds

        # Calculate progress percentage
        $percent = Get-TimerProgress -Timer $t
        $progressStr = if ($percent -ge 0) { "{0:N0}%" -f $percent } else { "-" }

        # Calculate remaining and ends at based on state
        if ($t.State -eq 'Running') {
            $endsAtStr = $endTime.ToString('HH:mm:ss')
        }
        elseif ($t.State -eq 'Paused' -or $t.State -eq 'Lost') {
            # For paused/lost: show remaining from saved value, calculate projected end time
            $savedRemaining = if ($t.RemainingSeconds -and $t.RemainingSeconds -gt 0) { $t.RemainingSeconds } else { $t.Seconds }
            $remainingStr = Format-RemainingTime -Remaining ([TimeSpan]::FromSeconds($savedRemaining))
            $projectedEnd = (Get-Date).AddSeconds($savedRemaining)
            $endsAtStr = $projectedEnd.ToString('HH:mm:ss')
            # Calculate progress for paused/lost
            $elapsed = $t.Seconds - $savedRemaining
            $percent = if ($t.Seconds -gt 0) { ($elapsed / $t.Seconds) * 100 } else { 0 }
            $progressStr = "{0:N0}%" -f $percent
        }
        else {
            $endsAtStr = "-"
        }

        # Output row
        Write-Host "  " -NoNewline
        Write-Host ("{0,-$colId}" -f $t.Id) -ForegroundColor Cyan -NoNewline
        Write-Host ("{0,-$colState}" -f $t.State) -ForegroundColor $stateColor -NoNewline
        Write-Host ("{0,-$colDuration}" -f $durationStr) -ForegroundColor White -NoNewline

        if ($t.State -eq 'Running' -or $t.State -eq 'Paused' -or $t.State -eq 'Lost') {
            $remainingColor = if ($t.State -eq 'Running') { 'Yellow' } elseif ($t.State -eq 'Lost') { 'DarkRed' } else { 'DarkYellow' }
            $endsColor = if ($t.State -eq 'Running') { 'Green' } else { 'DarkGray' }
            Write-Host ("{0,-$colRemaining}" -f $remainingStr) -ForegroundColor $remainingColor -NoNewline
            Write-Host ("{0,-$colProgress}" -f $progressStr) -ForegroundColor $remainingColor -NoNewline
            Write-Host ("{0,-$colEndsAt}" -f $endsAtStr) -ForegroundColor $endsColor -NoNewline
        }
        else {
            Write-Host ("{0,-$colRemaining}" -f "-") -ForegroundColor DarkGray -NoNewline
            Write-Host ("{0,-$colProgress}" -f $progressStr) -ForegroundColor DarkGray -NoNewline
            Write-Host ("{0,-$colEndsAt}" -f "-") -ForegroundColor DarkGray -NoNewline
        }

        Write-Host ("{0,-$colRepeat}" -f $repeatStr) -ForegroundColor Magenta -NoNewline
        Write-Host $msgDisplay -ForegroundColor Gray
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
    .DESCRIPTION
        Optimized for fast refresh: only reads JSON file, no Task Scheduler queries.
        State changes are detected via JSON file modifications (notification script updates it).
    #>
    param(
        [switch]$All
    )

    # ANSI color codes
    $c = Get-AnsiColors

    [Console]::CursorVisible = $false

    # Stopwatch for accurate 1-second ticks
    $sw = [System.Diagnostics.Stopwatch]::new()

    try {
        # Initial load - just read JSON, no sync (fast)
        $timers = @(Get-TimerData)

        while ($true) {
            $sw.Restart()
            $now = Get-Date

            # Fast path: only re-read JSON if file changed (no Task Scheduler queries)
            $cacheResult = Get-TimerDataIfChanged
            if ($cacheResult.Changed) {
                $timers = @($cacheResult.Data)
            }

            # Filter timers
            $displayTimers = $timers
            if (-not $All) {
                $displayTimers = @($timers | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Paused' })
            }

            # Build entire output as single string
            $sb = [System.Text.StringBuilder]::new()

            if ($displayTimers.Count -eq 0) {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("$($c.Gray)  No active timers.$($c.Reset)")
                Clear-Host
                [Console]::Write($sb.ToString())
                break
            }

            # Count by state
            $running = @($displayTimers | Where-Object { $_.State -eq 'Running' }).Count
            $paused = @($displayTimers | Where-Object { $_.State -eq 'Paused' }).Count

            [void]$sb.AppendLine("")
            $pausedPart = if ($paused -gt 0) { "$($c.Yellow), $paused paused$($c.Reset)" } else { "" }
            [void]$sb.AppendLine("$($c.Cyan)  BACKGROUND TIMERS $($c.Green)($running running${pausedPart}$($c.Green))$($c.Reset)")
            [void]$sb.AppendLine("$($c.DarkCyan)  =====================$($c.Reset)")
            [void]$sb.AppendLine("")

            # Column widths
            $colId = 5; $colState = 10; $colDuration = 11; $colRemaining = 11; $colProgress = 8; $colEndsAt = 10; $colRepeat = 8

            # Header
            $hdr = "  {0,-$colId}{1,-$colState}{2,-$colDuration}{3,-$colRemaining}{4,-$colProgress}{5,-$colEndsAt}{6,-$colRepeat}MESSAGE" -f "ID", "STATE", "DURATION", "REMAINING", "PROG", "ENDS AT", "REPEAT"
            [void]$sb.AppendLine("$($c.Gray)$hdr$($c.Reset)")
            [void]$sb.AppendLine("$($c.Gray)  $("-" * 83)$($c.Reset)")

            foreach ($t in $displayTimers) {
                $endTime = [DateTime]::Parse($t.EndTime)
                $remaining = $endTime - $now

                $remainingStr = Format-RemainingTime -Remaining $remaining
                $stateColor = Get-TimerStateColor -State $t.State -Ansi
                $repeatStr = if ($t.RepeatTotal -gt 1) { "$($t.CurrentRun)/$($t.RepeatTotal)" } else { "-" }
                $msgDisplay = Get-TruncatedMessage -Message $t.Message -MaxLength 20
                $durationStr = Format-Duration -Seconds $t.Seconds

                # Calculate progress percentage
                $percent = Get-TimerProgress -Timer $t
                $progressStr = if ($percent -ge 0) { "{0:N0}%" -f $percent } else { "-" }

                # Calculate values based on state
                if ($t.State -eq 'Running') {
                    $endsAtStr = $endTime.ToString('HH:mm:ss')
                }
                elseif ($t.State -eq 'Paused') {
                    $pausedRemaining = if ($t.RemainingSeconds) { $t.RemainingSeconds } else { $t.Seconds }
                    $remainingStr = Format-RemainingTime -Remaining ([TimeSpan]::FromSeconds($pausedRemaining))
                    $projectedEnd = $now.AddSeconds($pausedRemaining)
                    $endsAtStr = $projectedEnd.ToString('HH:mm:ss')
                }
                else {
                    $remainingStr = "-"
                    $endsAtStr = "-"
                }

                $line = "  $($c.Cyan){0,-$colId}$($c.Reset)${stateColor}{1,-$colState}$($c.Reset)$($c.White){2,-$colDuration}$($c.Reset)$($c.Yellow){3,-$colRemaining}$($c.Reset)$($c.Green){4,-$colProgress}$($c.Reset)$($c.Green){5,-$colEndsAt}$($c.Reset)$($c.Magenta){6,-$colRepeat}$($c.Reset)$($c.Gray){7}$($c.Reset)" -f $t.Id, $t.State, $durationStr, $remainingStr, $progressStr, $endsAtStr, $repeatStr, $msgDisplay
                [void]$sb.AppendLine($line)
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("$($c.Gray)  Press any key to exit watch mode...$($c.Reset)")

            # Clear and write in one go (minimizes flicker)
            Clear-Host
            [Console]::Write($sb.ToString())

            # Wait remaining time to complete 1 second (compensate for work done)
            $remainingMs = 1000 - $sw.ElapsedMilliseconds
            while ($remainingMs -gt 0) {
                if ([Console]::KeyAvailable) {
                    [Console]::ReadKey($true) | Out-Null
                    Write-Host ""
                    return
                }
                $sleepMs = [math]::Min(50, $remainingMs)
                Start-Sleep -Milliseconds $sleepMs
                $remainingMs = 1000 - $sw.ElapsedMilliseconds
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

# Short aliases for quick access
Set-Alias -Name t -Value Timer -Scope Global
Set-Alias -Name tl -Value TimerList -Scope Global
Set-Alias -Name tw -Value TimerWatch -Scope Global
Set-Alias -Name tp -Value TimerPause -Scope Global
Set-Alias -Name tr -Value TimerResume -Scope Global
Set-Alias -Name td -Value TimerRemove -Scope Global

function TimerWatch {
    <#
    .SYNOPSIS
        Watch a specific timer with live countdown and progress bar.
    .PARAMETER Id
        The timer ID to watch. If omitted and only one active timer exists, watches that one.
    .EXAMPLE
        tw 1
        tw
    #>
    param(
        [Parameter(Position=0)][string]$Id
    )

    $timers = @(Sync-TimerData)
    $activeTimers = @($timers | Where-Object { $_.State -eq 'Running' })

    if ($activeTimers.Count -eq 0) {
        Write-Host "`n  No active timers to watch." -ForegroundColor Gray
        Write-Host "  Use 't <time>' to create one.`n" -ForegroundColor DarkGray
        return
    }

    # Auto-select if only one timer or find by ID
    $timer = $null
    if ([string]::IsNullOrEmpty($Id)) {
        if ($activeTimers.Count -eq 1) {
            $timer = $activeTimers[0]
        }
        else {
            # Show picker for multiple timers
            $options = Get-TimerPickerOptions -Timers $activeTimers -FilterState 'Running' -ShowRemaining

            $selectedId = Show-MenuPicker -Title "SELECT TIMER TO WATCH" -Options $options -AllowCancel
            if (-not $selectedId) {
                return
            }

            $timer = $activeTimers | Where-Object { $_.Id -eq $selectedId }
        }
    }
    else {
        $timer = $timers | Where-Object { $_.Id -eq $Id }
        if (-not $timer) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
            return
        }
        if ($timer.State -ne 'Running') {
            Write-Host "`n  Timer '$Id' is not running (state: $($timer.State)).`n" -ForegroundColor Yellow
            return
        }
    }

    Show-TimerWatchDisplay -Timer $timer
}

function Show-TimerWatchDisplay {
    <#
    .SYNOPSIS
        Internal function to display live timer watch with progress bar.
    .DESCRIPTION
        Optimized for fast refresh: only reads JSON file, no Task Scheduler queries.
        State changes are detected via JSON file modifications (notification script updates it).
    #>
    param([PSCustomObject]$Timer)

    # ANSI color codes
    $c = Get-AnsiColors

    # Progress bar characters
    $barFull = [char]0x2588      # █
    $barEmpty = [char]0x2591    # ░

    [Console]::CursorVisible = $false

    # Stopwatch for accurate 1-second ticks
    $sw = [System.Diagnostics.Stopwatch]::new()

    try {
        $totalSeconds = $Timer.Seconds
        $endTime = [DateTime]::Parse($Timer.EndTime)
        $currentTimer = $Timer

        while ($true) {
            $sw.Restart()
            $now = Get-Date

            # Fast path: only re-read JSON if file changed (no Task Scheduler queries)
            $cacheResult = Get-TimerDataIfChanged
            if ($cacheResult.Changed) {
                $currentTimer = $cacheResult.Data | Where-Object { $_.Id -eq $Timer.Id }
                # Update endTime if timer was modified (e.g., repeat cycle)
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

            # Timer completed
            if ($remainingSeconds -le 0) {
                Clear-Host
                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("$($c.Green)$($c.Bold)  TIMER COMPLETED!$($c.Reset)")
                [void]$sb.AppendLine("$($c.Cyan)  ==================$($c.Reset)")
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("$($c.Gray)  Message:  $($c.White)$($Timer.Message)$($c.Reset)")
                [void]$sb.AppendLine("$($c.Gray)  Duration: $($c.White)$(Format-Duration -Seconds $totalSeconds)$($c.Reset)")
                [void]$sb.AppendLine("")

                # Full progress bar
                $barWidth = 40
                $fullBar = [string]$barFull * $barWidth
                [void]$sb.AppendLine("  $($c.Green)$fullBar$($c.Reset) $($c.Bold)100%$($c.Reset)")
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("$($c.Green)  Finished at $($endTime.ToString('HH:mm:ss'))$($c.Reset)")
                [void]$sb.AppendLine("")

                [Console]::Write($sb.ToString())
                break
            }

            # Build display
            $sb = [System.Text.StringBuilder]::new()

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("$($c.Cyan)$($c.Bold)  TIMER WATCH $($c.White)[$($Timer.Id)]$($c.Reset)")
            [void]$sb.AppendLine("$($c.Cyan)  ===================$($c.Reset)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("$($c.Gray)  Message:  $($c.White)$($Timer.Message)$($c.Reset)")
            [void]$sb.AppendLine("$($c.Gray)  Duration: $($c.White)$(Format-Duration -Seconds $totalSeconds)$($c.Reset)")
            [void]$sb.AppendLine("$($c.Gray)  Ends at:  $($c.Yellow)$($endTime.ToString('HH:mm:ss'))$($c.Reset)")

            if ($Timer.RepeatTotal -gt 1) {
                [void]$sb.AppendLine("$($c.Gray)  Repeat:   $($c.White)$($currentTimer.CurrentRun)/$($Timer.RepeatTotal)$($c.Reset)")
            }

            [void]$sb.AppendLine("")

            # Progress bar
            $barWidth = 40
            $filledCount = [int][math]::Floor(($percent / 100) * $barWidth)
            $emptyCount = [int]($barWidth - $filledCount)
            $filledBar = [string]$barFull * $filledCount
            $emptyBar = [string]$barEmpty * $emptyCount
            $percentStr = $percent.ToString("0.00", [System.Globalization.CultureInfo]::InvariantCulture) + "%"

            [void]$sb.AppendLine("  $($c.Green)$filledBar$($c.Gray)$emptyBar$($c.Reset) $($c.Bold)$percentStr$($c.Reset)")
            [void]$sb.AppendLine("")

            # Remaining time - large format
            $remainingStr = Format-RemainingTime -Remaining $remaining
            [void]$sb.AppendLine("$($c.Yellow)$($c.Bold)  Remaining: $remainingStr$($c.Reset)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("$($c.Dim)  Press any key to exit watch mode...$($c.Reset)")

            # Clear and write
            Clear-Host
            [Console]::Write($sb.ToString())

            # Wait remaining time to complete 1 second (compensate for work done)
            $remainingMs = 1000 - $sw.ElapsedMilliseconds
            while ($remainingMs -gt 0) {
                if ([Console]::KeyAvailable) {
                    [Console]::ReadKey($true) | Out-Null
                    Write-Host ""
                    return
                }
                $sleepMs = [math]::Min(50, $remainingMs)
                Start-Sleep -Milliseconds $sleepMs
                $remainingMs = 1000 - $sw.ElapsedMilliseconds
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
    .EXAMPLE
        tp
        tp 1
        tp all
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
        # Show picker for running timers
        $runningTimers = @($timers | Where-Object { $_.State -eq 'Running' })

        if ($runningTimers.Count -eq 0) {
            Write-Host "`n  No running timers to pause.`n" -ForegroundColor Gray
            return
        }

        $options = Get-TimerPickerOptions -Timers $runningTimers -FilterState 'Running' -ShowRemaining -IncludeAllOption -AllOptionLabel "Pause ALL running timers ($($runningTimers.Count) total)" -AllOptionColor 'Yellow'

        $selectedId = Show-MenuPicker -Title "SELECT TIMER TO PAUSE" -Options $options -AllowCancel
        if (-not $selectedId) {
            return
        }

        $Id = $selectedId
        $timers = @(Get-TimerData)
    }

    if ($Id -eq 'all') {
        # Pause all timers
        $count = 0
        foreach ($t in $timers) {
            if ($t.State -ne 'Running') { continue }

            # Stop the scheduled task
            Stop-TimerTask -TimerId $t.Id

            # Save remaining seconds for resume
            $endTime = [DateTime]::Parse($t.EndTime)
            $remaining = [int]($endTime - (Get-Date)).TotalSeconds
            if ($remaining -lt 0) { $remaining = 0 }
            $t | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $remaining -Force
            $t.State = 'Paused'
            $count++
        }
        Save-TimerData -Timers $timers
        Write-Host "`n  Paused $count timer(s).`n" -ForegroundColor Yellow
    }
    else {
        # Pause specific timer
        $timer = $timers | Where-Object { $_.Id -eq $Id }

        if (-not $timer) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
            return
        }

        if ($timer.State -ne 'Running') {
            Write-Host "`n  Timer '$Id' is not running.`n" -ForegroundColor Yellow
            return
        }

        # Stop the scheduled task
        Stop-TimerTask -TimerId $Id

        # Save remaining seconds for resume
        $endTime = [DateTime]::Parse($timer.EndTime)
        $remaining = [int]($endTime - (Get-Date)).TotalSeconds
        if ($remaining -lt 0) { $remaining = 0 }
        $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $remaining -Force
        $timer.State = 'Paused'
        Save-TimerData -Timers $timers

        Write-Host "`n  Timer " -ForegroundColor Yellow -NoNewline
        Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
        Write-Host " paused. " -ForegroundColor Yellow -NoNewline
        Write-Host "($(Format-Duration -Seconds $remaining) remaining)`n" -ForegroundColor Gray
    }
}

function TimerResume {
    <#
    .SYNOPSIS
        Resumes a paused or lost timer. Shows picker if no ID specified.
    .DESCRIPTION
        - Paused timers: resume with remaining time
        - Lost timers: restart with full duration (current repeat cycle preserved)
    .PARAMETER Id
        The timer ID to resume. Use 'all' to resume all. Omit for picker.
    .EXAMPLE
        tr
        tr 1
        tr all
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
        # Show picker for paused and lost timers
        $resumableTimers = @($timers | Where-Object { $_.State -eq 'Paused' -or $_.State -eq 'Lost' })

        if ($resumableTimers.Count -eq 0) {
            Write-Host "`n  No paused or lost timers to resume.`n" -ForegroundColor Gray
            return
        }

        $options = Get-TimerPickerOptions -Timers $resumableTimers -ShowRemaining -IncludeAllOption -AllOptionLabel "Resume ALL resumable timers ($($resumableTimers.Count) total)" -AllOptionColor 'Green'

        $selectedId = Show-MenuPicker -Title "SELECT TIMER TO RESUME" -Options $options -AllowCancel
        if (-not $selectedId) {
            return
        }

        $Id = $selectedId
        $timers = @(Get-TimerData)
    }

    if ($Id -eq 'all') {
        # Resume all paused and lost timers
        $count = 0
        foreach ($t in $timers) {
            if ($t.State -ne 'Paused' -and $t.State -ne 'Lost') { continue }

            # Use saved remaining time if available, otherwise full duration
            $seconds = if ($t.RemainingSeconds -and $t.RemainingSeconds -gt 0) {
                $t.RemainingSeconds
            } else {
                $t.Seconds
            }

            if ($seconds -le 0) {
                $t.State = 'Completed'
                continue
            }

            # Update times
            $now = Get-Date
            $t.StartTime = $now.ToString('o')
            $t.EndTime = $now.AddSeconds($seconds).ToString('o')
            $t.State = 'Running'
            $t | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $null -Force

            # Start the job with full timer info for notifications
            Start-TimerJob -Timer ([PSCustomObject]@{
                Id          = $t.Id
                Seconds     = $seconds
                Message     = $t.Message
                Duration    = Format-Duration -Seconds $t.Seconds
                StartTime   = $t.StartTime
                RepeatTotal = $t.RepeatTotal
                CurrentRun  = $t.CurrentRun
            })
            $count++
        }
        Save-TimerData -Timers $timers
        Write-Host "`n  Resumed $count timer(s).`n" -ForegroundColor Green
    }
    else {
        # Resume specific timer
        $timer = $timers | Where-Object { $_.Id -eq $Id }

        if (-not $timer) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
            return
        }

        if ($timer.State -ne 'Paused' -and $timer.State -ne 'Lost') {
            Write-Host "`n  Timer '$Id' cannot be resumed (state: $($timer.State)).`n" -ForegroundColor Yellow
            return
        }

        # Use saved remaining time if available, otherwise full duration
        $isLost = $timer.State -eq 'Lost'
        $seconds = if ($timer.RemainingSeconds -and $timer.RemainingSeconds -gt 0) {
            $timer.RemainingSeconds
        } else {
            $timer.Seconds
        }

        if ($seconds -le 0) {
            $timer.State = 'Completed'
            Save-TimerData -Timers $timers
            Write-Host "`n  Timer '$Id' has no time remaining.`n" -ForegroundColor Yellow
            return
        }

        # Update times
        $now = Get-Date
        $newEndTime = $now.AddSeconds($seconds)
        $timer.StartTime = $now.ToString('o')
        $timer.EndTime = $newEndTime.ToString('o')
        $timer.State = 'Running'
        $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $null -Force

        # Start the job with full timer info for notifications
        Start-TimerJob -Timer ([PSCustomObject]@{
            Id          = $timer.Id
            Seconds     = $seconds
            Message     = $timer.Message
            Duration    = Format-Duration -Seconds $timer.Seconds
            StartTime   = $timer.StartTime
            RepeatTotal = $timer.RepeatTotal
            CurrentRun  = $timer.CurrentRun
        })
        Save-TimerData -Timers $timers

        $action = if ($isLost) { "restarted" } else { "resumed" }
        Write-Host "`n  Timer " -ForegroundColor Green -NoNewline
        Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
        Write-Host " $action. " -ForegroundColor Green -NoNewline
        Write-Host "Ends at $($newEndTime.ToString('HH:mm:ss'))`n" -ForegroundColor Yellow
    }
}

function TimerRemove {
    <#
    .SYNOPSIS
        Removes a timer from the list by ID, or clears all finished timers.
    .PARAMETER Id
        The timer ID to remove. Use 'all' to remove all, 'done' to remove completed/stopped only.
    .EXAMPLE
        TimerRemove abc1
        TimerRemove done
        TimerRemove all
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
        # Sync first to get current states
        $timers = @(Sync-TimerData)

        if ($timers.Count -eq 0) {
            Write-Host "`n  No timers to remove.`n" -ForegroundColor Gray
            return
        }

        # Build options with done and all actions
        $options = Get-TimerPickerOptions -Timers $timers -IncludeDoneOption -IncludeAllOption -AllOptionLabel "Remove ALL timers ($($timers.Count) total)" -AllOptionColor 'Red'

        # Force add "all" option even if only 1 timer (override the count check)
        if ($timers.Count -eq 1) {
            $options += @{
                Id    = 'all'
                Label = "Remove ALL timers ($($timers.Count) total)"
                Color = 'Red'
            }
        }

        $selectedId = Show-MenuPicker -Title "SELECT TIMER TO REMOVE" -Options $options -AllowCancel
        if (-not $selectedId) {
            return
        }

        $Id = $selectedId
        # Re-fetch timers in case state changed
        $timers = @(Get-TimerData)
    }

    if ($Id -eq 'all') {
        # Stop and remove all
        foreach ($t in $timers) {
            Stop-TimerTask -TimerId $t.Id
        }
        Save-TimerData -Timers @()
        Write-Host "`n  All timers removed.`n" -ForegroundColor Yellow
    }
    elseif ($Id -eq 'done') {
        # Remove only completed/lost (preserve stopped/paused)
        $toKeep = @()
        $removed = 0

        foreach ($t in $timers) {
            if ($t.State -eq 'Completed' -or $t.State -eq 'Lost') {
                Stop-TimerTask -TimerId $t.Id
                $removed++
            }
            else {
                $toKeep += $t
            }
        }

        Save-TimerData -Timers $toKeep
        Write-Host "`n  Removed $removed finished timer(s).`n" -ForegroundColor Yellow
    }
    else {
        # Remove specific timer
        $timer = $timers | Where-Object { $_.Id -eq $Id }

        if (-not $timer) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
            return
        }

        # Stop scheduled task if running
        Stop-TimerTask -TimerId $Id

        # Remove from list
        $timers = @($timers | Where-Object { $_.Id -ne $Id })
        Save-TimerData -Timers $timers

        Write-Host "`n  Timer " -ForegroundColor Yellow -NoNewline
        Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
        Write-Host " removed.`n" -ForegroundColor Yellow
    }
}

