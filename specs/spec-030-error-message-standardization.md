# Spec 30: Error Message Standardization

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Consistent error messaging across all functions.

**Error Format**:
```powershell
Write-Error "FunctionName: Description of what failed. Additional context: $variable"
```

**Error Categories**:
- **Configuration errors**: Missing or invalid config
- **Network errors**: Download failures, API errors
- **File system errors**: Path issues, permission problems
- **Patch errors**: Application failures, verification failures
- **Validation errors**: Invalid input, missing dependencies

**Dependencies**: All function specs

**Success Criteria**:
- All errors follow consistent format
- Errors include function name and context
- Errors are actionable (tell user what to do)
