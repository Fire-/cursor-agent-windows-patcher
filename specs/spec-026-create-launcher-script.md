# Spec 26: Create Launcher Script Function

**Function**: `New-CursorAgentLauncher`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Generate `cursor-agent.bat` launcher script with update interception support.

**Signature**:
```powershell
function New-CursorAgentLauncher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallPath,
        
        [Parameter(Mandatory=$false)]
        [string]$LauncherName = "cursor-agent.bat",
        
        [Parameter(Mandatory=$false)]
        [string]$RealCursorAgentPath, # Path to real cursor-agent executable (for passthrough)
        
        [Parameter(Mandatory=$false)]
        [switch]$EnableUpdateInterception # Enable update interception and auto-patching
    )
    [string] # Returns path to created launcher
}
```

**Behavior**:

**Standard Mode** (when `-EnableUpdateInterception` is not specified):
1. Determine path to `index.js` in installed package
2. Generate batch script:
   ```batch
   @echo off
   cd /d "%~dp0"
   node index.js %*
   ```
3. Write to `$InstallPath\$LauncherName`
4. Return path to launcher

**Update Interception Mode** (when `-EnableUpdateInterception` is specified):
1. Determine path to `index.js` in installed package
2. Determine path to patcher module (CursorAgentPatcher.psm1)
3. Generate PowerShell wrapper script:
   ```powershell
   # cursor-agent.bat (PowerShell wrapper)
   param([string[]]$args)
   
   # Import patcher module
   $modulePath = Join-Path $PSScriptRoot "CursorAgentPatcher.psm1"
   if (Test-Path $modulePath) {
       Import-Module $modulePath -ErrorAction SilentlyContinue
   }
   
   # Check if update/upgrade command
   if ($args.Count -gt 0 -and ($args[0] -eq "update" -or $args[0] -eq "upgrade")) {
       # Intercept update command
       $result = Invoke-CursorAgentUpdateWithPatch -UpdateArguments $args[1..($args.Length-1)]
       
       if ($result.UpdateSuccess) {
           if ($result.PatchSuccess) {
               Write-Host "Update and patch completed successfully!" -ForegroundColor Green
               exit 0
           } else {
               Write-Warning "Update succeeded but patching failed. Run patch manually."
               exit 1
           }
       } else {
           Write-Error "Update failed: $($result.UpdateError)"
           exit $result.UpdateExitCode
       }
   } else {
       # Pass through to real cursor-agent
       $realPath = "$RealCursorAgentPath"
       if (Test-Path $realPath) {
           & $realPath @args
           exit $LASTEXITCODE
       } else {
           # Fallback: try to find in PATH
           $cmd = Get-Command cursor-agent -ErrorAction SilentlyContinue
           if ($cmd) {
               & $cmd.Source @args
               exit $LASTEXITCODE
           } else {
               Write-Error "Cannot find cursor-agent executable"
               exit 1
           }
       }
   }
   ```
4. Write to `$InstallPath\$LauncherName`
5. Return path to launcher

**Note**: The launcher script file extension can be `.bat` or `.ps1` depending on implementation. If `.bat`, it should call PowerShell to execute the wrapper logic.

**Alternative Implementation** (if `.bat` file):
```batch
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cursor-agent-wrapper.ps1" %*
```

Where `cursor-agent-wrapper.ps1` contains the PowerShell logic above.

**Error Handling**:
- Install path invalid → Throw
- Real cursor-agent path invalid (in interception mode) → Log warning, try PATH lookup
- Patcher module not found → Log warning, skip interception, pass through
- Write fails → Throw with path and error

**Dependencies**: Spec 37 (Invoke-CursorAgentUpdateWithPatch)

**Success Criteria**:
- Creates valid launcher script
- In standard mode: Launcher correctly invokes Node.js with index.js
- In interception mode: Launcher intercepts update commands and triggers auto-patching
- In interception mode: Launcher passes through all other commands to real cursor-agent
- Returns path to created file
