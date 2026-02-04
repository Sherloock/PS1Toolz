# Timer module - Sequence timer parsing and handling

# Timer presets - loaded from config.ps1
$script:TimerPresets = if ($global:Config -and $global:Config.TimerPresets) {
    $global:Config.TimerPresets
} else {
    @{}
}

function Test-TimerSequence {
    <#
    .SYNOPSIS
        Checks if a string is a timer sequence pattern (contains grouping or comma).
    #>
    param([string]$Pattern)

    # Check for preset name first
    if ($script:TimerPresets.ContainsKey($Pattern)) {
        return $true
    }

    # Check for sequence syntax: parentheses, comma separators, or xN multiplier
    if ($Pattern -match '\(' -or $Pattern -match ',' -or $Pattern -match '\)x\d+') {
        return $true
    }

    return $false
}

function ConvertFrom-TimerSequence {
    <#
    .SYNOPSIS
        Parses a timer sequence string into structured phase data.
    #>
    param([string]$Pattern)

    # Resolve preset if applicable
    if ($script:TimerPresets.ContainsKey($Pattern)) {
        $Pattern = $script:TimerPresets[$Pattern].Pattern
    }

    # Tokenize the pattern
    $tokens = @()
    $i = 0
    $len = $Pattern.Length

    while ($i -lt $len) {
        $char = $Pattern[$i]

        # Skip whitespace
        if ($char -match '\s') {
            $i++
            continue
        }

        # Parentheses
        if ($char -eq '(') {
            $tokens += @{ Type = 'LPAREN'; Value = '(' }
            $i++
            continue
        }
        if ($char -eq ')') {
            $tokens += @{ Type = 'RPAREN'; Value = ')' }
            $i++
            continue
        }

        # Comma
        if ($char -eq ',') {
            $tokens += @{ Type = 'COMMA'; Value = ',' }
            $i++
            continue
        }

        # Multiplier (xN)
        if ($char -eq 'x' -and $i + 1 -lt $len -and $Pattern[$i + 1] -match '\d') {
            $numStr = ''
            $i++  # Skip 'x'
            while ($i -lt $len -and $Pattern[$i] -match '\d') {
                $numStr += $Pattern[$i]
                $i++
            }
            $tokens += @{ Type = 'MULT'; Value = [int]$numStr }
            continue
        }

        # Quoted string (label)
        if ($char -eq "'" -or $char -eq '"') {
            $quote = $char
            $str = ''
            $i++  # Skip opening quote
            while ($i -lt $len -and $Pattern[$i] -ne $quote) {
                $str += $Pattern[$i]
                $i++
            }
            $i++  # Skip closing quote
            $tokens += @{ Type = 'LABEL'; Value = $str }
            continue
        }

        # Duration (e.g., 25m, 1h30m, 90s)
        if ($char -match '\d') {
            $durStr = ''
            while ($i -lt $len -and $Pattern[$i] -match '[\dhms]') {
                $durStr += $Pattern[$i]
                $i++
            }
            $tokens += @{ Type = 'DURATION'; Value = $durStr }
            continue
        }

        # Word (unquoted label)
        if ($char -match '[a-zA-Z]') {
            $word = ''
            while ($i -lt $len -and $Pattern[$i] -match '[a-zA-Z0-9_-]') {
                $word += $Pattern[$i]
                $i++
            }
            $tokens += @{ Type = 'LABEL'; Value = $word }
            continue
        }

        # Unknown character, skip
        $i++
    }

    # Parse tokens into AST
    $ast = ParseSequence -Tokens $tokens -Index ([ref]0)

    # Expand AST into flat phase list
    $phases = Expand-TimerSequence -Ast $ast

    return $phases
}

function ParseSequence {
    <#
    .SYNOPSIS
        Internal recursive parser for sequence tokens.
    #>
    param(
        [array]$Tokens,
        [ref]$Index
    )

    $items = @()

    while ($Index.Value -lt $Tokens.Count) {
        $token = $Tokens[$Index.Value]

        if ($token.Type -eq 'LPAREN') {
            # Start of group
            $Index.Value++
            $groupItems = ParseSequence -Tokens $Tokens -Index $Index

            # Check for multiplier after closing paren
            $mult = 1
            if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Type -eq 'MULT') {
                $mult = $Tokens[$Index.Value].Value
                $Index.Value++
            }

            $items += @{
                Type     = 'GROUP'
                Items    = $groupItems
                Multiply = $mult
            }
        }
        elseif ($token.Type -eq 'RPAREN') {
            # End of group
            $Index.Value++
            break
        }
        elseif ($token.Type -eq 'COMMA') {
            # Separator, skip
            $Index.Value++
        }
        elseif ($token.Type -eq 'DURATION') {
            # Single phase
            $seconds = ConvertTo-Seconds -Time $token.Value
            $label = "Timer"
            $Index.Value++

            # Check for label
            if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Type -eq 'LABEL') {
                $label = $Tokens[$Index.Value].Value
                $Index.Value++
            }

            $items += @{
                Type    = 'PHASE'
                Seconds = $seconds
                Label   = $label
                Duration = $token.Value
            }
        }
        else {
            # Skip unknown
            $Index.Value++
        }
    }

    return $items
}

function Expand-TimerSequence {
    <#
    .SYNOPSIS
        Expands AST into flat phase list with loop metadata.
    #>
    param(
        [array]$Ast,
        [string]$ParentLoopId = '',
        [int]$ParentIteration = 1,
        [int]$ParentTotal = 1
    )

    $phases = @()
    $groupCounter = 0

    foreach ($item in $Ast) {
        if ($item.Type -eq 'PHASE') {
            $phases += [PSCustomObject]@{
                Seconds       = $item.Seconds
                Label         = $item.Label
                Duration      = $item.Duration
                LoopId        = $ParentLoopId
                LoopIteration = $ParentIteration
                LoopTotal     = $ParentTotal
            }
        }
        elseif ($item.Type -eq 'GROUP') {
            $groupCounter++
            $loopId = if ($ParentLoopId) { "${ParentLoopId}.${groupCounter}" } else { [string]$groupCounter }

            for ($iter = 1; $iter -le $item.Multiply; $iter++) {
                $expanded = Expand-TimerSequence -Ast $item.Items -ParentLoopId $loopId -ParentIteration $iter -ParentTotal $item.Multiply
                $phases += $expanded
            }
        }
    }

    return $phases
}

function Get-SequenceSummary {
    <#
    .SYNOPSIS
        Returns summary information about a timer sequence.
    #>
    param([array]$Phases)

    $totalSeconds = 0
    foreach ($p in $Phases) {
        $totalSeconds += $p.Seconds
    }

    # Build description from unique labels
    $labelCounts = @{}
    foreach ($p in $Phases) {
        if (-not $labelCounts.ContainsKey($p.Label)) {
            $labelCounts[$p.Label] = 0
        }
        $labelCounts[$p.Label]++
    }

    $descParts = @()
    foreach ($label in $labelCounts.Keys) {
        $count = $labelCounts[$label]
        if ($count -gt 1) {
            $descParts += "${count}x $label"
        }
        else {
            $descParts += $label
        }
    }

    return [PSCustomObject]@{
        TotalSeconds  = $totalSeconds
        TotalDuration = Format-Duration -Seconds $totalSeconds
        PhaseCount    = $Phases.Count
        Description   = $descParts -join ', '
    }
}

function New-SequenceTimerFromPhases {
    <#
    .SYNOPSIS
        Builds the sequence timer object and phases data from parsed phases.
    #>
    param(
        [string]$Id,
        [string]$OriginalPattern,
        [array]$Phases,
        [object]$Summary,
        [DateTime]$Now
    )
    $firstPhase = $Phases[0]
    $endTime = $Now.AddSeconds($firstPhase.Seconds)
    $phasesData = @()
    foreach ($p in $Phases) {
        $phasesData += @{
            Seconds       = $p.Seconds
            Label         = $p.Label
            Duration      = $p.Duration
            LoopId        = $p.LoopId
            LoopIteration = $p.LoopIteration
            LoopTotal     = $p.LoopTotal
        }
    }
    $phaseCount = $Phases.Count
    $totalSecs = $Summary.TotalSeconds
    $timer = [PSCustomObject]@{
        Id              = $Id
        Duration        = $Summary.TotalDuration
        Seconds         = $firstPhase.Seconds
        Message         = $firstPhase.Label
        StartTime       = $Now.ToString('o')
        EndTime         = $endTime.ToString('o')
        RepeatTotal     = 1
        RepeatRemaining = 0
        CurrentRun      = 1
        State           = 'Running'
        IsSequence      = $true
        SequencePattern = $OriginalPattern
        Phases          = $phasesData
        CurrentPhase    = 0
        TotalPhases     = $phaseCount
        PhaseLabel      = $firstPhase.Label
        TotalSeconds    = $totalSecs
    }
    return $timer
}

function Write-SequenceTimerConfirmation {
    <#
    .SYNOPSIS
        Displays confirmation message for started sequence timer.
    #>
    param(
        [string]$Id,
        [string]$OriginalPattern,
        [object]$Summary,
        [int]$PhaseCount,
        [object]$FirstPhase,
        [DateTime]$EndTime
    )
    Write-Host ""
    Write-Host "  Sequence started " -ForegroundColor Green -NoNewline
    Write-Host "[$Id]" -ForegroundColor Cyan
    Write-Host "  Pattern:  " -ForegroundColor Gray -NoNewline
    Write-Host $OriginalPattern -ForegroundColor White
    Write-Host "  Total:    " -ForegroundColor Gray -NoNewline
    Write-Host "$($Summary.TotalDuration) ($PhaseCount phases)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Current phase:" -ForegroundColor DarkGray
    Write-Host "  [1/$PhaseCount] " -ForegroundColor Magenta -NoNewline
    Write-Host $FirstPhase.Label -ForegroundColor Cyan -NoNewline
    Write-Host " - $(Format-Duration -Seconds $FirstPhase.Seconds)" -ForegroundColor White
    Write-Host "  Ends at:  " -ForegroundColor Gray -NoNewline
    Write-Host $EndTime.ToString('HH:mm:ss') -ForegroundColor Yellow
    Write-Host ""
}

function Start-SequenceTimerJob {
    <#
    .SYNOPSIS
        Starts a sequence timer phase using Windows Scheduled Task.
    #>
    param([PSCustomObject]$Timer)

    $taskName = "PSTimer_$($Timer.Id)"
    $dataFile = Join-Path $env:TEMP "ps-timers.json"

    # Calculate trigger time for current phase
    $triggerTime = (Get-Date).AddSeconds($Timer.Seconds)

    # Build the notification script using here-string
    $script = @"
`$timerId = '$($Timer.Id)'
`$dataFile = '$dataFile'

# Read current timer state from JSON
if (-not (Test-Path -LiteralPath `$dataFile)) { exit }
`$jsonContent = Get-Content -LiteralPath `$dataFile -Raw -ErrorAction SilentlyContinue
`$parsed = `$jsonContent | ConvertFrom-Json
`$timers = New-Object System.Collections.ArrayList
`$parsed | ForEach-Object { [void]`$timers.Add(`$_) }
`$timer = `$timers | Where-Object { `$_.Id -eq `$timerId }

if (-not `$timer -or -not `$timer.IsSequence) { exit }

`$currentPhase = [int]`$timer.CurrentPhase
`$totalPhases = [int]`$timer.TotalPhases
`$phaseLabel = `$timer.PhaseLabel

# Beep notification - different tones for phase vs completion
if (`$currentPhase -eq `$totalPhases - 1) {
    [console]::beep(523, 200); [console]::beep(659, 200); [console]::beep(784, 400)
} else {
    [console]::beep(440, 300)
}

`$nextPhaseIdx = `$currentPhase + 1

if (`$nextPhaseIdx -lt `$totalPhases) {
    # More phases to go
    `$phases = `$timer.Phases
    `$nextPhase = `$phases[`$nextPhaseIdx]
    `$nextSeconds = [int]`$nextPhase.Seconds
    `$nextLabel = `$nextPhase.Label
    
    `$timer.CurrentPhase = `$nextPhaseIdx
    `$timer.PhaseLabel = `$nextLabel
    `$timer.Seconds = `$nextSeconds
    `$timer.Message = `$nextLabel
    `$timer.StartTime = (Get-Date).ToString('o')
    `$timer.EndTime = (Get-Date).AddSeconds(`$nextSeconds).ToString('o')
    `$timer.State = 'Running'
    
    # Schedule next phase
    `$nextTrigger = (Get-Date).AddSeconds(`$nextSeconds)
    `$nextAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File ```"`$env:TEMP\PSTimer_`$timerId.ps1```""
    `$nextTriggerObj = New-ScheduledTaskTrigger -Once -At `$nextTrigger
    `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName "PSTimer_`$timerId" -Action `$nextAction -Trigger `$nextTriggerObj -Settings `$settings -Force | Out-Null
} else {
    # All phases done
    `$timer.State = 'Completed'
    `$timer.CurrentPhase = `$totalPhases
    Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "`$env:TEMP\PSTimer_`$timerId.ps1" -Force -ErrorAction SilentlyContinue
}

ConvertTo-Json -InputObject `$timers -Depth 10 | Set-Content -LiteralPath `$dataFile -Force

# Show popup
`$phaseNum = `$currentPhase + 1
`$endStr = (Get-Date).ToString('HH:mm:ss')
if (`$currentPhase -eq `$totalPhases - 1) {
    `$body = @("Sequence completed!", "", "All `$totalPhases phases done", "Finished: `$endStr")
    `$title = "Sequence Complete!"
} else {
    `$nextPhaseNum = `$phaseNum + 1
    `$body = @("Phase `$phaseNum/`$totalPhases done: `$phaseLabel", "", "Next: Phase `$nextPhaseNum", "Time: `$endStr")
    `$title = "Phase Complete"
}
`$popup = New-Object -ComObject WScript.Shell
`$popup.Popup((`$body -join [char]10), 0, `$title, 64) | Out-Null
"@

    # Write script to temp file
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
