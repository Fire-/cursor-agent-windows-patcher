# version-compatibility.tests.ps1
# Compatibility matrix smoke checks for multiple Cursor Agent versions.

$modulePath = Join-Path $PSScriptRoot '..\..\CursorAgentPatcher.psm1'
Import-Module $modulePath -Force

Describe "Version Compatibility Integration Tests" {
    BeforeAll {
        $script:testBaseDir = Join-Path $env:TEMP "cursor-agent-compat-test-$(Get-Random)"
        $script:testCacheDir = Join-Path $script:testBaseDir "cache"
        $script:testConfigPath = Join-Path $script:testBaseDir "compat-test-config.json"

        New-Item -ItemType Directory -Force -Path $script:testBaseDir | Out-Null
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
                defaultPath    = (Join-Path $script:testBaseDir "install")
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

        # Seed test cache from local cache when available to reduce API calls.
        $localBinaryCache = Join-Path $env:LOCALAPPDATA "cursor-agent-patcher\cache\binaries"
        $testBinaryCache = Join-Path $script:testCacheDir "binaries"
        if (Test-Path $localBinaryCache) {
            New-Item -ItemType Directory -Force -Path $testBinaryCache | Out-Null
            Copy-Item -Path (Join-Path $localBinaryCache "*") -Destination $testBinaryCache -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Determine matrix versions:
        # - COMPAT_MATRIX_VERSIONS env var: comma-separated versions to test
        # - default: current install-script version only (stable baseline)
        $envMatrix = @()
        if (-not [string]::IsNullOrWhiteSpace($env:COMPAT_MATRIX_VERSIONS)) {
            $envMatrix = $env:COMPAT_MATRIX_VERSIONS.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }

        if ($envMatrix.Count -gt 0) {
            $script:compatVersions = $envMatrix
        }
        else {
            $installScript = (Invoke-WebRequest -Uri $script:testConfig.cursorAgent.installScriptUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop).Content
            $script:compatVersions = @(
                (Get-CursorAgentVersion -InstallScript $installScript)
            )
        }
    }

    AfterAll {
        Remove-Item -Path $script:testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($compatVersion in $script:compatVersions) {
        It "Patches and loads expected native modules for version $compatVersion" {
            $installPath = Join-Path $script:testBaseDir "install-$compatVersion"
            if (Test-Path $installPath) {
                Remove-Item -Path $installPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            $result = Invoke-CursorAgentPatch -Version $compatVersion -InstallPath $installPath -ConfigPath $script:testConfigPath -ErrorAction Stop
            $result.Success | Should Be $true
            Test-Path $result.InstallationPath | Should Be $true

            $merkleWinNodes = Get-ChildItem -Path $result.InstallationPath -Filter "merkle-tree-napi.win32-*.node" -Recurse -ErrorAction SilentlyContinue
            $merkleWinNodes.Count | Should BeGreaterThan 0
            $sqliteNodes = Get-ChildItem -Path $result.InstallationPath -Filter "node_sqlite3.node" -Recurse -ErrorAction SilentlyContinue
            $sqliteNodes.Count | Should BeGreaterThan 0
        }
    }
}
