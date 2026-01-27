# Spec 4: Fetch Cursor Agent Install Script

**Function**: `Get-CursorAgentInstallScript`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Download and return the install script from cursor.com/install.

**Signature**:
```powershell
function Get-CursorAgentInstallScript {
    [CmdletBinding()]
    param()
    [string] # Returns script content
}
```

**Behavior**:
1. Fetch `https://cursor.com/install` using `Invoke-WebRequest`
2. Return raw script content as string
3. Handle HTTP errors (404, 500, timeout)

**Error Handling**:
- Network error → Throw with URL and error details
- HTTP error status → Throw with status code and message
- Timeout → Throw with timeout duration

**Dependencies**: None (uses PowerShell built-ins)

**Success Criteria**:
- Returns script content on success
- Handles network errors with descriptive messages
- Works with PowerShell 5.1+
