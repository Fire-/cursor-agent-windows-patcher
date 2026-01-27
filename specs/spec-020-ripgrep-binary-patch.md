# Spec 20: RipGrep Binary Replacement Patch

**Patch ID**: `ripgrep-binary`

**Purpose**: Replace `rg` binary with Windows `rg.exe`.

**File Pattern**: `**/rg` (exact filename, no extension)

**Priority**: 2

**Dependencies**: None

**Apply Logic**:
1. Get ripgrep zip from `$Context.WindowsBinaries['ripgrep']`
2. Extract `rg.exe` from zip (may be in subdirectory like `ripgrep-13.0.0-x86_64-pc-windows-msvc/`)
3. Copy `rg.exe` to location of `rg` file
4. Delete original `rg` file
5. Rename `rg.exe` to `rg.exe` (keep .exe extension)

**Verify Logic**:
- Check `rg.exe` exists
- Check file size > 0
- Optionally: try to execute `rg.exe --version` to verify it's valid

**Dependencies**: Spec 16, Spec 10, Spec 11, Spec 12

**Success Criteria**:
- Replaces binary with Windows executable
- Handles zip extraction correctly
- Verification confirms executable is valid
