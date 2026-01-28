# Spec 35: State Machine Tests for Patching Workflow

**File**: `tests/state-machines/patching-workflow.tests.ps1`

**Purpose**: State machine tests for main patching workflow (Spec 25).

**State Machine Definition**:
```powershell
$PatchingWorkflow = New-StateMachine {
    States @('Initial', 'ConfigLoaded', 'CacheInitialized', 'VersionDetected', 
             'PackageDownloaded', 'PackageExtracted', 'ContextBuilt', 
             'PatchesApplied', 'PackageInstalled', 'Error')
    
    Transitions {
        From 'Initial' To 'ConfigLoaded' When { Test-ConfigLoaded }
        From 'ConfigLoaded' To 'CacheInitialized' When { Test-CacheInitialized }
        From 'CacheInitialized' To 'VersionDetected' When { Test-VersionDetected }
        From 'VersionDetected' To 'PackageDownloaded' When { Test-PackageDownloaded }
        From 'PackageDownloaded' To 'PackageExtracted' When { Test-PackageExtracted }
        From 'PackageExtracted' To 'ContextBuilt' When { Test-ContextBuilt }
        From 'ContextBuilt' To 'PatchesApplied' When { Test-PatchesApplied }
        From 'PatchesApplied' To 'PackageInstalled' When { Test-PackageInstalled }
        From Any To 'Error' When { Test-ErrorOccurred }
    }
    
    Invariants {
        'Config always valid' { 
            $State.Config -ne $null -and $State.Config.IsValid 
        }
        'Cache directory exists' { 
            $State.CacheDirectory | Test-Path 
        }
        'Package path valid when downloaded' { 
            if ($State.CurrentState -ge 'PackageDownloaded') {
                $State.PackagePath | Test-Path
            }
        }
        'All patches applied before installation' {
            if ($State.CurrentState -ge 'PackageInstalled') {
                $State.PatchesApplied.Count -eq $State.PatchesExpected.Count
            }
        }
        'No partial installations' {
            if ($State.CurrentState -eq 'PackageInstalled') {
                $State.InstallPath | Test-Path
                (Get-ChildItem $State.InstallPath).Count -gt 0
            }
        }
    }
    
    Commands {
        'LoadConfig' { Get-PatcherConfig }
        'InitializeCache' { Initialize-CacheDirectory }
        'DetectVersion' { Get-CursorAgentVersion }
        'DownloadPackage' { Get-CursorAgentPackage }
        'ExtractPackage' { Expand-CursorAgentPackage }
        'BuildContext' { New-PatchContext }
        'ApplyPatches' { Invoke-Patch }
        'InstallPackage' { Copy-Item -Recurse }
    }
}
```

**Test Execution**:
```powershell
Describe "Patching Workflow State Machine" {
    It "Maintains invariants across all valid transitions" {
        $result = Test-StateMachine -StateMachine $PatchingWorkflow -Sequences 1000
        
        $result | Where-Object { $_.InvariantViolations.Count -gt 0 } | 
            Should -BeNullOrEmpty
    }
    
    It "Detects invalid state transitions" {
        # Force invalid transition
        $workflow.State.CurrentState = 'PackageDownloaded'
        { $workflow.Transition('ConfigLoaded') } | Should -Throw
    }
    
    It "Handles error states correctly" {
        # Simulate error at each state
        foreach ($state in $workflow.States) {
            $workflow.State.CurrentState = $state
            $workflow.Transition('Error')
            $workflow.State.CurrentState | Should -Be 'Error'
            $workflow.State.Error | Should -Not -BeNullOrEmpty
        }
    }
}
```

**Dependencies**: Spec 32, Spec 25

**Success Criteria**:
- Generates 1000+ valid command sequences
- All invariants hold across all sequences
- Invalid transitions are detected
- Error states are handled correctly
