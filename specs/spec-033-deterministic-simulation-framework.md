# Spec 33: Deterministic Simulation Testing Framework

**Module**: `tests/helpers/Simulation.psm1`

**Purpose**: Create deterministic simulations with mocked external dependencies.

**Key Functions**:
```powershell
function New-Simulation {
    param(
        [scriptblock]$Setup
    )
    [Simulation] # Returns simulation object
}

function Mock-Http {
    param(
        [hashtable]$Responses # URL -> Response mapping
    )
}

function Mock-FileSystem {
    param(
        [hashtable]$Structure # Path -> Content mapping
    )
}

function Freeze-Time {
    param([datetime]$Time)
}

function Advance-Time {
    param([TimeSpan]$Duration)
}
```

**Simulation Structure**:
```powershell
$sim = New-Simulation {
    Mock-Http {
        'https://cursor.com/install' => $InstallScript
        'https://downloads.cursor.com/...' => $PackageBytes
        'https://api.github.com/repos/.../releases/latest' => $GitHubReleaseJSON
    }
    
    Mock-FileSystem {
        TempDirectory => @{
            'package.tar.gz' => $PackageBytes
        }
        CacheDirectory => @{}
        InstallPath => @{}
    }
    
    Freeze-Time '2025-01-15 10:00:00'
    Set-Seed 42  # Deterministic randomness
}
```

**Behavior**:
1. Intercept all HTTP requests and return mocked responses
2. Intercept all file system operations and use in-memory structure
3. Control time (freeze, advance, rewind)
4. Provide deterministic random number generation
5. Allow snapshot/restore of simulation state
6. Verify final state matches expectations

**Dependencies**: None (foundation for DST)

**Success Criteria**:
- All external dependencies are mocked
- Simulations are fully deterministic
- State can be inspected and verified
- Supports complex scenarios with multiple dependencies
