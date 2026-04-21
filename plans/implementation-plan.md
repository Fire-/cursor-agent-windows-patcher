---
name: Windows Cursor Agent Setup Automation
overview: Create an automated PowerShell script and supporting infrastructure to replicate the manual Windows setup process for Cursor Agent CLI, including downloading dependencies, patching native modules, and replacing binaries.
todos:
  - id: "1"
    content: Create config.json with version numbers and dependency URLs
    status: pending
  - id: "2"
    content: Implement CursorAgentInstaller.psm1 helper module with download/extraction functions
    status: pending
  - id: "3"
    content: Create main install-cursor-agent.ps1 script with architecture detection
    status: pending
  - id: "4"
    content: Implement native.js patching logic for Windows platform support
    status: pending
  - id: "5"
    content: Add dependency download functions (merkle-tree, sqlite3, ripgrep)
    status: pending
  - id: "6"
    content: Implement file replacement logic for native modules and binaries
    status: pending
  - id: "7"
    content: Create cursor-agent.bat launcher script
    status: pending
  - id: "8"
    content: Write comprehensive README.md with usage and troubleshooting
    status: pending
  - id: "9"
    content: Create AGENTS.md following SETUP.prompt.md structure, adapted for PowerShell project
    status: pending
  - id: "10"
    content: Create PLAN.md with progress tracker and chunk breakdown
    status: pending
isProject: false
---

# Windows Cursor Agent Setup Automation

## Overview

Automate the Windows setup process for Cursor Agent CLI. The solution will download the macOS package, patch it for Windows compatibility, and replace native dependencies with Windows versions.

## Architecture

The solution consists of:

1. **PowerShell installation script** (`install-cursor-agent.ps1`) - Main automation script
2. **Configuration file** (`config.json`) - Stores version numbers and download URLs
3. **Helper module** (`CursorAgentInstaller.psm1`) - Reusable functions for download, extraction, patching
4. **README** - Usage instructions and maintenance notes

## Implementation Details

### 1. Main Installation Script (`install-cursor-agent.ps1`)

**Location**: `c:\Users\us\tools\code\cursor-agent-windows-patcher\patch-cursor-agent.ps1`

**Responsibilities**:

- Detect Windows architecture (x64/arm64)
- Download Cursor Agent CLI package (macOS version as base)
- Extract the archive
- Patch `native.js` to support Windows platform
- Download and replace Windows-native dependencies:
  - Merkle Tree native module (`qfpzq242.node`)
  - SQLite3 native module (`kkkzjw1t.node`)
  - RipGrep binary (`rg.exe`)
- Create a launcher script (`cursor-agent.bat`)
- Optionally add to PATH or create desktop shortcut

**Key Functions**:

```powershell
- Install-CursorAgent
- Get-CursorAgentVersion (fetch latest from install script)
- Download-CursorAgentPackage
- Extract-Package
- Patch-NativeModule
- Download-WindowsDependencies
- Replace-NativeModules
- Create-Launcher
```

### 2. Configuration File (`config.json`)

**Location**: `c:\Users\us\tools\code\cursor-agent-windows-patcher\patcher-config.json`

**Structure**:

```json
{
  "cursorAgent": {
    "version": "2025.08.15-dbc8d73",
    "baseUrl": "https://downloads.cursor.com/lab",
    "sourceOs": "darwin",
    "sourceArch": "arm64"
  },
  "dependencies": {
    "merkleTree": {
      "repo": "btc-vision/rust-merkle-tree",
      "assetPattern": "merkle-tree-napi.win32-x64-msvc.node"
    },
    "sqlite3": {
      "repo": "TryGhost/node-sqlite3",
      "assetPattern": "node_sqlite3.node"
    },
    "ripgrep": {
      "repo": "BurntSushi/ripgrep",
      "assetPattern": "ripgrep-.*-x86_64-pc-windows-msvc.zip"
    }
  }
}
```

### 3. Helper Module (`CursorAgentInstaller.psm1`)

**Location**: `c:\Users\us\tools\code\cursor-agent-windows-patcher\CursorAgentPatcher.psm1`

**Functions**:

- `Get-GitHubReleaseAsset` - Download assets from GitHub releases
- `Invoke-SafeExtract` - Extract archives with error handling
- `Find-FileInArchive` - Locate files in extracted directories
- `Update-NativeJsFile` - Patch the native.js file for Windows support
- `Test-RuntimeInstallation` - Verify Node.js is installed

### 4. Native Module Patching

**File to patch**: `{extracted_dir}/merkle-tree/native.js` (or bundled equivalent)

**Change required**:

```javascript
// Before:
} else {
  throw new Error(`Unsupported platform: ${platform3}`);
}

// After:
} else if (platform3 === "win32") {
  nativeBinding = require_merkle_tree_napi_darwin_arm64(); // Temporary workaround
} else {
  throw new Error(`Unsupported platform: ${platform3}`);
}
```

**Note**: The patch uses the darwin-arm64 loader as a workaround since the Windows module will replace the actual `.node` file.

### 5. File Replacements

**Merkle Tree Module**:

- Source: GitHub release from `btc-vision/rust-merkle-tree`
- Target: `qfpzq242.node` (or file referenced in bundled code)
- Method: Download Windows `.node` file and replace

**SQLite3 Module**:

- Source: GitHub release from `TryGhost/node-sqlite3`
- Target: `kkkzjw1t.node` (or file referenced in bundled code)
- Method: Download Windows `.node` file and replace

**RipGrep Binary**:

- Source: GitHub release from `BurntSushi/ripgrep`
- Target: `rg` → `rg.exe`
- Method: Extract from zip and replace binary

### 6. Launcher Script (`cursor-agent.bat`)

**Location**: `c:\Users\us\tools\code\cursor-agent-windows-patcher\cursor-agent.bat`

**Content**:

```batch
@echo off
cd /d "%~dp0cursor-agent"
node index.js %*
```

### 7. Documentation (`README.md`)

**Location**: `c:\Users\us\tools\code\cursor-agent-windows-patcher\README.md`

**Sections**:

- Overview and purpose
- Prerequisites (Node.js, PowerShell)
- Installation instructions
- Usage
- Troubleshooting
- Maintenance (updating versions)
- Limitations and disclaimers

### 8. Agent Guidelines (`AGENTS.md`)

**Location**: `c:\Users\us\tools\code\cursor-agent-windows-patcher\AGENTS.md`

**Purpose**: Following `SETUP.prompt.md` structure, create agent guidelines adapted for PowerShell/Windows automation project.

**Sections** (adapted from template):

- **Project Overview**: PowerShell automation tool to install Cursor Agent CLI on Windows
- **PowerShell-First Approach**: Use native PowerShell cmdlets, avoid external dependencies where possible
- **Commands**: PowerShell execution commands, testing, validation
- **Project Structure**: PowerShell modules, scripts, config files
- **Code Style**: PowerShell best practices, error handling, function structure
- **Environment Variables**: Installation paths, version configs
- **Testing**: Pester test framework usage
- **Key Dependencies**: PowerShell modules (if any), external tools (Node.js, 7-Zip)
- **Common Tasks**: Adding new download functions, updating versions, patching logic
- **Progress Tracking**: Reference to PLAN.md system

**Adaptations from reference template**:

- Replace TypeScript-centric patterns with PowerShell patterns
- Use PowerShell module structure instead of TypeScript
- Document PowerShell testing with Pester
- Focus on Windows-specific automation patterns

### 9. Progress Plan (`PLAN.md`)

**Location**: `c:\Users\us\tools\code\cursor-agent-windows-patcher\WORK.md`

**Purpose**: Track implementation progress across sessions using chunk-based system.

**Structure**:

1. **Overview**: Brief description matching AGENTS.md
2. **Progress Tracker**: Chunks based on implementation steps:

   - Chunk 1: Project setup and configuration files
   - Chunk 2: Helper module implementation
   - Chunk 3: Main installation script core
   - Chunk 4: Native module patching
   - Chunk 5: Dependency download and replacement
   - Chunk 6: Launcher and finalization
   - Chunk 7: Documentation and testing

3. **Current Focus**: First chunk to start
4. **Session Log**: Track work sessions with dates and notes

**Status Legend**:

- ⬜ Not Started
- 🟡 In Progress
- ✅ Complete
- ⚠️ Blocked

## Implementation Steps

1. Create AGENTS.md and PLAN.md following SETUP.prompt.md structure
2. Create project structure and configuration files
3. Implement helper module with download/extraction utilities
4. Implement main installation script with error handling
5. Add native module patching logic
6. Implement dependency download and replacement
7. Create launcher script
8. Write comprehensive README
9. Add error handling and user feedback
10. Test installation flow end-to-end

## Technical Considerations

- **Version Detection**: Parse the install script from `https://cursor.com/install` to get latest version, or use config file
- **Architecture Detection**: Use `$env:PROCESSOR_ARCHITECTURE` or `[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture`
- **Error Handling**: Validate downloads, check file integrity, provide clear error messages
- **Idempotency**: Allow re-running script to update/reinstall
- **Cleanup**: Option to remove temporary files after installation
- **Logging**: Verbose mode for debugging

## Dependencies

- PowerShell 5.1+ (Windows 10+)
- Node.js - user must have it installed
- Internet connection for downloads
- 7-Zip or built-in `Expand-Archive` for extraction

## File Structure

```
cursor-agent-windows-patcher/
├── patch-cursor-agent.ps1        # Main installation script
├── CursorAgentPatcher.psm1       # Helper module
├── patcher-config.json           # Configuration
├── cursor-agent.bat              # Launcher script
├── README.md                     # User documentation
├── AGENTS.md                     # AI agent guidelines
├── WORK.md                       # Progress tracking
├── plans/                        # Implementation plans
│   └── implementation-plan.md   # This file
```
