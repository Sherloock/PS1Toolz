# Core helper functions used by other modules
# These are internal utilities - excluded from '??' dashboard

# ============================================================================
# SIZE HELPERS
# ============================================================================

function Get-ReadableSize {
    <#
    .SYNOPSIS
        Converts bytes into a human-readable format (GB, MB, KB).
    #>
    param([long]$Bytes)

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1GB) { return ($Bytes / 1GB).ToString("F2", $inv) + " GB" }
    if ($Bytes -ge 1MB) { return ($Bytes / 1MB).ToString("F2", $inv) + " MB" }
    if ($Bytes -ge 1KB) { return ($Bytes / 1KB).ToString("F2", $inv) + " KB" }
    return "$Bytes B"
}

# ============================================================================
# TIMER HELPERS
# ============================================================================

# Timer data file path (shared across timer functions)
$script:TimerDataFile = Join-Path $env:TEMP "ps-timers.json"
# Cache for watch mode optimization
$script:TimerDataCache = $null
$script:TimerDataCacheTime = [DateTime]::MinValue

function ConvertTo-Seconds {
    <#
    .SYNOPSIS
        Converts time string (1h20m, 90s, etc.) to seconds.
    #>
    param([string]$Time)

    $seconds = 0
    if ($Time -match '(\d+)h') { $seconds += [int]$matches[1] * 3600 }
    if ($Time -match '(\d+)m') { $seconds += [int]$matches[1] * 60 }
    if ($Time -match '(\d+)s') { $seconds += [int]$matches[1] }
    if ($Time -match '^\d+$') { $seconds = [int]$Time }

    return $seconds
}

function New-TimerId {
    <#
    .SYNOPSIS
        Generates a sequential timer ID (1, 2, 3, ...).
    #>
    $timers = @(Get-TimerData)
    if ($timers.Count -eq 0) {
        return "1"
    }

    # Find highest numeric ID
    $maxId = 0
    foreach ($t in $timers) {
        if ($t.Id -match '^\d+$') {
            $num = [int]$t.Id
            if ($num -gt $maxId) { $maxId = $num }
        }
    }

    return [string]($maxId + 1)
}

function Get-TimerData {
    <#
    .SYNOPSIS
        Loads timer metadata from JSON file.
    #>
    if (Test-Path -LiteralPath $script:TimerDataFile) {
        try {
            $content = Get-Content -LiteralPath $script:TimerDataFile -Raw -ErrorAction Stop
            if ($content) {
                $data = $content | ConvertFrom-Json
                # Handle nested value structures from ConvertTo-Json
                $result = @()
                foreach ($item in $data) {
                    if ($item.PSObject.Properties.Name -contains 'Id') {
                        $result += $item
                    }
                }
                return $result
            }
        }
        catch {
            # File corrupted or empty, return empty array
        }
    }
    return @()
}

function Get-TimerDataIfChanged {
    <#
    .SYNOPSIS
        Returns timer data only if the JSON file was modified since last read.
    .DESCRIPTION
        Optimized for watch mode - avoids unnecessary file reads by checking
        the file's LastWriteTime against a cached timestamp.
    .PARAMETER Force
        If set, always reads the file regardless of modification time.
    .RETURNS
        Hashtable with Keys: Data (array), Changed (bool)
    #>
    param([switch]$Force)

    if (-not (Test-Path -LiteralPath $script:TimerDataFile)) {
        $script:TimerDataCache = @()
        $script:TimerDataCacheTime = [DateTime]::MinValue
        return @{ Data = @(); Changed = $true }
    }

    $fileInfo = Get-Item -LiteralPath $script:TimerDataFile -ErrorAction SilentlyContinue
    if (-not $fileInfo) {
        return @{ Data = @(); Changed = $false }
    }

    $lastWrite = $fileInfo.LastWriteTime

    # Check if file was modified since last cache
    if (-not $Force -and $script:TimerDataCache -ne $null -and $lastWrite -le $script:TimerDataCacheTime) {
        return @{ Data = $script:TimerDataCache; Changed = $false }
    }

    # File changed or no cache - read fresh data
    $script:TimerDataCache = @(Get-TimerData)
    $script:TimerDataCacheTime = $lastWrite

    return @{ Data = $script:TimerDataCache; Changed = $true }
}

function Save-TimerData {
    <#
    .SYNOPSIS
        Saves timer metadata to JSON file.
    #>
    param([array]$Timers)

    if ($Timers.Count -eq 0) {
        if (Test-Path -LiteralPath $script:TimerDataFile) {
            Remove-Item -LiteralPath $script:TimerDataFile -Force
        }
        return
    }

    # Flatten and clean the array before saving
    $clean = @()
    foreach ($t in $Timers) {
        if ($t.PSObject.Properties.Name -contains 'Id') {
            $clean += [PSCustomObject]@{
                Id              = $t.Id
                Duration        = $t.Duration
                Seconds         = [int]$t.Seconds
                Message         = $t.Message
                StartTime       = $t.StartTime
                EndTime         = $t.EndTime
                RepeatTotal     = [int]$t.RepeatTotal
                RepeatRemaining = [int]$t.RepeatRemaining
                CurrentRun      = [int]$t.CurrentRun
                State           = $t.State
                RemainingSeconds = if ($t.RemainingSeconds) { [int]$t.RemainingSeconds } else { $null }
            }
        }
    }

    ConvertTo-Json -InputObject $clean -Depth 3 | Set-Content -LiteralPath $script:TimerDataFile -Force
}

function Format-Duration {
    <#
    .SYNOPSIS
        Formats seconds into readable duration (1h 20m 30s).
    #>
    param([int]$Seconds)

    $h = [math]::Floor($Seconds / 3600)
    $m = [math]::Floor(($Seconds % 3600) / 60)
    $s = $Seconds % 60

    $parts = @()
    if ($h -gt 0) { $parts += "${h}h" }
    if ($m -gt 0) { $parts += "${m}m" }
    if ($s -gt 0 -or $parts.Count -eq 0) { $parts += "${s}s" }

    return $parts -join ' '
}

function Sync-TimerData {
    <#
    .SYNOPSIS
        Syncs timer data with actual scheduled task states.
    .DESCRIPTION
        Checks if scheduled tasks exist for running timers.
        Only marks as Lost if task is missing AND end time has passed.
    #>
    $timers = @(Get-TimerData)
    $changed = $false

    foreach ($timer in $timers) {
        if ($timer.State -ne 'Running') { continue }
        
        $taskName = "PSTimer_$($timer.Id)"
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if ($task) {
            # Task exists - timer is still active, check if it ran
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
            if ($taskInfo -and $taskInfo.LastRunTime -and $taskInfo.LastRunTime -gt [DateTime]::MinValue) {
                # Task has run - the script should have updated the JSON
                # Re-read to get any changes made by the scheduled task
                $freshTimers = @(Get-TimerData)
                $freshTimer = $freshTimers | Where-Object { $_.Id -eq $timer.Id }
                if ($freshTimer -and $freshTimer.State -ne $timer.State) {
                    return $freshTimers  # Return updated data
                }
            }
            # Task exists and hasn't run yet - timer is valid
        }
        else {
            # Task not found - check if timer should have ended
            try {
                $endTime = [DateTime]::Parse($timer.EndTime)
                $remaining = [int]($endTime - (Get-Date)).TotalSeconds
                
                if ($remaining -le 0) {
                    # Timer expired without task - mark as lost
                    $timer.State = 'Lost'
                    # Save 0 remaining (cycle expired)
                    $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue 0 -Force
                    $changed = $true
                }
                # Otherwise, task might still be scheduling - give it a moment
                # If still no task after end time, mark as lost with remaining time
            }
            catch {
                # Invalid EndTime format - mark as lost
                $timer.State = 'Lost'
                $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $timer.Seconds -Force
                $changed = $true
            }
        }
    }

    if ($changed) {
        Save-TimerData -Timers $timers
    }

    return $timers
}

function Show-MenuPicker {
    <#
    .SYNOPSIS
        Shows an interactive menu picker with arrow key navigation.
    .PARAMETER Title
        Title to display above the menu.
    .PARAMETER Options
        Array of options. Each option should have 'Id', 'Label', and optionally 'Color'.
    .PARAMETER AllowCancel
        If true, Escape key cancels (returns $null).
    .RETURNS
        The selected option's Id, or $null if cancelled.
    .EXAMPLE
        $options = @(
            @{ Id = '1'; Label = 'First option' },
            @{ Id = '2'; Label = 'Second option'; Color = 'Yellow' }
        )
        $selected = Show-MenuPicker -Title 'Pick one' -Options $options
    #>
    param(
        [string]$Title,
        [array]$Options,
        [switch]$AllowCancel
    )

    if ($Options.Count -eq 0) {
        return $null
    }

    $selectedIndex = 0
    $optionCount = $Options.Count
    
    # Selection indicator
    $selector = [char]0x25B6  # ▶
    
    # ANSI color codes for flicker-free rendering
    $c = Get-AnsiColors
    
    # Map color names to ANSI codes
    $colorMap = @{
        'White'      = $c.White
        'Yellow'     = $c.Yellow
        'Green'      = $c.Green
        'Red'        = $c.Red
        'Cyan'       = $c.Cyan
        'Magenta'    = $c.Magenta
        'Gray'       = $c.Gray
        'DarkGray'   = $c.Dim
        'DarkYellow' = $c.Yellow
    }
    
    [Console]::CursorVisible = $false
    
    try {
        while ($true) {
            # Build entire output in StringBuilder to avoid flicker
            $sb = [System.Text.StringBuilder]::new()
            
            [void]$sb.AppendLine("")
            if ($Title) {
                [void]$sb.AppendLine("$($c.Cyan)  $Title$($c.Reset)")
                [void]$sb.AppendLine("$($c.DarkCyan)  $('-' * $Title.Length)$($c.Reset)")
            }
            [void]$sb.AppendLine("")
            
            # Draw options
            for ($i = 0; $i -lt $optionCount; $i++) {
                $opt = $Options[$i]
                $isSelected = ($i -eq $selectedIndex)
                $baseColorCode = if ($opt.Color -and $colorMap[$opt.Color]) { $colorMap[$opt.Color] } else { $c.White }
                
                if ($isSelected) {
                    # Selected: cyan selector with inverted colors (cyan bg, black text)
                    [void]$sb.AppendLine("$($c.Cyan)  $selector $($c.Reset)$($c.InvertCyan)$($opt.Label)$($c.Reset)")
                }
                else {
                    [void]$sb.AppendLine("    ${baseColorCode}$($opt.Label)$($c.Reset)")
                }
            }
            
            [void]$sb.AppendLine("")
            $cancelText = if ($AllowCancel) { ", Esc=cancel" } else { "" }
            [void]$sb.AppendLine("$($c.Yellow)  [Up/Down]$($c.Dim) navigate  $($c.Green)[Enter]$($c.Dim) select$cancelText$($c.Reset)")
            
            # Clear and write atomically
            Clear-Host
            [Console]::Write($sb.ToString())
            
            # Wait for keypress
            $key = [Console]::ReadKey($true)
            
            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    }
                    else {
                        $selectedIndex = $optionCount - 1  # Wrap to bottom
                    }
                }
                'DownArrow' {
                    if ($selectedIndex -lt $optionCount - 1) {
                        $selectedIndex++
                    }
                    else {
                        $selectedIndex = 0  # Wrap to top
                    }
                }
                'Enter' {
                    Clear-Host
                    return $Options[$selectedIndex].Id
                }
                'Escape' {
                    if ($AllowCancel) {
                        Clear-Host
                        return $null
                    }
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

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
    # This script is self-contained and runs independently of the terminal
    $script = @"
`$timerId = $($Timer.Id)
`$message = '$($Timer.Message -replace "'", "''")'
`$duration = '$($Timer.Duration)'
`$repeatTotal = $($Timer.RepeatTotal)
`$currentRun = $($Timer.CurrentRun)
`$timerSeconds = $($Timer.Seconds)
`$dataFile = '$dataFile'

# Beep notification
[console]::beep(440, 500)

# Update timer data FIRST (before popup, so tl shows correct state)
if (Test-Path -LiteralPath `$dataFile) {
    `$jsonContent = Get-Content -LiteralPath `$dataFile -Raw -ErrorAction SilentlyContinue
    `$parsed = `$jsonContent | ConvertFrom-Json
    `$timers = New-Object System.Collections.ArrayList
    `$parsed | ForEach-Object { [void]`$timers.Add(`$_) }
    `$timer = `$timers | Where-Object { `$_.Id -eq `$timerId }
    if (`$timer) {
        if (`$timer.RepeatRemaining -gt 0) {
            # More repeats to go - schedule next run
            `$timer.RepeatRemaining = `$timer.RepeatRemaining - 1
            `$timer.CurrentRun = `$timer.RepeatTotal - `$timer.RepeatRemaining
            `$timer.StartTime = (Get-Date).ToString('o')
            `$timer.EndTime = (Get-Date).AddSeconds(`$timerSeconds).ToString('o')
            `$timer.State = 'Running'
            
            # Schedule next run
            `$nextTrigger = (Get-Date).AddSeconds(`$timerSeconds)
            `$nextAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"`$env:TEMP\PSTimer_`$timerId.ps1`""
            `$nextTriggerObj = New-ScheduledTaskTrigger -Once -At `$nextTrigger
            `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
            Register-ScheduledTask -TaskName "PSTimer_`$timerId" -Action `$nextAction -Trigger `$nextTriggerObj -Settings `$settings -Force | Out-Null
        } else {
            # All done
            `$timer.State = 'Completed'
            Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "`$env:TEMP\PSTimer_`$timerId.ps1" -Force -ErrorAction SilentlyContinue
        }
        ConvertTo-Json -InputObject `$timers -Depth 10 | Set-Content -LiteralPath `$dataFile -Force
    }
}

# Show popup (after state update, so it can block without affecting tl display)
`$startStr = '$((Get-Date).ToString('HH:mm:ss'))'
`$endStr = (Get-Date).ToString('HH:mm:ss')
`$body = @("Timer #`$timerId completed!", "", "Duration: `$duration", "Started:  `$startStr", "Finished: `$endStr")
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
