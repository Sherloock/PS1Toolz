# System information and diagnostics

function ShowIP {
    <#
    .SYNOPSIS
        Displays instant local network info and fetches public details without clutter.
    #>
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 1. Collect Local Info (Instant)
    $Config = Get-NetIPConfiguration | Where-Object { $null -ne $_.IPv4Address } | Select-Object -First 1
    $Adapter = Get-NetAdapter -InterfaceIndex $Config.InterfaceIndex
    $Wifi = netsh wlan show interfaces | Select-String "Signal","SSID" | Out-String

    # 2. Print Local Header
    Write-Host "`n--- NETWORK DASHBOARD ---" -ForegroundColor Cyan
    Write-Host "ADAPTER:  $($Adapter.Name) ($($Adapter.Status))"
    Write-Host "MAC ADDR: $($Adapter.MacAddress)"
    Write-Host "LOCAL IP: $($Config.IPv4Address.IPAddress)"
    Write-Host "GATEWAY:  $($Config.IPv4DefaultGateway.NextHop)"
    Write-Host "DNS:      $($Config.DNSServer.ServerAddresses -join ', ')"

    if ($Wifi.Trim()) {
        Write-Host "WI-FI:    $($Wifi.Trim() -replace '[\r\n]', ' | ')" -ForegroundColor Yellow
    }

    # 3. Handle Public Info
    Write-Host "`nFetching Public Info..." -NoNewline -ForegroundColor Gray

    $PublicData = $null
    try {
        $PublicData = Invoke-RestMethod -Uri "http://ip-api.com/json/" -TimeoutSec 5 -ErrorAction Stop
    } catch {
        try {
            $PublicData = Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 5 -ErrorAction Stop
            if ($PublicData.loc) {
                $PublicData | Add-Member -NotePropertyName "city" -NotePropertyValue $PublicData.city -Force
                $PublicData | Add-Member -NotePropertyName "isp" -NotePropertyValue $PublicData.org -Force
                $PublicData | Add-Member -NotePropertyName "query" -NotePropertyValue $PublicData.ip -Force
            }
        } catch {
            $PublicData = $null
        }
    }

    # 4. Overwrite "Fetching" Line
    $ClearLine = "`r" + (" " * 30) + "`r"
    Write-Host $ClearLine -NoNewline

    if ($PublicData) {
        Write-Host "PUBLIC IP: $($PublicData.query)" -ForegroundColor Green
        Write-Host "ISP:       $($PublicData.isp)"
        Write-Host "LOCATION:  $($PublicData.city), $($PublicData.country) ($($PublicData.timezone))"
    } else {
        Write-Host "PUBLIC IP: Request timed out." -ForegroundColor Red
    }
    Write-Host "------------------------`n"
}

function DiskSpace {
    <#
    .SYNOPSIS
        Displays an aligned dashboard with Drive, Type, Label, Total, Free, and Usage %.
    #>
    Write-Host "`n--- DISK USAGE DASHBOARD ---" -ForegroundColor Cyan

    Get-WmiObject Win32_LogicalDisk | Where-Object { $_.Size -gt 0 } | ForEach-Object {
        $TotalGB = [Math]::Round($_.Size / 1GB, 1)
        $FreeGB  = [Math]::Round($_.FreeSpace / 1GB, 1)
        $PercentUsed = [Math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)

        # Handle Label & Truncation
        $Label = if ([string]::IsNullOrWhiteSpace($_.VolumeName)) { "(No Label)" } else { $_.VolumeName }
        if ($Label.Length -gt 12) { $Label = $Label.Substring(0,9) + "..." }

        # Map Drive Type
        $Type = switch ($_.DriveType) {
            2 { "USB" }
            3 { if ($_.DeviceID -eq $env:SystemDrive) { "OS" } else { "HDD" } }
            default { "EXT" }
        }

        # Usage Color
        $Color = "Green"
        if ($PercentUsed -gt 85) { $Color = "Yellow" }
        if ($PercentUsed -gt 92) { $Color = "Red" }

        # Output String (Aligned Columns)
        Write-Host (" {0,-3} " -f $_.DeviceID) -NoNewline -BackgroundColor DarkGray
        Write-Host (" {0,-4} " -f $Type) -ForegroundColor Cyan -NoNewline
        Write-Host (" {0,-13}" -f $Label) -ForegroundColor White -NoNewline
        Write-Host " | Free: " -NoNewline
        Write-Host ("{0,7} GB" -f $FreeGB) -ForegroundColor $Color -NoNewline
        Write-Host (" / {0,-7}GB" -f $TotalGB) -NoNewline
        Write-Host " | " -NoNewline
        Write-Host ("{0,5}% used" -f $PercentUsed) -ForegroundColor $Color
    }
    Write-Host "----------------------------`n"
}

function Fast {
    <#
    .SYNOPSIS
        Tests internet speed using the Speedtest CLI.
    #>
    $installDir = "$env:USERPROFILE\.speedtest"
    $exePath = "$installDir\speedtest.exe"

    if (-not (Test-Path $exePath)) {
        Write-Host "Tool not found. Installing to $installDir..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null

        $url = "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
        $zipPath = "$installDir\speedtest.zip"

        # Using TLS 1.2 for the download
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zipPath

        Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
        Remove-Item $zipPath
        Write-Host "Installation successful.`n" -ForegroundColor Green
    }

    # Run the test
    Write-Host "Running Speed Test..." -ForegroundColor Yellow
    & $exePath --accept-license --accept-gdpr
}
