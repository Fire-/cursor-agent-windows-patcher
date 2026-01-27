# Spec 21: Register All Patches Function

**Function**: `Register-StandardPatches`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Initialize patch registry with all standard patches.

**Signature**:
```powershell
function Register-StandardPatches {
    [CmdletBinding()]
    param()
    [void]
}
```

**Behavior**:
1. Define all standard patches (Specs 17-20) in registry
2. Store in `$script:PatchRegistry`
3. Validate registry structure after registration

**Dependencies**: Spec 13, Spec 17, Spec 18, Spec 19, Spec 20

**Success Criteria**:
- All standard patches registered
- Registry structure is valid
- Dependencies are correctly defined
