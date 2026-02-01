# Bálint's PowerShell Toolkit

Modular PowerShell environment for Full Stack development and System Management.

## Structure

- `loader.ps1`: The loader script (dot-source from your PowerShell Profile).
- `config.example.ps1`: Example configuration (copy to `config.ps1`).
- `core/`: Basic system utilities (IP, Disk, Timer, Dashboard).
  - `Helpers.ps1`: Internal helper functions (loaded first, excluded from dashboard).
- `dev/`: Development tools (Node cleanup, Port kill, Passwords, Navigation).
- `media/`: Movie and show library management.
- `tests/`: Pester test suite for all modules.

## Installation

1. Clone this repo anywhere on your system.
2. Run `Win + R` -> `notepad $PROFILE`.
3. Add this line to your profile (adjust path to where you cloned):
   ```powershell
   . "C:\path\to\ps-tools\loader.ps1"
   ```
4. Restart PowerShell or run `. $PROFILE` to reload.

## Configuration

Some functions require user-specific paths. To configure:

1. Copy `config.example.ps1` to `config.ps1`
2. Edit `config.ps1` with your local paths

**Configurable settings:**

- `MediaPaths` - Array of paths for `Movies` function
- `Bookmarks` - Hashtable of shortcuts for `Go` function
- `NodeKillPaths` - Hashtable of shortcuts for `NodeKill` function

The `config.ps1` file is gitignored and won't be committed.

## Usage

- Type `??` in PowerShell to see all available commands.
- Type `t` to see timer-specific commands.
- Type `Reload` to hot-reload all scripts after making changes.

## Functions

### Core

- `Reload` - Hot-reload all scripts without restarting PowerShell
- `Test` - Run Pester tests (-Detailed, -Coverage)
- `ShowIP` - Network dashboard with local info and public IP lookup
- `Disk-Space` - Disk usage dashboard with color-coded warnings
- `Fast` - Internet speed test using Speedtest CLI

### Timer (type `t` for help)

- `t <time> [-m msg] [-r N]` - Start a timer (simple or sequence)
- `tpre` - Pick from preset sequences (Pomodoro, etc.)
- `tl [-a] [-w]` - List active timers (-a all, -w watch) with progress
- `tw [id]` - Watch timer with progress bar (picker if no id)
- `tp [id|all]` - Pause timer (picker if no id)
- `tr [id|all]` - Resume paused timer (picker if no id)
- `td [id|done|all]` - Remove timer (picker if no id)

**Sequence Timers (Pomodoro-style)**

```powershell
# Use a preset
t pomodoro                    # Classic: 4x(25m work + 5m rest) + 20m break

# Custom sequence syntax: (duration label, duration label)xN
t "(25m work, 5m rest)x4"                      # 4 work/rest cycles
t "(50m focus, 10m break)x3, 30m 'long break'" # 3 cycles + long break
t "((25m work, 5m rest)x4, 20m break)x2"       # Nested: 2 full pomodoro sets
```

**Presets:** `pomodoro`, `pomodoro-short`, `pomodoro-long`, `52-17`, `90-20`

### Dev

- `Pass` - Secure password generator
- `PortKill -Port <n>` - Kill process by port number
- `NodeKill [path]` - Find and remove node_modules folders (sorted by size, with totals). Accepts path or shortcut from `NodeKillPaths`
- `Go` - Quick navigation bookmarks (requires config.ps1)

### Media

- `Size` - List files/folders sorted by size
- `Movies` - Aggregate video library statistics (requires config.ps1)

## Testing

Tests use [Pester 5](https://pester.dev/) framework. If Pester 5 is not installed, it auto-installs on first run.

```powershell
# Run all tests
Test

# Detailed output
Test -Detailed

# With code coverage
Test -Coverage

# Run specific test file
Invoke-Pester .\tests\Timer.Tests.ps1
```

**Test files:**

- `Core.Tests.ps1` - Helper functions (ConvertTo-Seconds, Format-Duration, etc.)
- `Timer.Tests.ps1` - Timer module with mocked scheduled tasks
- `System.Tests.ps1` - ShowIP, DiskSpace
- `DevTools.Tests.ps1` - PortKill, NodeKill
- `Navigation.Tests.ps1` - Go function
- `Pass.Tests.ps1` - Password generation
- `Media.Tests.ps1` - Size, Movies
