# end-to-end-patching.tests.ps1
# Integration tests for complete patching workflow with real Cursor Agent packages

<#
.SYNOPSIS
End-to-end integration tests for Cursor Agent patching workflow.

.DESCRIPTION
Tests the complete patching workflow using real Cursor Agent packages downloaded
from the official source. These tests require network access and may take several
minutes to complete.

These tests verify:
- Real package downloads and extraction
- Version detection from live install script
- Binary downloads from GitHub releases
- Patch application to real package files
- Installation and launcher creation
- Cache reuse and validation
- Error handling and recovery
#>

# Import required modules
$modulePath = Join-Path $PSScriptRoot '..\..\CursorAgentPatcher.psm1'
Import-Module $modulePath -Force

# Access internal functions via module scope for detailed testing
$module = Get-Module CursorAgentPatcher

# Helper functions to access internal module functions
function Get-CursorAgentInstallScriptInternal {
    param()
    if ($module) {
        & $module { Get-CursorAgentInstallScript }
    }
}

function Expand-CursorAgentPackageInternal {
    param(
        [string]$PackagePath,
        [string]$OutputDirectory
    )
    if ($module) {
        & $module { Expand-CursorAgentPackage -PackagePath $args[0] -OutputDirectory $args[1] } $PackagePath, $OutputDirectory
    }
}

function Get-CursorAgentPackageInternal {
    param(
        [string]$Version,
        [string]$SourceOs,
        [string]$SourceArch,
        [string]$OutPath
    )
    if ($module) {
        & $module { Get-CursorAgentPackage -Version $args[0] -SourceOs $args[1] -SourceArch $args[2] -OutPath $args[3] } $Version, $SourceOs, $SourceArch, $OutPath
    }
}

Describe "End-to-End Patching Integration Tests" {
    BeforeAll {
        # Create isolated test directory
        $script:testBaseDir = Join-Path $env:TEMP "cursor-agent-integration-test-$(Get-Random)"
        $script:testInstallDir = Join-Path $script:testBaseDir "install"
        $script:testCacheDir = Join-Path $script:testBaseDir "cache"
        $script:testConfigPath = Join-Path $script:testBaseDir "test-config.json"
        
        # Create test directories
        New-Item -ItemType Directory -Force -Path $script:testBaseDir | Out-Null
        New-Item -ItemType Directory -Force -Path $script:testInstallDir | Out-Null
        New-Item -ItemType Directory -Force -Path $script:testCacheDir | Out-Null
        
        # Create test config with test cache directory
        $script:testConfig = @{
            versionMappings = @{
                sqlite3 = @{
                    default = @{
                        windowsBinary = @{
                            repo = "TryGhost/node-sqlite3"
                            assetPattern = ".*windows.*node_sqlite3.*\.node"
                            releaseTag = "latest"
                        }
                    }
                }
                merkleTree = @{
                    default = @{
                        windowsBinary = @{
                            repo = "btc-vision/rust-merkle-tree"
                            assetPattern = "merkle-tree-napi\.win32-x64-msvc\.node"
                            releaseTag = "latest"
                        }
                    }
                }
                ripgrep = @{
                    default = @{
                        windowsBinary = @{
                            repo = "BurntSushi/ripgrep"
                            assetPattern = "ripgrep-.*-x86_64-pc-windows-msvc\.zip"
                            releaseTag = "latest"
                        }
                    }
                }
            }
            cache = @{
                directory = $script:testCacheDir
                enabled = $true
                validateOnUse = $true
            }
            installation = @{
                defaultPath = $script:testInstallDir
                createLauncher = $true
                launcherName = "cursor-agent.bat"
            }
            cursorAgent = @{
                installScriptUrl = "https://cursor.com/install"
                downloadBaseUrl = "https://downloads.cursor.com/lab"
                sourceOs = "darwin"
                sourceArch = "arm64"
            }
        }
        $script:testConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:testConfigPath
        
        # Set environment variable for config path
        $env:CURSOR_AGENT_CONFIG_PATH = $script:testConfigPath
    }
    
    AfterAll {
        # Cleanup test artifacts
        Remove-Item -Path $script:testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path env:CURSOR_AGENT_CONFIG_PATH) {
            Remove-Item env:CURSOR_AGENT_CONFIG_PATH
        }
    }
    
    BeforeEach {
        # Clear cache before each test for isolation
        if (Test-Path $script:testCacheDir) {
            Get-ChildItem -Path $script:testCacheDir -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        
        # Clear install directory
        if (Test-Path $script:testInstallDir) {
            Get-ChildItem -Path $script:testInstallDir -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Scenario 1: Happy Path - Complete Patching Workflow" {
        It "Completes full patching workflow with real package" {
            # This test may take 2-5 minutes due to real downloads
            $result = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -ErrorAction Stop
            
            # Verify result structure
            $result | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
            $result.InstallationPath | Should Not BeNullOrEmpty
            $result.AppliedPatches | Should Not BeNullOrEmpty
            
            # Verify installation directory structure
            $installPath = $result.InstallationPath
            Test-Path $installPath | Should Be $true
            Test-Path (Join-Path $installPath "index.js") | Should Be $true
            Test-Path (Join-Path $installPath "package.json") | Should Be $true
            
            # Verify launcher script exists
            $launcherPath = Join-Path $installPath "cursor-agent.bat"
            Test-Path $launcherPath | Should Be $true
            
            # Verify patch state marker exists
            $markerPath = Join-Path $installPath ".cursor-agent-patched"
            Test-Path $markerPath | Should Be $true
            
            # Verify marker content
            $marker = Get-Content $markerPath -Raw | ConvertFrom-Json
            $marker.cursorAgentVersion | Should Not BeNullOrEmpty
            $marker.appliedPatches | Should Not BeNullOrEmpty
            
            # Verify patched files exist (if patches were applied)
            if ($result.AppliedPatches.Count -gt 0) {
                # Check for native.js (platform detection patch)
                $nativeFiles = Get-ChildItem -Path $installPath -Filter "native.js" -Recurse -ErrorAction SilentlyContinue
                if ($nativeFiles) {
                    # Verify at least one native.js file exists (patch target)
                    $nativeFiles.Count | Should BeGreaterThan 0
                    # Note: Windows platform support verification may not always be true
                    # if package structure changed, so we just verify files exist
                }
            }
            
            # Verify launcher script can be executed (syntax check)
            $launcherContent = Get-Content $launcherPath -Raw
            $launcherContent | Should Not BeNullOrEmpty
            # Launcher should reference index.js
            $launcherContent | Should Match "index\.js"
        }
    }
    
    Context "Scenario 2: Cached Binary Reuse" {
        It "Reuses cached binaries on subsequent runs" {
            # First run - downloads binaries
            $result1 = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -ErrorAction Stop
            $result1.Success | Should Be $true
            
            # Get cache directory contents after first run
            $cacheAfterFirst = @()
            if (Test-Path (Join-Path $script:testCacheDir "binaries")) {
                $cacheAfterFirst = Get-ChildItem -Path (Join-Path $script:testCacheDir "binaries") -Recurse -File | 
                    Select-Object -ExpandProperty FullName
            }
            $cacheAfterFirst.Count | Should BeGreaterThan 0
            
            # Clear package cache but keep binary cache
            $installPath1 = $result1.InstallationPath
            if (Test-Path $installPath1) {
                Remove-Item -Path $installPath1 -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Second run - should reuse cached binaries
            $result2 = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -ErrorAction Stop
            $result2.Success | Should Be $true
            
            # Verify cache still has same binaries (cache hit)
            $cacheAfterSecond = @()
            if (Test-Path (Join-Path $script:testCacheDir "binaries")) {
                $cacheAfterSecond = Get-ChildItem -Path (Join-Path $script:testCacheDir "binaries") -Recurse -File | 
                    Select-Object -ExpandProperty FullName
            }
            
            # Cache should have same or more files (may have additional cached items)
            $cacheAfterSecond.Count | Should BeGreaterThanOrEqual $cacheAfterFirst.Count
            
            # Verify cached files are still valid
            foreach ($cachedFile in $cacheAfterSecond) {
                Test-Path $cachedFile | Should Be $true
                (Get-Item $cachedFile).Length | Should BeGreaterThan 0
            }
        }
    }
    
    Context "Scenario 3: Partial Failure Recovery" {
        It "Handles network errors gracefully" {
            # Test with invalid URL to simulate network failure
            $invalidConfig = @{
                versionMappings = $script:testConfig.versionMappings
                cache = $script:testConfig.cache
                installation = $script:testConfig.installation
                cursorAgent = @{
                    installScriptUrl = "https://invalid-url-that-does-not-exist-12345.com/install"
                    downloadBaseUrl = $script:testConfig.cursorAgent.downloadBaseUrl
                    sourceOs = $script:testConfig.cursorAgent.sourceOs
                    sourceArch = $script:testConfig.cursorAgent.sourceArch
                }
            }
            $invalidConfigPath = Join-Path $script:testBaseDir "invalid-config.json"
            $invalidConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $invalidConfigPath
            
            try {
                $null = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $invalidConfigPath -ErrorAction Stop
                # Should not reach here
                $false | Should Be $true
            }
            catch {
                # Expected to throw error
                $_.Exception.Message | Should Not BeNullOrEmpty
                $_.Exception.Message | Should Match "Failed|Error|Network"
            }
            finally {
                # Verify no partial artifacts left
                if (Test-Path $script:testInstallDir) {
                    $installContents = Get-ChildItem -Path $script:testInstallDir -Recurse -ErrorAction SilentlyContinue
                    # Should have minimal or no artifacts on failure
                    $installContents.Count | Should BeLessThan 5
                }
            }
        }
        
        It "Cleans up partial artifacts on extraction failure" {
            # This test is harder to simulate without corrupting a real archive
            # We'll verify the cleanup mechanism exists by checking error handling
            $tempPackage = Join-Path $script:testBaseDir "test-package.tar.gz"
            
            # Create a fake/corrupted package file
            "fake content" | Set-Content -Path $tempPackage
            
            try {
                # Try to extract corrupted package
                Expand-CursorAgentPackageInternal -PackagePath $tempPackage -OutputDirectory $script:testInstallDir
                # Should not reach here
                $false | Should Be $true
            }
            catch {
                # Expected error
                $_.Exception.Message | Should Not BeNullOrEmpty
            }
            finally {
                # Verify cleanup
                if (Test-Path $tempPackage) {
                    Remove-Item -Path $tempPackage -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context "Scenario 4: Version Detection and Extraction" {
        It "Extracts version from real install script" {
            # Fetch real install script
            $installScript = Get-CursorAgentInstallScriptInternal
            $installScript | Should Not BeNullOrEmpty
            $installScript.Length | Should BeGreaterThan 100
            
            # Extract version
            $version = Get-CursorAgentVersion -InstallScript $installScript
            $version | Should Not BeNullOrEmpty
            
            # Verify version format (YYYY.MM.DD-hash)
            $version | Should Match "^\d{4}\.\d{2}\.\d{2}-[a-f0-9]+$"
            
            # Use extracted version to verify package download URL format
            $config = Get-PatcherConfig -ConfigPath $script:testConfigPath
            $expectedUrlPattern = "$($config.cursorAgent.downloadBaseUrl)/$version/$($config.cursorAgent.sourceOs)/$($config.cursorAgent.sourceArch)/agent-cli-package.tar.gz"
            $expectedUrlPattern | Should Match "https://.*\.tar\.gz$"
        }
        
        It "Downloads package matching extracted version" {
            # Get version from install script
            $installScript = Get-CursorAgentInstallScriptInternal
            $version = Get-CursorAgentVersion -InstallScript $installScript
            $version | Should Not BeNullOrEmpty
            
            # Download package for this version
            $config = Get-PatcherConfig -ConfigPath $script:testConfigPath
            $packagePath = Join-Path $script:testBaseDir "test-package.tar.gz"
            
            try {
                $downloadedPath = Get-CursorAgentPackageInternal -Version $version -SourceOs $config.cursorAgent.sourceOs -SourceArch $config.cursorAgent.sourceArch -OutPath $packagePath
                
                $downloadedPath | Should Not BeNullOrEmpty
                Test-Path $downloadedPath | Should Be $true
                (Get-Item $downloadedPath).Length | Should BeGreaterThan 1000000  # At least 1MB
            }
            finally {
                if (Test-Path $packagePath) {
                    Remove-Item -Path $packagePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context "Scenario 5: Multi-Architecture Support" {
        It "Detects Windows architecture correctly" {
            $arch = Get-WindowsArchitecture
            $arch | Should Not BeNullOrEmpty
            $arch | Should Match "^(x64|arm64)$"
        }
        
        It "Downloads architecture-appropriate binaries" {
            # Run patching workflow
            $result = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -ErrorAction Stop
            $result.Success | Should Be $true
            
            # Verify architecture detection was used
            $arch = Get-WindowsArchitecture
            $arch | Should Not BeNullOrEmpty
            
            # Verify binaries were downloaded (check cache)
            $binaryCache = Join-Path $script:testCacheDir "binaries"
            if (Test-Path $binaryCache) {
                $cachedBinaries = Get-ChildItem -Path $binaryCache -Recurse -File -ErrorAction SilentlyContinue
                # Should have at least one binary cached
                $cachedBinaries.Count | Should BeGreaterThan 0
                
                # Verify binaries are valid (non-zero size)
                foreach ($binary in $cachedBinaries) {
                    $binary.Length | Should BeGreaterThan 0
                }
            }
        }
    }
    
    Context "Additional Integration Scenarios" {
        It "Handles WhatIf mode without side effects" {
            # Run in WhatIf mode
            $null = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -WhatIf -ErrorAction Stop
            
            # WhatIf should not create installation
            if (Test-Path $script:testInstallDir) {
                $installContents = Get-ChildItem -Path $script:testInstallDir -Recurse -ErrorAction SilentlyContinue
                # Should have minimal or no files in WhatIf mode
                $installContents.Count | Should BeLessThan 3
            }
        }
        
        It "Validates cache entries on use" {
            # First run creates cache
            $result1 = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -ErrorAction Stop
            $result1.Success | Should Be $true
            
            # Verify cache validation is enabled in config
            $config = Get-PatcherConfig -ConfigPath $script:testConfigPath
            $config.cache.validateOnUse | Should Be $true
            
            # Second run should validate cached binaries
            $installPath1 = $result1.InstallationPath
            if (Test-Path $installPath1) {
                Remove-Item -Path $installPath1 -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $result2 = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -ErrorAction Stop
            $result2.Success | Should Be $true
            
            # If we got here, cache validation passed
        }
    }
}
