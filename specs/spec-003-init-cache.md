# Spec 3: Initialize Cache Directory Function

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
