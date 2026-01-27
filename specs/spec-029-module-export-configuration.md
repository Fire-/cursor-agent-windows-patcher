# Spec 29: Module Export Configuration

**File**: `CursorAgentPatcher.psm1`

**Purpose**: Export public functions, keep internal functions private.

**Exports**:
- `Get-PatcherConfig`
- `Get-CursorAgentVersion`
- `Invoke-CursorAgentPatch`
- `New-CursorAgentLauncher`
- `Get-WindowsArchitecture`

**Internal Functions** (not exported):
- All helper functions (Specs 6-12, 14-16, 22-24)
- Patch registry accessors
- Cache management functions

**Dependencies**: All function specs

**Success Criteria**:
- Only public API functions are exported
- Internal functions are accessible within module
- Module loads without errors
