# Timer and countdown utilities

function timer {
    <#
    .SYNOPSIS
        Starts a countdown timer. Supports formats like '1h20m', '90s', '10m10s'.
    .PARAMETER Time
        The duration (e.g., 1h20m, 90s, 10m, 5s).
    .PARAMETER Message
        Optional message to show when time is up.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Time,
        [string]$Message = "Time is up!"
    )

    # 1. Parse the time string using Regex
    $seconds = 0
    if ($Time -match '(\d+)h') { $seconds += [int]$matches[1] * 3600 }
    if ($Time -match '(\d+)m') { $seconds += [int]$matches[1] * 60 }
    if ($Time -match '(\d+)s') { $seconds += [int]$matches[1] }

    # Handle pure numbers as seconds (e.g., '90')
    if ($Time -match '^\d+$') { $seconds = [int]$Time }

    if ($seconds -le 0) {
        Write-Host "Invalid time format. Use 1h20m, 90s, etc." -ForegroundColor Red
        return
    }

    $endTime = (Get-Date).AddSeconds($seconds)
    Write-Host "`nTimer started for: $Time" -ForegroundColor Cyan
    Write-Host "Message: $Message" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop.`n"

    # 2. Countdown Loop
    try {
        while ($seconds -gt 0) {
            $diff = $endTime - (Get-Date)
            $seconds = [int]$diff.TotalSeconds

            if ($seconds -lt 0) { break }

            # Format the remaining time: HH:mm:ss
            $display = "{0:D2}:{1:D2}:{2:D2}" -f $diff.Hours, $diff.Minutes, $diff.Seconds

            # Use `r to overwrite the same line
            Write-Host "`r[ COUNTDOWN: $display ] " -NoNewline -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }

        # 3. Time's up alert
        Write-Host "`r[ COUNTDOWN: 00:00:00 ] " -ForegroundColor Red
        [console]::beep(440, 500)
        Write-Host "`n`n*******************************" -ForegroundColor Green
        Write-Host " $Message" -ForegroundColor White -BackgroundColor DarkGreen
        Write-Host "*******************************`n"

        # Optional: Pop up a Windows message box
        $wshell = New-Object -ComObject WScript.Shell
        $wshell.Popup($Message, 0, "Timer Finished", 0x40) | Out-Null
    }
    catch {
        Write-Host "`n`nTimer stopped." -ForegroundColor Gray
    }
}



function TimerBg {
    <#
    .SYNOPSIS
        Runs a timer in a background job.
    .PARAMETER Time
        The duration (e.g., 1h20m, 90s, 10m).
    .PARAMETER Msg
        Optional message to show when time is up.
    #>
    param($Time, $Msg = "Time is up!")
    # Runs the timer function in a background job
    Start-Job -Name "TimerJob" -ScriptBlock {
        param($t, $m)
        # Re-define the logic for the background job
        $sec = 0
        if ($t -match '(\d+)h') { $sec += [int]$matches[1] * 3600 }
        if ($t -match '(\d+)m') { $sec += [int]$matches[1] * 60 }
        if ($t -match '(\d+)s') { $sec += [int]$matches[1] }
        Start-Sleep -Seconds $sec
        [console]::beep(440,500)
        (New-Object -ComObject WScript.Shell).Popup($m, 0, "Background Timer", 64)
    } -ArgumentList $Time, $Msg

    Write-Host "Timer for $Time running in background..." -ForegroundColor Cyan
}

function TimerList {
    <#
    .SYNOPSIS
        Shows all active background timers.
    #>
    Get-Job -Name "TimerJob*" | Select-Object Id, State, @{Name="Started";Expression={$_.PSBeginTime}}
}

function TimerStop {
    <#
    .SYNOPSIS
        Cancels and removes all background timers.
    #>
    Stop-Job -Name "TimerJob*"
    Remove-Job -Name "TimerJob*"
    Write-Host "All background timers canceled." -ForegroundColor Yellow
}
