# Spec 32: State Machine Testing Framework

**Module**: `tests/helpers/StateMachine.psm1`

**Purpose**: Define and test state machines for workflow validation.

**Key Functions**:
```powershell
function New-StateMachine {
    param(
        [scriptblock]$Definition
    )
    [StateMachine] # Returns state machine object
}

function Test-StateMachine {
    param(
        [StateMachine]$StateMachine,
        [int]$Sequences = 100,
        [int]$MaxCommands = 50
    )
    [TestResult[]]
}

function Invariant {
    param(
        [string]$Name,
        [scriptblock]$Check
    )
}
```

**State Machine Definition Syntax**:
```powershell
$StateMachine = New-StateMachine {
    States @('Initial', 'Downloaded', 'Extracted', 'Patched', 'Installed', 'Error')
    
    Transitions {
        From 'Initial' To 'Downloaded' When { Test-DownloadComplete }
        From 'Downloaded' To 'Extracted' When { Test-ExtractionComplete }
        From 'Extracted' To 'Patched' When { Test-PatchingComplete }
        From 'Patched' To 'Installed' When { Test-InstallationComplete }
        From Any To 'Error' When { Test-ErrorOccurred }
    }
    
    Invariants {
        'Package path valid' { $State.PackagePath | Test-Path }
        'No partial state' { $State.IsConsistent }
    }
    
    Commands {
        'Download' { Download-Package }
        'Extract' { Extract-Package }
        'Patch' { Apply-Patches }
        'Install' { Install-Package }
    }
}
```

**Behavior**:
1. Generate valid command sequences (respecting state transitions)
2. Execute commands in sequence
3. Verify invariants after each transition
4. Detect invalid states and transitions
5. Report any invariant violations

**Dependencies**: Spec 31 (uses property-based testing for sequence generation)

**Success Criteria**:
- Generates valid command sequences
- Detects invariant violations
- Reports state transition errors
- Supports parallel state machines
