# LOADER: Paste this into Win+R -> notepad $PROFILE
$ToolKitDir = "f:\Fejlesztes\projects\my\ps-tools"

# Automatically load all .ps1 files from subdirectories (exclude loader itself)
Get-ChildItem -Path $ToolKitDir -Filter "*.ps1" -Recurse | Where-Object { $_.Name -ne "loader.ps1" } | ForEach-Object {
    . $_.FullName
}

Write-Host "Balint's Toolkit Loaded ($((Get-ChildItem $ToolKitDir -Filter *.ps1 -Recurse).Count) modules)" -ForegroundColor Green

# Show dashboard on load
??
