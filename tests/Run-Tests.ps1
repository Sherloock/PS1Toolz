# Run all Pester tests
# Usage: .\Run-Tests.ps1 [-Detailed] [-Coverage]

param(
    [switch]$Detailed,
    [switch]$Coverage
)

$ErrorActionPreference = "Stop"

# Check Pester version
$pester = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pester -or $pester.Version.Major -lt 5) {
    Write-Host "Pester 5.x required. Installing (this may take a minute)..." -ForegroundColor Yellow
    
    # Ensure NuGet provider is available
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Host "  Installing NuGet provider..." -ForegroundColor Gray
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    
    # Trust PSGallery
    if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
        Write-Host "  Trusting PSGallery..." -ForegroundColor Gray
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    
    Write-Host "  Downloading Pester 5..." -ForegroundColor Gray
    Install-Module Pester -Force -Scope CurrentUser -SkipPublisherCheck
    
    Write-Host "  Done!" -ForegroundColor Green
    Import-Module Pester -MinimumVersion 5.0 -Force
} else {
    Import-Module Pester -MinimumVersion 5.0 -Force
}

# Build configuration
$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.Exit = $true

if ($Detailed) {
    $config.Output.Verbosity = "Detailed"
} else {
    $config.Output.Verbosity = "Normal"
}

if ($Coverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @(
        "$PSScriptRoot\..\core\*.ps1",
        "$PSScriptRoot\..\dev\*.ps1",
        "$PSScriptRoot\..\media\*.ps1"
    )
}

# Run tests
Write-Host "`n--- RUNNING TESTS ---`n" -ForegroundColor Cyan
Invoke-Pester -Configuration $config
