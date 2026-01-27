# Spec 38: Detect Updated Version Directory

**Function**: `Get-CursorAgentVersionDirectory`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Detect the cursor-agent version directory by resolving the launcher symlink/shortcut target.

**Signature**:
```powershell
function Get-CursorAgentVersionDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$LauncherPath # Optional: specific launcher path, otherwise searches PATH
    )
    [string] # Returns path to version directory
}
```

**Behavior**:

1. **Find Launcher**:
   - If `$LauncherPath` provided, use it
   - Otherwise, search for `cursor-agent` or `agent` in PATH using `Get-Command`
   - If not found, check common locations:
     - `%USERPROFILE%\.local\bin\cursor-agent`
     - `%USERPROFILE%\.local\bin\agent`
     - `%LOCALAPPDATA%\cursor-agent\bin\cursor-agent`

2. **Resolve Target** (try multiple methods):
   
   **Method 1: PowerShell Link Resolution** (PowerShell 5.1+):
   ```powershell
   if (Test-Path $LauncherPath -PathType Link) {
       $target = (Get-Item $LauncherPath).Target
   }
   ```
   
   **Method 2: Windows Shortcut** (`.lnk` files):
   ```powershell
   if ($LauncherPath -match '\.lnk$') {
       $shell = New-Object -ComObject WScript.Shell
       $shortcut = $shell.CreateShortcut($LauncherPath)
       $target = $shortcut.TargetPath
   }
   ```
   
   **Method 3: Read Script Content** (for bash/PowerShell scripts):
   - If launcher is a script file, parse it to find the target
   - Look for patterns like:
     - `exec "$SCRIPT_DIR/index.js"`
     - `"%~dp0node.exe" index.js`
     - `node "$SCRIPT_DIR/index.js"`
   - Extract `$SCRIPT_DIR` or equivalent variable
   
   **Method 4: Junction/Symlink** (Windows):
   - Use `cmd /c dir` with junction detection
   - Or use `Get-Item` with `-Force` to resolve

3. **Extract Version Directory**:
   - Get parent directory of resolved target
   - The target typically points to: `VERSIONS_DIR/VERSION/cursor-agent` or `VERSIONS_DIR/VERSION/agent`
   - Parent directory = version directory
   - Example: If target is `C:\Users\user\.local\share\cursor-agent\versions\2026.01.23-916f423\cursor-agent`
     - Version directory = `C:\Users\user\.local\share\cursor-agent\versions\2026.01.23-916f423`

4. **Validate Installation**:
   - Check that version directory exists
   - Verify it contains `index.js`
   - Optionally verify it contains `node` or `node.exe`
   - Return version directory path

5. **Fallback Strategy** (if symlink resolution fails):
   - Get parent directory of launcher (assumes launcher is in versions directory)
   - Or search for `versions` directory in common locations
   - Find newest directory by modification time
   - Verify contains `index.js`

**Error Handling**:
- Launcher not found → Throw with helpful message about installation
- Cannot resolve symlink → Try fallback strategy, then throw if still fails
- Invalid installation → Throw with path and reason
- Multiple launchers found → Use first one, log warning

**Helper Function**: `Resolve-LauncherTarget`
```powershell
function Resolve-LauncherTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LauncherPath
    )
    [string] # Returns resolved target path
}
```

This function implements the resolution methods described above and returns the actual target path.

**Dependencies**: None (standalone utility function)

**Success Criteria**:
- Successfully finds launcher in PATH or common locations
- Resolves symlink/shortcut/junction to actual target
- Extracts version directory correctly
- Validates installation structure
- Handles Windows-specific path resolution (shortcuts, junctions)
- Provides helpful error messages when resolution fails

**Example Usage**:
```powershell
# After cursor-agent update completes
$versionDir = Get-CursorAgentVersionDirectory
# Returns: "C:\Users\user\.local\share\cursor-agent\versions\2026.01.23-916f423"

# Can then patch this directory
Invoke-PatchExistingInstallation -InstallationPath $versionDir
```
