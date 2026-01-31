# User-specific configuration
# Copy this file to config.ps1 and customize your paths

$global:Config = @{
    # Paths for the Movies function (media library statistics)
    MediaPaths = @(
        "D:\movies",
        "D:\shows"
    )

    # Size function defaults
    SizeDefaults = @{
        Depth   = 0       # 0 = current folder only
        MinSize = 1MB     # Hide items smaller than this
    }

    # Bookmarks for the Go function (quick navigation)
    Bookmarks = [ordered]@{
        "c"       = "C:\"
        "d"       = "D:\"
        "docs"    = "$env:USERPROFILE\Documents"
        "proj"    = "D:\Projects"
    }
}
