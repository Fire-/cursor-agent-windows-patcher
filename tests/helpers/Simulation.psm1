# Simulation.psm1
# Deterministic simulation testing framework for PowerShell

<#
.SYNOPSIS
Deterministic simulation testing framework with mocked external dependencies.

.DESCRIPTION
Provides capabilities to create deterministic simulations by mocking HTTP requests,
file system operations, time, and random number generation.
#>

#region Simulation Classes

class Simulation {
    [hashtable]$HttpResponses
    [hashtable]$FileSystem
    [datetime]$CurrentTime
    [bool]$TimeFrozen
    [System.Random]$Random
    [hashtable]$State
    [System.Collections.ArrayList]$HttpRequests
    
    Simulation() {
        $this.HttpResponses = @{}
        $this.FileSystem = @{}
        $this.CurrentTime = Get-Date
        $this.TimeFrozen = $false
        $this.Random = New-Object System.Random
        $this.State = @{}
        $this.HttpRequests = [System.Collections.ArrayList]::new()
    }
    
    [void]SetSeed([int]$Seed) {
        $this.Random = New-Object System.Random $Seed
    }
    
    [void]FreezeTime([datetime]$Time) {
        $this.CurrentTime = $Time
        $this.TimeFrozen = $true
    }
    
    [void]AdvanceTime([TimeSpan]$Duration) {
        if ($this.TimeFrozen) {
            $this.CurrentTime = $this.CurrentTime.Add($Duration)
        }
    }
    
    [object]GetHttpResponse([string]$Url) {
        $this.HttpRequests.Add($Url) | Out-Null
        if ($this.HttpResponses.ContainsKey($Url)) {
            $response = $this.HttpResponses[$Url]
            if ($response -is [scriptblock]) {
                return & $response
            }
            return $response
        }
        throw "No mock response for URL: $Url"
    }
    
    [bool]FileExists([string]$Path) {
        return $this.FileSystem.ContainsKey($Path)
    }
    
    [object]ReadFile([string]$Path) {
        if ($this.FileSystem.ContainsKey($Path)) {
            return $this.FileSystem[$Path]
        }
        throw "File not found: $Path"
    }
    
    [void]WriteFile([string]$Path, [object]$Content) {
        $this.FileSystem[$Path] = $Content
    }
    
    [void]CreateDirectory([string]$Path) {
        if (-not $this.FileSystem.ContainsKey($Path)) {
            $this.FileSystem[$Path] = @{}
        }
    }
    
    [hashtable]GetSnapshot() {
        return @{
            HttpResponses = $this.HttpResponses.Clone()
            FileSystem = $this.FileSystem.Clone()
            CurrentTime = $this.CurrentTime
            State = $this.State.Clone()
        }
    }
    
    [void]RestoreSnapshot([hashtable]$Snapshot) {
        $this.HttpResponses = $Snapshot.HttpResponses.Clone()
        $this.FileSystem = $Snapshot.FileSystem.Clone()
        $this.CurrentTime = $Snapshot.CurrentTime
        $this.State = $Snapshot.State.Clone()
    }
}

#endregion

#region Simulation Functions

function New-Simulation {
    <#
    .SYNOPSIS
    Create a new deterministic simulation.
    
    .DESCRIPTION
    Creates a simulation object with mocked HTTP, file system, time, and random number generation.
    
    .PARAMETER Setup
    Scriptblock containing simulation setup (Mock-Http, Mock-FileSystem, Freeze-Time, etc.)
    
    .EXAMPLE
    $sim = New-Simulation {
        Mock-Http @{
            'https://example.com' = 'Response content'
        }
        Mock-FileSystem @{
            'C:\temp\file.txt' = 'File content'
        }
        Freeze-Time (Get-Date)
        Set-Seed 42
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Setup
    )
    
    $simulation = [Simulation]::new()
    
    # Set context variable to indicate we're in setup
    $script:InSimulationSetup = $true
    $script:CurrentSimulation = $simulation
    
    try {
        # Execute setup scriptblock - functions will check $script:InSimulationSetup
        & $Setup
    }
    finally {
        # Clear context
        $script:InSimulationSetup = $false
        $script:CurrentSimulation = $null
    }
    
    return $simulation
}

function Mock-Http {
    <#
    .SYNOPSIS
    Mock HTTP responses in a simulation (used in setup scriptblock).
    #>
    param(
        [hashtable]$Responses
    )
    if ($script:InSimulationSetup -and $script:CurrentSimulation) {
        $script:CurrentSimulation.HttpResponses = $Responses
    }
    else {
        throw "Mock-Http must be called within New-Simulation setup scriptblock"
    }
}

function Mock-FileSystem {
    <#
    .SYNOPSIS
    Mock file system structure in a simulation (used in setup scriptblock).
    #>
    param(
        [hashtable]$Structure
    )
    if ($script:InSimulationSetup -and $script:CurrentSimulation) {
        $script:CurrentSimulation.FileSystem = $Structure
    }
    else {
        throw "Mock-FileSystem must be called within New-Simulation setup scriptblock"
    }
}

function Freeze-Time {
    <#
    .SYNOPSIS
    Freeze time in a simulation (used in setup scriptblock).
    #>
    param([datetime]$Time)
    if ($script:InSimulationSetup -and $script:CurrentSimulation) {
        $script:CurrentSimulation.FreezeTime($Time)
    }
    else {
        throw "Freeze-Time must be called within New-Simulation setup scriptblock"
    }
}

function Advance-Time {
    <#
    .SYNOPSIS
    Advance time in a simulation (used in setup scriptblock).
    #>
    param([TimeSpan]$Duration)
    # This function is used within New-Simulation setup scriptblock
    throw "Advance-Time must be called within New-Simulation setup scriptblock"
}

#endregion

function Set-Seed {
    <#
    .SYNOPSIS
    Set random seed in a simulation (used in setup scriptblock).
    #>
    param([int]$Seed)
    if ($script:InSimulationSetup -and $script:CurrentSimulation) {
        $script:CurrentSimulation.SetSeed($Seed)
    }
    else {
        throw "Set-Seed must be called within New-Simulation setup scriptblock"
    }
}

# Export module members
Export-ModuleMember -Function New-Simulation, Mock-Http, Mock-FileSystem, Freeze-Time, Advance-Time, Set-Seed
