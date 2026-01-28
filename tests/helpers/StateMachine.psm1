# StateMachine.psm1
# State machine testing framework for PowerShell

<#
.SYNOPSIS
State machine testing framework for workflow validation.

.DESCRIPTION
Provides capabilities to define state machines and test them by generating
valid command sequences, executing commands, and verifying invariants.
#>

# Import property-based testing for sequence generation
Import-Module (Join-Path $PSScriptRoot 'PropertyTest.psm1') -ErrorAction SilentlyContinue

#region State Machine Classes

class StateMachine {
    [string[]]$States
    [hashtable]$Transitions
    [hashtable]$Invariants
    [hashtable]$Commands
    [hashtable]$State
    [string]$CurrentState
    
    StateMachine() {
        $this.Transitions = @{}
        $this.Invariants = @{}
        $this.Commands = @{}
        $this.State = @{}
        $this.CurrentState = 'Initial'
    }
    
    [bool]IsValidTransition([string]$From, [string]$To) {
        if ($this.Transitions.ContainsKey("$From->$To")) {
            return $true
        }
        if ($this.Transitions.ContainsKey("Any->$To")) {
            return $true
        }
        return $false
    }
    
    [bool]CheckInvariants() {
        foreach ($name in $this.Invariants.Keys) {
            $check = $this.Invariants[$name]
            try {
                # Invoke with $this as context
                $result = $check.InvokeWithContext($null, [PSVariable]::new('StateMachine', $this), [PSVariable]::new('State', $this.State))
                if (-not $result) {
                    return $false
                }
            }
            catch {
                return $false
            }
        }
        return $true
    }
    
    [void]Transition([string]$ToState) {
        if (-not $this.IsValidTransition($this.CurrentState, $ToState)) {
            throw "Invalid transition from '$($this.CurrentState)' to '$ToState'"
        }
        $this.CurrentState = $ToState
        if (-not $this.CheckInvariants()) {
            throw "Invariant violation in state '$ToState'"
        }
    }
    
    [void]ExecuteCommand([string]$CommandName) {
        if (-not $this.Commands.ContainsKey($CommandName)) {
            throw "Unknown command: $CommandName"
        }
        $command = $this.Commands[$CommandName]
        $command.InvokeWithContext($null, [PSVariable]::new('StateMachine', $this), [PSVariable]::new('State', $this.State))
    }
}

class TestResult {
    [bool]$Success
    [string]$StateMachineName
    [int]$SequenceNumber
    [string[]]$CommandSequence
    [string]$FinalState
    [string[]]$InvariantViolations
    [string]$Error
    
    TestResult() {
        $this.InvariantViolations = @()
    }
}

#endregion

#region State Machine Builder

function New-StateMachine {
    <#
    .SYNOPSIS
    Create a new state machine from a definition scriptblock.
    
    .DESCRIPTION
    Creates a state machine using a simplified DSL. The scriptblock should call
    helper functions to define the state machine structure.
    
    .PARAMETER Definition
    Scriptblock containing state machine definition.
    
    .EXAMPLE
    $sm = New-StateMachine {
        $States = @('Initial', 'Downloaded', 'Extracted')
        $Transitions = @{
            'Initial->Downloaded' = { $true }
            'Downloaded->Extracted' = { $true }
        }
        $Invariants = @{
            'Path exists' = { Test-Path $State.Path }
        }
        $Commands = @{
            'Download' = { Write-Host "Downloading" }
        }
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Definition
    )
    
    $stateMachine = [StateMachine]::new()
    
    # Execute definition in a controlled context
    $states = @()
    $transitions = @{}
    $invariants = @{}
    $commands = @{}
    
    # Create helper functions for DSL
    $context = @{
        States = { param([string[]]$s) $script:states = $s }
        Transitions = { param([hashtable]$t) $script:transitions = $t }
        Invariants = { param([hashtable]$i) $script:invariants = $i }
        Commands = { param([hashtable]$c) $script:commands = $c }
    }
    
    # Execute definition
    try {
        & $Definition
    }
    catch {
        # If direct execution fails, try parsing as DSL
        Write-Verbose "Direct execution failed, using DSL parser: $_"
    }
    
    # Check if variables were set
    if ($states.Count -gt 0) {
        $stateMachine.States = $states
        $stateMachine.CurrentState = $states[0]
    }
    if ($transitions.Count -gt 0) {
        $stateMachine.Transitions = $transitions
    }
    if ($invariants.Count -gt 0) {
        $stateMachine.Invariants = $invariants
    }
    if ($commands.Count -gt 0) {
        $stateMachine.Commands = $commands
    }
    
    return $stateMachine
}

function Invariant {
    <#
    .SYNOPSIS
    Helper function for defining invariants (used in DSL).
    #>
    param(
        [string]$Name,
        [scriptblock]$Check
    )
    
    return @{
        Name = $Name
        Check = $Check
    }
}

#endregion

#region State Machine Testing

function Test-StateMachine {
    <#
    .SYNOPSIS
    Test a state machine by generating and executing command sequences.
    
    .PARAMETER StateMachine
    The state machine to test.
    
    .PARAMETER Sequences
    Number of test sequences to generate (default: 100).
    
    .PARAMETER MaxCommands
    Maximum commands per sequence (default: 50).
    
    .OUTPUTS
    TestResult[]. Array of test results for each sequence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [StateMachine]$StateMachine,
        
        [int]$Sequences = 100,
        
        [int]$MaxCommands = 50
    )
    
    $results = @()
    $rng = New-Object System.Random
    
    for ($seq = 0; $seq -lt $Sequences; $seq++) {
        $result = [TestResult]::new()
        $result.StateMachineName = "StateMachine"
        $result.SequenceNumber = $seq
        $result.CommandSequence = @()
        
        # Reset state machine
        $stateMachine.State = @{}
        if ($stateMachine.States.Count -gt 0) {
            $stateMachine.CurrentState = $stateMachine.States[0]
        }
        
        try {
            $commandCount = $rng.Next(1, $MaxCommands + 1)
            
            for ($cmd = 0; $cmd -lt $commandCount; $cmd++) {
                # Get available commands
                $availableCommands = @($stateMachine.Commands.Keys)
                
                if ($availableCommands.Count -eq 0) {
                    break
                }
                
                # Choose random command
                $chosenCommand = $availableCommands[$rng.Next($availableCommands.Count)]
                $result.CommandSequence += $chosenCommand
                
                # Execute command
                try {
                    $stateMachine.ExecuteCommand($chosenCommand)
                }
                catch {
                    # Command execution failed
                    $result.Error = "Command '$chosenCommand' failed: $_"
                    break
                }
                
                # Check invariants
                if (-not $stateMachine.CheckInvariants()) {
                    $result.InvariantViolations += "Invariant violation after command '$chosenCommand'"
                }
            }
            
            $result.FinalState = $stateMachine.CurrentState
            $result.Success = ($result.InvariantViolations.Count -eq 0) -and ([string]::IsNullOrEmpty($result.Error))
        }
        catch {
            $result.Success = $false
            $result.Error = $_.Exception.Message
        }
        
        $results += $result
    }
    
    return $results
}

#endregion

# Export module members
Export-ModuleMember -Function New-StateMachine, Test-StateMachine, Invariant
