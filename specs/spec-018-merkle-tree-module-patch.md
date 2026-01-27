# Spec 18: Merkle Tree Module Replacement Patch

**Patch ID**: `merkle-tree-module`

**Purpose**: Replace merkle-tree native module file with Windows version.

**File Pattern**: `**/qfpzq242.node` (or any `.node` file referenced by merkle-tree loader)

**Priority**: 2

**Dependencies**: `platform-detection`

**Apply Logic**:
1. Get Windows merkle-tree binary from `$Context.WindowsBinaries['merkleTree']`
2. If binary path not in context, throw error
3. Copy Windows binary over existing `.node` file
4. Preserve file permissions if possible

**Verify Logic**:
- Check file exists
- Check file size > 0
- Optionally: verify file is valid `.node` module (check magic bytes)

**Dependencies**: Spec 16, Spec 10, Spec 11, Spec 12

**Success Criteria**:
- Replaces module file with Windows version
- Verification confirms file is valid
- Handles missing binary gracefully
