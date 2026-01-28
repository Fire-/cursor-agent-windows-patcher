# Spec 41: Documentation - Update README with Usage Examples

**File**: `README.md`

**Purpose**: Create comprehensive user-facing documentation with clear usage examples, installation instructions, troubleshooting guide, and API reference.

## Documentation Structure

### 1. Project Overview Section
**Content**:
- What the project does
- Why it exists (Windows compatibility for macOS package)
- Key features
- Prerequisites (PowerShell 5.1+, Bun/Node.js, optional 7-Zip)

**Example**:
```markdown
# Cursor Agent Windows Patcher

Automatically patches the Cursor Agent CLI package (designed for macOS) to run on Windows by replacing native dependencies with Windows-compatible versions.

## Features

- Automatic version detection from official install script
- Downloads Windows-native binaries for dependencies (sqlite3, merkle-tree, ripgrep)
- Patches platform detection code
- Creates launcher scripts with update interception
- Caches binaries for faster subsequent runs
```

### 2. Installation Instructions
**Content**:
- How to install/clone the project
- Prerequisites installation
- Configuration setup
- First-time setup steps

**Example**:
```markdown
## Installation

1. Clone this repository:
   ```powershell
   git clone https://github.com/Fire-/cursor-agent-windows-patcher.git
   cd cursor-agent-windows-patcher
   ```

2. Ensure prerequisites are installed:
   - PowerShell 5.1 or later
   - Bun (preferred) or Node.js
   - 7-Zip (optional, for better archive extraction)

3. Review and customize `patcher-config.json` if needed
```

### 3. Quick Start Guide
**Content**:
- Simplest usage example
- Most common use case
- Expected output

**Example**:
```markdown
## Quick Start

```powershell
# Patch and install latest Cursor Agent
.\patch-cursor-agent.ps1

# Patch specific version
.\patch-cursor-agent.ps1 -Version "2026.01.23-916f423"

# Patch existing installation
.\patch-cursor-agent.ps1 -PatchExistingInstallation -InstallPath "C:\Users\You\AppData\Local\cursor-agent"
```
```

### 4. Usage Examples Section
**Content**: Detailed examples for each major use case.

#### 4.1 Standard Installation
```markdown
### Standard Installation

Download, patch, and install Cursor Agent:

```powershell
.\patch-cursor-agent.ps1 -Version "2026.01.23-916f423" -InstallPath ".\cursor-agent"
```

**What happens**:
1. Fetches install script from cursor.com
2. Extracts version information
3. Downloads macOS package
4. Extracts package
5. Downloads Windows binaries for dependencies
6. Applies patches
7. Installs to specified path
8. Creates launcher script
```

#### 4.2 In-Place Patching
```markdown
### Patching Existing Installation

If you already have Cursor Agent installed:

```powershell
.\patch-cursor-agent.ps1 -PatchExistingInstallation -InstallPath "C:\path\to\cursor-agent"
```

This will:
- Detect the installed version
- Download required Windows binaries
- Apply patches to existing files
- Create/update launcher script
```

#### 4.3 Update Interception
```markdown
### Automatic Update Patching

Enable automatic patching after cursor-agent updates:

```powershell
.\patch-cursor-agent.ps1 -Update
```

This intercepts `cursor-agent update` commands and automatically patches newly updated versions.
```

#### 4.4 Dry Run Mode
```markdown
### Dry Run (What-If Mode)

Preview what would happen without making changes:

```powershell
.\patch-cursor-agent.ps1 -WhatIf -Verbose
```

Shows detailed output of all operations without executing them.
```

#### 4.5 Custom Dependency Versions
```markdown
### Using Custom Dependency Versions

Override default dependency versions:

```powershell
.\patch-cursor-agent.ps1 `
    -Sqlite3Version "5.1.7" `
    -MerkleTreeVersion "1.2.3" `
    -Version "2026.01.23-916f423"
```
```

### 5. Configuration Reference
**Content**:
- Complete `patcher-config.json` schema
- All configuration options explained
- Environment variable overrides
- Example configurations

**Example**:
```markdown
## Configuration

### patcher-config.json

The main configuration file controls version mappings, cache settings, and installation defaults.

#### versionMappings

Maps Cursor Agent dependency versions to Windows binary sources:

```json
{
  "versionMappings": {
    "sqlite3": {
      "5.1.7": {
        "windowsBinary": {
          "repo": "TryGhost/node-sqlite3",
          "assetPattern": ".*windows.*node_sqlite3.*\\.node",
          "releaseTag": "v5.1.7"
        }
      }
    }
  }
}
```

#### cache

Controls binary caching behavior:

- `directory`: Cache location (default: `%LOCALAPPDATA%\cursor-agent-patcher\cache`)
- `enabled`: Enable/disable caching (default: `true`)
- `validateOnUse`: Verify cached files on use (default: `true`)

#### installation

Installation defaults:

- `defaultPath`: Default installation directory
- `createLauncher`: Automatically create launcher script
- `launcherName`: Name of launcher script
```

### 6. API Reference
**Content**:
- Public functions exported by module
- Function signatures
- Parameter descriptions
- Return values
- Usage examples

**Example**:
```markdown
## API Reference

### Get-PatcherConfig

Loads and validates configuration from `patcher-config.json`.

**Syntax**:
```powershell
Get-PatcherConfig [-ConfigPath <String>]
```

**Parameters**:
- `ConfigPath`: Path to configuration file (default: `.\patcher-config.json`)

**Returns**: Hashtable with configuration data

**Example**:
```powershell
$config = Get-PatcherConfig
$config.cache.directory
```

### Get-CursorAgentVersion

Extracts version string from Cursor Agent install script.

**Syntax**:
```powershell
Get-CursorAgentVersion [-InstallScript <String>]
```

**Parameters**:
- `InstallScript`: Install script content (default: fetches from cursor.com)

**Returns**: Version string (format: `YYYY.MM.DD-hash`)

**Example**:
```powershell
$version = Get-CursorAgentVersion
# Returns: "2026.01.23-916f423"
```

### Invoke-CursorAgentPatch

Main patching workflow function.

**Syntax**:
```powershell
Invoke-CursorAgentPatch `
    [-Version <String>] `
    [-InstallPath <String>] `
    [-Sqlite3Version <String>] `
    [-MerkleTreeVersion <String>] `
    [-WhatIf] `
    [-Force] `
    [-PatchExistingInstallation]
```

**Parameters**:
- `Version`: Cursor Agent version to patch (default: latest from install script)
- `InstallPath`: Installation directory (default: from config)
- `Sqlite3Version`: Override SQLite3 version
- `MerkleTreeVersion`: Override Merkle Tree version
- `WhatIf`: Preview changes without applying
- `Force`: Re-patch even if already patched
- `PatchExistingInstallation`: Patch existing installation instead of downloading

**Returns**: Hashtable with result summary

**Example**:
```powershell
$result = Invoke-CursorAgentPatch -Version "2026.01.23-916f423"
if ($result.Success) {
    Write-Host "Installation path: $($result.InstallPath)"
}
```
```

### 7. Troubleshooting Guide
**Content**:
- Common errors and solutions
- Debugging tips
- Log locations
- Known issues

**Example**:
```markdown
## Troubleshooting

### Error: "Failed to download package"

**Possible causes**:
- Network connectivity issues
- Invalid version specified
- Cursor.com server issues

**Solutions**:
1. Check internet connection
2. Verify version exists: `Get-CursorAgentVersion`
3. Try again later if server issues

### Error: "Archive extraction failed"

**Possible causes**:
- Corrupted download
- Missing 7-Zip (PowerShell 5.1 limitation)
- Insufficient disk space

**Solutions**:
1. Install 7-Zip for better extraction support
2. Clear cache and retry: Remove `%LOCALAPPDATA%\cursor-agent-patcher\cache`
3. Check available disk space

### Error: "Patch application failed"

**Possible causes**:
- File permissions
- Files in use
- Invalid package structure

**Solutions**:
1. Run PowerShell as Administrator
2. Close any processes using Cursor Agent files
3. Verify package structure is correct
```

### 8. Advanced Usage
**Content**:
- Programmatic usage
- Module import examples
- Custom patch development
- Cache management

**Example**:
```markdown
## Advanced Usage

### Using the Module Programmatically

```powershell
Import-Module .\CursorAgentPatcher.psm1

# Get configuration
$config = Get-PatcherConfig

# Extract version
$version = Get-CursorAgentVersion

# Patch with custom options
$result = Invoke-CursorAgentPatch `
    -Version $version `
    -InstallPath "C:\Custom\Path" `
    -WhatIf
```

### Cache Management

Clear cache:
```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\cursor-agent-patcher\cache"
```

View cache contents:
```powershell
Get-ChildItem "$env:LOCALAPPDATA\cursor-agent-patcher\cache\binaries"
```
```

### 9. Contributing Section
**Content**:
- How to contribute
- Development setup
- Testing guidelines
- Code style

### 10. License and Credits
**Content**:
- License information
- Acknowledgments
- Related projects

## Success Criteria

1. **Complete coverage** - All major features documented
2. **Clear examples** - Every example is copy-paste ready
3. **Troubleshooting guide** - Covers common issues
4. **API reference** - All public functions documented
5. **Easy navigation** - Table of contents and clear sections
6. **Up-to-date** - Matches current implementation
7. **Beginner-friendly** - Assumes minimal PowerShell knowledge

## Dependencies

- All implementation specs (001-039)
- Understanding of user workflows
- Knowledge of common issues

## Notes

- Keep examples simple and focused
- Update documentation when features change
- Include both simple and advanced examples
- Add screenshots/terminal output where helpful
- Link to related documentation (testing.md, AGENTS.md)
