# Atomic Implementation Specifications

This document breaks down the Automatic Cursor Agent Windows Patcher into atomic, testable specifications. Each spec can be implemented and verified independently.

## Spec Categories

1. **Configuration & Setup** (Specs 1-3)
2. **Version Detection & Extraction** (Specs 4-8)
3. **Download & Caching** (Specs 9-12)
4. **Patch Registry System** (Specs 13-16)
5. **Individual Patches** (Specs 17-21)
6. **Main Workflow** (Specs 22-25)
7. **Utilities & Helpers** (Specs 26-30)
8. **Testing Infrastructure** (Specs 31-35)

---

## Testing Strategy

This project prioritizes **property-based testing**, **deterministic simulation testing (DST)**, and **state machine testing** over traditional unit tests. Unit tests are used only when property-based approaches are impractical.

### Testing Approach Hierarchy

1. **Property-Based Testing** (Primary)
   - Generate random inputs and verify properties hold
   - Test invariants, transformations, and relationships
   - Use for: version extraction, regex patterns, file operations, transformations

2. **State Machine Testing** (Primary)
   - Model patching workflow as finite state machine
   - Generate valid state transition sequences
   - Verify invariants hold across all transitions
   - Use for: main workflow, patch application, dependency resolution

3. **Deterministic Simulation Testing (DST)** (Primary)
   - Create deterministic simulation of entire system
   - Control all external dependencies (network, file system, time)
   - Verify system behavior under various scenarios
   - Use for: end-to-end workflows, integration testing, error scenarios

4. **Unit Tests** (Fallback Only)
   - Use only when property-based testing is impractical
   - Examples: complex error handling, edge cases hard to generate

### Testing Framework

**Custom Property-Based Testing Framework** for PowerShell:
- Generator functions for common types (strings, versions, file paths, JSON)
- Property definition syntax similar to FsCheck/QuickCheck
- Shrinking support for counterexamples
- Integration with Pester for test execution

**State Machine Testing Framework**:
- Define state machine with states, transitions, and invariants
- Generate valid command sequences
- Verify invariants after each transition
- Support for parallel state machines (cache, download, patch)

**Deterministic Simulation Framework**:
- Mock all external dependencies (HTTP, file system, processes)
- Deterministic random number generation
- Time control (freeze, advance, rewind)
- Snapshot/restore for state inspection

### Test Organization

```
tests/
├── properties/           # Property-based tests
│   ├── version-extraction.tests.ps1
│   ├── regex-patterns.tests.ps1
│   ├── file-operations.tests.ps1
│   └── transformations.tests.ps1
├── state-machines/        # State machine tests
│   ├── patching-workflow.tests.ps1
│   ├── patch-registry.tests.ps1
│   └── dependency-resolution.tests.ps1
├── simulations/          # DST tests
│   ├── full-workflow.tests.ps1
│   ├── error-scenarios.tests.ps1
│   └── edge-cases.tests.ps1
├── unit/                 # Unit tests (minimal)
│   └── error-handling.tests.ps1
└── helpers/              # Testing utilities
    ├── PropertyTest.psm1
    ├── StateMachine.psm1
    └── Simulation.psm1
```

### Property Examples

**Version Extraction Property**:
```powershell
# Property: Extracted version always matches input format
Property "Version extraction preserves format" {
    param([string]$Version)
    
    $script = "DOWNLOAD_URL=`"https://downloads.cursor.com/lab/$Version/darwin/arm64/agent-cli-package.tar.gz`""
    $extracted = Get-CursorAgentVersion -InstallScript $script
    
    $extracted | Should -Match '^\d{4}\.\d{2}\.\d{2}-[a-f0-9]+$'
} -ForAll (Gen-VersionString)
```

**File Operation Property**:
```powershell
# Property: File operations are idempotent
Property "Cache operations are idempotent" {
    param([string]$Content, [string]$CacheKey)
    
    $path1 = Save-BinaryToCache -SourcePath (New-TempFile $Content) -CacheKey $CacheKey
    $path2 = Save-BinaryToCache -SourcePath (New-TempFile $Content) -CacheKey $CacheKey
    
    (Get-FileHash $path1).Hash | Should -Be (Get-FileHash $path2).Hash
} -ForAll (Gen-BinaryContent, Gen-CacheKey)
```

### State Machine Example

**Patching Workflow State Machine**:
```powershell
$PatchingStateMachine = New-StateMachine {
    States @('Initial', 'Downloaded', 'Extracted', 'Analyzed', 'Patched', 'Installed', 'Error')
    
    Transitions {
        From 'Initial' To 'Downloaded' When { Test-DownloadComplete }
        From 'Downloaded' To 'Extracted' When { Test-ExtractionComplete }
        From 'Extracted' To 'Analyzed' When { Test-AnalysisComplete }
        From 'Analyzed' To 'Patched' When { Test-PatchingComplete }
        From 'Patched' To 'Installed' When { Test-InstallationComplete }
        From Any To 'Error' When { Test-ErrorOccurred }
    }
    
    Invariants {
        'Package path always valid' { $State.PackagePath | Test-Path }
        'Cache directory exists' { $State.CacheDirectory | Test-Path }
        'No partial patches' { $State.PatchesApplied.Count -eq $State.PatchesExpected.Count }
    }
}

# Generate and test valid command sequences
Test-StateMachine -StateMachine $PatchingStateMachine -Sequences 1000
```

### Deterministic Simulation Example

**Full Workflow Simulation**:
```powershell
Simulation "Complete patching workflow" {
    Setup {
        $sim = New-Simulation {
            Mock-Http {
                'https://cursor.com/install' => $InstallScript
                'https://downloads.cursor.com/...' => $PackageBytes
                'https://api.github.com/...' => $GitHubReleases
            }
            Mock-FileSystem {
                TempDirectory => $TempDir
                CacheDirectory => $CacheDir
            }
            Freeze-Time '2025-01-15 10:00:00'
        }
    }
    
    Execute {
        Invoke-CursorAgentPatch -Version "2025.08.15-dbc8d73"
    }
    
    Verify {
        $sim.FileSystem['InstallPath\index.js'] | Should -Exist
        $sim.FileSystem['InstallPath\rg.exe'] | Should -Exist
        $sim.FileSystem['InstallPath\cursor-agent.bat'] | Should -Exist
        $sim.Cache['binaries'] | Should -HaveCount 3
    }
}
```

---

## Configuration & Setup

### Spec 1: Create patcher-config.json Structure

**File**: `patcher-config.json`

**Purpose**: Define configuration schema for version mappings, cache settings, and installation defaults.

**Structure**:
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
      },
      "default": {
        "windowsBinary": {
          "repo": "TryGhost/node-sqlite3",
          "assetPattern": ".*windows.*node_sqlite3.*\\.node",
          "releaseTag": "latest"
        }
      }
    },
    "merkleTree": {
      "default": {
        "windowsBinary": {
          "repo": "btc-vision/rust-merkle-tree",
          "assetPattern": "merkle-tree-napi\\.win32-x64-msvc\\.node",
          "releaseTag": "latest"
        }
      }
    },
    "ripgrep": {
      "default": {
        "windowsBinary": {
          "repo": "BurntSushi/ripgrep",
          "assetPattern": "ripgrep-.*-x86_64-pc-windows-msvc\\.zip",
          "releaseTag": "latest"
        }
      }
    }
  },
  "cache": {
    "directory": "%LOCALAPPDATA%\\cursor-agent-patcher\\cache",
    "enabled": true,
    "validateOnUse": true
  },
  "installation": {
    "defaultPath": ".\\cursor-agent",
    "createLauncher": true,
    "launcherName": "cursor-agent.bat"
  },
  "cursorAgent": {
    "installScriptUrl": "https://cursor.com/install",
    "downloadBaseUrl": "https://downloads.cursor.com/lab",
    "sourceOs": "darwin",
    "sourceArch": "arm64"
  }
}
```

**Validation**:
- JSON must be valid and parseable
- All required top-level keys must exist
- Asset patterns must be valid regex
- Paths must use Windows-style separators

**Dependencies**: None

**Success Criteria**: File can be loaded and parsed without errors, all required keys present

---

### Spec 2: Load and Validate Configuration Function

**Function**: `Get-PatcherConfig`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Load configuration from JSON file with validation and environment variable expansion.

**Signature**:
```powershell
function Get-PatcherConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = ".\patcher-config.json"
    )
    [PSCustomObject] # Returns validated config object
}
```

**Behavior**:
1. Read JSON file from `$ConfigPath`
2. Expand environment variables in paths (e.g., `%LOCALAPPDATA%`)
3. Validate required keys exist
4. Validate regex patterns are valid
5. Return PSCustomObject with typed properties

**Error Handling**:
- File not found → Throw with clear message
- Invalid JSON → Throw with parse error details
- Missing required keys → Throw listing missing keys
- Invalid regex → Throw with pattern and error

**Dependencies**: Spec 1

**Success Criteria**: 
- Returns valid config object when file exists and is valid
- Throws descriptive errors for invalid configurations
- Expands environment variables correctly

---

### Spec 3: Initialize Cache Directory Function

**Function**: `Initialize-CacheDirectory`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Create cache directory structure if it doesn't exist.

**Signature**:
```powershell
function Initialize-CacheDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CachePath
    )
    [string] # Returns path to cache directory
}
```

**Behavior**:
1. If `$CachePath` not provided, use config value
2. Expand environment variables in path
3. Create directory if it doesn't exist
4. Create subdirectories: `binaries\`, `packages\`
5. Return absolute path to cache directory

**Error Handling**:
- Permission denied → Throw with path and permission error
- Invalid path → Throw with path validation error

**Dependencies**: Spec 2

**Success Criteria**:
- Creates directory structure if missing
- Returns existing directory if already present
- Handles permission errors gracefully

---

## Version Detection & Extraction

### Spec 4: Fetch Cursor Agent Install Script

**Function**: `Get-CursorAgentInstallScript`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Download and return the install script from cursor.com/install.

**Signature**:
```powershell
function Get-CursorAgentInstallScript {
    [CmdletBinding()]
    param()
    [string] # Returns script content
}
```

**Behavior**:
1. Fetch `https://cursor.com/install` using `Invoke-WebRequest`
2. Return raw script content as string
3. Handle HTTP errors (404, 500, timeout)

**Error Handling**:
- Network error → Throw with URL and error details
- HTTP error status → Throw with status code and message
- Timeout → Throw with timeout duration

**Dependencies**: None (uses PowerShell built-ins)

**Success Criteria**:
- Returns script content on success
- Handles network errors with descriptive messages
- Works with PowerShell 5.1+

---

### Spec 5: Extract Cursor Agent Version from Install Script

**Function**: `Get-CursorAgentVersion`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Parse install script to extract version string (e.g., `2025.08.15-dbc8d73`).

**Signature**:
```powershell
function Get-CursorAgentVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallScript
    )
    [string] # Returns version string
}
```

**Behavior**:
1. Search for version pattern in install script
2. Pattern: `DOWNLOAD_URL="https://downloads.cursor.com/lab/([^/]+)/`
3. Extract version from first capture group
4. Validate format: `YYYY.MM.DD-{hash}`

**Error Handling**:
- Version not found → Throw with message showing search context
- Invalid format → Throw with extracted value and expected format

**Dependencies**: Spec 4

**Success Criteria**:
- Extracts version string from valid install script
- Returns null or throws on invalid/missing version
- Handles multiple URL patterns if script format changes

**Testing**:
- Property-based: Version format preservation (Spec 34)
- Property-based: Idempotency (Spec 34)
- Unit tests: Edge cases (malformed scripts, missing URLs)

---

### Spec 6: Extract SQLite3 Version from Package

**Function**: `Get-Sqlite3Version`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Extract sqlite3 version from extracted package (bundled code or package.json).

**Signature**:
```powershell
function Get-Sqlite3Version {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath
    )
    [string] # Returns version string or $null
}
```

**Behavior**:
1. Search for `package.json` in package directory
2. If found, parse JSON and look for `sqlite3` in dependencies
3. If not found, search bundled `index.js` for patterns:
   - `sqlite3@(\d+\.\d+\.\d+)`
   - `"sqlite3":\s*"(\d+\.\d+\.\d+)"`
   - `sqlite3@5\.1\.7` (extract version)
4. Return first match or `$null`

**Error Handling**:
- Package path invalid → Throw
- No version found → Return `$null` (not an error)

**Dependencies**: None

**Success Criteria**:
- Extracts version from package.json if present
- Extracts version from bundled code as fallback
- Returns `$null` gracefully when not found

---

### Spec 7: Extract Merkle Tree Version from Package

**Function**: `Get-MerkleTreeVersion`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Extract @btc-vision/rust-merkle-tree version from package.

**Signature**:
```powershell
function Get-MerkleTreeVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath
    )
    [string] # Returns version string or $null
}
```

**Behavior**:
1. Search for `package.json` in package directory
2. If found, parse JSON and look for `@btc-vision/rust-merkle-tree` in dependencies
3. If not found, search bundled code for patterns:
   - `@btc-vision/rust-merkle-tree@(\d+\.\d+\.\d+)`
   - `"@btc-vision/rust-merkle-tree":\s*"(\d+\.\d+\.\d+)"`
4. Return first match or `$null`

**Error Handling**: Same as Spec 6

**Dependencies**: None

**Success Criteria**: Same pattern as Spec 6

---

### Spec 8: Extract RipGrep Version from Package

**Function**: `Get-RipGrepVersion`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Attempt to extract ripgrep version from binary or package metadata.

**Signature**:
```powershell
function Get-RipGrepVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath
    )
    [string] # Returns version string or $null
}
```

**Behavior**:
1. Locate `rg` binary in package
2. If binary exists, try to execute `rg --version` (may fail on macOS binary on Windows)
3. Parse version from output: `ripgrep (\d+\.\d+\.\d+)`
4. If execution fails, search for version strings in package files
5. Return version or `$null` if not detectable

**Error Handling**:
- Binary not found → Return `$null`
- Execution fails → Return `$null` (expected for cross-platform binaries)

**Dependencies**: None

**Success Criteria**:
- Returns version if binary is executable and reports version
- Returns `$null` gracefully when version cannot be determined
- Does not throw errors on failure

---

## Download & Caching

### Spec 9: Download File with Progress Function

**Function**: `Get-FileWithProgress`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Download file from URL with progress indication and error handling.

**Signature**:
```powershell
function Get-FileWithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowProgress
    )
    [void]
}
```

**Behavior**:
1. Use `Invoke-WebRequest` with `-OutFile` parameter
2. If `$ShowProgress`, use `Write-Progress` to show download status
3. Handle redirects automatically
4. Verify file exists and has non-zero size after download

**Error Handling**:
- Network error → Throw with URL and error
- HTTP error → Throw with status code
- Write error → Throw with path and error
- Zero-size file → Throw indicating download may have failed

**Dependencies**: None

**Success Criteria**:
- Downloads file successfully
- Shows progress when requested
- Validates downloaded file
- Provides clear error messages

---

### Spec 10: Get GitHub Release Asset Function

**Function**: `Get-GitHubReleaseAsset`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Find and download a specific asset from a GitHub release.

**Signature**:
```powershell
function Get-GitHubReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Repo, # e.g., "btc-vision/rust-merkle-tree"
        
        [Parameter(Mandatory=$true)]
        [string]$AssetPattern, # Regex pattern to match asset name
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath,
        
        [Parameter(Mandatory=$false)]
        [string]$ReleaseTag = "latest" # "latest" or specific tag like "v1.2.3"
    )
    [void]
```

**Behavior**:
1. Construct GitHub API URL:
   - Latest: `https://api.github.com/repos/$Repo/releases/latest`
   - Specific: `https://api.github.com/repos/$Repo/releases/tags/$ReleaseTag`
2. Fetch release metadata using `Invoke-RestMethod`
3. Filter assets by `$AssetPattern` regex
4. If multiple matches, prefer Windows-specific assets, then take first
5. Download matched asset using `Get-FileWithProgress`
6. Save to `$OutPath`

**Error Handling**:
- API error → Throw with repo and error details
- No matching asset → Throw listing available assets
- Multiple matches → Use first, log warning if verbose
- Download fails → Propagate error from `Get-FileWithProgress`

**Dependencies**: Spec 9

**Success Criteria**:
- Finds and downloads correct asset
- Handles "latest" and specific tags
- Provides clear errors when asset not found
- Prefers Windows-specific assets when multiple match

---

### Spec 11: Get Cached Binary Function

**Function**: `Get-CachedBinary`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Check cache for binary and return path if valid, or `$null` if not cached.

**Signature**:
```powershell
function Get-CachedBinary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheKey, # e.g., "merkle-tree-v1.2.3-windows"
        
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory
    )
    [string] # Returns path to cached file or $null
}
```

**Behavior**:
1. Construct cache file path: `$CacheDirectory\binaries\$CacheKey`
2. If file exists:
   - If config has `validateOnUse: true`, verify file is readable and non-zero size
   - Return absolute path to cached file
3. If file doesn't exist, return `$null`

**Error Handling**:
- Cache directory invalid → Throw
- File exists but invalid → Return `$null` (treat as cache miss)

**Dependencies**: Spec 2, Spec 3

**Success Criteria**:
- Returns cached path when file exists and is valid
- Returns `$null` when not cached
- Validates cached files when configured

---

### Spec 12: Cache Binary Function

**Function**: `Save-BinaryToCache`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Save downloaded binary to cache with version-based naming.

**Signature**:
```powershell
function Save-BinaryToCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$CacheKey,
        
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory
    )
    [string] # Returns path to cached file
}
```

**Behavior**:
1. Ensure cache directory exists (call `Initialize-CacheDirectory`)
2. Construct destination: `$CacheDirectory\binaries\$CacheKey`
3. Copy file from `$SourcePath` to destination
4. Return absolute path to cached file

**Error Handling**:
- Source file doesn't exist → Throw
- Copy fails → Throw with source, destination, and error
- Permission denied → Throw with path and permission error

**Dependencies**: Spec 3

**Success Criteria**:
- Copies file to cache successfully
- Returns path to cached file
- Handles errors with clear messages

---

## Patch Registry System

### Spec 13: Patch Registry Data Structure

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Define patch registry hashtable structure.

**Structure**:
```powershell
$script:PatchRegistry = @{
    "patch-id" = @{
        Description = "Human-readable description"
        FilePattern = "**/glob/pattern.js" # PowerShell glob pattern
        Priority = 1 # Lower numbers apply first
        Dependencies = @("other-patch-id") # Patches that must run first
        Apply = {
            param(
                [string]$FilePath, # Path to file being patched
                [hashtable]$Context # Context with versions, paths, etc.
            )
            # Patch application logic
        }
        Verify = {
            param([string]$FilePath)
            # Return $true if patch was successful, $false otherwise
            return $true
        }
    }
}
```

**Validation**:
- Each patch must have: Description, FilePattern, Priority, Apply, Verify
- Dependencies must reference existing patch IDs
- Priorities must be positive integers
- Apply and Verify must be scriptblocks

**Dependencies**: None

**Success Criteria**: Registry structure is valid and can be queried

---

### Spec 14: Find Files Matching Pattern Function

**Function**: `Find-FilesMatchingPattern`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Find all files in directory tree matching a glob pattern.

**Signature**:
```powershell
function Find-FilesMatchingPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Pattern # PowerShell glob pattern like "**/native.js"
    )
    [string[]] # Returns array of matching file paths
}
```

**Behavior**:
1. Convert glob pattern to PowerShell `Get-ChildItem` filter
2. Handle `**` as recursive wildcard
3. Search recursively from `$RootPath`
4. Return array of absolute paths to matching files

**Error Handling**:
- Root path invalid → Throw
- No matches found → Return empty array (not an error)

**Dependencies**: None

**Success Criteria**:
- Finds files matching simple patterns (`*.js`)
- Finds files matching recursive patterns (`**/native.js`)
- Returns empty array when no matches (doesn't throw)

---

### Spec 15: Resolve Patch Dependencies Function

**Function**: `Resolve-PatchDependencies`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Sort patches by priority and dependencies to determine execution order.

**Signature**:
```powershell
function Resolve-PatchDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PatchRegistry
    )
    [array] # Returns ordered array of patch IDs
}
```

**Behavior**:
1. Build dependency graph from registry
2. Detect circular dependencies (throw if found)
3. Sort by priority (lower first)
4. Within same priority, ensure dependencies run first (topological sort)
5. Return ordered array of patch IDs

**Error Handling**:
- Circular dependency → Throw with cycle details
- Missing dependency → Throw with patch ID and missing dependency

**Dependencies**: Spec 13

**Success Criteria**:
- Returns patches in correct execution order
- Detects and reports circular dependencies
- Handles patches with no dependencies

---

### Spec 16: Apply Patch Function

**Function**: `Invoke-Patch`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Apply a single patch to matching files with verification.

**Signature**:
```powershell
function Invoke-Patch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PatchDefinition,
        
        [Parameter(Mandatory=$true)]
        [string]$PackagePath,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    [hashtable] # Returns result: {Success, FilesPatched, Errors}
}
```

**Behavior**:
1. Find files matching `$PatchDefinition.FilePattern` in `$PackagePath`
2. For each matching file:
   - If `$WhatIf`, log what would be done
   - Otherwise, call `$PatchDefinition.Apply` with file path and context
   - Call `$PatchDefinition.Verify` to validate
   - If verification fails, record error
3. Return result hashtable with success status, file count, and errors

**Error Handling**:
- Apply scriptblock throws → Catch, record error, continue with next file
- Verify fails → Record error but don't throw (allow manual inspection)
- No files found → Return success with 0 files patched

**Dependencies**: Spec 13, Spec 14

**Success Criteria**:
- Applies patch to all matching files
- Verifies each patch
- Returns detailed results
- Supports `-WhatIf` mode
- Continues on individual file errors

---

## Individual Patches

### Spec 17: Platform Detection Patch

**Patch ID**: `platform-detection`

**Purpose**: Modify `native.js` to support Windows platform by adding win32 branch.

**File Pattern**: `**/native.js`

**Priority**: 1 (must run first)

**Dependencies**: None

**Apply Logic**:
1. Read file content
2. Detect available loaders by searching for `require_merkle_tree_napi_*` patterns
3. Select best loader:
   - If Windows x64 and darwin-x64 available → use darwin-x64
   - Else if darwin-arm64 available → use darwin-arm64
   - Else use first available loader
4. Find pattern: `} else {\s+throw new Error(\`Unsupported platform: \$\{platform3\}\`);`
5. Replace with:
   ```javascript
   } else if (platform3 === "win32") {
       nativeBinding = require_merkle_tree_napi_{selectedLoader}();
   } else {
       throw new Error(`Unsupported platform: ${platform3}`);
   }
   ```
6. Write patched content back

**Verify Logic**:
- Check file contains `platform3 === "win32"`
- Check file contains `require_merkle_tree_napi_` (any variant)

**Dependencies**: Spec 16

**Success Criteria**:
- Adds Windows platform support
- Selects appropriate loader based on available options
- Verification confirms patch was applied

---

### Spec 18: Merkle Tree Module Replacement Patch

**Patch ID**: `merkle-tree-module`

**Purpose**: Replace merkle-tree native module file with Windows version.

**File Pattern**: `**/qfpzq242.node` (or any `.node` file referenced by merkle-tree loader)

**Priority**: 2

**Dependencies**: `platform-detection`

**Apply Logic**:
1. Get Windows merkle-tree binary from `$Context.WindowsBinaries['merkleTree']`
2. If binary path not in context, throw error
3. Copy Windows binary over existing `.node` file
4. Preserve file permissions if possible

**Verify Logic**:
- Check file exists
- Check file size > 0
- Optionally: verify file is valid `.node` module (check magic bytes)

**Dependencies**: Spec 16, Spec 10, Spec 11, Spec 12

**Success Criteria**:
- Replaces module file with Windows version
- Verification confirms file is valid
- Handles missing binary gracefully

---

### Spec 19: SQLite3 Module Replacement Patch

**Patch ID**: `sqlite3-module`

**Purpose**: Replace sqlite3 native module file with Windows version.

**File Pattern**: `**/kkkzjw1t.node` (or any `.node` file referenced by sqlite3 loader)

**Priority**: 2

**Dependencies**: None

**Apply Logic**: Same pattern as Spec 18, but for sqlite3 binary

**Verify Logic**: Same pattern as Spec 18

**Dependencies**: Spec 16, Spec 10, Spec 11, Spec 12

**Success Criteria**: Same pattern as Spec 18

---

### Spec 20: RipGrep Binary Replacement Patch

**Patch ID**: `ripgrep-binary`

**Purpose**: Replace `rg` binary with Windows `rg.exe`.

**File Pattern**: `**/rg` (exact filename, no extension)

**Priority**: 2

**Dependencies**: None

**Apply Logic**:
1. Get ripgrep zip from `$Context.WindowsBinaries['ripgrep']`
2. Extract `rg.exe` from zip (may be in subdirectory like `ripgrep-13.0.0-x86_64-pc-windows-msvc/`)
3. Copy `rg.exe` to location of `rg` file
4. Delete original `rg` file
5. Rename `rg.exe` to `rg.exe` (keep .exe extension)

**Verify Logic**:
- Check `rg.exe` exists
- Check file size > 0
- Optionally: try to execute `rg.exe --version` to verify it's valid

**Dependencies**: Spec 16, Spec 10, Spec 11, Spec 12

**Success Criteria**:
- Replaces binary with Windows executable
- Handles zip extraction correctly
- Verification confirms executable is valid

---

### Spec 21: Register All Patches Function

**Function**: `Register-StandardPatches`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Initialize patch registry with all standard patches.

**Signature**:
```powershell
function Register-StandardPatches {
    [CmdletBinding()]
    param()
    [void]
}
```

**Behavior**:
1. Define all standard patches (Specs 17-20) in registry
2. Store in `$script:PatchRegistry`
3. Validate registry structure after registration

**Dependencies**: Spec 13, Spec 17, Spec 18, Spec 19, Spec 20

**Success Criteria**:
- All standard patches registered
- Registry structure is valid
- Dependencies are correctly defined

---

## Main Workflow

### Spec 22: Download Cursor Agent Package Function

**Function**: `Get-CursorAgentPackage`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Download Cursor Agent package for specified version and architecture.

**Signature**:
```powershell
function Get-CursorAgentPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version,
        
        [Parameter(Mandatory=$false)]
        [string]$SourceOs = "darwin",
        
        [Parameter(Mandatory=$false)]
        [string]$SourceArch = "arm64",
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath
    )
    [string] # Returns path to downloaded package
}
```

**Behavior**:
1. Construct URL: `https://downloads.cursor.com/lab/$Version/$SourceOs/$SourceArch/agent-cli-package.tar.gz`
2. Download using `Get-FileWithProgress`
3. Verify file exists and has reasonable size (> 1MB)
4. Return path to downloaded file

**Error Handling**:
- Invalid URL → Throw
- Download fails → Propagate error
- File too small → Throw indicating possible corruption

**Dependencies**: Spec 9

**Success Criteria**:
- Downloads package successfully
- Validates download size
- Returns path to package file

---

### Spec 23: Extract Package Archive Function

**Function**: `Expand-CursorAgentPackage`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Extract `.tar.gz` archive to directory.

**Signature**:
```powershell
function Expand-CursorAgentPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,
        
        [Parameter(Mandatory=$true)]
        [string]$OutDirectory
    )
    [string] # Returns path to extracted directory
}
```

**Behavior**:
1. Check if 7-Zip is available (`7z.exe` in PATH)
2. If available, use 7-Zip to extract `.tar.gz`
3. If not available, try PowerShell `Expand-Archive` (may not support `.tar.gz` in 5.1)
4. If PowerShell fails, throw with instructions to install 7-Zip
5. Return path to extracted directory

**Error Handling**:
- Archive not found → Throw
- Extraction fails → Throw with tool used and error
- No extraction tool available → Throw with installation instructions

**Dependencies**: None (uses external tools)

**Success Criteria**:
- Extracts archive successfully
- Handles both 7-Zip and PowerShell methods
- Provides clear errors when tools missing

---

### Spec 24: Build Patch Context Function

**Function**: `New-PatchContext`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Build context hashtable with all information needed for patches.

**Signature**:
```powershell
function New-PatchContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath,
        
        [Parameter(Mandatory=$true)]
        [string]$CursorAgentVersion,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$DependencyVersions = @{},
        
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory
    )
    [hashtable] # Returns context object
}
```

**Behavior**:
1. Detect Windows architecture (x64 or arm64)
2. Extract dependency versions if not provided (call Specs 6-8)
3. Download/cache Windows binaries (call Specs 10-12)
4. Build context hashtable:
   ```powershell
   @{
       PackagePath = $PackagePath
       CursorAgentVersion = $CursorAgentVersion
       WindowsArchitecture = "x64" or "arm64"
       DependencyVersions = @{
           sqlite3 = "5.1.7"
           merkleTree = "1.2.3"
           ripgrep = "13.0.0"
       }
       WindowsBinaries = @{
           sqlite3 = "C:\path\to\cached\binary.node"
           merkleTree = "C:\path\to\cached\binary.node"
           ripgrep = "C:\path\to\cached\ripgrep.zip"
       }
       CacheDirectory = $CacheDirectory
   }
   ```

**Error Handling**:
- Version extraction fails → Use defaults from config
- Binary download fails → Throw with dependency name and error
- Architecture detection fails → Default to x64

**Dependencies**: Specs 6-8, Specs 10-12, Spec 2

**Success Criteria**:
- Builds complete context with all required information
- Handles missing versions gracefully
- Downloads and caches binaries successfully

---

### Spec 25: Main Patching Workflow Function

**Function**: `Invoke-CursorAgentPatch`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Orchestrate complete patching workflow from download to installation.

**Signature**:
```powershell
function Invoke-CursorAgentPatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Version, # Override version, or auto-detect if not provided
        
        [Parameter(Mandatory=$false)]
        [string]$InstallPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf,
        
        [Parameter(Mandatory=$false)]
        [switch]$Verbose
    )
    [hashtable] # Returns result summary
}
```

**Behavior**:
1. Load configuration (Spec 2)
2. Initialize cache (Spec 3)
3. Get Cursor Agent version (Specs 4-5, or use provided)
4. Download package (Spec 22)
5. Extract package (Spec 23)
6. Build patch context (Spec 24)
7. Resolve patch order (Spec 15)
8. Apply all patches (Spec 16) in order
9. Copy patched package to install path
10. Create launcher script (Spec 26)
11. Return summary with success status and details

**Error Handling**:
- Fail fast on any critical error
- Provide clear error messages at each step
- Clean up temp files on failure (optional)

**Dependencies**: All previous specs

**Success Criteria**:
- Completes full workflow successfully
- Supports `-WhatIf` mode
- Provides detailed progress and results
- Handles errors gracefully

**Testing**:
- State machine: Workflow state transitions and invariants (Spec 35)
- DST: End-to-end scenarios (Spec 36)
- Property-based: Workflow idempotency
- Unit tests: Error handling edge cases

---

## Utilities & Helpers

### Spec 26: Create Launcher Script Function

**Function**: `New-CursorAgentLauncher`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Generate `cursor-agent.bat` launcher script.

**Signature**:
```powershell
function New-CursorAgentLauncher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallPath,
        
        [Parameter(Mandatory=$false)]
        [string]$LauncherName = "cursor-agent.bat"
    )
    [string] # Returns path to created launcher
}
```

**Behavior**:
1. Determine path to `index.js` in installed package
2. Generate batch script:
   ```batch
   @echo off
   cd /d "%~dp0"
   node index.js %*
   ```
3. Write to `$InstallPath\$LauncherName`
4. Return path to launcher

**Error Handling**:
- Install path invalid → Throw
- Write fails → Throw with path and error

**Dependencies**: None

**Success Criteria**:
- Creates valid batch launcher
- Launcher correctly invokes Node.js with index.js
- Returns path to created file

---

### Spec 27: Detect Windows Architecture Function

**Function**: `Get-WindowsArchitecture`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Detect Windows system architecture (x64 or arm64).

**Signature**:
```powershell
function Get-WindowsArchitecture {
    [CmdletBinding()]
    param()
    [string] # Returns "x64" or "arm64"
}
```

**Behavior**:
1. Check `$env:PROCESSOR_ARCHITECTURE` environment variable
2. Map values:
   - `AMD64` → `x64`
   - `ARM64` → `arm64`
3. Fallback: Use `[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture`
4. Default to `x64` if detection fails

**Dependencies**: None

**Success Criteria**:
- Correctly detects x64 and arm64
- Has fallback methods
- Never throws (always returns a value)

---

### Spec 28: Main Script Entry Point

**File**: `patch-cursor-agent.ps1`

**Purpose**: Command-line interface for the patcher.

**Structure**:
```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string]$Sqlite3Version,
    
    [Parameter(Mandatory=$false)]
    [string]$MerkleTreeVersion,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Import module
Import-Module .\CursorAgentPatcher.psm1

# Set error action
$ErrorActionPreference = "Stop"

# Call main workflow
try {
    $result = Invoke-CursorAgentPatch @PSBoundParameters
    Write-Host "Patch completed successfully!" -ForegroundColor Green
    Write-Host "Installed to: $($result.InstallPath)" -ForegroundColor Cyan
}
catch {
    Write-Error "Patching failed: $_"
    exit 1
}
```

**Dependencies**: Spec 25

**Success Criteria**:
- Parses all command-line parameters
- Calls main workflow function
- Provides user-friendly output
- Exits with appropriate codes

---

### Spec 29: Module Export Configuration

**File**: `CursorAgentPatcher.psm1`

**Purpose**: Export public functions, keep internal functions private.

**Exports**:
- `Get-PatcherConfig`
- `Get-CursorAgentVersion`
- `Invoke-CursorAgentPatch`
- `New-CursorAgentLauncher`
- `Get-WindowsArchitecture`

**Internal Functions** (not exported):
- All helper functions (Specs 6-12, 14-16, 22-24)
- Patch registry accessors
- Cache management functions

**Dependencies**: All function specs

**Success Criteria**:
- Only public API functions are exported
- Internal functions are accessible within module
- Module loads without errors

---

### Spec 30: Error Message Standardization

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Consistent error messaging across all functions.

**Error Format**:
```powershell
Write-Error "FunctionName: Description of what failed. Additional context: $variable"
```

**Error Categories**:
- **Configuration errors**: Missing or invalid config
- **Network errors**: Download failures, API errors
- **File system errors**: Path issues, permission problems
- **Patch errors**: Application failures, verification failures
- **Validation errors**: Invalid input, missing dependencies

**Dependencies**: All function specs

**Success Criteria**:
- All errors follow consistent format
- Errors include function name and context
- Errors are actionable (tell user what to do)

---

## Testing Infrastructure

### Spec 31: Property-Based Testing Framework

**Module**: `tests/helpers/PropertyTest.psm1`

**Purpose**: Provide property-based testing framework similar to FsCheck/QuickCheck for PowerShell.

**Key Functions**:
```powershell
function Property {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [hashtable]$ForAll # Generators for each parameter
    )
}

function Gen-VersionString { ... }      # Generate version strings like "2025.08.15-dbc8d73"
function Gen-SemanticVersion { ... }     # Generate semantic versions like "5.1.7"
function Gen-FilePath { ... }            # Generate valid file paths
function Gen-JSON { ... }                # Generate valid JSON structures
function Gen-String { ... }              # Generate strings with constraints
function Gen-Integer { ... }             # Generate integers in range
function Gen-Choice { ... }              # Choose from array of values
```

**Behavior**:
1. Generate random inputs using generators
2. Run test scriptblock with generated inputs
3. If test fails, attempt to shrink inputs to minimal counterexample
4. Report results with generated inputs and any failures

**Shrinking Strategy**:
- Strings: Remove characters, shorten length
- Numbers: Move toward zero, reduce magnitude
- Collections: Remove elements, reduce size
- Composite types: Shrink individual components

**Dependencies**: None (foundation for all property tests)

**Success Criteria**:
- Generates diverse test inputs
- Shrinks counterexamples effectively
- Integrates with Pester test framework
- Provides clear failure reports

**Testing Approach**: Test the testing framework itself using property-based tests (metacircular)

---

### Spec 32: State Machine Testing Framework

**Module**: `tests/helpers/StateMachine.psm1`

**Purpose**: Define and test state machines for workflow validation.

**Key Functions**:
```powershell
function New-StateMachine {
    param(
        [scriptblock]$Definition
    )
    [StateMachine] # Returns state machine object
}

function Test-StateMachine {
    param(
        [StateMachine]$StateMachine,
        [int]$Sequences = 100,
        [int]$MaxCommands = 50
    )
    [TestResult[]]
}

function Invariant {
    param(
        [string]$Name,
        [scriptblock]$Check
    )
}
```

**State Machine Definition Syntax**:
```powershell
$StateMachine = New-StateMachine {
    States @('Initial', 'Downloaded', 'Extracted', 'Patched', 'Installed', 'Error')
    
    Transitions {
        From 'Initial' To 'Downloaded' When { Test-DownloadComplete }
        From 'Downloaded' To 'Extracted' When { Test-ExtractionComplete }
        From 'Extracted' To 'Patched' When { Test-PatchingComplete }
        From 'Patched' To 'Installed' When { Test-InstallationComplete }
        From Any To 'Error' When { Test-ErrorOccurred }
    }
    
    Invariants {
        'Package path valid' { $State.PackagePath | Test-Path }
        'No partial state' { $State.IsConsistent }
    }
    
    Commands {
        'Download' { Download-Package }
        'Extract' { Extract-Package }
        'Patch' { Apply-Patches }
        'Install' { Install-Package }
    }
}
```

**Behavior**:
1. Generate valid command sequences (respecting state transitions)
2. Execute commands in sequence
3. Verify invariants after each transition
4. Detect invalid states and transitions
5. Report any invariant violations

**Dependencies**: Spec 31 (uses property-based testing for sequence generation)

**Success Criteria**:
- Generates valid command sequences
- Detects invariant violations
- Reports state transition errors
- Supports parallel state machines

---

### Spec 33: Deterministic Simulation Testing Framework

**Module**: `tests/helpers/Simulation.psm1`

**Purpose**: Create deterministic simulations with mocked external dependencies.

**Key Functions**:
```powershell
function New-Simulation {
    param(
        [scriptblock]$Setup
    )
    [Simulation] # Returns simulation object
}

function Mock-Http {
    param(
        [hashtable]$Responses # URL -> Response mapping
    )
}

function Mock-FileSystem {
    param(
        [hashtable]$Structure # Path -> Content mapping
    )
}

function Freeze-Time {
    param([datetime]$Time)
}

function Advance-Time {
    param([TimeSpan]$Duration)
}
```

**Simulation Structure**:
```powershell
$sim = New-Simulation {
    Mock-Http {
        'https://cursor.com/install' => $InstallScript
        'https://downloads.cursor.com/...' => $PackageBytes
        'https://api.github.com/repos/.../releases/latest' => $GitHubReleaseJSON
    }
    
    Mock-FileSystem {
        TempDirectory => @{
            'package.tar.gz' => $PackageBytes
        }
        CacheDirectory => @{}
        InstallPath => @{}
    }
    
    Freeze-Time '2025-01-15 10:00:00'
    Set-Seed 42  # Deterministic randomness
}
```

**Behavior**:
1. Intercept all HTTP requests and return mocked responses
2. Intercept all file system operations and use in-memory structure
3. Control time (freeze, advance, rewind)
4. Provide deterministic random number generation
5. Allow snapshot/restore of simulation state
6. Verify final state matches expectations

**Dependencies**: None (foundation for DST)

**Success Criteria**:
- All external dependencies are mocked
- Simulations are fully deterministic
- State can be inspected and verified
- Supports complex scenarios with multiple dependencies

---

### Spec 34: Property Tests for Version Extraction

**File**: `tests/properties/version-extraction.tests.ps1`

**Purpose**: Property-based tests for version extraction functions (Specs 5-8).

**Properties to Test**:

1. **Version Format Preservation**:
   ```powershell
   Property "Extracted version matches input format" {
       param([string]$Version)
       $script = "DOWNLOAD_URL=`"https://downloads.cursor.com/lab/$Version/darwin/arm64/package.tar.gz`""
       $extracted = Get-CursorAgentVersion -InstallScript $script
       $extracted | Should -Be $Version
   } -ForAll (Gen-VersionString)
   ```

2. **Version Extraction Idempotency**:
   ```powershell
   Property "Version extraction is idempotent" {
       param([string]$Script)
       $v1 = Get-CursorAgentVersion -InstallScript $Script
       $v2 = Get-CursorAgentVersion -InstallScript $Script
       $v1 | Should -Be $v2
   } -ForAll (Gen-InstallScript)
   ```

3. **SQLite3 Version Extraction**:
   ```powershell
   Property "SQLite3 version extracted correctly" {
       param([string]$Version, [string]$PackageContent)
       $package = Create-TestPackage -Sqlite3Version $Version -Content $PackageContent
       $extracted = Get-Sqlite3Version -PackagePath $package
       $extracted | Should -Be $Version
   } -ForAll (Gen-SemanticVersion, Gen-PackageContent)
   ```

4. **Merkle Tree Version Extraction**:
   ```powershell
   Property "Merkle tree version extracted correctly" {
       param([string]$Version, [string]$PackageContent)
       $package = Create-TestPackage -MerkleTreeVersion $Version -Content $PackageContent
       $extracted = Get-MerkleTreeVersion -PackagePath $package
       $extracted | Should -Be $Version
   } -ForAll (Gen-SemanticVersion, Gen-PackageContent)
   ```

**Dependencies**: Spec 31, Specs 5-8

**Success Criteria**:
- All properties pass with 1000+ generated test cases
- Counterexamples are shrunk to minimal cases
- Tests cover edge cases (missing versions, malformed input, etc.)

---

### Spec 35: State Machine Tests for Patching Workflow

**File**: `tests/state-machines/patching-workflow.tests.ps1`

**Purpose**: State machine tests for main patching workflow (Spec 25).

**State Machine Definition**:
```powershell
$PatchingWorkflow = New-StateMachine {
    States @('Initial', 'ConfigLoaded', 'CacheInitialized', 'VersionDetected', 
             'PackageDownloaded', 'PackageExtracted', 'ContextBuilt', 
             'PatchesApplied', 'PackageInstalled', 'Error')
    
    Transitions {
        From 'Initial' To 'ConfigLoaded' When { Test-ConfigLoaded }
        From 'ConfigLoaded' To 'CacheInitialized' When { Test-CacheInitialized }
        From 'CacheInitialized' To 'VersionDetected' When { Test-VersionDetected }
        From 'VersionDetected' To 'PackageDownloaded' When { Test-PackageDownloaded }
        From 'PackageDownloaded' To 'PackageExtracted' When { Test-PackageExtracted }
        From 'PackageExtracted' To 'ContextBuilt' When { Test-ContextBuilt }
        From 'ContextBuilt' To 'PatchesApplied' When { Test-PatchesApplied }
        From 'PatchesApplied' To 'PackageInstalled' When { Test-PackageInstalled }
        From Any To 'Error' When { Test-ErrorOccurred }
    }
    
    Invariants {
        'Config always valid' { 
            $State.Config -ne $null -and $State.Config.IsValid 
        }
        'Cache directory exists' { 
            $State.CacheDirectory | Test-Path 
        }
        'Package path valid when downloaded' { 
            if ($State.CurrentState -ge 'PackageDownloaded') {
                $State.PackagePath | Test-Path
            }
        }
        'All patches applied before installation' {
            if ($State.CurrentState -ge 'PackageInstalled') {
                $State.PatchesApplied.Count -eq $State.PatchesExpected.Count
            }
        }
        'No partial installations' {
            if ($State.CurrentState -eq 'PackageInstalled') {
                $State.InstallPath | Test-Path
                (Get-ChildItem $State.InstallPath).Count -gt 0
            }
        }
    }
    
    Commands {
        'LoadConfig' { Get-PatcherConfig }
        'InitializeCache' { Initialize-CacheDirectory }
        'DetectVersion' { Get-CursorAgentVersion }
        'DownloadPackage' { Get-CursorAgentPackage }
        'ExtractPackage' { Expand-CursorAgentPackage }
        'BuildContext' { New-PatchContext }
        'ApplyPatches' { Invoke-Patch }
        'InstallPackage' { Copy-Item -Recurse }
    }
}
```

**Test Execution**:
```powershell
Describe "Patching Workflow State Machine" {
    It "Maintains invariants across all valid transitions" {
        $result = Test-StateMachine -StateMachine $PatchingWorkflow -Sequences 1000
        
        $result | Where-Object { $_.InvariantViolations.Count -gt 0 } | 
            Should -BeNullOrEmpty
    }
    
    It "Detects invalid state transitions" {
        # Force invalid transition
        $workflow.State.CurrentState = 'PackageDownloaded'
        { $workflow.Transition('ConfigLoaded') } | Should -Throw
    }
    
    It "Handles error states correctly" {
        # Simulate error at each state
        foreach ($state in $workflow.States) {
            $workflow.State.CurrentState = $state
            $workflow.Transition('Error')
            $workflow.State.CurrentState | Should -Be 'Error'
            $workflow.State.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

**Dependencies**: Spec 32, Spec 25

**Success Criteria**:
- Generates 1000+ valid command sequences
- All invariants hold across all sequences
- Invalid transitions are detected
- Error states are handled correctly

---

### Spec 36: Deterministic Simulation Tests for Full Workflow

**File**: `tests/simulations/full-workflow.tests.ps1`

**Purpose**: End-to-end deterministic simulation tests for complete patching workflow.

**Simulation Scenarios**:

1. **Happy Path**:
   ```powershell
   Simulation "Complete patching workflow succeeds" {
       Setup {
           $sim = New-Simulation {
               Mock-Http {
                   'https://cursor.com/install' => $ValidInstallScript
                   'https://downloads.cursor.com/lab/2025.08.15-dbc8d73/darwin/arm64/agent-cli-package.tar.gz' => $ValidPackage
                   'https://api.github.com/repos/btc-vision/rust-merkle-tree/releases/latest' => $MerkleTreeRelease
                   'https://api.github.com/repos/TryGhost/node-sqlite3/releases/tags/v5.1.7' => $Sqlite3Release
                   'https://api.github.com/repos/BurntSushi/ripgrep/releases/latest' => $RipGrepRelease
               }
               Mock-FileSystem {
                   TempDirectory => @{}
                   CacheDirectory => @{}
                   InstallPath => @{}
               }
               Freeze-Time '2025-01-15 10:00:00'
           }
       }
       
       Execute {
           Invoke-CursorAgentPatch -Version "2025.08.15-dbc8d73"
       }
       
       Verify {
           $sim.FileSystem['InstallPath\index.js'] | Should -Exist
           $sim.FileSystem['InstallPath\rg.exe'] | Should -Exist
           $sim.FileSystem['InstallPath\cursor-agent.bat'] | Should -Exist
           $sim.FileSystem['InstallPath\qfpzq242.node'] | Should -Exist
           $sim.FileSystem['InstallPath\kkkzjw1t.node'] | Should -Exist
           $sim.Cache['binaries'] | Should -HaveCount 3
           $sim.HttpRequests.Count | Should -Be 5
       }
   }
   ```

2. **Network Error Recovery**:
   ```powershell
   Simulation "Handles network errors gracefully" {
       Setup {
           $sim = New-Simulation {
               Mock-Http {
                   'https://cursor.com/install' => { throw "Network error" }
               }
           }
       }
       
       Execute {
           { Invoke-CursorAgentPatch } | Should -Throw
       }
       
       Verify {
           $sim.State.CurrentState | Should -Be 'Error'
           $sim.State.Error | Should -Match 'Network error'
       }
   }
   ```

3. **Version Mismatch Handling**:
   ```powershell
   Simulation "Handles version mismatches" {
       Setup {
           $sim = New-Simulation {
               Mock-Http {
                   'https://cursor.com/install' => $InstallScriptWithVersion
                   'https://downloads.cursor.com/lab/...' => $PackageWithDifferentVersion
               }
           }
       }
       
       Execute {
           Invoke-CursorAgentPatch -Version "2025.08.15-dbc8d73"
       }
       
       Verify {
           # Should either fail gracefully or use fallback versions
           if ($sim.State.CurrentState -eq 'Error') {
               $sim.State.Error | Should -Match 'version'
           } else {
               $sim.State.DependencyVersions | Should -Not -BeNullOrEmpty
           }
       }
   }
   ```

**Dependencies**: Spec 33, Spec 25

**Success Criteria**:
- All scenarios execute deterministically
- Final state matches expectations
- Error scenarios are handled correctly
- Simulations are reproducible (same seed = same results)

---

## Implementation Order

Recommended implementation order (dependencies first):

1. **Foundation** (Specs 1-3): Configuration and cache setup
2. **Version Detection** (Specs 4-8): Extract versions from various sources
3. **Download Infrastructure** (Specs 9-12): Download and caching system
4. **Patch System** (Specs 13-16): Registry and application framework
5. **Individual Patches** (Specs 17-21): Implement each patch type
6. **Workflow** (Specs 22-25): Main orchestration
7. **Utilities** (Specs 26-30): Helpers and main script
8. **Testing Infrastructure** (Specs 31-36): Property-based, state machine, and DST frameworks

**Note**: Testing infrastructure (Specs 31-33) should be implemented early and used to test other components as they're built. Property tests (Spec 34) and state machine tests (Spec 35) can be written in parallel with implementation. DST tests (Spec 36) should be written after the main workflow is complete.

Recommended implementation order (dependencies first):

1. **Foundation** (Specs 1-3): Configuration and cache setup
2. **Version Detection** (Specs 4-8): Extract versions from various sources
3. **Download Infrastructure** (Specs 9-12): Download and caching system
4. **Patch System** (Specs 13-16): Registry and application framework
5. **Individual Patches** (Specs 17-21): Implement each patch type
6. **Workflow** (Specs 22-25): Main orchestration
7. **Utilities** (Specs 26-30): Helpers and main script

Each spec can be implemented and tested independently before integration.
