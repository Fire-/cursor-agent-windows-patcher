# Spec 9: Download File with Progress Function

**Function**: `Get-FileWithProgress`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Download file from URL with progress indication and error handling.

**Signature**:
```powershell
function Get-FileWithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowProgress
    )
    [void]
}
```

**Behavior**:
1. Use `Invoke-WebRequest` with `-OutFile` parameter
2. If `$ShowProgress`, use `Write-Progress` to show download status
3. Handle redirects automatically
4. Verify file exists and has non-zero size after download

**Error Handling**:
- Network error → Throw with URL and error
- HTTP error → Throw with status code
- Write error → Throw with path and error
- Zero-size file → Throw indicating download may have failed

**Dependencies**: None

**Success Criteria**:
- Downloads file successfully
- Shows progress when requested
- Validates downloaded file
- Provides clear error messages
