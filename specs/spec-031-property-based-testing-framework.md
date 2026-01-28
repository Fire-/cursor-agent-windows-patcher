# Spec 31: Property-Based Testing Framework

**Module**: `tests/helpers/PropertyTest.psm1`

**Purpose**: Provide property-based testing framework similar to FsCheck/QuickCheck for PowerShell.

**Key Functions**:
```powershell
function Property {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [hashtable]$ForAll # Generators for each parameter
    )
}

function Gen-VersionString { ... }      # Generate version strings like "2025.08.15-dbc8d73"
function Gen-SemanticVersion { ... }     # Generate semantic versions like "5.1.7"
function Gen-FilePath { ... }            # Generate valid file paths
function Gen-JSON { ... }                # Generate valid JSON structures
function Gen-String { ... }              # Generate strings with constraints
function Gen-Integer { ... }             # Generate integers in range
function Gen-Choice { ... }              # Choose from array of values
```

**Behavior**:
1. Generate random inputs using generators
2. Run test scriptblock with generated inputs
3. If test fails, attempt to shrink inputs to minimal counterexample
4. Report results with generated inputs and any failures

**Shrinking Strategy**:
- Strings: Remove characters, shorten length
- Numbers: Move toward zero, reduce magnitude
- Collections: Remove elements, reduce size
- Composite types: Shrink individual components

**Dependencies**: None (foundation for all property tests)

**Success Criteria**:
- Generates diverse test inputs
- Shrinks counterexamples effectively
- Integrates with Pester test framework
- Provides clear failure reports

**Testing Approach**: Test the testing framework itself using property-based tests (metacircular)
