# Spec 5: Extract Cursor Agent Version from Install Script

**Function**: `Get-CursorAgentVersion`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Parse install script to extract version string (e.g., `2025.08.15-dbc8d73`).

**Signature**:
```powershell
function Get-CursorAgentVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallScript
    )
    [string] # Returns version string
}
```

**Behavior**:
1. Search for version pattern in install script
2. Pattern: `DOWNLOAD_URL="https://downloads.cursor.com/lab/([^/]+)/`
3. Extract version from first capture group
4. Validate format: `YYYY.MM.DD-{hash}`

**Error Handling**:
- Version not found → Throw with message showing search context
- Invalid format → Throw with extracted value and expected format

**Dependencies**: Spec 4

**Success Criteria**:
- Extracts version string from valid install script
- Returns null or throws on invalid/missing version
- Handles multiple URL patterns if script format changes

**Testing**:
- Property-based: Version format preservation (Spec 34)
- Property-based: Idempotency (Spec 34)
- Unit tests: Edge cases (malformed scripts, missing URLs)
