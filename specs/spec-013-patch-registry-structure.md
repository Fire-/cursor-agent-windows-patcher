# Spec 13: Patch Registry Data Structure

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Define patch registry hashtable structure.

**Structure**:
```powershell
$script:PatchRegistry = @{
    "patch-id" = @{
        Description = "Human-readable description"
        FilePattern = "**/glob/pattern.js" # PowerShell glob pattern
        Priority = 1 # Lower numbers apply first
        Dependencies = @("other-patch-id") # Patches that must run first
        Apply = {
            param(
                [string]$FilePath, # Path to file being patched
                [hashtable]$Context # Context with versions, paths, etc.
            )
            # Patch application logic
        }
        Verify = {
            param([string]$FilePath)
            # Return $true if patch was successful, $false otherwise
            return $true
        }
    }
}
```

**Validation**:
- Each patch must have: Description, FilePattern, Priority, Apply, Verify
- Dependencies must reference existing patch IDs
- Priorities must be positive integers
- Apply and Verify must be scriptblocks

**Dependencies**: None

**Success Criteria**: Registry structure is valid and can be queried
