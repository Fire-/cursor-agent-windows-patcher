# Testing Guide

This document describes how to test the Cursor Agent Windows Patcher project.

## Overview

The project uses **Pester** (PowerShell testing framework) with three specialized testing approaches:

1. **Property-Based Tests** - Generate random inputs and verify properties hold
2. **State Machine Tests** - Verify workflow state transitions and invariants
3. **Simulation Tests** - End-to-end tests with mocked dependencies

## Prerequisites

- **PowerShell 5.1+** (required)
- **Pester 3.4.0+** (install with: `Install-Module -Name Pester -Force -SkipPublisherCheck`)
- **CursorAgentPatcher.psm1** module in project root

## Quick Start

### Run All Tests

```powershell
cd c:\Users\us\tools\code\cursor-agent-windows-patcher
Invoke-Pester -Path tests\
```

### Run Specific Test Suites

```powershell
# Property-based tests only
Invoke-Pester -Path tests\properties\

# State machine tests only
Invoke-Pester -Path tests\state-machines\

# Simulation tests only
Invoke-Pester -Path tests\simulations\
```

### Run Specific Test File

```powershell
Invoke-Pester -Path tests\properties\version-extraction.tests.ps1
```

## Test Structure

```
tests/
├── helpers/                    # Testing framework modules
│   ├── PropertyTest.psm1      # Property-based testing framework
│   ├── StateMachine.psm1      # State machine testing framework
│   └── Simulation.psm1        # Deterministic simulation framework
├── properties/                 # Property-based tests
│   └── version-extraction.tests.ps1
├── state-machines/             # State machine tests
│   └── patching-workflow.tests.ps1
└── simulations/               # Simulation tests
    └── full-workflow.tests.ps1
```

## Test Types

### 1. Property-Based Tests

Property-based tests generate random inputs and verify that certain properties always hold true.

**Location:** `tests/properties/`

**Example:**
```powershell
Property "Extracted version matches input format" {
    param([string]$Version)
    $script = "DOWNLOAD_URL=`"https://downloads.cursor.com/lab/$Version/darwin/arm64/package.tar.gz`""
    $extracted = Get-CursorAgentVersion -InstallScript $script
    $extracted | Should -Be $Version
} -ForAll @{
    Version = Gen-VersionString
} -Tests 100
```

**Available Generators:**
- `Gen-Integer` - Random integers
- `Gen-String` - Random strings
- `Gen-VersionString` - Cursor Agent version strings (YYYY.MM.DD-hash)
- `Gen-SemanticVersion` - Semantic versions (major.minor.patch)
- `Gen-FilePath` - Valid file paths
- `Gen-JSON` - JSON structures
- `Gen-Choice` - Choose from array of values

**Features:**
- Generates 100+ test cases automatically
- Shrinks counterexamples to minimal cases
- Supports seeded random generation for reproducibility

### 2. State Machine Tests

State machine tests verify that workflow state transitions are valid and invariants are maintained.

**Location:** `tests/state-machines/`

**Example:**
```powershell
$workflow = New-StateMachine {
    $States = @('Initial', 'ConfigLoaded', 'CacheInitialized', 'VersionDetected')
    $Transitions = @{
        'Initial->ConfigLoaded' = { $true }
        'ConfigLoaded->CacheInitialized' = { $true }
    }
    $Invariants = @{
        'Config always valid' = { $State.Config -ne $null }
    }
}

$results = Test-StateMachine -StateMachine $workflow -Sequences 1000
```

**Features:**
- Validates state transitions
- Checks invariants after each transition
- Detects invalid transitions and invariant violations
- Generates valid command sequences automatically

### 3. Simulation Tests

Simulation tests provide end-to-end testing with mocked HTTP, file system, and time dependencies.

**Location:** `tests/simulations/`

**Example:**
```powershell
$sim = New-Simulation {
    Mock-Http @{
        'https://cursor.com/install' = $ValidInstallScript
    }
    Mock-FileSystem @{
        'C:\test\file.txt' = 'Test content'
    }
    Freeze-Time (Get-Date)
    Set-Seed 42
}
```

**Features:**
- Mocks HTTP requests/responses
- Mocks file system operations
- Controls time for deterministic testing
- Provides deterministic randomness via seeds
- Supports snapshot/restore for complex scenarios

## Test Options

### Verbose Output

```powershell
Invoke-Pester -Path tests\ -Verbose
```

### Code Coverage

```powershell
Invoke-Pester -Path tests\ -CodeCoverage CursorAgentPatcher.psm1
```

### Output to File

```powershell
# NUnit XML format (for CI/CD)
Invoke-Pester -Path tests\ -OutputFile test-results.xml -OutputFormat NUnitXml

# JUnit XML format
Invoke-Pester -Path tests\ -OutputFile test-results.xml -OutputFormat JUnitXml
```

### Run Specific Test

```powershell
Invoke-Pester -Path tests\properties\version-extraction.tests.ps1 -TestName "Extracted version matches input format"
```

### Watch Mode (Pester 5+)

```powershell
Invoke-Pester -Path tests\ -Watch
```

## Writing Tests

### Property-Based Test Example

```powershell
Describe "My Function Properties" {
    It "Property name" {
        $result = Property "Property description" {
            param($Input1, $Input2)
            # Test logic here
            $output = My-Function -Input1 $Input1 -Input2 $Input2
            $output | Should -Not -BeNullOrEmpty
        } -ForAll @{
            Input1 = Gen-Integer -Min 0 -Max 100
            Input2 = Gen-String -MinLength 1 -MaxLength 50
        } -Tests 100
        
        $result.Success | Should -Be $true
    }
}
```

### State Machine Test Example

```powershell
Describe "Workflow State Machine" {
    BeforeAll {
        $script:workflow = New-StateMachine {
            $States = @('State1', 'State2', 'State3')
            $Transitions = @{
                'State1->State2' = { $State.Condition -eq $true }
            }
            $Invariants = @{
                'Invariant name' = { $State.Value -ne $null }
            }
            $Commands = @{
                'Command1' = { $State.Value = 'test' }
            }
        }
    }
    
    It "Maintains invariants" {
        $results = Test-StateMachine -StateMachine $script:workflow -Sequences 100
        $failures = $results | Where-Object { -not $_.Success }
        $failures | Should -BeNullOrEmpty
    }
}
```

### Simulation Test Example

```powershell
Describe "Function with Dependencies" {
    It "Handles mocked dependencies" {
        $sim = New-Simulation {
            Mock-Http @{
                'https://api.example.com/data' = @{
                    status = 'ok'
                    data = 'test'
                } | ConvertTo-Json
            }
            Mock-FileSystem @{
                'C:\config.json' = '{"key": "value"}'
            }
            Set-Seed 42
        }
        
        # Test your function with mocked dependencies
        $result = My-Function -ConfigPath 'C:\config.json'
        $result | Should -Not -BeNullOrEmpty
    }
}
```

## Test Best Practices

1. **Use descriptive test names** - Test names should clearly describe what is being tested
2. **Validate inputs** - Property tests should validate generated inputs before using them
3. **Handle edge cases** - Test boundary conditions and error cases
4. **Keep tests isolated** - Each test should be independent and not rely on other tests
5. **Use appropriate test types** - Choose property-based, state machine, or simulation tests based on what you're testing
6. **Mock external dependencies** - Use simulation framework for HTTP, file system, etc.
7. **Set seeds for reproducibility** - Use `Set-Seed` or `-Seed` parameter for deterministic tests
8. **Clean up resources** - Use `BeforeEach`/`AfterEach` to set up and tear down test data

## Troubleshooting

### Tests Fail with "Module not found"

Ensure the module is imported:
```powershell
Import-Module .\CursorAgentPatcher.psm1 -Force
```

### Property Tests Generate Invalid Inputs

Check that generators are producing valid values:
```powershell
$gen = Gen-VersionString
$value = $gen.Generate.Invoke((New-Object System.Random))
Write-Host "Generated: $value"
```

### State Machine Tests Fail on Transitions

Verify transition conditions are correct:
```powershell
$workflow.Transitions['State1->State2'].Invoke($workflow.State)
```

### Simulation Tests Don't Mock Correctly

Ensure HTTP URLs match exactly (case-sensitive):
```powershell
$sim.GetHttpResponse('https://exact-url.com')
```

## Known Issues

### Property Test Generator Objects

If property tests are receiving generator objects instead of generated values, this indicates the generator's `Generate` scriptblock is not being invoked correctly. The Property function should automatically handle this, but if issues persist:

1. Verify the generator's `Generate` scriptblock is properly defined
2. Check that the RNG is being passed correctly
3. Ensure the generated value is stored, not the generator object

## Continuous Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install Pester
        run: Install-Module -Name Pester -Force -SkipPublisherCheck
      - name: Run Tests
        run: Invoke-Pester -Path tests\ -OutputFile test-results.xml -OutputFormat NUnitXml
      - name: Publish Test Results
        uses: EnricoMi/publish-unit-test-result-action@v1
        if: always()
        with:
          files: test-results.xml
```

## Resources

- [Pester Documentation](https://pester.dev/)
- [Property-Based Testing](https://hypothesis.works/articles/what-is-property-based-testing/)
- [State Machine Testing](https://www.cs.cmu.edu/~aldrich/courses/654/tools/quickcheck-manual.pdf)
