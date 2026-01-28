# User Acceptance Testing - Test Execution Template

**Project**: Cursor Agent Windows Patcher  
**Spec**: Spec 043 - User Acceptance Testing  
**Purpose**: Manual testing procedures and results tracking

## Test Environment

**Date**: _______________  
**Tester**: _______________  
**Environment**:
- Windows Version: _______________
- PowerShell Version: _______________
- Architecture: _______________ (x64/arm64)
- Bun/Node.js Version: _______________
- 7-Zip Installed: _______________ (Yes/No)
- Internet Connection: _______________ (Yes/No)
- Administrator Privileges: _______________ (Yes/No)

**Test Data**:
- Repository Path: _______________
- Cache Directory: _______________
- Test Installation Path: _______________

## Test Scenarios

### Scenario 1: First-Time Installation (Happy Path)

**Objective**: Verify complete installation workflow for new user.

**Steps Executed**:
1. [ ] Opened PowerShell in project directory
2. [ ] Reviewed `patcher-config.json` (verified default settings)
3. [ ] Ran: `.\patch-cursor-agent.ps1`
4. [ ] Observed output and progress indicators
5. [ ] Waited for completion
6. [ ] Verified installation directory structure
7. [ ] Tested launcher script execution
8. [ ] Verified Cursor Agent can start

**Expected Results**:
- [ ] Script executes without errors
- [ ] Progress indicators show download/extraction progress
- [ ] Installation directory created with correct structure
- [ ] Launcher script exists and is executable
- [ ] Cursor Agent starts (may fail later due to missing Bun/Node, but should get past initial load)
- [ ] Cache directory contains downloaded binaries
- [ ] Patch state marker file exists

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 2: Specific Version Installation

**Objective**: Verify installation of specific Cursor Agent version.

**Steps Executed**:
1. [ ] Got available version: Checked cursor.com or used `Get-CursorAgentVersion`
2. [ ] Ran: `.\patch-cursor-agent.ps1 -Version "YYYY.MM.DD-hash"`
3. [ ] Verified correct version is downloaded
4. [ ] Verified patches are applied
5. [ ] Verified installation contains correct version

**Expected Results**:
- [ ] Specified version is downloaded (not latest)
- [ ] Version matches requested version
- [ ] Installation directory reflects correct version
- [ ] Patch state marker contains correct version

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 3: Custom Installation Path

**Objective**: Verify installation to custom location.

**Steps Executed**:
1. [ ] Chose custom path: `C:\Tools\cursor-agent-test`
2. [ ] Ran: `.\patch-cursor-agent.ps1 -InstallPath "C:\Tools\cursor-agent-test"`
3. [ ] Verified installation at custom path
4. [ ] Verified launcher script location
5. [ ] Tested launcher from custom path

**Expected Results**:
- [ ] Installation created at specified path
- [ ] Launcher script created at specified path
- [ ] Path can be absolute or relative
- [ ] Launcher works from custom location

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 4: In-Place Patching

**Objective**: Verify patching of existing Cursor Agent installation.

**Prerequisites**: Existing Cursor Agent installation (from official installer or previous test)

**Steps Executed**:
1. [ ] Located existing installation: `C:\Users\...\cursor-agent\...`
2. [ ] Verified installation is not already patched
3. [ ] Ran: `.\patch-cursor-agent.ps1 -PatchExistingInstallation -InstallPath "C:\path\to\existing"`
4. [ ] Observed patch application
5. [ ] Verified patches were applied
6. [ ] Tested launcher script

**Expected Results**:
- [ ] Existing files are patched in-place
- [ ] No duplicate installation created
- [ ] Patches are applied correctly
- [ ] Launcher script created/updated
- [ ] Original files backed up (if applicable)

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 5: Update Interception

**Objective**: Verify automatic patching after cursor-agent update.

**Prerequisites**: Cursor Agent installed and launcher with update interception enabled

**Steps Executed**:
1. [ ] Installed Cursor Agent with update interception launcher
2. [ ] Ran: `cursor-agent update` (or equivalent)
3. [ ] Observed update process
4. [ ] Verified new version is detected
5. [ ] Verified automatic patching occurs
6. [ ] Verified patched version is active

**Expected Results**:
- [ ] Update command is intercepted
- [ ] New version is downloaded by cursor-agent
- [ ] New version directory is detected
- [ ] Automatic patching is triggered
- [ ] Patched version becomes active
- [ ] User is notified of patching

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 6: Dry Run (What-If Mode)

**Objective**: Verify preview mode shows what would happen without making changes.

**Steps Executed**:
1. [ ] Ran: `.\patch-cursor-agent.ps1 -WhatIf -Verbose`
2. [ ] Reviewed output
3. [ ] Verified no actual changes are made
4. [ ] Compared with actual run output

**Expected Results**:
- [ ] All operations are previewed
- [ ] No files are created/modified
- [ ] Output clearly indicates "What-If" mode
- [ ] Output matches actual operations when run for real

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 7: Cache Functionality

**Objective**: Verify binary caching works correctly.

**Steps Executed**:
1. [ ] First run: `.\patch-cursor-agent.ps1` (downloads binaries)
2. [ ] Noted cache location and contents
3. [ ] Second run: `.\patch-cursor-agent.ps1 -Version "same-version"`
4. [ ] Verified binaries are retrieved from cache
5. [ ] Verified no redundant downloads
6. [ ] Tested cache validation (corrupted a cache entry, verified it's re-downloaded)

**Expected Results**:
- [ ] Binaries are cached after first download
- [ ] Subsequent runs use cached binaries
- [ ] Cache hit is indicated in output
- [ ] Corrupted cache entries are detected and re-downloaded
- [ ] Cache location is correct

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 8: Error Handling - Network Failure

**Objective**: Verify graceful handling of network errors.

**Steps Executed**:
1. [ ] Disconnected network (or blocked cursor.com)
2. [ ] Ran: `.\patch-cursor-agent.ps1`
3. [ ] Observed error handling
4. [ ] Reconnected network
5. [ ] Verified retry works (if implemented)
6. [ ] Verified cleanup of partial downloads

**Expected Results**:
- [ ] Clear error message about network failure
- [ ] No corrupted partial files left
- [ ] System can retry after network restored
- [ ] Error message is actionable

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 9: Error Handling - Invalid Version

**Objective**: Verify handling of invalid version specification.

**Steps Executed**:
1. [ ] Ran: `.\patch-cursor-agent.ps1 -Version "invalid-version"`
2. [ ] Observed error handling
3. [ ] Verified helpful error message
4. [ ] Tried with valid version format but non-existent version

**Expected Results**:
- [ ] Clear error message about invalid version
- [ ] Error message suggests valid format
- [ ] System doesn't crash or leave partial state

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 10: Error Handling - Permission Issues

**Objective**: Verify handling of permission errors.

**Steps Executed**:
1. [ ] Created read-only directory
2. [ ] Tried to install to read-only location
3. [ ] Observed error handling
4. [ ] Tested with insufficient permissions for cache directory
5. [ ] Tested with file locked (Cursor Agent running)

**Expected Results**:
- [ ] Clear error messages about permissions
- [ ] Suggestions for resolution (run as admin, close processes)
- [ ] No partial installations left

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 11: Multiple Architecture Support

**Objective**: Verify correct binaries for system architecture.

**Steps Executed**:
1. [ ] Checked system architecture (x64 or arm64)
2. [ ] Ran installation
3. [ ] Verified correct architecture binaries are downloaded
4. [ ] Verified patches use correct binaries
5. [ ] Tested on different architecture if available

**Expected Results**:
- [ ] Architecture is detected correctly
- [ ] Correct binaries are downloaded
- [ ] Patches use architecture-appropriate binaries
- [ ] Installation works on target architecture

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 12: Configuration Customization

**Objective**: Verify custom configuration works.

**Steps Executed**:
1. [ ] Modified `patcher-config.json`:
   - Changed cache directory
   - Changed default installation path
   - Added custom version mapping
2. [ ] Ran installation
3. [ ] Verified custom settings are used
4. [ ] Verified custom cache location
5. [ ] Verified custom installation path

**Expected Results**:
- [ ] Custom configuration is loaded
- [ ] Custom settings are applied
- [ ] Custom paths are used
- [ ] Configuration validation works

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 13: Force Re-Patching

**Objective**: Verify Force flag re-patches already patched installation.

**Steps Executed**:
1. [ ] Installed and patched Cursor Agent
2. [ ] Verified patch state marker exists
3. [ ] Ran: `.\patch-cursor-agent.ps1 -PatchExistingInstallation -Force -InstallPath "path"`
4. [ ] Verified patches are re-applied
5. [ ] Verified patch state marker is updated

**Expected Results**:
- [ ] Force flag bypasses "already patched" check
- [ ] Patches are re-applied
- [ ] Patch state marker is updated
- [ ] Installation still works after re-patching

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 14: Verbose Output

**Objective**: Verify verbose mode provides useful debugging information.

**Steps Executed**:
1. [ ] Ran: `.\patch-cursor-agent.ps1 -Verbose`
2. [ ] Reviewed verbose output
3. [ ] Verified output includes:
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

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

### Scenario 15: Clean Uninstallation

**Objective**: Verify clean removal of installation.

**Steps Executed**:
1. [ ] Installed Cursor Agent
2. [ ] Manually removed installation directory
3. [ ] Verified cache is not removed (by design)
4. [ ] Verified launcher script can be removed
5. [ ] Tested re-installation after removal

**Expected Results**:
- [ ] Installation directory can be removed
- [ ] Cache persists (for future use)
- [ ] Launcher script can be removed
- [ ] Re-installation works after removal

**Actual Results**:
- Status: ⬜ Not Started / 🟡 In Progress / ✅ Pass / ❌ Fail / ⚠️ Partial
- Notes: _______________

**Issues Found**:
- _______________

**Screenshots/Logs**: _______________

---

## Test Summary

**Total Scenarios**: 15  
**Passed**: ___ / 15  
**Failed**: ___ / 15  
**Partial**: ___ / 15  
**Not Started**: ___ / 15

## Overall Assessment

**User Experience**: ⬜ Excellent / ⬜ Good / ⬜ Acceptable / ⬜ Poor  
**Performance**: ⬜ Excellent / ⬜ Good / ⬜ Acceptable / ⬜ Poor  
**Error Handling**: ⬜ Excellent / ⬜ Good / ⬜ Acceptable / ⬜ Poor  
**Documentation Accuracy**: ⬜ Excellent / ⬜ Good / ⬜ Acceptable / ⬜ Poor

## Issues Summary

### Critical Issues
1. _______________
2. _______________

### High Priority Issues
1. _______________
2. _______________

### Medium Priority Issues
1. _______________
2. _______________

### Low Priority Issues / Enhancements
1. _______________
2. _______________

## Recommendations

1. _______________
2. _______________
3. _______________

## Test Completion

**Test Completed By**: _______________  
**Date**: _______________  
**Signature/Approval**: _______________

---

## Notes

- This template should be filled out during actual manual testing
- Screenshots and logs should be attached or referenced
- All issues should be documented with steps to reproduce
- Test on multiple Windows versions and architectures if possible
