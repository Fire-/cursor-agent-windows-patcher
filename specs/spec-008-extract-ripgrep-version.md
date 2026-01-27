# Spec 8: Extract RipGrep Version from Package

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
