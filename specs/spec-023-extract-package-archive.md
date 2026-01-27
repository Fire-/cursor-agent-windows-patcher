# Spec 23: Extract Package Archive Function

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
