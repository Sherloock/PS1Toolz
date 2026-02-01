# Development utilities

function PortKill {
    <#
    .SYNOPSIS
        Finds and terminates the process running on a specific TCP port.
    .PARAMETER Port
        The port number (e.g. 3000).
    #>
    param ([int]$Port)

    if (-not $PSBoundParameters.ContainsKey('Port')) {
        throw "Port parameter is required."
    }

    $ProcId = (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue).OwningProcess | Select-Object -First 1
    if ($ProcId) {
        try {
            $Name = (Get-Process -Id $ProcId).ProcessName
            Write-Host "Killing '$Name' (PID: $ProcId) on port $Port..." -ForegroundColor Yellow
            Stop-Process -Id $ProcId -Force -ErrorAction Stop
            Write-Host "Port $Port is now clear." -ForegroundColor Green
        } catch {
            Write-Host "Access Denied. Run PS as Admin." -ForegroundColor Red
        }
    } else {
        Write-Host "No process on port $Port." -ForegroundColor Cyan
    }
}

function NodeKill {
    <#
    .SYNOPSIS
        Scans for top-level node_modules only. Ignores nested ones inside dependencies.
    .PARAMETER Path
        Optional. A path or shortcut (from Config.NodeKillPaths) to scan. Defaults to current directory.
    #>
    param (
        [Parameter(Position = 0)]
        [string]$Path
    )

    # Resolve path from shortcut or use provided path
    $scanPath = "."
    if ($Path) {
        if ($global:Config -and $global:Config.NodeKillPaths -and $global:Config.NodeKillPaths.Contains($Path)) {
            $scanPath = $global:Config.NodeKillPaths[$Path]
            Write-Host "`nUsing shortcut '$Path' -> $scanPath" -ForegroundColor Cyan
        } elseif (Test-Path $Path) {
            $scanPath = $Path
        } else {
            Write-Host "Path '$Path' not found and not a valid shortcut." -ForegroundColor Red
            if ($global:Config -and $global:Config.NodeKillPaths) {
                Write-Host "Available shortcuts: $($global:Config.NodeKillPaths.Keys -join ', ')" -ForegroundColor Yellow
            }
            return
        }
    }

    Write-Host "`nScanning for project node_modules... (Top-level only)" -ForegroundColor Cyan

    # This logic finds node_modules but prevents recursing INTO them
    $folders = Get-ChildItem -Path $scanPath -Recurse -Directory -Filter "node_modules" -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch 'node_modules.+node_modules' }

    if (-not $folders) {
        Write-Host "No project node_modules found." -ForegroundColor Green
        return
    }

    $list = @()
    foreach ($f in $folders) {
        # Calculate total size of this project's node_modules
        $sizeBytes = (Get-ChildItem -LiteralPath $f.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($sizeBytes -is [System.Array]) {
            $sumBytes = 0.0
            foreach ($value in $sizeBytes) {
                if ($null -ne $value) {
                    $sumBytes += [double]$value
                }
            }
            $sizeBytes = $sumBytes
        }
        if ($null -eq $sizeBytes) {
            $sizeBytes = 0
        }
        $sizeMB = [math]::Round([double]$sizeBytes / 1MB, 2)

        $list += [PSCustomObject]@{ Size = $sizeMB; Path = $f.FullName }
    }

    # Sort by size descending and assign IDs
    $list = $list | Sort-Object -Property Size -Descending
    $index = 1
    $list = $list | ForEach-Object { $_ | Add-Member -NotePropertyName ID -NotePropertyValue $index -PassThru; $index++ }

    Write-Host "`nID  | SIZE (MB) | PROJECT PATH" -ForegroundColor White
    Write-Host ("-" * 70)
    foreach ($item in $list) {
        $color = if ($item.Size -gt 500) { "Red" } else { "Yellow" }
        # Show the parent folder path so it's easier to see which project it is
        $projectPath = Split-Path $item.Path -Parent
        Write-Host ("{0,-3} | {1,9} | {2}" -f $item.ID, $item.Size, $projectPath) -ForegroundColor $color
    }
    Write-Host ("-" * 70)

    $totalSizeMB = 0.0
    foreach ($item in $list) {
        if ($null -ne $item.Size) {
            $totalSizeMB += [double]$item.Size
        }
    }
    $totalScanGB = [math]::Round($totalSizeMB / 1024, 2)
    Write-Host "TOTAL RECLAIMABLE SPACE: $totalScanGB GB" -ForegroundColor Green

    Write-Host "`nOptions: ID numbers (1,3), 'all', or Enter to cancel."
    $selection = Read-Host "Selection"

    if ([string]::IsNullOrWhiteSpace($selection)) { return }

    $toDelete = if ($selection -eq "all") { $list } else {
        $ids = $selection -split ',' | ForEach-Object { $_.Trim() }
        $list | Where-Object { $ids -contains $_.ID.ToString() }
    }

    $cleanedBytes = 0
    foreach ($item in $toDelete) {
        Write-Host "Cleaning $($item.Path)..." -NoNewline -ForegroundColor Yellow
        try {
            # Capture size before deleting
            $currentSize = $item.Size
            Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction Stop
            $cleanedBytes += $currentSize
            Write-Host " DONE (+$($currentSize) MB)" -ForegroundColor Green
        } catch {
            Write-Host " FAILED (File in use?)" -ForegroundColor Red
        }
    }

    # Final Summary
    if ($cleanedBytes -gt 0) {
        $totalSaved = if ($cleanedBytes -gt 1024) {
            "$([math]::Round($cleanedBytes / 1024, 2)) GB"
        } else {
            "$cleanedBytes MB"
        }
        Write-Host "`n[ SUCCESS ] Total space reclaimed: $totalSaved" -ForegroundColor Green
    }
    Write-Host "Cleanup finished.`n"
}
