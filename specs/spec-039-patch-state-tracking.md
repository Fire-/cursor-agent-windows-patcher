# Spec 39: Patch State Tracking

**Functions**: 
- `Write-PatchStateMarker`
- `Read-PatchStateMarker`
- `Test-InstallationPatched`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Track whether a cursor-agent installation has been patched and which patches were applied, using a JSON marker file.

**Marker File Location**: `.cursor-agent-patched` in the installation directory root

**Marker File Structure**:
```json
{
  "cursorAgentVersion": "2026.01.23-916f423",
  "patchTimestamp": "2026-01-27T10:30:00Z",
  "patcherVersion": "1.0.0",
  "appliedPatches": [
    "platform-detection",
    "merkle-tree-module",
    "sqlite3-module",
    "ripgrep-binary"
  ],
  "patchResults": {
    "platform-detection": {
      "success": true,
      "filesModified": ["node_modules/merkle-tree/native.js"],
      "errors": []
    },
    "merkle-tree-module": {
      "success": true,
      "filesModified": ["node_modules/merkle-tree/qfpzq242.node"],
      "errors": []
    },
    "sqlite3-module": {
      "success": true,
      "filesModified": ["node_modules/sqlite3/kkkzjw1t.node"],
      "errors": []
    },
    "ripgrep-binary": {
      "success": true,
      "filesModified": ["node_modules/.bin/rg.exe"],
      "errors": []
    }
  },
  "dependencyVersions": {
    "sqlite3": "5.1.7",
    "merkleTree": "1.2.3",
    "ripgrep": "13.0.0"
  },
  "patchHash": "sha256:abc123def456..."
}
```

## Function 1: Write-PatchStateMarker

**Signature**:
```powershell
function Write-PatchStateMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath,
        
        [Parameter(Mandatory=$true)]
        [string]$CursorAgentVersion,
        
        [Parameter(Mandatory=$true)]
        [string[]]$AppliedPatches,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$PatchResults,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$DependencyVersions,
        
        [Parameter(Mandatory=$false)]
        [string]$PatcherVersion = "1.0.0",
        
        [Parameter(Mandatory=$false)]
        [string]$PatchHash
    )
    [void]
}
```

**Behavior**:
1. Build marker file structure with all provided data
2. Set `patchTimestamp` to current UTC time (ISO 8601 format)
3. Calculate `patchHash` if not provided:
   - Hash of patch configuration (patch IDs, dependency versions, patcher version)
   - Used to detect if patch configuration changed
4. Write JSON to `.cursor-agent-patched` in `$InstallationPath`
5. Validate JSON is valid before writing

**Error Handling**:
- Installation path invalid → Throw
- JSON serialization fails → Throw with error details
- File write fails → Throw with path and error

## Function 2: Read-PatchStateMarker

**Signature**:
```powershell
function Read-PatchStateMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath
    )
    [hashtable] # Returns marker data or $null if not found
}
```

**Behavior**:
1. Check if `.cursor-agent-patched` exists in `$InstallationPath`
2. If not found, return `$null`
3. Read and parse JSON file
4. Validate structure (check required fields)
5. Return hashtable with marker data

**Error Handling**:
- File not found → Return `$null` (not an error)
- Invalid JSON → Return `$null` and log warning
- Missing required fields → Return `$null` and log warning

## Function 3: Test-InstallationPatched

**Signature**:
```powershell
function Test-InstallationPatched {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath,
        
        [Parameter(Mandatory=$false)]
        [string[]]$RequiredPatches = @(
            "platform-detection",
            "merkle-tree-module",
            "sqlite3-module",
            "ripgrep-binary"
        ),
        
        [Parameter(Mandatory=$false)]
        [switch]$VerifyFiles # Also verify files exist and are correct
    )
    [hashtable] # Returns: {IsPatched, MissingPatches, MarkerData, VerificationResults}
}
```

**Behavior**:

1. **Marker File Check** (Fast):
   - Read marker file using `Read-PatchStateMarker`
   - If marker not found → Return `IsPatched = $false`
   - Check if all `$RequiredPatches` are in `appliedPatches` array
   - If any missing → Return `IsPatched = $false`, `MissingPatches = [...]`

2. **File Verification** (if `-VerifyFiles` specified):
   - Check platform detection patch is present in code
     - Search for `platform3 === "win32"` in `native.js` files
   - Check Windows binaries exist:
     - Merkle tree `.node` file exists and has reasonable size
     - SQLite3 `.node` file exists and has reasonable size
     - RipGrep `.exe` exists
   - Verify binary file hashes match expected (optional, slow)

3. **Return Result**:
   ```powershell
   @{
       IsPatched = $true or $false
       MissingPatches = @("patch-id") # Patches in RequiredPatches but not in appliedPatches
       MarkerData = @{ ... } # Full marker data or $null
       VerificationResults = @{
           PlatformDetectionPresent = $true or $false
           MerkleTreeBinaryExists = $true or $false
           Sqlite3BinaryExists = $true or $false
           RipGrepBinaryExists = $true or $false
       } # Only if -VerifyFiles
   }
   ```

**Error Handling**:
- Installation path invalid → Throw
- File verification errors → Log warnings, continue with other checks
- Return partial results if some checks fail

**Dependencies**: Spec 14 (Find-FilesMatchingPattern for file verification)

**Success Criteria**:
- Successfully writes marker file with all patch information
- Reads marker file correctly
- Detects if installation is patched
- Identifies missing patches
- Optionally verifies files exist
- Handles missing or invalid marker files gracefully

**Usage Examples**:

```powershell
# After patching, write marker
Write-PatchStateMarker `
    -InstallationPath "C:\path\to\version" `
    -CursorAgentVersion "2026.01.23-916f423" `
    -AppliedPatches @("platform-detection", "merkle-tree-module", "sqlite3-module", "ripgrep-binary") `
    -PatchResults $patchResults `
    -DependencyVersions @{sqlite3="5.1.7"; merkleTree="1.2.3"; ripgrep="13.0.0"}

# Check if patched
$result = Test-InstallationPatched -InstallationPath "C:\path\to\version"
if (-not $result.IsPatched) {
    # Need to patch
    Write-Host "Missing patches: $($result.MissingPatches -join ', ')"
}

# Check with file verification
$result = Test-InstallationPatched -InstallationPath "C:\path\to\version" -VerifyFiles
if ($result.VerificationResults.MerkleTreeBinaryExists) {
    Write-Host "Merkle tree binary is present"
}
```

**Integration with Patching Workflow**:

1. **Before Patching** (Spec 25):
   - Call `Test-InstallationPatched` to check if already patched
   - If patched and not `-Force`, skip patching
   - If not patched or `-Force`, proceed with patching

2. **After Patching** (Spec 25):
   - Collect patch results from all applied patches
   - Call `Write-PatchStateMarker` with results
   - Include all applied patch IDs, files modified, dependency versions

3. **After Update** (Spec 37):
   - Call `Test-InstallationPatched` on new version directory
   - If not patched, trigger patching
   - If patched, verify all required patches are present
