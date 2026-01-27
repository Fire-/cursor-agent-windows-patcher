# Spec 37: Intercept Update Command

**Function**: `Invoke-CursorAgentUpdateWithPatch`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Intercept `cursor-agent update` commands, execute the real update, then automatically patch the newly updated version.

**Signature**:
```powershell
function Invoke-CursorAgentUpdateWithPatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$UpdateArguments, # Additional arguments to pass to cursor-agent update
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force # Force re-patch even if already patched
    )
    [hashtable] # Returns result summary
}
```

**Behavior**:
1. Find the real cursor-agent executable/script
   - Check for `cursor-agent` or `agent` in PATH
   - Resolve to actual executable (may be wrapper, need to find real one)
2. Execute `cursor-agent update` (or `agent update`) with provided arguments
3. Capture exit code
4. If exit code is 0 (success):
   - Wait briefly for symlink update to complete (100-500ms)
   - Detect new version directory (Spec 038)
   - Check if already patched (Spec 039)
   - If not patched (or `-Force`), patch the new version (Spec 25 with `-PatchExistingInstallation`)
   - Return combined result of update + patch
5. If exit code is non-zero:
   - Return error result (don't attempt patching)
   - Preserve original error message

**Error Handling**:
- Cannot find cursor-agent executable → Throw with helpful message
- Update command fails → Return error, don't patch
- Version detection fails → Log warning, return partial success
- Patching fails → Return error with both update and patch status

**Dependencies**: Spec 25, Spec 38, Spec 39

**Success Criteria**:
- Successfully intercepts and executes update command
- Detects new version after update
- Automatically patches new version
- Returns detailed results including both update and patch status
- Handles errors gracefully without breaking update process

**Integration with Launcher**:

This function is called by the launcher wrapper (Spec 26) when `update` or `upgrade` subcommand is detected. The launcher script structure:

```powershell
# In cursor-agent.bat wrapper
if ($args[0] -eq "update" -or $args[0] -eq "upgrade") {
    # Import patcher module
    Import-Module $PSScriptRoot\CursorAgentPatcher.psm1
    
    # Call update with patch
    $result = Invoke-CursorAgentUpdateWithPatch -UpdateArguments $args[1..($args.Length-1)]
    
    if ($result.UpdateSuccess) {
        if ($result.PatchSuccess) {
            Write-Host "Update and patch completed successfully!" -ForegroundColor Green
        } else {
            Write-Warning "Update succeeded but patching failed. Run patch manually."
            exit 1
        }
    } else {
        Write-Error "Update failed: $($result.UpdateError)"
        exit $result.UpdateExitCode
    }
} else {
    # Pass through to real cursor-agent
    & $realCursorAgentPath @args
    exit $LASTEXITCODE
}
```

**Return Value Structure**:
```powershell
@{
    UpdateSuccess = $true or $false
    UpdateExitCode = 0 or non-zero
    UpdateError = "Error message if failed"
    PatchSuccess = $true or $false
    PatchResult = @{ ... } # Result from Invoke-PatchExistingInstallation
    VersionDirectory = "Path to version directory"
    AlreadyPatched = $true or $false
}
```
