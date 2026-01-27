# Spec 6: Extract SQLite3 Version from Package

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
