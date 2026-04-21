# Spec 43: User Acceptance Testing - Manual Testing of Full Workflow

**Purpose**: Create comprehensive manual testing procedures to validate the complete user experience and ensure the tool works as expected in real-world scenarios.

## Test Environment Setup

### Prerequisites
- [ ] Clean Windows system (or VM)
- [ ] PowerShell 5.1 or later
- [ ] Node.js installed
- [ ] 7-Zip installed (optional but recommended)
- [ ] Internet connection
- [ ] Sufficient disk space (at least 500MB free)
- [ ] Administrator privileges (for some operations)

### Test Data Preparation
- [ ] Fresh clone of repository
- [ ] Default `patcher-config.json` (unmodified)
- [ ] Clean cache directory (or note existing cache state)
- [ ] Test installation directory path
- [ ] Note current Cursor Agent installation (if any)

## Test Scenarios

### Scenario 1: First-Time Installation (Happy Path)

**Objective**: Verify complete installation workflow for new user.

**Steps**:
1. Open PowerShell in project directory
2. Review `patcher-config.json` (verify default settings)
3. Run: `.\patch-cursor-agent.ps1`
4. Observe output and progress indicators
5. Wait for completion
6. Verify installation directory structure
7. Test launcher script execution
8. Verify Cursor Agent can start

**Expected Results**:
- [ ] Script executes without errors
- [ ] Progress indicators show download/extraction progress
- [ ] Installation directory created with correct structure
- [ ] Launcher script exists and is executable
- [ ] Cursor Agent starts (may fail later due to missing Node.js, but should get past initial load)
- [ ] Cache directory contains downloaded binaries
- [ ] Patch state marker file exists

**Success Criteria**: Complete installation succeeds, all files in place, launcher works.

### Scenario 2: Specific Version Installation

**Objective**: Verify installation of specific Cursor Agent version.

**Steps**:
1. Get available version: Check cursor.com or use `Get-CursorAgentVersion`
2. Run: `.\patch-cursor-agent.ps1 -Version "YYYY.MM.DD-hash"`
3. Verify correct version is downloaded
4. Verify patches are applied
5. Verify installation contains correct version

**Expected Results**:
- [ ] Specified version is downloaded (not latest)
- [ ] Version matches requested version
- [ ] Installation directory reflects correct version
- [ ] Patch state marker contains correct version

**Success Criteria**: Correct version is installed and patched.

### Scenario 3: Custom Installation Path

**Objective**: Verify installation to custom location.

**Steps**:
1. Choose custom path: `C:\Tools\cursor-agent-test`
2. Run: `.\patch-cursor-agent.ps1 -InstallPath "C:\Tools\cursor-agent-test"`
3. Verify installation at custom path
4. Verify launcher script location
5. Test launcher from custom path

**Expected Results**:
- [ ] Installation created at specified path
- [ ] Launcher script created at specified path
- [ ] Path can be absolute or relative
- [ ] Launcher works from custom location

**Success Criteria**: Custom path installation works correctly.

### Scenario 4: In-Place Patching

**Objective**: Verify patching of existing Cursor Agent installation.

**Prerequisites**: Existing Cursor Agent installation (from official installer or previous test)

**Steps**:
1. Locate existing installation: `C:\Users\...\cursor-agent\...`
2. Verify installation is not already patched
3. Run: `.\patch-cursor-agent.ps1 -PatchExistingInstallation -InstallPath "C:\path\to\existing"`
4. Observe patch application
5. Verify patches were applied
6. Test launcher script

**Expected Results**:
- [ ] Existing files are patched in-place
- [ ] No duplicate installation created
- [ ] Patches are applied correctly
- [ ] Launcher script created/updated
- [ ] Original files backed up (if applicable)

**Success Criteria**: Existing installation is successfully patched.

### Scenario 5: Update Interception

**Objective**: Verify automatic patching after cursor-agent update.

**Prerequisites**: Cursor Agent installed and launcher with update interception enabled

**Steps**:
1. Install Cursor Agent with update interception launcher
2. Run: `cursor-agent update` (or equivalent)
3. Observe update process
4. Verify new version is detected
5. Verify automatic patching occurs
6. Verify patched version is active

**Expected Results**:
- [ ] Update command is intercepted
- [ ] New version is downloaded by cursor-agent
- [ ] New version directory is detected
- [ ] Automatic patching is triggered
- [ ] Patched version becomes active
- [ ] User is notified of patching

**Success Criteria**: Update interception works, new versions are automatically patched.

### Scenario 6: Dry Run (What-If Mode)

**Objective**: Verify preview mode shows what would happen without making changes.

**Steps**:
1. Run: `.\patch-cursor-agent.ps1 -WhatIf -Verbose`
2. Review output
3. Verify no actual changes are made
4. Compare with actual run output

**Expected Results**:
- [ ] All operations are previewed
- [ ] No files are created/modified
- [ ] Output clearly indicates "What-If" mode
- [ ] Output matches actual operations when run for real

**Success Criteria**: What-If mode accurately previews operations without side effects.

### Scenario 7: Cache Functionality

**Objective**: Verify binary caching works correctly.

**Steps**:
1. First run: `.\patch-cursor-agent.ps1` (downloads binaries)
2. Note cache location and contents
3. Second run: `.\patch-cursor-agent.ps1 -Version "same-version"`
4. Verify binaries are retrieved from cache
5. Verify no redundant downloads
6. Test cache validation (corrupt a cache entry, verify it's re-downloaded)

**Expected Results**:
- [ ] Binaries are cached after first download
- [ ] Subsequent runs use cached binaries
- [ ] Cache hit is indicated in output
- [ ] Corrupted cache entries are detected and re-downloaded
- [ ] Cache location is correct

**Success Criteria**: Caching reduces download time, corrupted cache is handled.

### Scenario 8: Error Handling - Network Failure

**Objective**: Verify graceful handling of network errors.

**Steps**:
1. Disconnect network (or block cursor.com)
2. Run: `.\patch-cursor-agent.ps1`
3. Observe error handling
4. Reconnect network
5. Verify retry works (if implemented)
6. Verify cleanup of partial downloads

**Expected Results**:
- [ ] Clear error message about network failure
- [ ] No corrupted partial files left
- [ ] System can retry after network restored
- [ ] Error message is actionable

**Success Criteria**: Network errors are handled gracefully, user can recover.

### Scenario 9: Error Handling - Invalid Version

**Objective**: Verify handling of invalid version specification.

**Steps**:
1. Run: `.\patch-cursor-agent.ps1 -Version "invalid-version"`
2. Observe error handling
3. Verify helpful error message
4. Try with valid version format but non-existent version

**Expected Results**:
- [ ] Clear error message about invalid version
- [ ] Error message suggests valid format
- [ ] System doesn't crash or leave partial state

**Success Criteria**: Invalid versions are rejected with helpful messages.

### Scenario 10: Error Handling - Permission Issues

**Objective**: Verify handling of permission errors.

**Steps**:
1. Create read-only directory
2. Try to install to read-only location
3. Observe error handling
4. Test with insufficient permissions for cache directory
5. Test with file locked (Cursor Agent running)

**Expected Results**:
- [ ] Clear error messages about permissions
- [ ] Suggestions for resolution (run as admin, close processes)
- [ ] No partial installations left

**Success Criteria**: Permission errors are clearly communicated.

### Scenario 11: Multiple Architecture Support

**Objective**: Verify correct binaries for system architecture.

**Steps**:
1. Check system architecture (x64 or arm64)
2. Run installation
3. Verify correct architecture binaries are downloaded
4. Verify patches use correct binaries
5. Test on different architecture if available

**Expected Results**:
- [ ] Architecture is detected correctly
- [ ] Correct binaries are downloaded
- [ ] Patches use architecture-appropriate binaries
- [ ] Installation works on target architecture

**Success Criteria**: Architecture detection and binary selection work correctly.

### Scenario 12: Configuration Customization

**Objective**: Verify custom configuration works.

**Steps**:
1. Modify `patcher-config.json`:
   - Change cache directory
   - Change default installation path
   - Add custom version mapping
2. Run installation
3. Verify custom settings are used
4. Verify custom cache location
5. Verify custom installation path

**Expected Results**:
- [ ] Custom configuration is loaded
- [ ] Custom settings are applied
- [ ] Custom paths are used
- [ ] Configuration validation works

**Success Criteria**: Configuration customization works as expected.

### Scenario 13: Force Re-Patching

**Objective**: Verify Force flag re-patches already patched installation.

**Steps**:
1. Install and patch Cursor Agent
2. Verify patch state marker exists
3. Run: `.\patch-cursor-agent.ps1 -PatchExistingInstallation -Force -InstallPath "path"`
4. Verify patches are re-applied
5. Verify patch state marker is updated

**Expected Results**:
- [ ] Force flag bypasses "already patched" check
- [ ] Patches are re-applied
- [ ] Patch state marker is updated
- [ ] Installation still works after re-patching

**Success Criteria**: Force flag allows re-patching when needed.

### Scenario 14: Verbose Output

**Objective**: Verify verbose mode provides useful debugging information.

**Steps**:
1. Run: `.\patch-cursor-agent.ps1 -Verbose`
2. Review verbose output
3. Verify output includes:
   - Configuration loading
   - Version detection
   - Download progress
   - Extraction progress
   - Patch application details
   - File operations

**Expected Results**:
- [ ] Verbose output is comprehensive
- [ ] Output is readable and informative
- [ ] Output helps with debugging
- [ ] No sensitive information exposed

**Success Criteria**: Verbose mode provides useful debugging information.

### Scenario 15: Clean Uninstallation

**Objective**: Verify clean removal of installation.

**Steps**:
1. Install Cursor Agent
2. Manually remove installation directory
3. Verify cache is not removed (by design)
4. Verify launcher script can be removed
5. Test re-installation after removal

**Expected Results**:
- [ ] Installation directory can be removed
- [ ] Cache persists (for future use)
- [ ] Launcher script can be removed
- [ ] Re-installation works after removal

**Success Criteria**: Clean removal is possible, cache persists appropriately.

## Test Documentation Template

For each test scenario, document:

```markdown
### Test: [Scenario Name]
**Date**: YYYY-MM-DD
**Tester**: [Name]
**Environment**: Windows X, PowerShell Y, Architecture Z

**Steps Executed**:
1. ...
2. ...

**Results**:
- ✅ Pass / ❌ Fail / ⚠️ Partial

**Issues Found**:
- Issue 1: Description
- Issue 2: Description

**Screenshots/Logs**: [Attach if relevant]

**Notes**:
Additional observations or comments
```

## Success Criteria

1. **All scenarios pass** - Every test scenario completes successfully
2. **User experience is smooth** - No confusing errors or unclear messages
3. **Performance is acceptable** - Installation completes in reasonable time
4. **Error handling is clear** - Users understand what went wrong and how to fix it
5. **Documentation matches reality** - README examples work as written
6. **Edge cases handled** - Unusual scenarios don't break the tool
7. **Feedback is provided** - Users know what's happening at each step

## Deliverables

1. **Test Execution Report**:
   - Results for each scenario
   - Issues found
   - Screenshots/logs
   - Recommendations

2. **Issue List**:
   - Bugs found during testing
   - Usability issues
   - Documentation gaps
   - Feature requests

3. **Test Scripts** (Optional):
   - Automated test scripts for repeatable scenarios
   - Manual test checklists
   - Test data sets

## Dependencies

- All implementation specs (001-039)
- Integration testing (Spec 040)
- Documentation (Spec 041)
- Error handling review (Spec 042)

## Notes

- Test with real users if possible
- Test on different Windows versions (10, 11)
- Test on different architectures (x64, arm64)
- Test with different PowerShell versions
- Consider accessibility testing
- Test with antivirus software (may interfere)
- Test with limited user permissions
- Test with network restrictions/proxies
