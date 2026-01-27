# Spec 22: Download Cursor Agent Package Function

**Function**: `Get-CursorAgentPackage`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Download Cursor Agent package for specified version and architecture.

**Signature**:
```powershell
function Get-CursorAgentPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version,
        
        [Parameter(Mandatory=$false)]
        [string]$SourceOs = "darwin",
        
        [Parameter(Mandatory=$false)]
        [string]$SourceArch = "arm64",
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath
    )
    [string] # Returns path to downloaded package
}
```

**Behavior**:
1. Construct URL: `https://downloads.cursor.com/lab/$Version/$SourceOs/$SourceArch/agent-cli-package.tar.gz`
2. Download using `Get-FileWithProgress`
3. Verify file exists and has reasonable size (> 1MB)
4. Return path to downloaded file

**Error Handling**:
- Invalid URL → Throw
- Download fails → Propagate error
- File too small → Throw indicating possible corruption

**Dependencies**: Spec 9

**Success Criteria**:
- Downloads package successfully
- Validates download size
- Returns path to package file
