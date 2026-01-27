# Spec 10: Get GitHub Release Asset Function

**Function**: `Get-GitHubReleaseAsset`

**Module**: `CursorAgentPatcher.psm1`

**Purpose**: Find and download a specific asset from a GitHub release.

**Signature**:
```powershell
function Get-GitHubReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Repo, # e.g., "btc-vision/rust-merkle-tree"
        
        [Parameter(Mandatory=$true)]
        [string]$AssetPattern, # Regex pattern to match asset name
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath,
        
        [Parameter(Mandatory=$false)]
        [string]$ReleaseTag = "latest" # "latest" or specific tag like "v1.2.3"
    )
    [void]
}
```

**Behavior**:
1. Construct GitHub API URL:
   - Latest: `https://api.github.com/repos/$Repo/releases/latest`
   - Specific: `https://api.github.com/repos/$Repo/releases/tags/$ReleaseTag`
2. Fetch release metadata using `Invoke-RestMethod`
3. Filter assets by `$AssetPattern` regex
4. If multiple matches, prefer Windows-specific assets, then take first
5. Download matched asset using `Get-FileWithProgress`
6. Save to `$OutPath`

**Error Handling**:
- API error → Throw with repo and error details
- No matching asset → Throw listing available assets
- Multiple matches → Use first, log warning if verbose
- Download fails → Propagate error from `Get-FileWithProgress`

**Dependencies**: Spec 9

**Success Criteria**:
- Finds and downloads correct asset
- Handles "latest" and specific tags
- Provides clear errors when asset not found
- Prefers Windows-specific assets when multiple match
