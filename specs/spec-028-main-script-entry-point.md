# Spec 28: Main Script Entry Point

**File**: `patch-cursor-agent.ps1`

**Purpose**: Command-line interface for the patcher.

**Structure**:
```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string]$Sqlite3Version,
    
    [Parameter(Mandatory=$false)]
    [string]$MerkleTreeVersion,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,
    
    [Parameter(Mandatory=$false)]
    [string]$PatchExistingInstallation, # Path to already-extracted installation
    
    [Parameter(Mandatory=$false)]
    [switch]$Force, # Re-patch even if already patched
    
    [Parameter(Mandatory=$false)]
    [switch]$Update # Run cursor-agent update, then patch new version
)

# Import module
Import-Module .\CursorAgentPatcher.psm1

# Set error action
$ErrorActionPreference = "Stop"

# Handle update mode
if ($Update) {
    try {
        $result = Invoke-CursorAgentUpdateWithPatch -UpdateArguments @() -WhatIf:$WhatIf -Force:$Force
        if ($result.UpdateSuccess -and $result.PatchSuccess) {
            Write-Host "Update and patch completed successfully!" -ForegroundColor Green
            Write-Host "New version: $($result.VersionDirectory)" -ForegroundColor Cyan
            exit 0
        } elseif ($result.UpdateSuccess) {
            Write-Warning "Update succeeded but patching failed."
            Write-Host "Version directory: $($result.VersionDirectory)" -ForegroundColor Yellow
            exit 1
        } else {
            Write-Error "Update failed: $($result.UpdateError)"
            exit $result.UpdateExitCode
        }
    }
    catch {
        Write-Error "Update and patch workflow failed: $_"
        exit 1
    }
}
# Handle in-place patching mode
elseif ($PatchExistingInstallation) {
    try {
        $result = Invoke-CursorAgentPatch `
            -PatchExistingInstallation $PatchExistingInstallation `
            -Force:$Force `
            -WhatIf:$WhatIf `
            -Verbose:$Verbose
        Write-Host "Patching completed successfully!" -ForegroundColor Green
        Write-Host "Patched installation: $PatchExistingInstallation" -ForegroundColor Cyan
        exit 0
    }
    catch {
        Write-Error "Patching failed: $_"
        exit 1
    }
}
# Standard mode: download, extract, patch, install
else {
    try {
        $result = Invoke-CursorAgentPatch @PSBoundParameters
        Write-Host "Patch completed successfully!" -ForegroundColor Green
        Write-Host "Installed to: $($result.InstallPath)" -ForegroundColor Cyan
        exit 0
    }
    catch {
        Write-Error "Patching failed: $_"
        exit 1
    }
}
```

**Dependencies**: Spec 25, Spec 37

**Success Criteria**:
- Parses all command-line parameters including new update and in-place patching modes
- Calls appropriate workflow function based on mode:
  - Standard mode: `Invoke-CursorAgentPatch`
  - In-place patching mode: `Invoke-CursorAgentPatch` with `-PatchExistingInstallation`
  - Update mode: `Invoke-CursorAgentUpdateWithPatch`
- Provides user-friendly output for all modes
- Exits with appropriate codes (0 for success, non-zero for failure)

**Usage Examples**:

```powershell
# Standard installation
.\patch-cursor-agent.ps1 -Version "2026.01.23-916f423" -InstallPath "C:\cursor-agent"

# Patch existing installation
.\patch-cursor-agent.ps1 -PatchExistingInstallation "C:\Users\user\.local\share\cursor-agent\versions\2026.01.23-916f423"

# Update cursor-agent and auto-patch
.\patch-cursor-agent.ps1 -Update

# Force re-patch existing installation
.\patch-cursor-agent.ps1 -PatchExistingInstallation "C:\path\to\version" -Force
```
