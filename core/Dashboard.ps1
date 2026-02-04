# Dashboard and help system

function ?? {
    <#
    .SYNOPSIS
        Lists all custom functions defined in this toolkit with their descriptions.
    #>
    Write-Host "`n--- BALINT'S TOOLBOX ---" -ForegroundColor Cyan

    $ToolKitDir = $global:ToolKitDir

    # Get function list from config (inclusion-based, ordered)
    $functionList = if ($global:Config -and $global:Config.FunctionNames) {
        $global:Config.FunctionNames
    } else {
        @{}
    }

    # Display functions from config (in order); only Timer shown for timer commands
    $excludeFromToolbox = @('TimerList')
    foreach ($funcName in $functionList.Keys) {
        if ($funcName -in $excludeFromToolbox) { continue }
        $desc = $functionList[$funcName]

        # Get help for the function to extract parameters
        $help = Get-Help $funcName -ErrorAction SilentlyContinue

        # Format parameters
        if ($help -and $help.parameters -and $help.parameters.parameter) {
            $rawParams = $help.parameters.parameter | ForEach-Object { "[$($_.name)]" }
            $paramString = [string]::Join(" ", $rawParams)
        } else {
            $paramString = ""
        }

        # Output with aligned columns
        Write-Host (" {0,-12}" -f $funcName) -ForegroundColor Yellow -NoNewline
        Write-Host (" {0,-22}" -f $paramString) -ForegroundColor Gray -NoNewline
        Write-Host " | $desc"
    }

    Write-Host ""
    Write-Host " Type 'timer' for timer commands." -ForegroundColor DarkGray
    Write-Host "------------------------`n"
}
