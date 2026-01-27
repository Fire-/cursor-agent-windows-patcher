<#
.SYNOPSIS
Patch Cursor Agent for Windows compatibility.

.DESCRIPTION
Main entry point for the Cursor Agent Windows Patcher. Supports three modes:
- Standard mode: Download, extract, patch, and install Cursor Agent
- In-place patching mode: Patch an existing Cursor Agent installation
- Update mode: Update cursor-agent and automatically patch the new version

.PARAMETER Version
Cursor Agent version to download and patch. If not provided, will be auto-detected.

.PARAMETER InstallPath
Installation path for the patched package. Defaults to config value.

.PARAMETER Sqlite3Version
Override SQLite3 version (optional).

.PARAMETER MerkleTreeVersion
Override Merkle Tree version (optional).

.PARAMETER PatchExistingInstallation
Path to already-extracted installation. If provided, skips download/extract steps.

.PARAMETER Force
Re-patch even if installation is already patched.

.PARAMETER Update
Run cursor-agent update, then patch new version. Requires Spec 37 to be fully functional.

.EXAMPLE
.\patch-cursor-agent.ps1 -Version "2026.01.23-916f423" -InstallPath "C:\cursor-agent"
# Standard installation

.EXAMPLE
.\patch-cursor-agent.ps1 -PatchExistingInstallation "C:\Users\user\.local\share\cursor-agent\versions\2026.01.23-916f423"
# Patch existing installation

.EXAMPLE
.\patch-cursor-agent.ps1 -Update
# Update cursor-agent and auto-patch

.EXAMPLE
.\patch-cursor-agent.ps1 -PatchExistingInstallation "C:\path\to\version" -Force
# Force re-patch existing installation
#>
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
    [string]$PatchExistingInstallation,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$Update
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Import module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "CursorAgentPatcher.psm1"
if (-not (Test-Path -Path $modulePath -PathType Leaf)) {
    Write-Error "patch-cursor-agent.ps1: CursorAgentPatcher.psm1 not found at '$modulePath'"
    exit 1
}

try {
    Import-Module $modulePath -ErrorAction Stop
}
catch {
    Write-Error "patch-cursor-agent.ps1: Failed to import CursorAgentPatcher module. Error: $_"
    exit 1
}

# Handle update mode
if ($Update) {
    try {
        # Check if Invoke-CursorAgentUpdateWithPatch is available (Spec 037)
        if (-not (Get-Command Invoke-CursorAgentUpdateWithPatch -ErrorAction SilentlyContinue)) {
            Write-Error "patch-cursor-agent.ps1: Update mode requires Spec 037 (Invoke-CursorAgentUpdateWithPatch) to be implemented."
            Write-Host "Please use standard patching mode or in-place patching mode instead." -ForegroundColor Yellow
            exit 1
        }
        
        $result = Invoke-CursorAgentUpdateWithPatch -UpdateArguments @() -WhatIf:$WhatIf -Force:$Force
        
        if ($result.UpdateSuccess -and $result.PatchSuccess) {
            Write-Host "Update and patch completed successfully!" -ForegroundColor Green
            Write-Host "New version: $($result.VersionDirectory)" -ForegroundColor Cyan
            exit 0
        }
        elseif ($result.UpdateSuccess) {
            Write-Warning "Update succeeded but patching failed."
            Write-Host "Version directory: $($result.VersionDirectory)" -ForegroundColor Yellow
            exit 1
        }
        else {
            Write-Error "Update failed: $($result.UpdateError)"
            exit $result.UpdateExitCode
        }
    }
    catch {
        Write-Error "patch-cursor-agent.ps1: Update and patch workflow failed: $_"
        exit 1
    }
}
# Handle in-place patching mode
elseif ($PatchExistingInstallation) {
    try {
        $result = Invoke-CursorAgentPatch `
            -PatchExistingInstallation $PatchExistingInstallation `
            -Force:$Force `
            -WhatIf:$WhatIf
        
        if ($result.Success) {
            Write-Host "Patching completed successfully!" -ForegroundColor Green
            Write-Host "Patched installation: $PatchExistingInstallation" -ForegroundColor Cyan
            if ($result.AppliedPatches) {
                Write-Host "Applied patches: $($result.AppliedPatches -join ', ')" -ForegroundColor Cyan
            }
            exit 0
        }
        else {
            Write-Error "Patching completed with errors. Check output above for details."
            exit 1
        }
    }
    catch {
        Write-Error "patch-cursor-agent.ps1: Patching failed: $_"
        exit 1
    }
}
# Standard mode: download, extract, patch, install
else {
    try {
        # Build parameter hashtable for Invoke-CursorAgentPatch
        $patchParams = @{}
        if ($Version) { $patchParams['Version'] = $Version }
        if ($InstallPath) { $patchParams['InstallPath'] = $InstallPath }
        if ($WhatIf) { $patchParams['WhatIf'] = $true }
        if ($Force) { $patchParams['Force'] = $true }
        
        $result = Invoke-CursorAgentPatch @patchParams
        
        if ($result.Success) {
            Write-Host "Patch completed successfully!" -ForegroundColor Green
            Write-Host "Installed to: $($result.InstallationPath)" -ForegroundColor Cyan
            if ($result.AppliedPatches) {
                Write-Host "Applied patches: $($result.AppliedPatches -join ', ')" -ForegroundColor Cyan
            }
            exit 0
        }
        else {
            Write-Error "Patching completed with errors. Check output above for details."
            exit 1
        }
    }
    catch {
        Write-Error "patch-cursor-agent.ps1: Patching failed: $_"
        exit 1
    }
}
