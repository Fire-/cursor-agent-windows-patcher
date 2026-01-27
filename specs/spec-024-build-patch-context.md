# Spec 24: Build Patch Context Function

**Function**: `New-PatchContext`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Build context hashtable with all information needed for patches.

**Signature**:
```powershell
function New-PatchContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath,
        
        [Parameter(Mandatory=$true)]
        [string]$CursorAgentVersion,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$DependencyVersions = @{},
        
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory
    )
    [hashtable] # Returns context object
}
```

**Behavior**:
1. Detect Windows architecture (x64 or arm64)
2. Extract dependency versions if not provided (call Specs 6-8)
3. Download/cache Windows binaries (call Specs 10-12)
4. Build context hashtable:
   ```powershell
   @{
       PackagePath = $PackagePath
       CursorAgentVersion = $CursorAgentVersion
       WindowsArchitecture = "x64" or "arm64"
       DependencyVersions = @{
           sqlite3 = "5.1.7"
           merkleTree = "1.2.3"
           ripgrep = "13.0.0"
       }
       WindowsBinaries = @{
           sqlite3 = "C:\path\to\cached\binary.node"
           merkleTree = "C:\path\to\cached\binary.node"
           ripgrep = "C:\path\to\cached\ripgrep.zip"
       }
       CacheDirectory = $CacheDirectory
   }
   ```

**Error Handling**:
- Version extraction fails → Use defaults from config
- Binary download fails → Throw with dependency name and error
- Architecture detection fails → Default to x64

**Dependencies**: Specs 6-8, Specs 10-12, Spec 2

**Success Criteria**:
- Builds complete context with all required information
- Handles missing versions gracefully
- Downloads and caches binaries successfully
