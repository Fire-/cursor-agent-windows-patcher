# critical-bootstrap.tests.ps1
# Fast-fail gate for core dependency/bootstrap integration behavior.

$modulePath = Join-Path $PSScriptRoot '..\..\CursorAgentPatcher.psm1'
Import-Module $modulePath -Force

Describe "Critical Bootstrap Integration Tests" {
    BeforeAll {
        $script:testBaseDir = Join-Path $env:TEMP "cursor-agent-critical-test-$(Get-Random)"
        $script:testInstallDir = Join-Path $script:testBaseDir "install"
        $script:testCacheDir = Join-Path $script:testBaseDir "cache"
        $script:testConfigPath = Join-Path $script:testBaseDir "critical-test-config.json"

        New-Item -ItemType Directory -Force -Path $script:testBaseDir | Out-Null
        New-Item -ItemType Directory -Force -Path $script:testInstallDir | Out-Null
        New-Item -ItemType Directory -Force -Path $script:testCacheDir | Out-Null

        $script:testConfig = @{
            versionMappings = @{
                sqlite3    = @{
                    default = @{
                        windowsBinary = @{
                            repo         = "TryGhost/node-sqlite3"
                            assetPattern = "sqlite3-.*-napi-v6-win32-x64\.tar\.gz"
                            releaseTag   = "latest"
                        }
                    }
                }
                merkleTree = @{
                    default = @{
                        windowsBinary = @{
                            repo         = "btc-vision/rust-merkle-tree"
                            assetPattern = "rust-merkle-tree\.win32-x64-msvc\.node"
                            releaseTag   = "latest"
                        }
                    }
                }
                ripgrep    = @{
                    default = @{
                        windowsBinary = @{
                            repo         = "BurntSushi/ripgrep"
                            assetPattern = "ripgrep-.*-x86_64-pc-windows-msvc\.zip"
                            releaseTag   = "latest"
                        }
                    }
                }
            }
            cache           = @{
                directory     = $script:testCacheDir
                enabled       = $true
                validateOnUse = $true
            }
            installation    = @{
                defaultPath    = $script:testInstallDir
                createLauncher = $true
                launcherName   = "cursor-agent.bat"
            }
            cursorAgent     = @{
                installScriptUrl = "https://cursor.com/install"
                downloadBaseUrl  = "https://downloads.cursor.com/lab"
                sourceOs         = "darwin"
                sourceArch       = "arm64"
            }
        }
        $script:testConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:testConfigPath
        
        # Seed test cache from local cache when available to reduce GitHub API calls
        $localBinaryCache = Join-Path $env:LOCALAPPDATA "cursor-agent-patcher\cache\binaries"
        $testBinaryCache = Join-Path $script:testCacheDir "binaries"
        if (Test-Path $localBinaryCache) {
            New-Item -ItemType Directory -Force -Path $testBinaryCache | Out-Null
            Copy-Item -Path (Join-Path $localBinaryCache "*") -Destination $testBinaryCache -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        Remove-Item -Path $script:testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Bootstraps core patching dependencies and workflow" {
        $result = Invoke-CursorAgentPatch -InstallPath $script:testInstallDir -ConfigPath $script:testConfigPath -ErrorAction Stop

        $result | Should Not BeNullOrEmpty
        $result.Success | Should Be $true
        Test-Path $result.InstallationPath | Should Be $true
        Test-Path (Join-Path $result.InstallationPath ".cursor-agent-patched") | Should Be $true
        $result.AppliedPatches.Count | Should BeGreaterThan 0
        
        $merkleWinNodes = Get-ChildItem -Path $result.InstallationPath -Filter "merkle-tree-napi.win32-*.node" -Recurse -ErrorAction SilentlyContinue
        $merkleWinNodes.Count | Should BeGreaterThan 0
        (Test-Path (Join-Path $result.InstallationPath "node.exe")) | Should Be $true

        $launcherPath = Join-Path $result.InstallationPath "cursor-agent.bat"
        (Test-Path $launcherPath) | Should Be $true
        $launcherOutputText = ""
        try {
            # Running with no args exercises real startup path.
            # Use cmd + <nul to avoid stdin-related hangs in non-interactive shells/CI.
            $launcherOutputText = (& cmd /c "`"$launcherPath`" <nul" 2>&1 | Out-String)
        }
        catch {
            $launcherOutputText = ($_ | Out-String)
        }
        $launcherOutputText | Should Not Match "Failed to load native binding"
    }
}
