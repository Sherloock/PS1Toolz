# Media library utilities

function Size {
    <#
    .SYNOPSIS
        Lists files and folders sorted by size in descending order.
    .PARAMETER Depth
        Defines recursion depth (0 = current folder only).
    #>
    param ([int]$Depth = 0)

    Get-ChildItem -Depth $Depth -ErrorAction SilentlyContinue | ForEach-Object {
        $itemSize = 0
        if ($_.PSIsContainer) {
            $files = Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue
            $itemSize = ($files | Measure-Object -Property Length -Sum).Sum
        } else {
            $itemSize = $_.Length
        }

        if ($null -eq $itemSize) { $itemSize = 0 }

        [PSCustomObject]@{
            Size    = Get-ReadableSize -Bytes $itemSize
            RawSize = $itemSize
            Path    = $_.FullName
        }
    } | Sort-Object RawSize -Descending | Select-Object Size, Path
}

function Movies {
    <#
    .SYNOPSIS
        Aggregates content from 3 specific paths and shows a total summary.
    #>
    $paths = @("F:\_movies", "F:\_shows", "F:\_ufc")
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
                    Size = Get-ReadableSize -Bytes $itemSize
                    RawSize = $itemSize
                    Path = $_.FullName
                }
            }
            $allResults += $results
        }
    }

    $allResults | Sort-Object RawSize -Descending | Select-Object Size, Path
    Write-Host "`n------------------------------" -ForegroundColor Cyan
    Write-Host "TOTAL AGGREGATED SIZE: $(Get-ReadableSize -Bytes $totalBytes)" -ForegroundColor Green
    Write-Host "------------------------------`n" -ForegroundColor Cyan
}
