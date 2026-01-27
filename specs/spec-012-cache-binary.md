# Spec 12: Cache Binary Function

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
