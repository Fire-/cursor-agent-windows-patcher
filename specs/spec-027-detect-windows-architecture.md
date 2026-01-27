# Spec 27: Detect Windows Architecture Function

**Function**: `Get-WindowsArchitecture`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Detect Windows system architecture (x64 or arm64).

**Signature**:
```powershell
function Get-WindowsArchitecture {
    [CmdletBinding()]
    param()
    [string] # Returns "x64" or "arm64"
}
```

**Behavior**:
1. Check `$env:PROCESSOR_ARCHITECTURE` environment variable
2. Map values:
   - `AMD64` → `x64`
   - `ARM64` → `arm64`
3. Fallback: Use `[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture`
4. Default to `x64` if detection fails

**Dependencies**: None

**Success Criteria**:
- Correctly detects x64 and arm64
- Has fallback methods
- Never throws (always returns a value)
