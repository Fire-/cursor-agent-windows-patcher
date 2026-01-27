# Spec 11: Get Cached Binary Function

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
