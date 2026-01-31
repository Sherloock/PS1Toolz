# Dashboard and help system

function ?? {
    <#
    .SYNOPSIS
        Lists all custom functions defined in this toolkit with their descriptions.
    #>
    Write-Host "`n--- BALINT'S TOOLBOX ---" -ForegroundColor Cyan

    $ToolKitDir = "f:\Fejlesztes\projects\my\ps-tools"

    # Exclude specific functions by name
    $ExcludedFunctions = @("??")

    # Exclude entire files (relative to toolkit dir, use just filename or path like "core\Helpers.ps1")
    $ExcludedFiles = @(
        "Helpers.ps1",
        "Timer.ps1"
    )

    # Get all .ps1 files in the toolkit
    $scripts = Get-ChildItem -Path $ToolKitDir -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue

    foreach ($script in $scripts) {
        # Check if file is excluded (by filename or relative path)
        $relativePath = $script.FullName.Replace($ToolKitDir + "\", "")
        $isExcludedFile = $false
        foreach ($excluded in $ExcludedFiles) {
            if ($script.Name -eq $excluded -or $relativePath -eq $excluded) {
                $isExcludedFile = $true
                break
            }
        }
        if ($isExcludedFile) { continue }

        $content = Get-Content -LiteralPath $script.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        # Find all function definitions in the file
        $functionMatches = [regex]::Matches($content, 'function\s+([A-Za-z?][\w?-]*)')

        foreach ($match in $functionMatches) {
            $funcName = $match.Groups[1].Value

            # Skip excluded functions
            if ($ExcludedFunctions -contains $funcName) { continue }

            # Get help for the function
            $cmd = Get-Command -Name $funcName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $cmd) { continue }

            $help = Get-Help $funcName -ErrorAction SilentlyContinue

            # Get synopsis
            $desc = [string]$help.Synopsis
            if ([string]::IsNullOrWhiteSpace($desc) -or $desc -eq $funcName) {
                $desc = [string]$help.Description
            }
            if ([string]::IsNullOrWhiteSpace($desc) -or $desc.Trim() -eq $funcName) {
                $desc = "No description provided."
            }

            # Format parameters
            $rawParams = $help.parameters.parameter | ForEach-Object { "[$($_.name)]" }
            $paramString = [string]::Join(" ", $rawParams)

            # Output with aligned columns
            Write-Host (" {0,-12}" -f $funcName) -ForegroundColor Yellow -NoNewline
            Write-Host (" {0,-22}" -f $paramString) -ForegroundColor Gray -NoNewline
            Write-Host " | $desc"
        }
    }
    Write-Host ""
    Write-Host " Type 'timer' for timer commands." -ForegroundColor DarkGray
    Write-Host "------------------------`n"
}
