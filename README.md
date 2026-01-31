# Bálint's PowerShell Toolkit

Modular PowerShell environment for Full Stack development and System Management.

## Structure

- `loader.ps1`: The loader script (dot-source from your PowerShell Profile).
- `core/`: Basic system utilities (IP, Disk, Timer, Dashboard).
  - `Helpers.ps1`: Internal helper functions (loaded first, excluded from dashboard).
- `dev/`: Development tools (Node cleanup, Port kill, Passwords, Navigation).
- `media/`: Movie and show library management.

## Installation

1. Clone this repo to `f:\Fejlesztes\projects\my\ps-tools`.
2. Run `Win + R` -> `notepad $PROFILE`.
3. Add this line to your profile:
   ```powershell
   . "f:\Fejlesztes\projects\my\ps-tools\loader.ps1"
   ```
4. Restart PowerShell or run `. $PROFILE` to reload.

## Usage

- Type `??` in PowerShell to see all available commands.
- Type `timer` to see timer-specific commands.
- Type `Reload` to hot-reload all scripts after making changes.

## Functions

### Core

- `Reload` - Hot-reload all scripts without restarting PowerShell
- `ShowIP` - Network dashboard with local and public IP info
- `Disk-Space` - Disk usage dashboard with color-coded warnings
- `Fast` - Internet speed test using Speedtest CLI

### Timer (type `timer` for help)

- `Timer <time>` - Foreground countdown (blocks terminal)
- `TimerBg <time> [-m msg] [-r N]` - Background timer with optional repeat
- `TimerList [-a]` - List active timers
- `TimerStop [id|all]` - Stop timer(s)
- `TimerRemove [id|done|all]` - Remove timer(s)

### Dev

- `Pass` - Secure password generator
- `PortKill` - Kill process by port number
- `CleanNode` - Find and remove node_modules folders
- `Go` - Quick navigation bookmarks

### Media

- `Size` - List files/folders sorted by size
- `Movies` - Aggregate video library statistics
