# Timer module - Timer operations (pause, resume, remove)

function Get-TimerResumeSeconds {
    <#
    .SYNOPSIS
        Returns the number of seconds to use when resuming a timer (from RemainingSeconds or full duration).
    #>
    param([PSCustomObject]$Timer)
    if ($Timer.RemainingSeconds -and $Timer.RemainingSeconds -gt 0) {
        return $Timer.RemainingSeconds
    }
    return $Timer.Seconds
}

function Invoke-PauseTimersBulk {
    <#
    .SYNOPSIS
        Pauses all running timers in the given array. Updates objects and saves. Returns count paused.
    #>
    param([array]$Timers)
    $count = 0
    foreach ($t in $Timers) {
        if ($t.State -ne 'Running') { continue }
        Stop-TimerTask -TimerId $t.Id
        $endTime = [DateTime]::Parse($t.EndTime)
        $remaining = [int]($endTime - (Get-Date)).TotalSeconds
        if ($remaining -lt 0) { $remaining = 0 }
        $t | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $remaining -Force
        $t.State = 'Paused'
        $count++
    }
    Save-TimerData -Timers $Timers
    return $count
}

function Invoke-PauseSingleTimer {
    param([array]$Timers, [string]$Id)
    $timer = $Timers | Where-Object { $_.Id -eq $Id }
    if (-not $timer) { return $false }
    if ($timer.State -ne 'Running') { return $null }
    Stop-TimerTask -TimerId $Id
    $endTime = [DateTime]::Parse($timer.EndTime)
    $remaining = [int]($endTime - (Get-Date)).TotalSeconds
    if ($remaining -lt 0) { $remaining = 0 }
    $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $remaining -Force
    $timer.State = 'Paused'
    Save-TimerData -Timers $Timers
    return $remaining
}

function Invoke-ResumeTimersBulk {
    param([array]$Timers)
    $count = 0
    foreach ($t in $Timers) {
        if ($t.State -ne 'Paused' -and $t.State -ne 'Lost') { continue }
        $seconds = Get-TimerResumeSeconds -Timer $t
        if ($seconds -le 0) {
            $t.State = 'Completed'
            continue
        }
        $now = Get-Date
        $t.StartTime = $now.ToString('o')
        $t.EndTime = $now.AddSeconds($seconds).ToString('o')
        $t.State = 'Running'
        $t | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $null -Force
        Start-TimerJob -Timer ([PSCustomObject]@{
            Id = $t.Id; Seconds = $seconds; Message = $t.Message; Duration = Format-Duration -Seconds $t.Seconds
            StartTime = $t.StartTime; RepeatTotal = $t.RepeatTotal; CurrentRun = $t.CurrentRun
        })
        $count++
    }
    Save-TimerData -Timers $Timers
    return $count
}

function Invoke-ResumeSingleTimer {
    param([array]$Timers, [string]$Id)
    $timer = $Timers | Where-Object { $_.Id -eq $Id }
    if (-not $timer) { return @{ Found = $false } }
    if ($timer.State -ne 'Paused' -and $timer.State -ne 'Lost') { return @{ Found = $true; CanResume = $false } }
    $isLost = ($timer.State -eq 'Lost')
    $seconds = Get-TimerResumeSeconds -Timer $timer
    if ($seconds -le 0) {
        $timer.State = 'Completed'
        Save-TimerData -Timers $Timers
        return @{ Found = $true; CanResume = $false; NoTime = $true }
    }
    $now = Get-Date
    $newEndTime = $now.AddSeconds($seconds)
    $timer.StartTime = $now.ToString('o')
    $timer.EndTime = $newEndTime.ToString('o')
    $timer.State = 'Running'
    $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $null -Force
    Start-TimerJob -Timer ([PSCustomObject]@{
        Id = $timer.Id; Seconds = $seconds; Message = $timer.Message; Duration = Format-Duration -Seconds $timer.Seconds
        StartTime = $timer.StartTime; RepeatTotal = $timer.RepeatTotal; CurrentRun = $timer.CurrentRun
    })
    Save-TimerData -Timers $Timers
    return @{ Found = $true; CanResume = $true; IsLost = $isLost; NewEndTime = $newEndTime }
}

function Invoke-RemoveTimersBulk {
    param([array]$Timers, [string]$Mode)
    if ($Mode -eq 'all') {
        foreach ($t in $Timers) { Stop-TimerTask -TimerId $t.Id }
        Save-TimerData -Timers @()
        return $Timers.Count
    }
    $toKeep = @()
    $removed = 0
    foreach ($t in $Timers) {
        if ($t.State -eq 'Completed' -or $t.State -eq 'Lost') {
            Stop-TimerTask -TimerId $t.Id
            $removed++
        }
        else { $toKeep += $t }
    }
    Save-TimerData -Timers $toKeep
    return $removed
}

function Invoke-RemoveSingleTimer {
    param([array]$Timers, [string]$Id)
    $timer = $Timers | Where-Object { $_.Id -eq $Id }
    if (-not $timer) { return $false }
    Stop-TimerTask -TimerId $Id
    $newList = @($Timers | Where-Object { $_.Id -ne $Id })
    Save-TimerData -Timers $newList
    return $true
}
