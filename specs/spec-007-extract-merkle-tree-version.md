# Spec 7: Extract Merkle Tree Version from Package

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
