# Spec 25: Main Patching Workflow Function

**Function**: `Invoke-CursorAgentPatch`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Orchestrate complete patching workflow from download to installation.

**Signature**:
```powershell
function Invoke-CursorAgentPatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Version, # Override version, or auto-detect if not provided
        
        [Parameter(Mandatory=$false)]
        [string]$InstallPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf,
        
        [Parameter(Mandatory=$false)]
        [switch]$Verbose,
        
        [Parameter(Mandatory=$false)]
        [string]$PatchExistingInstallation, # Path to already-extracted installation (skip download/extract)
        
        [Parameter(Mandatory=$false)]
        [switch]$Force # Re-patch even if already patched
    )
    [hashtable] # Returns result summary
}
```

**Behavior**:

**Standard Mode** (when `-PatchExistingInstallation` is not provided):
1. Load configuration (Spec 2)
2. Initialize cache (Spec 3)
3. Get Cursor Agent version (Specs 4-5, or use provided)
4. Download package (Spec 22)
5. Extract package (Spec 23)
6. Build patch context (Spec 24)
7. Resolve patch order (Spec 15)
8. Apply all patches (Spec 16) in order
9. Copy patched package to install path
10. Create launcher script (Spec 26)
11. Write patch state marker (Spec 039)
12. Return summary with success status and details

**In-Place Patching Mode** (when `-PatchExistingInstallation` is provided):
1. Load configuration (Spec 2)
2. Initialize cache (Spec 3)
3. Validate installation path exists and contains `index.js`
4. Check if already patched (Spec 039) - skip if patched and `-Force` not specified
5. Extract cursor-agent version from installation (read package.json or similar)
6. Build patch context (Spec 24) using existing installation path
7. Resolve patch order (Spec 15)
8. Apply all patches (Spec 16) in order to existing files
9. Write patch state marker (Spec 039)
10. Return summary with success status and details

**New Function**: `Invoke-PatchExistingInstallation`
```powershell
function Invoke-PatchExistingInstallation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath, # Path to already-extracted cursor-agent
        
        [Parameter(Mandatory=$false)]
        [switch]$Force # Re-patch even if already patched
    )
    [hashtable] # Returns result summary
}
```

This function is a convenience wrapper that calls `Invoke-CursorAgentPatch` with `-PatchExistingInstallation $InstallationPath`.

**Error Handling**:
- Fail fast on any critical error
- Provide clear error messages at each step
- Clean up temp files on failure (optional)

**Dependencies**: All previous specs, Spec 039 (patch state tracking)

**Success Criteria**:
- Completes full workflow successfully in both modes
- Supports `-WhatIf` mode
- Skips patching if already patched (unless `-Force`)
- Provides detailed progress and results
- Handles errors gracefully
- Writes patch state marker after successful patching

**Testing**:
- State machine: Workflow state transitions and invariants (Spec 35)
- DST: End-to-end scenarios (Spec 36)
- Property-based: Workflow idempotency
- Unit tests: Error handling edge cases
