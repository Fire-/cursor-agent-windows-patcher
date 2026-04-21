# AGENTS.md - Cursor Agent Windows Setup

Guidelines for AI agents working on this codebase.

## Project Overview

A PowerShell automation tool to install and configure Cursor Agent CLI on Windows. The tool downloads the macOS package, patches native Node modules for Windows compatibility, replaces dependencies with Windows-native versions (merkle-tree, sqlite3, ripgrep), and creates a launcher script. Built with PowerShell 5.1+ and uses native PowerShell cmdlets for downloads, extraction, and file manipulation.

## Progress Tracking

**IMPORTANT**: This project uses a progress tracking system in [WORK.md](./WORK.md) to maintain state across context windows.

### At Session Start

1. Read `WORK.md` → "Progress Tracker" section
2. Check the "Current Focus" to see what's next
3. Review "Session Log" for recent context
4. Validate `patcher-config.json` syntax and check for updates
5. Review implementation plan in `plans/implementation-plan.md`
6. Revuew `specs/index.md` for the current spec to be implemented

### During Work

1. Update chunk status to 🟡 when starting work
2. Follow the chunk's tasks and verification steps
3. Test PowerShell scripts with `-WhatIf` before execution
4. Commit frequently with descriptive messages

### At Session End (or before context exhaustion)

1. Update chunk status in Progress Tracker:
   - ✅ Complete (with date)
   - 🟡 In Progress (note where you stopped)
   - ⚠️ Blocked (explain why)
2. Update "Current Focus" → "Next Chunk"
3. Add entry to "Session Log" with date and notes
4. Commit changes to WORK.md
5. If the spec is Complete, update `specs/index.md` checking off the current spec

### Status Legend

| Symbol | Meaning |
|--------|---------|
| ⬜ | Not Started |
| 🟡 | In Progress |
| ✅ | Complete |
| ⚠️ | Blocked |

### Git Commit Convention

```
spec(NNN): spec description

# Examples:
spec(001): create patcher-config.json structure
spec(002): load and validate configuration
spec(003): initialize cache directory
```

## PowerShell-First Approach

This project prioritizes native PowerShell capabilities:

- **HTTP**: Use `Invoke-WebRequest` or `Invoke-RestMethod` for downloads
- **Processes**: Use `Start-Process` or direct cmdlet execution
- **File Operations**: Use `Copy-Item`, `Move-Item`, `Remove-Item`, `Get-Content`, `Set-Content`
- **Archives**: Use `Expand-Archive` (PowerShell 5.0+) or fallback to 7-Zip
- **JSON**: Use `ConvertFrom-Json` and `ConvertTo-Json` for config files
- **Error Handling**: Use `try/catch` blocks with `$ErrorActionPreference`
- **Modules**: Organize reusable functions in `.psm1` PowerShell modules

Avoid external dependencies where possible. When needed, document prerequisites clearly.

## Commands

```powershell
# Development
.\patch-cursor-agent.ps1               # Run patch/install workflow
.\patch-cursor-agent.ps1 -Verbose      # Run with verbose output
.\patch-cursor-agent.ps1 -WhatIf       # Dry run mode

# Testing
Invoke-Pester                           # Run all tests
Invoke-Pester -Path tests/integration/  # Run integration tests
.\tests\integration\run-end-to-end-failfast.ps1  # Fail-fast integration runner

# Module Import
Import-Module .\CursorAgentPatcher.psm1  # Import patcher module
Get-Command -Module CursorAgentPatcher   # List module functions

# Validation
Test-Path .\patcher-config.json                 # Check if config exists
Get-Content .\patcher-config.json | ConvertFrom-Json  # Validate JSON syntax
```

## Project Structure

```
cursor-agent-windows-patcher/
├── patch-cursor-agent.ps1        # Main patch/install script
├── CursorAgentPatcher.psm1       # Helper module with reusable functions
├── patcher-config.json           # Configuration (versions, URLs)
├── cursor-agent.bat              # Launcher script for installed agent
├── README.md                     # User documentation
├── AGENTS.md                     # This file
├── WORK.md                       # Progress tracking
├── plans/                        # Implementation plans
│   └── implementation-plan.md
```

## Code Style

### PowerShell Best Practices

1. **Functions**: Use approved verbs, explicit parameters, help comments
   ```powershell
   function Get-CursorAgentVersion {
       <#
       .SYNOPSIS
       Fetches the latest Cursor Agent version from install script.
       
       .DESCRIPTION
       Parses the install script from cursor.com to extract version information.
       #>
       [CmdletBinding()]
       param()
       
       # Implementation
   }
   ```

2. **Error Handling**: Use try/catch with appropriate error actions
   ```powershell
   try {
       $result = Invoke-WebRequest -Uri $url -ErrorAction Stop
   }
   catch {
       Write-Error "Failed to download: $_"
       return $null
   }
   ```

3. **Parameter Validation**: Validate inputs early
   ```powershell
   function Install-CursorAgent {
       param(
           [Parameter(Mandatory=$true)]
           [ValidateScript({Test-Path $_})]
           [string]$InstallPath
       )
   }
   ```

4. **Module Functions**: Export only public functions
   ```powershell
   # In .psm1 file
   function Get-GitHubReleaseAsset { ... }
   function Invoke-SafeExtract { ... }
   
   Export-ModuleMember -Function Get-GitHubReleaseAsset, Invoke-SafeExtract
   ```

5. **Progress Indication**: Use Write-Progress for long operations
   ```powershell
   Write-Progress -Activity "Downloading" -Status "Fetching package" -PercentComplete 50
   ```

### PowerShell Conventions

- Use approved verbs: `Get-`, `Set-`, `New-`, `Remove-`, `Test-`, `Invoke-`
- Use PascalCase for function names
- Use `$PSCmdlet` for advanced function features
- Prefer `-ErrorAction Stop` over `-ErrorAction SilentlyContinue` for critical operations
- Use `[ValidateSet()]` for constrained parameter values
- Document functions with comment-based help

### Imports

```powershell
# System modules first
using namespace System.IO
using namespace System.Net

# Then local modules
Import-Module .\CursorAgentPatcher.psm1

# Then helper functions
. .\scripts\helpers.ps1
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CURSOR_AGENT_INSTALL_PATH` | `.\cursor-agent` | Installation directory for Cursor Agent |
| `CURSOR_AGENT_CONFIG_PATH` | `.\patcher-config.json` | Path to configuration file |
| `TEMP_DOWNLOAD_DIR` | `$env:TEMP\cursor-agent-setup` | Temporary directory for downloads |

**Note**: Most configuration is stored in `patcher-config.json` rather than environment variables. Environment variables are optional overrides.

## Testing

- Use Pester framework for PowerShell testing
- Property tests go in `tests/properties/`
- Integration tests go in `tests/integration/`

```powershell
# Example Pester test
Describe "Get-CursorAgentVersion" {
    It "Should return version string" {
        $version = Get-CursorAgentVersion
        $version | Should -Match '^\d{4}\.\d{2}\.\d{2}-[a-f0-9]+$'
    }
    
    It "Should handle network errors gracefully" {
        Mock Invoke-WebRequest { throw "Network error" }
        { Get-CursorAgentVersion } | Should -Throw
    }
}
```

## Key Dependencies

| Dependency | Purpose | Type |
|------------|---------|------|
| PowerShell 5.1+ | Runtime and cmdlets | System Requirement |
| Node.js | Required for Cursor Agent CLI | Prerequisite |
| 7-Zip (optional) | Archive extraction fallback | Optional Tool |
| Pester (optional) | Testing framework | Development Dependency |

**Note**: This project uses minimal external dependencies. Most functionality relies on built-in PowerShell cmdlets.

## Common Tasks

### Adding a New Download Function

1. Add function to `CursorAgentPatcher.psm1`
2. Use `Invoke-WebRequest` or `Invoke-RestMethod`
3. Include error handling and progress indication
4. Export function with `Export-ModuleMember`
5. Add tests if Pester is available

```powershell
function Get-GitHubReleaseAsset {
    param(
        [string]$Repo,
        [string]$AssetPattern,
        [string]$OutPath
    )
    
    try {
        $releases = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
        $asset = $releases.assets | Where-Object { $_.name -match $AssetPattern }
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $OutPath
    }
    catch {
        Write-Error "Failed to download asset: $_"
        throw
    }
}
```

### Updating Version Configuration

1. Edit `patcher-config.json` with new version numbers
2. Update download URLs if structure changes
3. Test with `-WhatIf` flag first
4. Document breaking changes in README

### Adding Native Module Patching

1. Locate the file to patch (may be bundled in `index.js`)
2. Use regex or string replacement to modify platform detection
3. Test patching logic with sample content
4. Add verification step after patching

```powershell
function Update-NativeJsFile {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $patched = $content -replace 'throw new Error\(`Unsupported platform`\)', 
        'nativeBinding = require_merkle_tree_napi_darwin_arm64();'
    Set-Content -Path $FilePath -Value $patched -NoNewline
}
```

### Debugging

```powershell
# Enable verbose output
$VerbosePreference = "Continue"
.\patch-cursor-agent.ps1 -Verbose

# Check module functions
Get-Command -Module CursorAgentPatcher

# Validate JSON config
Get-Content patcher-config.json | ConvertFrom-Json | ConvertTo-Json

# Test individual functions
Import-Module .\CursorAgentPatcher.psm1
Get-GitHubReleaseAsset -Repo "user/repo" -AssetPattern ".*\.zip" -OutPath "test.zip"
```


## Resources

- [PowerShell Documentation](https://learn.microsoft.com/en-us/powershell/)
- [PowerShell Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines)
- [Pester Testing Framework](https://pester.dev/)
- [GitHub API Documentation](https://docs.github.com/en/rest)
- [Cursor Agent CLI Blog Post](https://cursor.com/blog/cli)
