# Timer module - Data persistence and management

# Timer data file path (shared across timer functions)
$script:TimerDataFile = Join-Path $env:TEMP "ps-timers.json"
# Cache for watch mode optimization
$script:TimerDataCache = $null
$script:TimerDataCacheTime = [DateTime]::MinValue

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
            $obj = [PSCustomObject]@{
                Id               = $t.Id
                Duration         = $t.Duration
                Seconds          = [int]$t.Seconds
                Message          = $t.Message
                StartTime        = $t.StartTime
                EndTime          = $t.EndTime
                RepeatTotal      = [int]$t.RepeatTotal
                RepeatRemaining  = [int]$t.RepeatRemaining
                CurrentRun       = [int]$t.CurrentRun
                State            = $t.State
                RemainingSeconds = if ($t.RemainingSeconds) { [int]$t.RemainingSeconds } else { $null }
                IsSequence       = if ($t.IsSequence) { $true } else { $false }
            }

            # Add sequence-specific fields if present
            if ($t.IsSequence) {
                $obj | Add-Member -NotePropertyName 'SequencePattern' -NotePropertyValue $t.SequencePattern
                $obj | Add-Member -NotePropertyName 'Phases' -NotePropertyValue $t.Phases
                $obj | Add-Member -NotePropertyName 'CurrentPhase' -NotePropertyValue ([int]$t.CurrentPhase)
                $obj | Add-Member -NotePropertyName 'TotalPhases' -NotePropertyValue ([int]$t.TotalPhases)
                $obj | Add-Member -NotePropertyName 'PhaseLabel' -NotePropertyValue $t.PhaseLabel
                $obj | Add-Member -NotePropertyName 'TotalSeconds' -NotePropertyValue ([int]$t.TotalSeconds)
            }

            $clean += $obj
        }
    }

    ConvertTo-Json -InputObject $clean -Depth 10 | Set-Content -LiteralPath $script:TimerDataFile -Force
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

function Get-TimerForWatch {
    <#
    .SYNOPSIS
        Resolves which timer to watch: by Id, single active, or picker. Returns timer or error info.
    #>
    param(
        [array]$Timers,
        [string]$Id
    )
    $active = @($Timers | Where-Object { $_.State -eq 'Running' })
    if ($active.Count -eq 0) {
        return @{ Error = 'NoActive' }
    }
    if ([string]::IsNullOrEmpty($Id)) {
        if ($active.Count -eq 1) {
            return @{ Timer = $active[0] }
        }
        $options = Get-TimerPickerOptions -Timers $active -FilterState 'Running' -ShowRemaining
        $selectedId = Show-MenuPicker -Title "SELECT TIMER TO WATCH" -Options $options -AllowCancel
        if (-not $selectedId) { return @{ Error = 'Cancelled' } }
        $t = $active | Where-Object { $_.Id -eq $selectedId }
        return @{ Timer = $t }
    }
    $t = $Timers | Where-Object { $_.Id -eq $Id }
    if (-not $t) {
        return @{ Error = 'NotFound'; Id = $Id }
    }
    if ($t.State -ne 'Running') {
        return @{ Error = 'NotRunning'; Id = $Id; State = $t.State }
    }
    return @{ Timer = $t }
}

function Get-TruncatedMessage {
    <#
    .SYNOPSIS
        Truncates a message to a maximum length with ellipsis.
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

function Get-TimerPickerOptions {
    <#
    .SYNOPSIS
        Builds options array for Show-MenuPicker from timer list.
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
