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

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# ============================================================================
# TIMER HELPERS
# ============================================================================

# Timer data file path (shared across timer functions)
$script:TimerDataFile = Join-Path $env:TEMP "ps-timers.json"

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
        Generates a short unique timer ID (4 chars).
    #>
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $id = -join (1..4 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $id
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
        Syncs timer data with actual job states, cleans up finished jobs.
    #>
    $timers = @(Get-TimerData)
    $changed = $false

    foreach ($timer in $timers) {
        $jobName = "Timer_$($timer.Id)"
        $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue

        if ($job) {
            if ($job.State -eq 'Completed') {
                if ($timer.RepeatRemaining -gt 0) {
                    $timer.RepeatRemaining = $timer.RepeatRemaining - 1
                    $timer.CurrentRun = $timer.RepeatTotal - $timer.RepeatRemaining
                    $timer.StartTime = (Get-Date).ToString('o')
                    $timer.EndTime = (Get-Date).AddSeconds($timer.Seconds).ToString('o')
                    $timer.State = 'Running'

                    Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
                    Start-TimerJob -Timer $timer
                    $changed = $true
                }
                else {
                    $timer.State = 'Completed'
                    Remove-Job -Name $jobName -Force -ErrorAction SilentlyContinue
                    $changed = $true
                }
            }
            elseif ($job.State -eq 'Running') {
                $timer.State = 'Running'
            }
            elseif ($job.State -eq 'Stopped') {
                $timer.State = 'Stopped'
            }
        }
        else {
            # Job not found - could be a different terminal/process
            # Only mark as lost if the timer should have already ended
            if ($timer.State -eq 'Running') {
                try {
                    $endTime = [DateTime]::ParseExact($timer.EndTime, 'o', $null)
                    if ((Get-Date) -gt $endTime) {
                        # Timer expired without job - mark as lost
                        $timer.State = 'Lost'
                        $changed = $true
                    }
                    # Otherwise, timer is still valid but job is in another process - leave as Running
                }
                catch {
                    # Invalid EndTime format - mark as lost
                    $timer.State = 'Lost'
                    $changed = $true
                }
            }
        }
    }

    if ($changed) {
        Save-TimerData -Timers $timers
    }

    return $timers
}

function Start-TimerJob {
    <#
    .SYNOPSIS
        Internal function to start a timer job.
    #>
    param([PSCustomObject]$Timer)

    $jobName = "Timer_$($Timer.Id)"

    Start-Job -Name $jobName -ScriptBlock {
        param($seconds, $message, $timerId)

        Start-Sleep -Seconds $seconds
        [console]::beep(440, 500)
        $popup = New-Object -ComObject WScript.Shell
        $popup.Popup($message, 0, "Timer [$timerId]", 64) | Out-Null
    } -ArgumentList $Timer.Seconds, $Timer.Message, $Timer.Id | Out-Null
}
