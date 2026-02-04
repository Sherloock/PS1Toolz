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

# Load Timer module (via _init.ps1 which loads all sub-files in correct order)
$timerInitPath = Join-Path $ToolKitDir "core\Timer\_init.ps1"
if (Test-Path -LiteralPath $timerInitPath) {
    . $timerInitPath
}

# Load remaining .ps1 files (exclude loader, helpers, config, tests, and Timer sub-files)
Get-ChildItem -Path $ToolKitDir -Filter "*.ps1" -Recurse | Where-Object {
    $_.Name -ne "loader.ps1" -and
    $_.Name -ne "Helpers.ps1" -and
    $_.Name -ne "_init.ps1" -and                    # Timer module loader
    $_.FullName -notlike "*\Timer\*" -and          # All Timer sub-files already loaded
    $_.Name -notlike "config*.ps1" -and
    $_.FullName -notlike "*\tests\*"
} | ForEach-Object {
    . $_.FullName
}

# Count feature modules only (exclude loader, config, Helpers, tests; Timer counts as one)
$toolkitScripts = Get-ChildItem -Path $ToolKitDir -Filter "*.ps1" -Recurse | Where-Object {
    $_.Name -ne "loader.ps1" -and
    $_.Name -ne "Helpers.ps1" -and
    $_.Name -notlike "config*.ps1" -and
    $_.FullName -notlike "*\tests\*"
}
$timerScriptCount = ($toolkitScripts | Where-Object { $_.FullName -like "*\Timer\*" }).Count
$otherScriptCount = ($toolkitScripts | Where-Object { $_.FullName -notlike "*\Timer\*" }).Count
$moduleCount = $otherScriptCount + [Math]::Min(1, $timerScriptCount)  # Timer folder = 1 module

Write-Host "Balint's Toolkit Loaded ($moduleCount modules) - Type '??' for commands" -ForegroundColor Green

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

