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

- `t <time> [-m msg] [-r N]` - Start a background timer with optional repeat
- `tl [-a] [-w]` - List active timers (-a all, -w watch) with progress
- `tw [id]` - Watch timer with progress bar (picker if no id)
- `tp [id|all]` - Pause timer (picker if no id)
- `tr [id|all]` - Resume paused timer (picker if no id)
- `td [id|done|all]` - Remove timer (picker if no id)

### Dev

- `Pass` - Secure password generator
- `PortKill -Port <n>` - Kill process by port number
- `NodeKill` - Find and remove node_modules folders (sorted by size, with totals)
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
