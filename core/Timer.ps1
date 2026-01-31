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
    Write-Host "ts" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|all]" -ForegroundColor Gray
    Write-Host "      Pause specific timer or all (can resume)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tr" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|all]" -ForegroundColor Gray
    Write-Host "      Resume stopped timer(s)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "td" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|done|all]" -ForegroundColor Gray
    Write-Host "      Remove timer(s) from list" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tc" -ForegroundColor Yellow
    Write-Host "      Clear all Lost and Completed timers" -ForegroundColor DarkGray
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
        $timers = @($timers | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Stopped' })
    }

    if ($timers.Count -eq 0) {
        Write-Host "`n  No active timers." -ForegroundColor Gray
        Write-Host "  Use 'TimerList -a' to see all timers.`n" -ForegroundColor DarkGray
        return $false
    }

    # Count by state
    $running = @($timers | Where-Object { $_.State -eq 'Running' }).Count
    $stopped = @($timers | Where-Object { $_.State -eq 'Stopped' }).Count

    Write-Host ""
    Write-Host "  BACKGROUND TIMERS " -ForegroundColor Cyan -NoNewline
    Write-Host "($running running" -ForegroundColor Green -NoNewline
    if ($stopped -gt 0) {
        Write-Host ", $stopped stopped" -ForegroundColor Yellow -NoNewline
    }
    Write-Host ")" -ForegroundColor Gray
    Write-Host "  =================" -ForegroundColor DarkCyan
    Write-Host ""

    # Column widths
    $colId = 5
    $colState = 10
    $colDuration = 11
    $colRemaining = 11
    $colEndsAt = 10
    $colRepeat = 8

    # Header
    Write-Host "  " -NoNewline
    Write-Host ("{0,-$colId}" -f "ID") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colState}" -f "STATE") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colDuration}" -f "DURATION") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colRemaining}" -f "REMAINING") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colEndsAt}" -f "ENDS AT") -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-$colRepeat}" -f "REPEAT") -ForegroundColor DarkGray -NoNewline
    Write-Host "MESSAGE" -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 75)) -ForegroundColor DarkGray

    foreach ($t in $timers) {
        $now = Get-Date
        $endTime = [DateTime]::Parse($t.EndTime)

        # Calculate remaining time
        $remaining = $endTime - $now
        if ($remaining.TotalSeconds -lt 0) {
            $remainingStr = "00:00:00"
        }
        else {
            $remainingStr = "{0:D2}:{1:D2}:{2:D2}" -f [int]$remaining.Hours, $remaining.Minutes, $remaining.Seconds
        }

        # State color
        $stateColor = switch ($t.State) {
            'Running'   { 'Green' }
            'Completed' { 'DarkGray' }
            'Stopped'   { 'Yellow' }
            'Lost'      { 'Red' }
            default     { 'Gray' }
        }

        # Repeat info
        if ($t.RepeatTotal -gt 1) {
            $repeatStr = "$($t.CurrentRun)/$($t.RepeatTotal)"
        }
        else {
            $repeatStr = "-"
        }

        # Truncate message
        $msgDisplay = $t.Message
        if ($msgDisplay.Length -gt 20) {
            $msgDisplay = $msgDisplay.Substring(0, 17) + "..."
        }

        # Ends at time
        $endsAtStr = if ($t.State -eq 'Running') { $endTime.ToString('HH:mm:ss') } else { "-" }

        # Duration formatted
        $durationStr = Format-Duration -Seconds $t.Seconds

        # Output row
        Write-Host "  " -NoNewline
        Write-Host ("{0,-$colId}" -f $t.Id) -ForegroundColor Cyan -NoNewline
        Write-Host ("{0,-$colState}" -f $t.State) -ForegroundColor $stateColor -NoNewline
        Write-Host ("{0,-$colDuration}" -f $durationStr) -ForegroundColor White -NoNewline

        if ($t.State -eq 'Running') {
            Write-Host ("{0,-$colRemaining}" -f $remainingStr) -ForegroundColor Yellow -NoNewline
            Write-Host ("{0,-$colEndsAt}" -f $endsAtStr) -ForegroundColor Green -NoNewline
        }
        else {
            Write-Host ("{0,-$colRemaining}" -f "-") -ForegroundColor DarkGray -NoNewline
            Write-Host ("{0,-$colEndsAt}" -f "-") -ForegroundColor DarkGray -NoNewline
        }

        Write-Host ("{0,-$colRepeat}" -f $repeatStr) -ForegroundColor Magenta -NoNewline
        Write-Host $msgDisplay -ForegroundColor Gray
    }

    Write-Host ""

    if ($ShowCommands) {
        Write-Host "  Stop " -ForegroundColor DarkGray -NoNewline
        Write-Host "ts <id>" -ForegroundColor White -NoNewline
        Write-Host " | Resume " -ForegroundColor DarkGray -NoNewline
        Write-Host "tr <id>" -ForegroundColor White -NoNewline
        Write-Host " | Delete " -ForegroundColor DarkGray -NoNewline
        Write-Host "td <id>" -ForegroundColor White -NoNewline
        Write-Host " | Clear " -ForegroundColor DarkGray -NoNewline
        Write-Host "tc" -ForegroundColor White -NoNewline
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

    # ANSI color codes
    $esc = [char]27
    $reset = "$esc[0m"
    $cyan = "$esc[36m"
    $green = "$esc[32m"
    $yellow = "$esc[33m"
    $magenta = "$esc[35m"
    $white = "$esc[97m"
    $gray = "$esc[90m"
    $darkCyan = "$esc[36m"

    [Console]::CursorVisible = $false

    try {
        while ($true) {
            # Get timers first (before clearing)
            $timers = @(Sync-TimerData)
            if (-not $All) {
                $timers = @($timers | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Stopped' })
            }

            # Build entire output as single string
            $sb = [System.Text.StringBuilder]::new()

            if ($timers.Count -eq 0) {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("${gray}  No active timers.${reset}")
                Clear-Host
                [Console]::Write($sb.ToString())
                break
            }

            # Count by state
            $running = @($timers | Where-Object { $_.State -eq 'Running' }).Count
            $stopped = @($timers | Where-Object { $_.State -eq 'Stopped' }).Count

            [void]$sb.AppendLine("")
            $stoppedPart = if ($stopped -gt 0) { "${yellow}, $stopped stopped${reset}" } else { "" }
            [void]$sb.AppendLine("${cyan}  BACKGROUND TIMERS ${green}($running running${stoppedPart}${green})${reset}")
            [void]$sb.AppendLine("${darkCyan}  ===================${reset}")
            [void]$sb.AppendLine("")

            # Column widths
            $colId = 5; $colState = 10; $colDuration = 11; $colRemaining = 11; $colEndsAt = 10; $colRepeat = 8

            # Header
            $hdr = "  {0,-$colId}{1,-$colState}{2,-$colDuration}{3,-$colRemaining}{4,-$colEndsAt}{5,-$colRepeat}MESSAGE" -f "ID", "STATE", "DURATION", "REMAINING", "ENDS AT", "REPEAT"
            [void]$sb.AppendLine("${gray}$hdr${reset}")
            [void]$sb.AppendLine("${gray}  $("-" * 75)${reset}")

            foreach ($t in $timers) {
                $now = Get-Date
                $endTime = [DateTime]::Parse($t.EndTime)
                $remaining = $endTime - $now

                $remainingStr = if ($remaining.TotalSeconds -lt 0) { "00:00:00" } else {
                    "{0:D2}:{1:D2}:{2:D2}" -f [int]$remaining.Hours, $remaining.Minutes, $remaining.Seconds
                }

                $stateColor = switch ($t.State) { 'Running' { $green } 'Stopped' { $yellow } default { $gray } }
                $repeatStr = if ($t.RepeatTotal -gt 1) { "$($t.CurrentRun)/$($t.RepeatTotal)" } else { "-" }
                $msgDisplay = if ($t.Message.Length -gt 20) { $t.Message.Substring(0, 17) + "..." } else { $t.Message }
                $endsAtStr = if ($t.State -eq 'Running') { $endTime.ToString('HH:mm:ss') } else { "-" }
                $durationStr = Format-Duration -Seconds $t.Seconds

                if ($t.State -ne 'Running') { $remainingStr = "-"; $endsAtStr = "-" }

                $line = "  ${cyan}{0,-$colId}${reset}${stateColor}{1,-$colState}${reset}${white}{2,-$colDuration}${reset}${yellow}{3,-$colRemaining}${reset}${green}{4,-$colEndsAt}${reset}${magenta}{5,-$colRepeat}${reset}${gray}{6}${reset}" -f $t.Id, $t.State, $durationStr, $remainingStr, $endsAtStr, $repeatStr, $msgDisplay
                [void]$sb.AppendLine($line)
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("${gray}  Press any key to exit watch mode...${reset}")

            # Clear and write in one go (minimizes flicker)
            Clear-Host
            [Console]::Write($sb.ToString())

            # Check for keypress (1 second loop)
            $waited = 0
            while ($waited -lt 1000) {
                if ([Console]::KeyAvailable) {
                    [Console]::ReadKey($true) | Out-Null
                    Write-Host ""
                    return
                }
                Start-Sleep -Milliseconds 100
                $waited += 100
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
Set-Alias -Name ts -Value TimerStop -Scope Global
Set-Alias -Name tr -Value TimerResume -Scope Global
Set-Alias -Name td -Value TimerRemove -Scope Global
Set-Alias -Name tc -Value TimerClear -Scope Global

function TimerStop {
    <#
    .SYNOPSIS
        Stops a background timer by ID, or all timers if no ID specified.
    .PARAMETER Id
        The timer ID to stop. Use 'all' or omit to stop all timers.
    .EXAMPLE
        TimerStop abc1
        TimerStop all
    #>
    param(
        [Parameter(Position=0)][string]$Id
    )

    $timers = @(Get-TimerData)

    if ($timers.Count -eq 0) {
        Write-Host "`n  No timers to stop.`n" -ForegroundColor Gray
        return
    }

    if ([string]::IsNullOrEmpty($Id) -or $Id -eq 'all') {
        # Stop all timers
        $count = 0
        foreach ($t in $timers) {
            if ($t.State -ne 'Running') { continue }

            $jobName = "Timer_$($t.Id)"
            $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue
            if ($job) {
                Stop-Job -Name $jobName -ErrorAction SilentlyContinue
                Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
            }

            # Save remaining seconds for resume
            $endTime = [DateTime]::Parse($t.EndTime)
            $remaining = [int]($endTime - (Get-Date)).TotalSeconds
            if ($remaining -lt 0) { $remaining = 0 }
            $t | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $remaining -Force
            $t.State = 'Stopped'
            $count++
        }
        Save-TimerData -Timers $timers
        Write-Host "`n  Stopped $count timer(s).`n" -ForegroundColor Yellow
    }
    else {
        # Stop specific timer
        $timer = $timers | Where-Object { $_.Id -eq $Id }

        if (-not $timer) {
            Write-Host "`n  Timer '$Id' not found.`n" -ForegroundColor Red
            return
        }

        if ($timer.State -ne 'Running') {
            Write-Host "`n  Timer '$Id' is not running.`n" -ForegroundColor Yellow
            return
        }

        $jobName = "Timer_$Id"
        $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue

        if ($job) {
            Stop-Job -Name $jobName -ErrorAction SilentlyContinue
            Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
        }

        # Save remaining seconds for resume
        $endTime = [DateTime]::Parse($timer.EndTime)
        $remaining = [int]($endTime - (Get-Date)).TotalSeconds
        if ($remaining -lt 0) { $remaining = 0 }
        $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $remaining -Force
        $timer.State = 'Stopped'
        Save-TimerData -Timers $timers

        Write-Host "`n  Timer " -ForegroundColor Yellow -NoNewline
        Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
        Write-Host " stopped. " -ForegroundColor Yellow -NoNewline
        Write-Host "($(Format-Duration -Seconds $remaining) remaining)`n" -ForegroundColor Gray
    }
}

function TimerResume {
    <#
    .SYNOPSIS
        Resumes a stopped background timer by ID, or all stopped timers.
    .PARAMETER Id
        The timer ID to resume. Use 'all' or omit to resume all stopped timers.
    .EXAMPLE
        TimerResume abc1
        TimerResume all
    #>
    param(
        [Parameter(Position=0)][string]$Id
    )

    $timers = @(Get-TimerData)

    if ($timers.Count -eq 0) {
        Write-Host "`n  No timers to resume.`n" -ForegroundColor Gray
        return
    }

    if ([string]::IsNullOrEmpty($Id) -or $Id -eq 'all') {
        # Resume all stopped timers
        $count = 0
        foreach ($t in $timers) {
            if ($t.State -ne 'Stopped') { continue }

            $remaining = if ($t.RemainingSeconds) { $t.RemainingSeconds } else { $t.Seconds }
            if ($remaining -le 0) {
                $t.State = 'Completed'
                continue
            }

            # Update end time
            $now = Get-Date
            $newEndTime = $now.AddSeconds($remaining)
            $t.EndTime = $newEndTime.ToString('o')
            $t.State = 'Running'
            $t | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $null -Force

            # Start the job
            Start-TimerJob -Timer ([PSCustomObject]@{
                Id      = $t.Id
                Seconds = $remaining
                Message = $t.Message
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

        if ($timer.State -ne 'Stopped') {
            Write-Host "`n  Timer '$Id' is not stopped (state: $($timer.State)).`n" -ForegroundColor Yellow
            return
        }

        $remaining = if ($timer.RemainingSeconds) { $timer.RemainingSeconds } else { $timer.Seconds }
        if ($remaining -le 0) {
            $timer.State = 'Completed'
            Save-TimerData -Timers $timers
            Write-Host "`n  Timer '$Id' has no time remaining.`n" -ForegroundColor Yellow
            return
        }

        # Update end time
        $now = Get-Date
        $newEndTime = $now.AddSeconds($remaining)
        $timer.EndTime = $newEndTime.ToString('o')
        $timer.State = 'Running'
        $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $null -Force

        # Start the job
        Start-TimerJob -Timer ([PSCustomObject]@{
            Id      = $timer.Id
            Seconds = $remaining
            Message = $timer.Message
        })
        Save-TimerData -Timers $timers

        Write-Host "`n  Timer " -ForegroundColor Green -NoNewline
        Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
        Write-Host " resumed. " -ForegroundColor Green -NoNewline
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
        Write-Host "`n  Specify timer ID, 'done' (finished only), or 'all'.`n" -ForegroundColor Yellow
        return
    }

    if ($Id -eq 'all') {
        # Stop and remove all
        foreach ($t in $timers) {
            $jobName = "Timer_$($t.Id)"
            Stop-Job -Name $jobName -ErrorAction SilentlyContinue
            Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
        }
        Save-TimerData -Timers @()
        Write-Host "`n  All timers removed.`n" -ForegroundColor Yellow
    }
    elseif ($Id -eq 'done') {
        # Remove only completed/stopped
        $toKeep = @()
        $removed = 0

        foreach ($t in $timers) {
            if ($t.State -eq 'Running') {
                $toKeep += $t
            }
            else {
                $jobName = "Timer_$($t.Id)"
                Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
                $removed++
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

        # Stop job if running
        $jobName = "Timer_$Id"
        Stop-Job -Name $jobName -ErrorAction SilentlyContinue
        Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue

        # Remove from list
        $timers = @($timers | Where-Object { $_.Id -ne $Id })
        Save-TimerData -Timers $timers

        Write-Host "`n  Timer " -ForegroundColor Yellow -NoNewline
        Write-Host "[$Id]" -ForegroundColor Cyan -NoNewline
        Write-Host " removed.`n" -ForegroundColor Yellow
    }
}

function TimerClear {
    <#
    .SYNOPSIS
        Clears all Lost and Completed timers from the list.
    .EXAMPLE
        TimerClear
        tc
    #>
    $timers = @(Get-TimerData)

    if ($timers.Count -eq 0) {
        Write-Host "`n  No timers to clear.`n" -ForegroundColor Gray
        return
    }

    $toKeep = @()
    $cleared = 0

    foreach ($t in $timers) {
        if ($t.State -eq 'Lost' -or $t.State -eq 'Completed') {
            $jobName = "Timer_$($t.Id)"
            Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
            $cleared++
        }
        else {
            $toKeep += $t
        }
    }

    if ($cleared -eq 0) {
        Write-Host "`n  No Lost or Completed timers to clear.`n" -ForegroundColor Gray
        return
    }

    Save-TimerData -Timers $toKeep
    Write-Host "`n  Cleared $cleared timer(s).`n" -ForegroundColor Yellow
}
