# Spec 16: Apply Patch Function

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
