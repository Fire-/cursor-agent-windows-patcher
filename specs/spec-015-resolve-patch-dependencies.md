# Spec 15: Resolve Patch Dependencies Function

**Function**: `Resolve-PatchDependencies`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Sort patches by priority and dependencies to determine execution order.

**Signature**:
```powershell
function Resolve-PatchDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PatchRegistry
    )
    [array] # Returns ordered array of patch IDs
}
```

**Behavior**:
1. Build dependency graph from registry
2. Detect circular dependencies (throw if found)
3. Sort by priority (lower first)
4. Within same priority, ensure dependencies run first (topological sort)
5. Return ordered array of patch IDs

**Error Handling**:
- Circular dependency → Throw with cycle details
- Missing dependency → Throw with patch ID and missing dependency

**Dependencies**: Spec 13

**Success Criteria**:
- Returns patches in correct execution order
- Detects and reports circular dependencies
- Handles patches with no dependencies
