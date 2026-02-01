# LOADER: Paste this into Win+R -> notepad $PROFILE
$global:ToolKitDir = $PSScriptRoot

# Load user config if exists
$configPath = Join-Path $ToolKitDir "config.ps1"
if (Test-Path -LiteralPath $configPath) {
    . $configPath
}

# Load Helpers.ps1 first (required by other modules)
$helpersPath = Join-Path $ToolKitDir "core\Helpers.ps1"
if (Test-Path -LiteralPath $helpersPath) {
    . $helpersPath
}

# Load TimerHelpers.ps1 second (required by Timer.ps1)
$timerHelpersPath = Join-Path $ToolKitDir "core\TimerHelpers.ps1"
if (Test-Path -LiteralPath $timerHelpersPath) {
    . $timerHelpersPath
}

# Load remaining .ps1 files (exclude loader, helpers, config, and tests)
Get-ChildItem -Path $ToolKitDir -Filter "*.ps1" -Recurse | Where-Object {
    $_.Name -ne "loader.ps1" -and
    $_.Name -ne "Helpers.ps1" -and
    $_.Name -ne "TimerHelpers.ps1" -and
    $_.Name -notlike "config*.ps1" -and
    $_.FullName -notlike "*\tests\*"
} | ForEach-Object {
    . $_.FullName
}

Write-Host "Balint's Toolkit Loaded ($((Get-ChildItem $ToolKitDir -Filter *.ps1 -Recurse).Count) modules)" -ForegroundColor Green

# Hot-reload function for development
function global:Reload {
    . "$ToolKitDir\loader.ps1"
}

# Run Pester tests
function global:Test {
    param(
        [switch]$Detailed,
        [switch]$Coverage
    )
    $params = @{}
    if ($Detailed) { $params['Detailed'] = $true }
    if ($Coverage) { $params['Coverage'] = $true }
    & "$ToolKitDir\tests\Run-Tests.ps1" @params
}

