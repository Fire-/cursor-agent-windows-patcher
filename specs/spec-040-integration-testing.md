# Spec 40: Integration Testing - End-to-End Test with Real Cursor Agent Package

**File**: `tests/integration/end-to-end-patching.tests.ps1`

**Purpose**: Create comprehensive integration tests that exercise the complete patching workflow with a real Cursor Agent package downloaded from the official source.

## Test Scenarios

### Scenario 1: Happy Path - Complete Patching Workflow
**Description**: Test the full workflow from download to installation with a real package.

**Steps**:
1. Download actual Cursor Agent package from official source
2. Extract package archive
3. Build patch context with real dependency versions
4. Apply all patches (platform detection, merkle-tree, sqlite3, ripgrep)
5. Verify patches were applied correctly
6. Install patched package to test directory
7. Create launcher script
8. Verify installation structure
9. Execute launcher script to verify it works
10. Clean up test artifacts

**Verification Points**:
- Package downloads successfully
- Archive extracts correctly
- All patches apply without errors
- Patched files exist and are valid
- Installation directory structure is correct
- Launcher script executes without errors
- Cursor Agent can start (even if it fails later due to missing dependencies)

### Scenario 2: Cached Binary Reuse
**Description**: Verify that cached binaries are reused on subsequent runs.

**Steps**:
1. Run complete patching workflow (downloads binaries)
2. Clear package cache but keep binary cache
3. Run patching workflow again with different version
4. Verify binaries are retrieved from cache
5. Verify cache hit is logged/indicated

**Verification Points**:
- Binaries are retrieved from cache
- No redundant downloads occur
- Cache validation works correctly
- Cache keys are correct

### Scenario 3: Partial Failure Recovery
**Description**: Test error handling when some steps fail.

**Steps**:
1. Simulate network failure during package download
2. Verify graceful error handling
3. Simulate extraction failure
4. Verify cleanup of partial artifacts
5. Simulate patch application failure
6. Verify rollback or error reporting

**Verification Points**:
- Errors are caught and reported clearly
- Partial artifacts are cleaned up
- Error messages are actionable
- System can recover and retry

### Scenario 4: Version Detection and Extraction
**Description**: Verify version extraction works with real install script.

**Steps**:
1. Fetch real install script from cursor.com
2. Extract version string
3. Verify version format is correct
4. Use extracted version to download package
5. Verify package matches version

**Verification Points**:
- Version extraction succeeds
- Version format is valid (YYYY.MM.DD-hash)
- Package download uses correct version
- Package version matches extracted version

### Scenario 5: Multi-Architecture Support
**Description**: Test patching for both x64 and arm64 Windows architectures.

**Steps**:
1. Detect current architecture
2. Download appropriate Windows binaries for architecture
3. Apply patches
4. Verify architecture-specific binaries are used
5. Test on both architectures if possible

**Verification Points**:
- Architecture detection is correct
- Correct binaries are downloaded
- Patches use architecture-appropriate binaries
- Installation works on target architecture

## Test Infrastructure Requirements

**Test Environment**:
- Isolated test directory for each test run
- Clean cache state (or ability to reset)
- Network access for downloads
- Sufficient disk space for packages and binaries
- PowerShell 5.1+ with required modules

**Test Data**:
- Real Cursor Agent install script URL
- Real package download URLs
- Real GitHub release URLs for dependencies
- Test installation paths

**Cleanup**:
- Remove test directories after each test
- Clear test cache entries
- Remove downloaded packages
- Remove extracted archives

## Implementation Details

**Test File Structure**:
```powershell
Describe "End-to-End Patching Integration Tests" {
    BeforeAll {
        $script:testBaseDir = Join-Path $env:TEMP "cursor-agent-integration-test-$(Get-Random)"
        $script:testInstallDir = Join-Path $script:testBaseDir "install"
        $script:testCacheDir = Join-Path $script:testBaseDir "cache"
        # Setup test environment
    }
    
    AfterAll {
        # Cleanup test artifacts
        Remove-Item -Path $script:testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    It "Completes full patching workflow with real package" {
        # Test implementation
    }
    
    # Additional test cases...
}
```

**Key Functions to Test**:
- `Get-CursorAgentInstallScript` - Real network call
- `Get-CursorAgentVersion` - Real script parsing
- `Get-CursorAgentPackage` - Real download
- `Expand-CursorAgentPackage` - Real extraction
- `New-PatchContext` - Real version extraction and binary downloads
- `Invoke-CursorAgentPatch` - Complete workflow
- `New-CursorAgentLauncher` - Launcher creation
- `Get-CachedBinary` - Cache retrieval
- `Save-BinaryToCache` - Cache storage

**Error Scenarios to Test**:
- Network timeouts
- Invalid package versions
- Corrupted archives
- Missing dependencies
- Permission errors
- Disk space exhaustion
- Invalid cache entries

## Success Criteria

1. **All test scenarios pass** with real packages
2. **No hardcoded test data** - uses real URLs and versions
3. **Clean test isolation** - each test is independent
4. **Comprehensive coverage** - tests all major code paths
5. **Clear failure reporting** - failures are easy to diagnose
6. **Reasonable execution time** - tests complete in < 5 minutes
7. **Proper cleanup** - no leftover test artifacts

## Dependencies

- Spec 004: Fetch Cursor Agent Install Script
- Spec 005: Extract Cursor Agent Version
- Spec 022: Download Cursor Agent Package
- Spec 023: Extract Package Archive
- Spec 024: Build Patch Context
- Spec 025: Main Patching Workflow
- Spec 011: Get Cached Binary
- Spec 012: Cache Binary

## Notes

- Integration tests require network access and may be slower
- Consider using test markers to skip integration tests in CI if needed
- May need to handle rate limiting for GitHub API calls
- Should test with latest stable version and at least one older version
- Consider testing update interception workflow (Spec 037)
