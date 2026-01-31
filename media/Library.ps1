# Media library utilities

function Size {
    <#
    .SYNOPSIS
        Lists files and folders sorted by size in descending order.
    .PARAMETER Depth
        Defines recursion depth (0 = current folder only).
    .PARAMETER MinSize
        Minimum size threshold to display (default: 1MB). Use 0 to show all.
    #>
    param (
        [int]$Depth = $global:Config.SizeDefaults.Depth,
        [long]$MinSize = $global:Config.SizeDefaults.MinSize
    )

    $basePath = (Get-Location).Path
    $items = Get-ChildItem -Depth $Depth -ErrorAction SilentlyContinue | ForEach-Object {
        $itemSize = 0
        if ($_.PSIsContainer) {
            $files = Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue
            $itemSize = ($files | Measure-Object -Property Length -Sum).Sum
        } else {
            $itemSize = $_.Length
        }

        if ($null -eq $itemSize) { $itemSize = 0 }

        $parentPath = if ($_.PSIsContainer) { $_.Parent.FullName } else { $_.Directory.FullName }
        [PSCustomObject]@{
            Size    = Get-ReadableSize -Bytes $itemSize
            RawSize = $itemSize
            Path    = $_.FullName
            Name    = $_.Name
            Parent  = $parentPath
        }
    } | Sort-Object RawSize -Descending

    $totalBytes = ($items | Measure-Object -Property RawSize -Sum).Sum
    $filteredItems = $items | Where-Object { $_.RawSize -ge $MinSize }
    $filteredCount = $items.Count - $filteredItems.Count

    if ($Depth -gt 0) {
        Write-SizeTable -Items $filteredItems -GroupByParent -TotalBytes $totalBytes -FilteredCount $filteredCount -MinSize $MinSize
    } else {
        Write-SizeTable -Items $filteredItems -TotalBytes $totalBytes -FilteredCount $filteredCount -MinSize $MinSize
    }
}

function Movies {
    <#
    .SYNOPSIS
        Aggregates content from configured media paths and shows a grouped summary.
    #>
    $paths = if ($global:Config.MediaPaths) { $global:Config.MediaPaths } else {
        Write-Host "  No media paths configured. Copy config.example.ps1 to config.ps1" -ForegroundColor Yellow
        return
    }
    $allResults = @()
    $totalBytes = 0

    foreach ($path in $paths) {
        if (Test-Path $path) {
            $results = Get-ChildItem -LiteralPath $path -Depth 0 -ErrorAction SilentlyContinue | ForEach-Object {
                $itemSize = 0
                if ($_.PSIsContainer) {
                    $itemSize = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                } else {
                    $itemSize = $_.Length
                }

                if ($null -eq $itemSize) { $itemSize = 0 }
                $totalBytes += $itemSize
                [PSCustomObject]@{
                    Size    = Get-ReadableSize -Bytes $itemSize
                    RawSize = $itemSize
                    Path    = $_.FullName
                    Name    = $_.Name
                    Parent  = $path
                }
            }
            $allResults += $results
        }
    }

    Write-SizeTable -Items $allResults -GroupByParent -TotalBytes $totalBytes
}

function Write-SizeTable {
    <#
    .SYNOPSIS
        Pretty prints size results, optionally grouped by parent folder.
    #>
    param(
        [array]$Items,
        [switch]$GroupByParent,
        [long]$TotalBytes = 0,
        [int]$FilteredCount = 0,
        [long]$MinSize = 0
    )

    if (-not $Items -or $Items.Count -eq 0) {
        Write-Host "  No items found." -ForegroundColor DarkGray
        return
    }

    # Column widths
    $sizeWidth = 12

    if ($GroupByParent) {
        # Group by parent folder, sort groups by total size
        $groups = $Items | Group-Object Parent | ForEach-Object {
            $groupTotal = ($_.Group | Measure-Object -Property RawSize -Sum).Sum
            [PSCustomObject]@{
                Parent   = $_.Name
                Items    = $_.Group | Sort-Object RawSize -Descending
                Total    = $groupTotal
            }
        } | Sort-Object Total -Descending

        foreach ($group in $groups) {
            $groupSize = Get-ReadableSize -Bytes $group.Total
            Write-Host ""
            Write-Host ("{0,$sizeWidth}  " -f $groupSize) -NoNewline -ForegroundColor Cyan
            Write-Host $group.Parent -ForegroundColor Yellow

            foreach ($item in $group.Items) {
                $sizeColor = Get-SizeColor -Bytes $item.RawSize
                Write-Host ("{0,$sizeWidth}    " -f $item.Size) -NoNewline -ForegroundColor $sizeColor
                Write-Host $item.Name -ForegroundColor Gray
            }
        }

        if ($TotalBytes -gt 0) {
            Write-Host ""
            Write-Host ("-" * 50) -ForegroundColor DarkGray
            Write-Host ("{0,$sizeWidth}  " -f (Get-ReadableSize -Bytes $TotalBytes)) -NoNewline -ForegroundColor Green
            Write-Host "TOTAL" -ForegroundColor Green
        }
    }
    else {
        # Simple list sorted by size
        $calcTotal = 0
        foreach ($item in $Items) {
            $calcTotal += $item.RawSize
            $sizeColor = Get-SizeColor -Bytes $item.RawSize
            Write-Host ("{0,$sizeWidth}  " -f $item.Size) -NoNewline -ForegroundColor $sizeColor
            Write-Host $item.Name -ForegroundColor Gray
        }

        $finalTotal = if ($TotalBytes -gt 0) { $TotalBytes } else { $calcTotal }
        Write-Host ""
        Write-Host ("-" * 50) -ForegroundColor DarkGray
        Write-Host ("{0,$sizeWidth}  " -f (Get-ReadableSize -Bytes $finalTotal)) -NoNewline -ForegroundColor Green
        Write-Host "TOTAL" -ForegroundColor Green
    }

    if ($FilteredCount -gt 0) {
        Write-Host "  ($FilteredCount items < $(Get-ReadableSize -Bytes $MinSize) hidden)" -ForegroundColor DarkGray
    }

    Write-Host ""
}

function Get-SizeColor {
    <#
    .SYNOPSIS
        Returns color based on size thresholds.
    #>
    param([long]$Bytes)

    if ($Bytes -ge 10GB) { return "Red" }
    if ($Bytes -ge 1GB)  { return "Yellow" }
    if ($Bytes -ge 100MB) { return "White" }
    return "DarkGray"
}
