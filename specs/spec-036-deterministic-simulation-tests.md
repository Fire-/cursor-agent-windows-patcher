# Spec 36: Deterministic Simulation Tests for Full Workflow

**File**: `tests/simulations/full-workflow.tests.ps1`

**Purpose**: End-to-end deterministic simulation tests for complete patching workflow.

**Simulation Scenarios**:

1. **Happy Path**:
   ```powershell
   Simulation "Complete patching workflow succeeds" {
       Setup {
           $sim = New-Simulation {
               Mock-Http {
                   'https://cursor.com/install' => $ValidInstallScript
                   'https://downloads.cursor.com/lab/2025.08.15-dbc8d73/darwin/arm64/agent-cli-package.tar.gz' => $ValidPackage
                   'https://api.github.com/repos/btc-vision/rust-merkle-tree/releases/latest' => $MerkleTreeRelease
                   'https://api.github.com/repos/TryGhost/node-sqlite3/releases/tags/v5.1.7' => $Sqlite3Release
                   'https://api.github.com/repos/BurntSushi/ripgrep/releases/latest' => $RipGrepRelease
               }
               Mock-FileSystem {
                   TempDirectory => @{}
                   CacheDirectory => @{}
                   InstallPath => @{}
               }
               Freeze-Time '2025-01-15 10:00:00'
           }
       }
       
       Execute {
           Invoke-CursorAgentPatch -Version "2025.08.15-dbc8d73"
       }
       
       Verify {
           $sim.FileSystem['InstallPath\index.js'] | Should -Exist
           $sim.FileSystem['InstallPath\rg.exe'] | Should -Exist
           $sim.FileSystem['InstallPath\cursor-agent.bat'] | Should -Exist
           $sim.FileSystem['InstallPath\qfpzq242.node'] | Should -Exist
           $sim.FileSystem['InstallPath\kkkzjw1t.node'] | Should -Exist
           $sim.Cache['binaries'] | Should -HaveCount 3
           $sim.HttpRequests.Count | Should -Be 5
       }
   }
   ```

2. **Network Error Recovery**:
   ```powershell
   Simulation "Handles network errors gracefully" {
       Setup {
           $sim = New-Simulation {
               Mock-Http {
                   'https://cursor.com/install' => { throw "Network error" }
               }
           }
       }
       
       Execute {
           { Invoke-CursorAgentPatch } | Should -Throw
       }
       
       Verify {
           $sim.State.CurrentState | Should -Be 'Error'
           $sim.State.Error | Should -Match 'Network error'
       }
   }
   ```

3. **Version Mismatch Handling**:
   ```powershell
   Simulation "Handles version mismatches" {
       Setup {
           $sim = New-Simulation {
               Mock-Http {
                   'https://cursor.com/install' => $InstallScriptWithVersion
                   'https://downloads.cursor.com/lab/...' => $PackageWithDifferentVersion
               }
           }
       }
       
       Execute {
           Invoke-CursorAgentPatch -Version "2025.08.15-dbc8d73"
       }
       
       Verify {
           # Should either fail gracefully or use fallback versions
           if ($sim.State.CurrentState -eq 'Error') {
               $sim.State.Error | Should -Match 'version'
           } else {
               $sim.State.DependencyVersions | Should -Not -BeNullOrEmpty
           }
       }
   }
   ```

**Dependencies**: Spec 33, Spec 25

**Success Criteria**:
- All scenarios execute deterministically
- Final state matches expectations
- Error scenarios are handled correctly
- Simulations are reproducible (same seed = same results)
