# Spec 2: Load and Validate Configuration Function

**Function**: `Get-PatcherConfig`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Load configuration from JSON file with validation and environment variable expansion.

**Signature**:
```powershell
function Get-PatcherConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = ".\patcher-config.json"
    )
    [PSCustomObject] # Returns validated config object
}
```

**Behavior**:
1. Read JSON file from `$ConfigPath`
2. Expand environment variables in paths (e.g., `%LOCALAPPDATA%`)
3. Validate required keys exist
4. Validate regex patterns are valid
5. Return PSCustomObject with typed properties

**Error Handling**:
- File not found → Throw with clear message
- Invalid JSON → Throw with parse error details
- Missing required keys → Throw listing missing keys
- Invalid regex → Throw with pattern and error

**Dependencies**: Spec 1

**Success Criteria**: 
- Returns valid config object when file exists and is valid
- Throws descriptive errors for invalid configurations
- Expands environment variables correctly
