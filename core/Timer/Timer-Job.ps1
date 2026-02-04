# Timer module - Windows Scheduled Tasks integration

function Start-TimerJob {
    <#
    .SYNOPSIS
        Internal function to start a timer using Windows Scheduled Task.
    .DESCRIPTION
        Uses Scheduled Tasks instead of PowerShell jobs so timers survive terminal closure.
    #>
    param([PSCustomObject]$Timer)

    $taskName = "PSTimer_$($Timer.Id)"
    $dataFile = Join-Path $env:TEMP "ps-timers.json"

    # Calculate trigger time
    $triggerTime = (Get-Date).AddSeconds($Timer.Seconds)

    # Build the notification script that runs when timer fires
    $script = @"
`$timerId = '$($Timer.Id)'
`$message = '$($Timer.Message -replace "'", "''")'
`$duration = '$($Timer.Duration)'
`$repeatTotal = $($Timer.RepeatTotal)
`$currentRun = $($Timer.CurrentRun)
`$timerSeconds = $($Timer.Seconds)
`$dataFile = '$dataFile'
`$logFile = "`$env:TEMP\PSTimer_`$timerId.log"

try {
    # Beep notification
    [console]::beep(440, 500)

    # Update timer data FIRST (before popup, so tl shows correct state)
    if (Test-Path -LiteralPath `$dataFile) {
        `$jsonContent = Get-Content -LiteralPath `$dataFile -Raw -ErrorAction Stop
        `$parsed = `$jsonContent | ConvertFrom-Json

        # Ensure we have an array
        `$timers = @()
        if (`$parsed -is [array]) {
            `$timers = @(`$parsed)
        } else {
            `$timers = @(`$parsed)
        }

        # Find timer by ID (compare as strings)
        `$timerIndex = -1
        for (`$i = 0; `$i -lt `$timers.Count; `$i++) {
            if ([string]`$timers[`$i].Id -eq [string]`$timerId) {
                `$timerIndex = `$i
                break
            }
        }

        if (`$timerIndex -ge 0) {
            `$timer = `$timers[`$timerIndex]
            `$repeatRemaining = [int]`$timer.RepeatRemaining

            if (`$repeatRemaining -gt 0) {
                # More repeats to go - schedule next run
                `$newRepeatRemaining = `$repeatRemaining - 1
                `$newCurrentRun = [int]`$timer.RepeatTotal - `$newRepeatRemaining
                `$newStart = (Get-Date).ToString('o')
                `$newEnd = (Get-Date).AddSeconds(`$timerSeconds).ToString('o')

                # Create updated timer object
                `$updatedTimer = [PSCustomObject]@{
                    Id              = `$timer.Id
                    Duration        = `$timer.Duration
                    Seconds         = [int]`$timer.Seconds
                    Message         = `$timer.Message
                    StartTime       = `$newStart
                    EndTime         = `$newEnd
                    RepeatTotal     = [int]`$timer.RepeatTotal
                    RepeatRemaining = `$newRepeatRemaining
                    CurrentRun      = `$newCurrentRun
                    State           = 'Running'
                    RemainingSeconds = `$null
                }
                `$timers[`$timerIndex] = `$updatedTimer

                # Save BEFORE scheduling next task
                ConvertTo-Json -InputObject `$timers -Depth 10 | Set-Content -LiteralPath `$dataFile -Force

                # Schedule next run
                `$nextTrigger = (Get-Date).AddSeconds(`$timerSeconds)
                `$scriptPath = "`$env:TEMP\PSTimer_`$timerId.ps1"
                `$nextAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File ```"`$scriptPath```""
                `$nextTriggerObj = New-ScheduledTaskTrigger -Once -At `$nextTrigger
                `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

                Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName "PSTimer_`$timerId" -Action `$nextAction -Trigger `$nextTriggerObj -Settings `$settings -Force | Out-Null

                `$currentRun = `$newCurrentRun
            } else {
                # All done - create completed timer
                `$updatedTimer = [PSCustomObject]@{
                    Id              = `$timer.Id
                    Duration        = `$timer.Duration
                    Seconds         = [int]`$timer.Seconds
                    Message         = `$timer.Message
                    StartTime       = `$timer.StartTime
                    EndTime         = `$timer.EndTime
                    RepeatTotal     = [int]`$timer.RepeatTotal
                    RepeatRemaining = 0
                    CurrentRun      = [int]`$timer.RepeatTotal
                    State           = 'Completed'
                    RemainingSeconds = `$null
                }
                `$timers[`$timerIndex] = `$updatedTimer

                ConvertTo-Json -InputObject `$timers -Depth 10 | Set-Content -LiteralPath `$dataFile -Force

                Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath "`$env:TEMP\PSTimer_`$timerId.ps1" -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch {
    # Log error for debugging
    "`$(Get-Date -Format 'o') ERROR: `$(`$_.Exception.Message)" | Add-Content -LiteralPath `$logFile -Force
}

# Show popup (after state update, so it can block without affecting tl display)
`$endStr = (Get-Date).ToString('HH:mm:ss')
`$body = @("Timer #`$timerId completed!", "", "Duration: `$duration", "Finished: `$endStr")
if (`$repeatTotal -gt 1) { `$body += "Run:      `$currentRun of `$repeatTotal" }
`$popup = New-Object -ComObject WScript.Shell
`$popup.Popup((`$body -join [char]10), 0, `$message, 64) | Out-Null
"@

    # Write script to temp file (scheduled tasks work better with script files)
    $scriptPath = Join-Path $env:TEMP "PSTimer_$($Timer.Id).ps1"
    $script | Set-Content -LiteralPath $scriptPath -Force -Encoding UTF8

    # Remove any existing task with same name
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    # Create scheduled task
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At $triggerTime
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
}

function Stop-TimerTask {
    <#
    .SYNOPSIS
        Stops and unregisters a timer's scheduled task.
    #>
    param([int]$TimerId)

    $taskName = "PSTimer_$TimerId"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    # Also clean up the script file
    $scriptPath = Join-Path $env:TEMP "PSTimer_$TimerId.ps1"
    Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
}
