# Quick navigation bookmarks

function Go {
    <#
    .SYNOPSIS
        Jumps to bookmarked paths. Type 'go' without params to see the list.
    .PARAMETER Target
        The shortcut name.
    #>
    param($Target)

    # Define your shortcuts here (Key = alias, Value = path)
    $Bookmarks = [ordered]@{
        "c"       = "C:\"
        "f"       = "F:\"
        "my"      = "F:\Fejlesztes\projects\my"
        "o42"     = "F:\Fejlesztes\projects\office42"
        "movies"  = "F:\_movies"
        "shows"   = "F:\_shows"
        "ufc"     = "F:\_ufc"
    }

    # If no target or invalid target, show the "Menu"
    if (-not $Target -or -not $Bookmarks.ContainsKey($Target)) {
        Write-Host "`n--- GO BOOKMARKS ---" -ForegroundColor Cyan
        $Bookmarks.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host (" {0,-10}" -f $_.Name) -ForegroundColor Yellow -NoNewline
            Write-Host "-> $($_.Value)" -ForegroundColor Gray
        }
        Write-Host "--------------------`n"
        return
    }

    # Jump to the destination
    $Dest = $Bookmarks[$Target]
    if (Test-Path $Dest) {
        Set-Location $Dest
        Write-Host "Arrived at: $Dest" -ForegroundColor Green
    } else {
        Write-Host "Error: Path not found -> $Dest" -ForegroundColor Red
    }
}
