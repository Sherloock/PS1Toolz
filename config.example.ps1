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

    # Shortcuts for NodeKill function (node_modules cleanup)
    # Usage: nodekill proj
    NodeKillPaths = [ordered]@{
        "proj" = "D:\Projects"
    }

    # Timer sequence presets
    # Syntax: (duration label, duration label)xN, duration label
    # Use with: t <preset-name> or tpre for interactive picker
    TimerPresets = @{
        'pomodoro' = @{
            Pattern     = "(25m work, 5m rest)x4, 20m 'long break'"
            Description = "Classic Pomodoro: 4 cycles of 25m work + 5m rest, then 20m break"
        }
        'pomodoro-short' = @{
            Pattern     = "(25m work, 5m rest)x2"
            Description = "Quick Pomodoro: 2 cycles of 25m work + 5m rest"
        }
        'pomodoro-long' = @{
            Pattern     = "(50m work, 10m rest)x3, 30m 'long break'"
            Description = "Extended focus: 3 cycles of 50m work + 10m rest, then 30m break"
        }
        '52-17' = @{
            Pattern     = "(52m focus, 17m break)x3"
            Description = "Science-backed: 52m focus + 17m break ratio"
        }
        '90-20' = @{
            Pattern     = "(90m deep, 20m rest)x2"
            Description = "Ultradian rhythm: 90m deep work + 20m rest"
        }
    }
}
