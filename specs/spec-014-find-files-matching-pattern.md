# Spec 14: Find Files Matching Pattern Function

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
