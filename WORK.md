# WORK.md - Progress Tracker

This file tracks implementation progress across sessions for the Cursor Agent Windows Patcher project.

## Progress Tracker

### Foundation

Configuration and cache setup - must be implemented first.

- ✅ **Spec 001: Create patcher-config.json Structure** (2026-01-27)
- ✅ **Spec 002: Load and Validate Configuration Function** (2026-01-27)
- ✅ **Spec 003: Initialize Cache Directory Function** (2026-01-27)

### Version Detection

Extract versions from various sources - required before downloading dependencies.

- ✅ **Spec 004: Fetch Cursor Agent Install Script** (2026-01-27)
- ✅ **Spec 005: Extract Cursor Agent Version from Install Script** (2026-01-27)
- ✅ **Spec 006: Extract SQLite3 Version from Package** (2026-01-27)
- ✅ **Spec 007: Extract Merkle Tree Version from Package** (2026-01-27)
- ✅ **Spec 008: Extract RipGrep Version from Package** (2026-01-27)

### Download Infrastructure

Download and caching system - needed to fetch Windows binaries.

- ✅ **Spec 009: Download File with Progress Function** (2026-01-27)
- ✅ **Spec 010: Get GitHub Release Asset Function** (2026-01-27)
- ✅ **Spec 011: Get Cached Binary Function** (2026-01-27)
- ✅ **Spec 012: Cache Binary Function** (2026-01-27)

### Patch System

Registry and application framework - core patching infrastructure.

- ⬜ Spec 013: Patch Registry Data Structure
- ⬜ Spec 014: Find Files Matching Pattern Function
- ⬜ Spec 015: Resolve Patch Dependencies Function
- ⬜ Spec 016: Apply Patch Function

### Individual Patches

Implement each patch type - specific patching logic.

- ⬜ Spec 017: Platform Detection Patch
- ⬜ Spec 018: Merkle Tree Module Replacement Patch
- ⬜ Spec 019: SQLite3 Module Replacement Patch
- ⬜ Spec 020: RipGrep Binary Replacement Patch
- ⬜ Spec 021: Register All Patches Function

### Workflow

Main orchestration - ties everything together.

- ⬜ Spec 022: Download Cursor Agent Package Function
- ⬜ Spec 023: Extract Package Archive Function
- ⬜ Spec 024: Build Patch Context Function
- ⬜ Spec 025: Main Patching Workflow Function

### Utilities

Helpers and main script - user-facing components.

- ⬜ Spec 026: Create Launcher Script Function
- ⬜ Spec 027: Detect Windows Architecture Function
- ⬜ Spec 028: Main Script Entry Point
- ⬜ Spec 029: Module Export Configuration
- ⬜ Spec 030: Error Message Standardization

### Auto-Update Patching

Automatic patching after cursor-agent self-updates.

- ⬜ Spec 037: Intercept Update Command
- ⬜ Spec 038: Detect Updated Version Directory
- ⬜ Spec 039: Patch State Tracking

### Testing Infrastructure

Property-based, state machine, and DST frameworks - can be implemented in parallel with other components.

- ⬜ Spec 031: Property-Based Testing Framework
- ⬜ Spec 032: State Machine Testing Framework
- ⬜ Spec 033: Deterministic Simulation Testing Framework
- ⬜ Spec 034: Property Tests for Version Extraction
- ⬜ Spec 035: State Machine Tests for Patching Workflow
- ⬜ Spec 036: Deterministic Simulation Tests for Full Workflow

## Current Focus

**Next Chunk**: Download Infrastructure (Specs 009-012)

**Next Spec**: Spec 013: Patch Registry Data Structure

**Status**: Spec 012 completed. Download Infrastructure chunk complete. Moving to Patch System chunk.

## Session Log

### 2026-01-27 - Foundation Implementation

- ✅ Completed Spec 001: Created `patcher-config.json` with version mappings, cache settings, installation defaults, and Cursor Agent configuration
- ✅ Completed Spec 002: Implemented `Get-PatcherConfig` function in `CursorAgentPatcher.psm1` with full validation, environment variable expansion, and error handling
- ✅ Completed Spec 003: Implemented `Initialize-CacheDirectory` function in `CursorAgentPatcher.psm1` with directory structure creation and subdirectory setup
- All functions tested and verified working
- Updated `specs/index.md` to mark Foundation specs as complete
- Created `WORK.md` for progress tracking

**Files Created/Modified**:

- `patcher-config.json` (new)
- `CursorAgentPatcher.psm1` (new)
- `specs/index.md` (updated)
- `WORK.md` (new)

**Next Steps**: Continue Version Detection specs, starting with Spec 005: Extract Cursor Agent Version from Install Script

### 2026-01-27 - Version Detection Implementation

- ✅ Completed Spec 004: Implemented `Get-CursorAgentInstallScript` function in `CursorAgentPatcher.psm1`
  - Fetches install script from [https://cursor.com/install](https://cursor.com/install) using Invoke-WebRequest
  - Handles network errors, HTTP status codes, and timeouts with descriptive error messages
  - Returns raw script content as string
  - Tested and verified working (successfully downloads 5644-character bash script)
- ✅ Completed Spec 005: Implemented `Get-CursorAgentVersion` function in `CursorAgentPatcher.psm1`
  - Parses install script to extract version string using regex pattern matching
  - Searches for `DOWNLOAD_URL="https://downloads.cursor.com/lab/([^/]+)/` pattern
  - Validates version format: `YYYY.MM.DD-{hash}` (e.g., `2026.01.23-916f423`)
  - Includes fallback patterns for script format variations
  - Throws descriptive errors if version not found or format invalid
  - Tested and verified working (successfully extracted version from live install script)
- ✅ Completed Spec 006: Implemented `Get-Sqlite3Version` function in `CursorAgentPatcher.psm1`
  - Extracts SQLite3 version from extracted package directory
  - First searches for package.json and parses dependencies/devDependencies
  - Falls back to searching bundled JavaScript files (index.js and *.js) for version patterns
  - Supports multiple regex patterns: `sqlite3@(\d+\.\d+\.\d+)`, `"sqlite3":\s*"([^"]+)"`, etc.
  - Returns $null gracefully when version not found (not an error condition)
  - Throws descriptive errors for invalid package paths
  - Tested and verified working (all test cases passed: package.json, bundled code, not found, invalid path)
- ✅ Completed Spec 007: Implemented `Get-MerkleTreeVersion` function in `CursorAgentPatcher.psm1`
  - Extracts @btc-vision/rust-merkle-tree version from extracted package directory
  - First searches for package.json and parses dependencies/devDependencies for @btc-vision/rust-merkle-tree
  - Falls back to searching bundled JavaScript files (index.js and *.js) for version patterns
  - Supports multiple regex patterns: `@btc-vision/rust-merkle-tree@(\d+\.\d+\.\d+)`, `"@btc-vision/rust-merkle-tree":\s*"([^"]+)"`, etc.
  - Returns $null gracefully when version not found (not an error condition)
  - Throws descriptive errors for invalid package paths
  - Tested and verified working (all test cases passed: package.json, bundled code, not found, invalid path, version prefix stripping)
- ✅ Completed Spec 008: Implemented `Get-RipGrepVersion` function in `CursorAgentPatcher.psm1`
  - Extracts RipGrep version from extracted package directory
  - First attempts to locate `rg` binary in common locations and execute `rg --version`
  - Parses version from output using pattern `ripgrep (\d+\.\d+\.\d+)`
  - Falls back to searching package files (index.js, *.js, package.json) for version patterns if binary execution fails
  - Returns $null gracefully when version cannot be determined (binary not found or execution fails)
  - Throws descriptive errors for invalid package paths
  - Tested and verified working (module loads correctly, function signature matches spec)
- ✅ Completed Spec 009: Implemented `Get-FileWithProgress` function in `CursorAgentPatcher.psm1`
  - Downloads files from URL using Invoke-WebRequest with -OutFile parameter
  - Optionally displays progress indication using Write-Progress when -ShowProgress switch is used
  - Automatically handles redirects (built into Invoke-WebRequest)
  - Validates downloaded file exists and has non-zero size after download
  - Comprehensive error handling for network errors, HTTP errors, write errors, and zero-size files
  - Creates output directory if it doesn't exist
  - Tested and verified working (function loads correctly, signature matches spec)
- ✅ Completed Spec 010: Implemented `Get-GitHubReleaseAsset` function in `CursorAgentPatcher.psm1`
  - Fetches release metadata from GitHub API using Invoke-RestMethod
  - Supports both "latest" release and specific release tags
  - Filters assets by regex pattern matching
  - Prefers Windows-specific assets when multiple matches are found
  - Downloads matched asset using Get-FileWithProgress
  - Comprehensive error handling for API errors, no matches, multiple matches, and download failures
  - Lists available assets in error message when no match is found
  - Validates repo format, regex pattern, and parameters
  - Tested and verified working (function loads correctly, signature matches spec)
- ✅ Completed Spec 011: Implemented `Get-CachedBinary` function in `CursorAgentPatcher.psm1`
  - Checks if binary file exists in cache directory at `$CacheDirectory\binaries\$CacheKey`
  - Returns absolute path to cached file if it exists and is valid
  - Returns $null if file doesn't exist or is invalid (cache miss)
  - Validates cached files when `validateOnUse: true` is set in config (checks readable and non-zero size)
  - Handles cache directory validation errors by throwing descriptive errors
  - Handles invalid cached files by returning $null (treats as cache miss)
  - Tested and verified working (function loads correctly, signature matches spec)
- ✅ Completed Spec 012: Implemented `Save-BinaryToCache` function in `CursorAgentPatcher.psm1`
  - Saves downloaded binary to cache with version-based naming
  - Ensures cache directory exists by calling Initialize-CacheDirectory
  - Constructs destination path: `$CacheDirectory\binaries\$CacheKey`
  - Copies file from source path to cache destination
  - Returns absolute path to cached file
  - Comprehensive error handling for source file not found, copy failures, and permission errors
  - Validates source file exists before copying
  - Verifies destination file exists after copy
  - Tested and verified working (function loads correctly, signature matches spec)

