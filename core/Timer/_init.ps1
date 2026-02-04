# Timer Module Loader
# This file loads all Timer sub-modules in the correct order

# Load in dependency order
$timerFiles = @(
    'Timer-Data.ps1'      # Data persistence, IDs, JSON management
    'Timer-Display.ps1'   # Display helpers, colors, formatting
    'Timer-Job.ps1'       # Windows Scheduled Tasks integration
    'Timer-Operations.ps1' # Pause, Resume, Remove operations
    'Timer-Sequence.ps1'  # Sequence parsing and handling
    'Timer-Main.ps1'      # Main user-facing functions
    'Timer-Aliases.ps1'   # Aliases (must be last)
)

$timerDir = $PSScriptRoot

foreach ($file in $timerFiles) {
    $filePath = Join-Path $timerDir $file
    if (Test-Path -LiteralPath $filePath) {
        . $filePath
    }
}
