# Spec 17: Platform Detection Patch

**Patch ID**: `platform-detection`

**Purpose**: Modify `native.js` to support Windows platform by adding win32 branch.

**File Pattern**: `**/native.js`

**Priority**: 1 (must run first)

**Dependencies**: None

**Apply Logic**:
1. Read file content
2. Detect available loaders by searching for `require_merkle_tree_napi_*` patterns
3. Select best loader:
   - If Windows x64 and darwin-x64 available → use darwin-x64
   - Else if darwin-arm64 available → use darwin-arm64
   - Else use first available loader
4. Find pattern: `} else {\s+throw new Error(\`Unsupported platform: \$\{platform3\}\`);`
5. Replace with:
   ```javascript
   } else if (platform3 === "win32") {
       nativeBinding = require_merkle_tree_napi_{selectedLoader}();
   } else {
       throw new Error(`Unsupported platform: ${platform3}`);
   }
   ```
6. Write patched content back

**Verify Logic**:
- Check file contains `platform3 === "win32"`
- Check file contains `require_merkle_tree_napi_` (any variant)

**Dependencies**: Spec 16

**Success Criteria**:
- Adds Windows platform support
- Selects appropriate loader based on available options
- Verification confirms patch was applied
