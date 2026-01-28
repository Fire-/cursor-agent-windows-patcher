# Spec 34: Property Tests for Version Extraction

**File**: `tests/properties/version-extraction.tests.ps1`

**Purpose**: Property-based tests for version extraction functions (Specs 5-8).

**Properties to Test**:

1. **Version Format Preservation**:
   ```powershell
   Property "Extracted version matches input format" {
       param([string]$Version)
       $script = "DOWNLOAD_URL=`"https://downloads.cursor.com/lab/$Version/darwin/arm64/package.tar.gz`""
       $extracted = Get-CursorAgentVersion -InstallScript $script
       $extracted | Should -Be $Version
   } -ForAll (Gen-VersionString)
   ```

2. **Version Extraction Idempotency**:
   ```powershell
   Property "Version extraction is idempotent" {
       param([string]$Script)
       $v1 = Get-CursorAgentVersion -InstallScript $Script
       $v2 = Get-CursorAgentVersion -InstallScript $Script
       $v1 | Should -Be $v2
   } -ForAll (Gen-InstallScript)
   ```

3. **SQLite3 Version Extraction**:
   ```powershell
   Property "SQLite3 version extracted correctly" {
       param([string]$Version, [string]$PackageContent)
       $package = Create-TestPackage -Sqlite3Version $Version -Content $PackageContent
       $extracted = Get-Sqlite3Version -PackagePath $package
       $extracted | Should -Be $Version
   } -ForAll (Gen-SemanticVersion, Gen-PackageContent)
   ```

4. **Merkle Tree Version Extraction**:
   ```powershell
   Property "Merkle tree version extracted correctly" {
       param([string]$Version, [string]$PackageContent)
       $package = Create-TestPackage -MerkleTreeVersion $Version -Content $PackageContent
       $extracted = Get-MerkleTreeVersion -PackagePath $package
       $extracted | Should -Be $Version
   } -ForAll (Gen-SemanticVersion, Gen-PackageContent)
   ```

**Dependencies**: Spec 31, Specs 5-8

**Success Criteria**:
- All properties pass with 1000+ generated test cases
- Counterexamples are shrunk to minimal cases
- Tests cover edge cases (missing versions, malformed input, etc.)
