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
    Write-Host " [-m 'msg']" -ForegroundColor Gray
    Write-Host "      Foreground countdown (blocks terminal)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tbg <time>" -ForegroundColor Yellow -NoNewline
    Write-Host " [-m 'msg'] [-r N]" -ForegroundColor Gray
    Write-Host "      Background timer with optional repeat" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tlist" -ForegroundColor Yellow -NoNewline
    Write-Host " [-a] [-w]" -ForegroundColor Gray
    Write-Host "      List active timers (-a all, -w live watch)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tstop" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|all]" -ForegroundColor Gray
    Write-Host "      Pause specific timer or all (can resume)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tresume" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|all]" -ForegroundColor Gray
    Write-Host "      Resume stopped timer(s)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "tremove" -ForegroundColor Yellow -NoNewline
    Write-Host " [id|done|all]" -ForegroundColor Gray
    Write-Host "      Remove timer(s) from list" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Time formats: " -ForegroundColor DarkGray -NoNewline
    Write-Host "1h30m, 25m, 90s, 1h20m30s" -ForegroundColor White
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor DarkGray
    Write-Host "    t 25m -m 'Coffee break'" -ForegroundColor Gray
    Write-Host "    tbg 1h -r 3 -m 'Stretch'" -ForegroundColor Gray
    Write-Host "    tstop 1" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# FOREGROUND TIMER
# ============================================================================

function Timer {
    <#
    .SYNOPSIS
        Starts a countdown timer or shows help. Formats: '1h20m', '90s', '10m10s'.
    .PARAMETER Time
        The duration (e.g., 1h20m, 90s, 10m, 5s). Omit to see timer commands.
    .PARAMETER Message
        Optional message to show when time is up.
    #>
    param(
        [Parameter(Position=0)][string]$Time,
        [Alias('m')][string]$Message = "Time is up!"
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

    $endTime = (Get-Date).AddSeconds($seconds)
    Write-Host "`nTimer started for: $Time" -ForegroundColor Cyan
    Write-Host "Message: $Message" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop.`n"

    try {
        while ($seconds -gt 0) {
            $diff = $endTime - (Get-Date)
            $seconds = [int]$diff.TotalSeconds

            if ($seconds -lt 0) { break }

            $display = "{0:D2}:{1:D2}:{2:D2}" -f $diff.Hours, $diff.Minutes, $diff.Seconds
            Write-Host "`r[ COUNTDOWN: $display ] " -NoNewline -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }

        Write-Host "`r[ COUNTDOWN: 00:00:00 ] " -ForegroundColor Red
        [console]::beep(440, 500)
        Write-Host "`n`n*******************************" -ForegroundColor Green
        Write-Host " $Message" -ForegroundColor White -BackgroundColor DarkGreen
        Write-Host "*******************************`n"

        $wshell = New-Object -ComObject WScript.Shell
        $wshell.Popup($Message, 0, "Timer Finished", 0x40) | Out-Null
    }
    catch {
        Write-Host "`n`nTimer stopped." -ForegroundColor Gray
    }
}

# ============================================================================
# BACKGROUND TIMER FUNCTIONS
# ============================================================================

function TimerBg {
    <#
    .SYNOPSIS
        Starts a background timer with optional repeat. Use TimerList to view all timers.
    .PARAMETER Time
        The duration (e.g., 1h20m, 90s, 10m, 3h).
    .PARAMETER Message
        Optional message to show when time is up.
    .PARAMETER Repeat
        Number of times to repeat the timer (e.g., -r 3 repeats 3 times total).
    .EXAMPLE
        TimerBg 25m -m "Break time!"
        TimerBg 1h30m -r 3 -m "Hydration reminder"
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Time,
        [Alias('m')][string]$Message = "Time is up!",
        [Alias('r')][int]$Repeat = 1
    )

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
        Write-Host "  Use 'TimerBg <time>' to create one.`n" -ForegroundColor DarkGray
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
        Write-Host "  Commands: " -ForegroundColor DarkGray -NoNewline
        Write-Host "tstop <id>" -ForegroundColor White -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "tresume <id>" -ForegroundColor White -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "tremove <id>" -ForegroundColor White -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "tlist -w" -ForegroundColor White -NoNewline
        Write-Host " (watch)" -ForegroundColor DarkGray
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

    [Console]::CursorVisible = $false

    try {
        while ($true) {
            # Clear screen for clean redraw
            Clear-Host

            # Get timers
            $timers = @(Sync-TimerData)
            if (-not $All) {
                $timers = @($timers | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Stopped' })
            }

            if ($timers.Count -eq 0) {
                Write-Host "`n  No active timers." -ForegroundColor Gray
                break
            }

            # Count by state
            $running = @($timers | Where-Object { $_.State -eq 'Running' }).Count
            $stopped = @($timers | Where-Object { $_.State -eq 'Stopped' }).Count

            Write-Host ""
            Write-Host "  BACKGROUND TIMERS " -ForegroundColor Cyan -NoNewline
            Write-Host "($running running" -ForegroundColor Green -NoNewline
            if ($stopped -gt 0) { Write-Host ", $stopped stopped" -ForegroundColor Yellow -NoNewline }
            Write-Host ")" -ForegroundColor Gray
            Write-Host "  =================" -ForegroundColor DarkCyan
            Write-Host ""

            # Column widths
            $colId = 5; $colState = 10; $colDuration = 11; $colRemaining = 11; $colEndsAt = 10; $colRepeat = 8

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
                $remaining = $endTime - $now

                $remainingStr = if ($remaining.TotalSeconds -lt 0) { "00:00:00" } else {
                    "{0:D2}:{1:D2}:{2:D2}" -f [int]$remaining.Hours, $remaining.Minutes, $remaining.Seconds
                }

                $stateColor = switch ($t.State) { 'Running' { 'Green' } 'Stopped' { 'Yellow' } default { 'Gray' } }
                $repeatStr = if ($t.RepeatTotal -gt 1) { "$($t.CurrentRun)/$($t.RepeatTotal)" } else { "-" }
                $msgDisplay = if ($t.Message.Length -gt 20) { $t.Message.Substring(0, 17) + "..." } else { $t.Message }
                $endsAtStr = if ($t.State -eq 'Running') { $endTime.ToString('HH:mm:ss') } else { "-" }
                $durationStr = Format-Duration -Seconds $t.Seconds

                if ($t.State -ne 'Running') { $remainingStr = "-"; $endsAtStr = "-" }

                Write-Host "  " -NoNewline
                Write-Host ("{0,-$colId}" -f $t.Id) -ForegroundColor Cyan -NoNewline
                Write-Host ("{0,-$colState}" -f $t.State) -ForegroundColor $stateColor -NoNewline
                Write-Host ("{0,-$colDuration}" -f $durationStr) -ForegroundColor White -NoNewline
                Write-Host ("{0,-$colRemaining}" -f $remainingStr) -ForegroundColor Yellow -NoNewline
                Write-Host ("{0,-$colEndsAt}" -f $endsAtStr) -ForegroundColor Green -NoNewline
                Write-Host ("{0,-$colRepeat}" -f $repeatStr) -ForegroundColor Magenta -NoNewline
                Write-Host $msgDisplay -ForegroundColor Gray
            }

            Write-Host ""
            Write-Host "  Press any key to exit watch mode..." -ForegroundColor DarkGray

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
Set-Alias -Name tbg -Value TimerBg -Scope Global
Set-Alias -Name tlist -Value TimerList -Scope Global
Set-Alias -Name tstop -Value TimerStop -Scope Global
Set-Alias -Name tresume -Value TimerResume -Scope Global
Set-Alias -Name tremove -Value TimerRemove -Scope Global

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
