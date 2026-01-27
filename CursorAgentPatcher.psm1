# CursorAgentPatcher.psm1
# PowerShell module for Cursor Agent Windows patching functionality

<#
.SYNOPSIS
Cursor Agent Windows Patcher Module

.DESCRIPTION
Provides functions for patching Cursor Agent CLI to work on Windows by replacing
native modules and binaries with Windows-compatible versions.

.NOTES
Module version: 1.0.0
#>

#region Configuration Functions

function Get-PatcherConfig {
    <#
    .SYNOPSIS
    Load configuration from JSON file with validation and environment variable expansion.
    
    .DESCRIPTION
    Reads the patcher configuration file, validates its structure, expands environment
    variables in paths, and returns a validated configuration object.
    
    .PARAMETER ConfigPath
    Path to the configuration JSON file. Defaults to ".\patcher-config.json".
    
    .OUTPUTS
    PSCustomObject. Returns a validated configuration object with the following structure:
    - versionMappings: Dependency version mappings
    - cache: Cache configuration
    - installation: Installation defaults
    - cursorAgent: Cursor Agent download settings
    
    .EXAMPLE
    $config = Get-PatcherConfig
    $cacheDir = $config.cache.directory
    
    .EXAMPLE
    $config = Get-PatcherConfig -ConfigPath ".\custom-config.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = ".\patcher-config.json"
    )
    
    try {
        # Check if file exists
        if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
            throw "Get-PatcherConfig: Configuration file not found at '$ConfigPath'"
        }
        
        # Read and parse JSON
        Write-Verbose "Reading configuration from '$ConfigPath'"
        $jsonContent = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        
        # Validate required top-level keys
        $requiredKeys = @('versionMappings', 'cache', 'installation', 'cursorAgent')
        $missingKeys = @()
        foreach ($key in $requiredKeys) {
            if (-not (Get-Member -InputObject $config -Name $key -MemberType NoteProperty)) {
                $missingKeys += $key
            }
        }
        
        if ($missingKeys.Count -gt 0) {
            throw "Get-PatcherConfig: Missing required configuration keys: $($missingKeys -join ', ')"
        }
        
        # Expand environment variables in paths
        if ($config.cache.directory) {
            $config.cache.directory = [System.Environment]::ExpandEnvironmentVariables($config.cache.directory)
        }
        if ($config.installation.defaultPath) {
            $config.installation.defaultPath = [System.Environment]::ExpandEnvironmentVariables($config.installation.defaultPath)
        }
        
        # Validate regex patterns in versionMappings
        $regexErrors = @()
        foreach ($depName in $config.versionMappings.PSObject.Properties.Name) {
            $dep = $config.versionMappings.$depName
            foreach ($version in $dep.PSObject.Properties.Name) {
                $versionConfig = $dep.$version
                if ($versionConfig.windowsBinary.assetPattern) {
                    try {
                        $null = [regex]::Match('', $versionConfig.windowsBinary.assetPattern)
                    }
                    catch {
                        $regexErrors += "$depName.$version.assetPattern: $_"
                    }
                }
            }
        }
        
        if ($regexErrors.Count -gt 0) {
            throw "Get-PatcherConfig: Invalid regex patterns found: $($regexErrors -join '; ')"
        }
        
        Write-Verbose "Configuration loaded and validated successfully"
        return $config
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Get-PatcherConfig: Configuration file not found at '$ConfigPath'"
        throw
    }
    catch [System.ArgumentException] {
        # JSON parse error
        Write-Error "Get-PatcherConfig: Invalid JSON in configuration file '$ConfigPath'. Error: $_"
        throw
    }
    catch {
        Write-Error "Get-PatcherConfig: Failed to load configuration. Error: $_"
        throw
    }
}

function Initialize-CacheDirectory {
    <#
    .SYNOPSIS
    Create cache directory structure if it doesn't exist.
    
    .DESCRIPTION
    Initializes the cache directory structure for storing downloaded binaries and packages.
    If the cache path is not provided, it uses the value from the configuration file.
    Creates subdirectories for binaries and packages.
    
    .PARAMETER CachePath
    Optional path to the cache directory. If not provided, uses the value from
    patcher-config.json.
    
    .OUTPUTS
    string. Returns the absolute path to the cache directory.
    
    .EXAMPLE
    $cacheDir = Initialize-CacheDirectory
    # Uses cache path from configuration
    
    .EXAMPLE
    $cacheDir = Initialize-CacheDirectory -CachePath "C:\MyCache"
    # Uses the specified cache path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CachePath
    )
    
    try {
        # If CachePath not provided, get from config
        if ([string]::IsNullOrWhiteSpace($CachePath)) {
            Write-Verbose "Cache path not provided, loading from configuration"
            $config = Get-PatcherConfig
            $CachePath = $config.cache.directory
        }
        
        # Expand environment variables
        $CachePath = [System.Environment]::ExpandEnvironmentVariables($CachePath)
        
        # Convert to absolute path
        if (-not [System.IO.Path]::IsPathRooted($CachePath)) {
            $CachePath = [System.IO.Path]::GetFullPath($CachePath)
        }
        
        Write-Verbose "Initializing cache directory at '$CachePath'"
        
        # Validate path characters
        $invalidChars = [System.IO.Path]::GetInvalidPathChars()
        foreach ($char in $invalidChars) {
            if ($CachePath.Contains($char)) {
                throw "Initialize-CacheDirectory: Invalid path characters found in cache path: '$CachePath'"
            }
        }
        
        # Create main cache directory if it doesn't exist
        if (-not (Test-Path -Path $CachePath -PathType Container)) {
            Write-Verbose "Creating cache directory: $CachePath"
            $null = New-Item -Path $CachePath -ItemType Directory -Force -ErrorAction Stop
        }
        else {
            Write-Verbose "Cache directory already exists: $CachePath"
        }
        
        # Create subdirectories
        $subdirs = @('binaries', 'packages')
        foreach ($subdir in $subdirs) {
            $subdirPath = Join-Path -Path $CachePath -ChildPath $subdir
            if (-not (Test-Path -Path $subdirPath -PathType Container)) {
                Write-Verbose "Creating subdirectory: $subdirPath"
                $null = New-Item -Path $subdirPath -ItemType Directory -Force -ErrorAction Stop
            }
        }
        
        Write-Verbose "Cache directory initialized successfully at '$CachePath'"
        return $CachePath
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Initialize-CacheDirectory: Permission denied when creating cache directory at '$CachePath'. Error: $_"
        throw
    }
    catch [System.IO.DirectoryNotFoundException] {
        Write-Error "Initialize-CacheDirectory: Invalid path - parent directory does not exist for '$CachePath'. Error: $_"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Initialize-CacheDirectory: Invalid path format: '$CachePath'. Error: $_"
        throw
    }
    catch {
        Write-Error "Initialize-CacheDirectory: Failed to initialize cache directory. Error: $_"
        throw
    }
}

#endregion

#region Version Detection Functions

function Get-CursorAgentInstallScript {
    <#
    .SYNOPSIS
    Download and return the install script from cursor.com/install.
    
    .DESCRIPTION
    Fetches the Cursor Agent installation script from https://cursor.com/install using
    Invoke-WebRequest and returns the raw script content as a string. Handles network
    errors, HTTP error status codes, and timeouts with descriptive error messages.
    
    .OUTPUTS
    string. Returns the raw script content from the install URL.
    
    .EXAMPLE
    $scriptContent = Get-CursorAgentInstallScript
    # Downloads and returns the install script content
    
    .EXAMPLE
    try {
        $script = Get-CursorAgentInstallScript
        Write-Host "Script downloaded: $($script.Length) characters"
    }
    catch {
        Write-Error "Failed to download script: $_"
    }
    #>
    [CmdletBinding()]
    param()
    
    $installUrl = "https://cursor.com/install"
    
    try {
        Write-Verbose "Fetching Cursor Agent install script from '$installUrl'"
        
        # Set timeout to 30 seconds (default is usually 100 seconds, but we want faster failure)
        $response = Invoke-WebRequest -Uri $installUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        
        # Check if response is successful
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            Write-Verbose "Successfully downloaded install script ($($response.Content.Length) characters)"
            return $response.Content
        }
        else {
            throw "Get-CursorAgentInstallScript: HTTP error status $($response.StatusCode) when fetching '$installUrl'. Status description: $($response.StatusDescription)"
        }
    }
    catch [System.Net.WebException] {
        # Handle specific HTTP error status codes
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $statusDescription = $_.Exception.Response.StatusDescription
            $errorMessage = "Get-CursorAgentInstallScript: HTTP error $statusCode ($statusDescription) when fetching '$installUrl'"
            Write-Error $errorMessage
            throw $errorMessage
        }
        # Handle network errors (connection refused, DNS failure, etc.)
        elseif ($_.Exception.InnerException) {
            $errorMessage = "Get-CursorAgentInstallScript: Network error when fetching '$installUrl'. Error: $($_.Exception.InnerException.Message)"
            Write-Error $errorMessage
            throw $errorMessage
        }
        else {
            $errorMessage = "Get-CursorAgentInstallScript: Network error when fetching '$installUrl'. Error: $($_.Exception.Message)"
            Write-Error $errorMessage
            throw $errorMessage
        }
    }
    catch [System.TimeoutException] {
        $errorMessage = "Get-CursorAgentInstallScript: Request to '$installUrl' timed out after 30 seconds"
        Write-Error $errorMessage
        throw $errorMessage
    }
    catch {
        $errorMessage = "Get-CursorAgentInstallScript: Failed to fetch install script from '$installUrl'. Error: $_"
        Write-Error $errorMessage
        throw $errorMessage
    }
}

function Get-CursorAgentVersion {
    <#
    .SYNOPSIS
    Extract Cursor Agent version string from install script.
    
    .DESCRIPTION
    Parses the Cursor Agent installation script to extract the version string (e.g., 
    `2025.08.15-dbc8d73`) by searching for the DOWNLOAD_URL pattern that contains the 
    version in the path. Validates that the extracted version matches the expected 
    format `YYYY.MM.DD-{hash}`.
    
    .PARAMETER InstallScript
    The raw install script content as a string, typically obtained from 
    Get-CursorAgentInstallScript.
    
    .OUTPUTS
    string. Returns the version string in format YYYY.MM.DD-{hash}.
    
    .EXAMPLE
    $script = Get-CursorAgentInstallScript
    $version = Get-CursorAgentVersion -InstallScript $script
    # Extracts version from downloaded script
    
    .EXAMPLE
    $scriptContent = Get-Content -Path "install.sh" -Raw
    $version = Get-CursorAgentVersion -InstallScript $scriptContent
    # Extracts version from local script file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallScript
    )
    
    try {
        if ([string]::IsNullOrWhiteSpace($InstallScript)) {
            throw "Get-CursorAgentVersion: Install script content is null or empty"
        }
        
        Write-Verbose "Searching for version pattern in install script"
        
        # Pattern to match: DOWNLOAD_URL="https://downloads.cursor.com/lab/([^/]+)/
        # The version is in the first capture group
        $versionPattern = 'DOWNLOAD_URL="https://downloads\.cursor\.com/lab/([^/]+)/'
        
        # Try to match the pattern
        $match = [regex]::Match($InstallScript, $versionPattern)
        
        if (-not $match.Success) {
            # Try alternative patterns in case script format changes
            $alternativePatterns = @(
                'downloads\.cursor\.com/lab/([^/]+)/',
                'DOWNLOAD_URL.*cursor\.com/lab/([^/]+)/',
                'VERSION="([^"]+)"',
                'version="([^"]+)"'
            )
            
            $found = $false
            foreach ($altPattern in $alternativePatterns) {
                $altMatch = [regex]::Match($InstallScript, $altPattern)
                if ($altMatch.Success) {
                    $match = $altMatch
                    $found = $true
                    Write-Verbose "Found version using alternative pattern: $altPattern"
                    break
                }
            }
            
            if (-not $found) {
                # Show context around where we searched
                $scriptPreview = if ($InstallScript.Length -gt 200) {
                    $InstallScript.Substring(0, 200) + "..."
                } else {
                    $InstallScript
                }
                throw "Get-CursorAgentVersion: Version pattern not found in install script. Searched for pattern '$versionPattern'. Script preview: $scriptPreview"
            }
        }
        
        # Extract version from first capture group
        $extractedVersion = $match.Groups[1].Value
        
        if ([string]::IsNullOrWhiteSpace($extractedVersion)) {
            throw "Get-CursorAgentVersion: Version string extracted but is empty. Match result: $($match.Value)"
        }
        
        Write-Verbose "Extracted version string: $extractedVersion"
        
        # Validate format: YYYY.MM.DD-{hash}
        # Pattern: 4 digits, dot, 2 digits, dot, 2 digits, dash, one or more alphanumeric characters
        $versionFormatPattern = '^\d{4}\.\d{2}\.\d{2}-[a-zA-Z0-9]+$'
        $formatMatch = [regex]::Match($extractedVersion, $versionFormatPattern)
        
        if (-not $formatMatch.Success) {
            throw "Get-CursorAgentVersion: Invalid version format. Extracted value: '$extractedVersion'. Expected format: YYYY.MM.DD-{hash} (e.g., '2025.08.15-dbc8d73')"
        }
        
        Write-Verbose "Version validated successfully: $extractedVersion"
        return $extractedVersion
    }
    catch {
        Write-Error "Get-CursorAgentVersion: Failed to extract version from install script. Error: $_"
        throw
    }
}

function Get-Sqlite3Version {
    <#
    .SYNOPSIS
    Extract SQLite3 version from extracted package directory.
    
    .DESCRIPTION
    Searches for SQLite3 version information in an extracted Cursor Agent package.
    First attempts to find and parse package.json for sqlite3 in dependencies.
    If package.json is not found, searches bundled index.js files for version patterns.
    Returns $null if version is not found (this is not an error condition).
    
    .PARAMETER PackagePath
    Path to the extracted package directory to search for SQLite3 version information.
    
    .OUTPUTS
    string or $null. Returns the version string (e.g., "5.1.7") if found, or $null if not found.
    
    .EXAMPLE
    $version = Get-Sqlite3Version -PackagePath ".\cursor-agent-2026.01.23-916f423"
    # Searches for SQLite3 version in the extracted package
    
    .EXAMPLE
    $version = Get-Sqlite3Version -PackagePath "C:\packages\cursor-agent"
    if ($version) {
        Write-Host "Found SQLite3 version: $version"
    } else {
        Write-Host "SQLite3 version not found in package"
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath
    )
    
    try {
        # Validate package path
        if ([string]::IsNullOrWhiteSpace($PackagePath)) {
            throw "Get-Sqlite3Version: Package path is null or empty"
        }
        
        # Expand environment variables and convert to absolute path
        $PackagePath = [System.Environment]::ExpandEnvironmentVariables($PackagePath)
        if (-not [System.IO.Path]::IsPathRooted($PackagePath)) {
            $PackagePath = [System.IO.Path]::GetFullPath($PackagePath)
        }
        
        # Check if path exists
        if (-not (Test-Path -Path $PackagePath -PathType Container)) {
            throw "Get-Sqlite3Version: Package path does not exist or is not a directory: '$PackagePath'"
        }
        
        Write-Verbose "Searching for SQLite3 version in package directory: $PackagePath"
        
        # Strategy 1: Look for package.json
        $packageJsonPath = Join-Path -Path $PackagePath -ChildPath "package.json"
        if (Test-Path -Path $packageJsonPath -PathType Leaf) {
            Write-Verbose "Found package.json, attempting to parse for SQLite3 version"
            try {
                $packageJsonContent = Get-Content -Path $packageJsonPath -Raw -ErrorAction Stop
                $packageJson = $packageJsonContent | ConvertFrom-Json -ErrorAction Stop
                
                # Check dependencies
                if ($packageJson.dependencies -and $packageJson.dependencies.sqlite3) {
                    $version = $packageJson.dependencies.sqlite3
                    # Remove version prefix if present (e.g., "^5.1.7" -> "5.1.7")
                    $version = $version -replace '^[\^~]', ''
                    Write-Verbose "Found SQLite3 version in package.json dependencies: $version"
                    return $version
                }
                
                # Check devDependencies
                if ($packageJson.devDependencies -and $packageJson.devDependencies.sqlite3) {
                    $version = $packageJson.devDependencies.sqlite3
                    $version = $version -replace '^[\^~]', ''
                    Write-Verbose "Found SQLite3 version in package.json devDependencies: $version"
                    return $version
                }
                
                Write-Verbose "package.json found but sqlite3 not in dependencies"
            }
            catch {
                Write-Verbose "Failed to parse package.json: $_"
                # Continue to fallback strategy
            }
        }
        
        # Strategy 2: Search bundled index.js files for version patterns
        Write-Verbose "Searching bundled JavaScript files for SQLite3 version patterns"
        
        # Patterns to search for:
        # - sqlite3@(\d+\.\d+\.\d+)
        # - "sqlite3":\s*"(\d+\.\d+\.\d+)"
        # - sqlite3@5\.1\.7 (extract version)
        $versionPatterns = @(
            'sqlite3@(\d+\.\d+\.\d+)',
            '"sqlite3":\s*"([^"]+)"',
            'sqlite3@(\d+\.\d+\.\d+)',
            "'sqlite3':\s*'([^']+)'"
        )
        
        # First try index.js specifically
        $indexJsPath = Join-Path -Path $PackagePath -ChildPath "index.js"
        if (Test-Path -Path $indexJsPath -PathType Leaf) {
            try {
                $content = Get-Content -Path $indexJsPath -Raw -ErrorAction Stop
                
                foreach ($pattern in $versionPatterns) {
                    $match = [regex]::Match($content, $pattern)
                    if ($match.Success) {
                        $version = $match.Groups[1].Value
                        # Clean up version string (remove prefixes, quotes, etc.)
                        $version = $version -replace '^[\^~]', ''
                        $version = $version -replace '^["'']|["'']$', ''
                        
                        # Validate it looks like a version (digits and dots)
                        if ($version -match '^\d+\.\d+\.\d+') {
                            Write-Verbose "Found SQLite3 version in index.js using pattern '$pattern': $version"
                            return $version
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Error reading index.js: $_"
            }
        }
        
        # Then search all .js files in the package directory
        $jsFiles = Get-ChildItem -Path $PackagePath -Filter "*.js" -Recurse -ErrorAction SilentlyContinue
        if ($jsFiles) {
            foreach ($file in $jsFiles) {
                try {
                    $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                    
                    foreach ($pattern in $versionPatterns) {
                        $match = [regex]::Match($content, $pattern)
                        if ($match.Success) {
                            $version = $match.Groups[1].Value
                            # Clean up version string (remove prefixes, quotes, etc.)
                            $version = $version -replace '^[\^~]', ''
                            $version = $version -replace '^["'']|["'']$', ''
                            
                            # Validate it looks like a version (digits and dots)
                            if ($version -match '^\d+\.\d+\.\d+') {
                                Write-Verbose "Found SQLite3 version in $($file.Name) using pattern '$pattern': $version"
                                return $version
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "Error reading file $($file.FullName): $_"
                    continue
                }
            }
        }
        
        # Version not found - return $null (not an error per spec)
        Write-Verbose "SQLite3 version not found in package directory"
        return $null
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Get-Sqlite3Version: Package path not found: '$PackagePath'"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Get-Sqlite3Version: Invalid package path format: '$PackagePath'. Error: $_"
        throw
    }
    catch {
        Write-Error "Get-Sqlite3Version: Failed to extract SQLite3 version from package. Error: $_"
        throw
    }
}

function Get-MerkleTreeVersion {
    <#
    .SYNOPSIS
    Extract @btc-vision/rust-merkle-tree version from extracted package directory.
    
    .DESCRIPTION
    Searches for @btc-vision/rust-merkle-tree version information in an extracted Cursor Agent package.
    First attempts to find and parse package.json for @btc-vision/rust-merkle-tree in dependencies.
    If package.json is not found, searches bundled index.js files for version patterns.
    Returns $null if version is not found (this is not an error condition).
    
    .PARAMETER PackagePath
    Path to the extracted package directory to search for @btc-vision/rust-merkle-tree version information.
    
    .OUTPUTS
    string or $null. Returns the version string (e.g., "1.0.0") if found, or $null if not found.
    
    .EXAMPLE
    $version = Get-MerkleTreeVersion -PackagePath ".\cursor-agent-2026.01.23-916f423"
    # Searches for @btc-vision/rust-merkle-tree version in the extracted package
    
    .EXAMPLE
    $version = Get-MerkleTreeVersion -PackagePath "C:\packages\cursor-agent"
    if ($version) {
        Write-Host "Found Merkle Tree version: $version"
    } else {
        Write-Host "Merkle Tree version not found in package"
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath
    )
    
    try {
        # Validate package path
        if ([string]::IsNullOrWhiteSpace($PackagePath)) {
            throw "Get-MerkleTreeVersion: Package path is null or empty"
        }
        
        # Expand environment variables and convert to absolute path
        $PackagePath = [System.Environment]::ExpandEnvironmentVariables($PackagePath)
        if (-not [System.IO.Path]::IsPathRooted($PackagePath)) {
            $PackagePath = [System.IO.Path]::GetFullPath($PackagePath)
        }
        
        # Check if path exists
        if (-not (Test-Path -Path $PackagePath -PathType Container)) {
            throw "Get-MerkleTreeVersion: Package path does not exist or is not a directory: '$PackagePath'"
        }
        
        Write-Verbose "Searching for @btc-vision/rust-merkle-tree version in package directory: $PackagePath"
        
        # Strategy 1: Look for package.json
        $packageJsonPath = Join-Path -Path $PackagePath -ChildPath "package.json"
        if (Test-Path -Path $packageJsonPath -PathType Leaf) {
            Write-Verbose "Found package.json, attempting to parse for @btc-vision/rust-merkle-tree version"
            try {
                $packageJsonContent = Get-Content -Path $packageJsonPath -Raw -ErrorAction Stop
                $packageJson = $packageJsonContent | ConvertFrom-Json -ErrorAction Stop
                
                # Check dependencies (package name is @btc-vision/rust-merkle-tree)
                $packageName = "@btc-vision/rust-merkle-tree"
                if ($packageJson.dependencies -and $packageJson.dependencies.$packageName) {
                    $version = $packageJson.dependencies.$packageName
                    # Remove version prefix if present (e.g., "^1.0.0" -> "1.0.0")
                    $version = $version -replace '^[\^~]', ''
                    Write-Verbose "Found @btc-vision/rust-merkle-tree version in package.json dependencies: $version"
                    return $version
                }
                
                # Check devDependencies
                if ($packageJson.devDependencies -and $packageJson.devDependencies.$packageName) {
                    $version = $packageJson.devDependencies.$packageName
                    $version = $version -replace '^[\^~]', ''
                    Write-Verbose "Found @btc-vision/rust-merkle-tree version in package.json devDependencies: $version"
                    return $version
                }
                
                Write-Verbose "package.json found but @btc-vision/rust-merkle-tree not in dependencies"
            }
            catch {
                Write-Verbose "Failed to parse package.json: $_"
                # Continue to fallback strategy
            }
        }
        
        # Strategy 2: Search bundled index.js files for version patterns
        Write-Verbose "Searching bundled JavaScript files for @btc-vision/rust-merkle-tree version patterns"
        
        # Patterns to search for:
        # - @btc-vision/rust-merkle-tree@(\d+\.\d+\.\d+)
        # - "@btc-vision/rust-merkle-tree":\s*"(\d+\.\d+\.\d+)"
        $versionPatterns = @(
            '@btc-vision/rust-merkle-tree@(\d+\.\d+\.\d+)',
            '"@btc-vision/rust-merkle-tree":\s*"([^"]+)"',
            "'@btc-vision/rust-merkle-tree':\s*'([^']+)'"
        )
        
        # First try index.js specifically
        $indexJsPath = Join-Path -Path $PackagePath -ChildPath "index.js"
        if (Test-Path -Path $indexJsPath -PathType Leaf) {
            try {
                $content = Get-Content -Path $indexJsPath -Raw -ErrorAction Stop
                
                foreach ($pattern in $versionPatterns) {
                    $match = [regex]::Match($content, $pattern)
                    if ($match.Success) {
                        $version = $match.Groups[1].Value
                        # Clean up version string (remove prefixes, quotes, etc.)
                        $version = $version -replace '^[\^~]', ''
                        $version = $version -replace '^["'']|["'']$', ''
                        
                        # Validate it looks like a version (digits and dots)
                        if ($version -match '^\d+\.\d+\.\d+') {
                            Write-Verbose "Found @btc-vision/rust-merkle-tree version in index.js using pattern '$pattern': $version"
                            return $version
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Error reading index.js: $_"
            }
        }
        
        # Then search all .js files in the package directory
        $jsFiles = Get-ChildItem -Path $PackagePath -Filter "*.js" -Recurse -ErrorAction SilentlyContinue
        if ($jsFiles) {
            foreach ($file in $jsFiles) {
                try {
                    $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                    
                    foreach ($pattern in $versionPatterns) {
                        $match = [regex]::Match($content, $pattern)
                        if ($match.Success) {
                            $version = $match.Groups[1].Value
                            # Clean up version string (remove prefixes, quotes, etc.)
                            $version = $version -replace '^[\^~]', ''
                            $version = $version -replace '^["'']|["'']$', ''
                            
                            # Validate it looks like a version (digits and dots)
                            if ($version -match '^\d+\.\d+\.\d+') {
                                Write-Verbose "Found @btc-vision/rust-merkle-tree version in $($file.Name) using pattern '$pattern': $version"
                                return $version
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "Error reading file $($file.FullName): $_"
                    continue
                }
            }
        }
        
        # Version not found - return $null (not an error per spec)
        Write-Verbose "@btc-vision/rust-merkle-tree version not found in package directory"
        return $null
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Get-MerkleTreeVersion: Package path not found: '$PackagePath'"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Get-MerkleTreeVersion: Invalid package path format: '$PackagePath'. Error: $_"
        throw
    }
    catch {
        Write-Error "Get-MerkleTreeVersion: Failed to extract @btc-vision/rust-merkle-tree version from package. Error: $_"
        throw
    }
}

function Get-RipGrepVersion {
    <#
    .SYNOPSIS
    Extract RipGrep version from extracted package directory.
    
    .DESCRIPTION
    Attempts to extract ripgrep version from binary or package metadata. First tries to locate
    the `rg` binary in the package and execute `rg --version` to get the version. If execution
    fails (expected for cross-platform binaries like macOS binaries on Windows), falls back to
    searching package files for version strings. Returns $null if version cannot be determined
    (this is not an error condition).
    
    .PARAMETER PackagePath
    Path to the extracted package directory to search for RipGrep version information.
    
    .OUTPUTS
    string or $null. Returns the version string (e.g., "14.1.0") if found, or $null if not found.
    
    .EXAMPLE
    $version = Get-RipGrepVersion -PackagePath ".\cursor-agent-2026.01.23-916f423"
    # Searches for RipGrep version in the extracted package
    
    .EXAMPLE
    $version = Get-RipGrepVersion -PackagePath "C:\packages\cursor-agent"
    if ($version) {
        Write-Host "Found RipGrep version: $version"
    } else {
        Write-Host "RipGrep version not found in package"
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackagePath
    )
    
    try {
        # Validate package path
        if ([string]::IsNullOrWhiteSpace($PackagePath)) {
            throw "Get-RipGrepVersion: Package path is null or empty"
        }
        
        # Expand environment variables and convert to absolute path
        $PackagePath = [System.Environment]::ExpandEnvironmentVariables($PackagePath)
        if (-not [System.IO.Path]::IsPathRooted($PackagePath)) {
            $PackagePath = [System.IO.Path]::GetFullPath($PackagePath)
        }
        
        # Check if path exists
        if (-not (Test-Path -Path $PackagePath -PathType Container)) {
            throw "Get-RipGrepVersion: Package path does not exist or is not a directory: '$PackagePath'"
        }
        
        Write-Verbose "Searching for RipGrep version in package directory: $PackagePath"
        
        # Strategy 1: Try to locate and execute rg binary
        Write-Verbose "Attempting to locate rg binary in package directory"
        
        # Common locations for rg binary
        $rgPaths = @(
            Join-Path -Path $PackagePath -ChildPath "rg"
            Join-Path -Path $PackagePath -ChildPath "rg.exe"
            Join-Path -Path $PackagePath -ChildPath "bin" -AdditionalChildPath "rg"
            Join-Path -Path $PackagePath -ChildPath "bin" -AdditionalChildPath "rg.exe"
        )
        
        # Also search recursively for rg binary
        $rgBinaries = Get-ChildItem -Path $PackagePath -Filter "rg*" -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { -not $_.PSIsContainer }
        
        foreach ($rgPath in $rgPaths) {
            if (Test-Path -Path $rgPath -PathType Leaf) {
                Write-Verbose "Found rg binary at: $rgPath"
                
                # Try to execute rg --version
                try {
                    $versionOutput = & $rgPath --version 2>&1
                    
                    # Parse version from output: ripgrep (\d+\.\d+\.\d+)
                    # Example output: "ripgrep 14.1.0\n..."
                    $versionPattern = 'ripgrep\s+(\d+\.\d+\.\d+)'
                    $match = [regex]::Match($versionOutput, $versionPattern)
                    
                    if ($match.Success) {
                        $version = $match.Groups[1].Value
                        Write-Verbose "Extracted RipGrep version from binary output: $version"
                        return $version
                    }
                    else {
                        Write-Verbose "rg --version executed but version pattern not found in output: $versionOutput"
                    }
                }
                catch {
                    # Execution failed (expected for cross-platform binaries)
                    Write-Verbose "Failed to execute rg --version (expected for cross-platform binaries): $_"
                    # Continue to fallback strategy
                }
            }
        }
        
        # Also try any rg binaries found via recursive search
        if ($rgBinaries) {
            foreach ($rgBinary in $rgBinaries) {
                try {
                    Write-Verbose "Trying rg binary at: $($rgBinary.FullName)"
                    $versionOutput = & $rgBinary.FullName --version 2>&1
                    
                    $versionPattern = 'ripgrep\s+(\d+\.\d+\.\d+)'
                    $match = [regex]::Match($versionOutput, $versionPattern)
                    
                    if ($match.Success) {
                        $version = $match.Groups[1].Value
                        Write-Verbose "Extracted RipGrep version from binary output: $version"
                        return $version
                    }
                }
                catch {
                    Write-Verbose "Failed to execute rg --version from $($rgBinary.FullName): $_"
                    continue
                }
            }
        }
        
        # Strategy 2: Search package files for version strings
        Write-Verbose "Binary execution failed or not found, searching package files for version strings"
        
        # Patterns to search for:
        # - ripgrep (\d+\.\d+\.\d+)
        # - ripgrep-(\d+\.\d+\.\d+)
        # - "ripgrep":\s*"(\d+\.\d+\.\d+)"
        # - rg-(\d+\.\d+\.\d+)
        $versionPatterns = @(
            'ripgrep\s+(\d+\.\d+\.\d+)',
            'ripgrep-(\d+\.\d+\.\d+)',
            '"ripgrep":\s*"([^"]+)"',
            "'ripgrep':\s*'([^']+)'",
            'rg-(\d+\.\d+\.\d+)',
            'ripgrep\s+version\s+(\d+\.\d+\.\d+)'
        )
        
        # First try index.js specifically
        $indexJsPath = Join-Path -Path $PackagePath -ChildPath "index.js"
        if (Test-Path -Path $indexJsPath -PathType Leaf) {
            try {
                $content = Get-Content -Path $indexJsPath -Raw -ErrorAction Stop
                
                foreach ($pattern in $versionPatterns) {
                    $match = [regex]::Match($content, $pattern)
                    if ($match.Success) {
                        $version = $match.Groups[1].Value
                        # Clean up version string (remove quotes, etc.)
                        $version = $version -replace '^["'']|["'']$', ''
                        
                        # Validate it looks like a version (digits and dots)
                        if ($version -match '^\d+\.\d+\.\d+') {
                            Write-Verbose "Found RipGrep version in index.js using pattern '$pattern': $version"
                            return $version
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Error reading index.js: $_"
            }
        }
        
        # Then search all .js files in the package directory
        $jsFiles = Get-ChildItem -Path $PackagePath -Filter "*.js" -Recurse -ErrorAction SilentlyContinue
        if ($jsFiles) {
            foreach ($file in $jsFiles) {
                try {
                    $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                    
                    foreach ($pattern in $versionPatterns) {
                        $match = [regex]::Match($content, $pattern)
                        if ($match.Success) {
                            $version = $match.Groups[1].Value
                            # Clean up version string (remove quotes, etc.)
                            $version = $version -replace '^["'']|["'']$', ''
                            
                            # Validate it looks like a version (digits and dots)
                            if ($version -match '^\d+\.\d+\.\d+') {
                                Write-Verbose "Found RipGrep version in $($file.Name) using pattern '$pattern': $version"
                                return $version
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "Error reading file $($file.FullName): $_"
                    continue
                }
            }
        }
        
        # Also search package.json if it exists
        $packageJsonPath = Join-Path -Path $PackagePath -ChildPath "package.json"
        if (Test-Path -Path $packageJsonPath -PathType Leaf) {
            try {
                $packageJsonContent = Get-Content -Path $packageJsonPath -Raw -ErrorAction Stop
                $packageJson = $packageJsonContent | ConvertFrom-Json -ErrorAction Stop
                
                # Check dependencies for ripgrep
                if ($packageJson.dependencies -and $packageJson.dependencies.ripgrep) {
                    $version = $packageJson.dependencies.ripgrep
                    $version = $version -replace '^[\^~]', ''
                    Write-Verbose "Found RipGrep version in package.json dependencies: $version"
                    return $version
                }
                
                # Check devDependencies
                if ($packageJson.devDependencies -and $packageJson.devDependencies.ripgrep) {
                    $version = $packageJson.devDependencies.ripgrep
                    $version = $version -replace '^[\^~]', ''
                    Write-Verbose "Found RipGrep version in package.json devDependencies: $version"
                    return $version
                }
            }
            catch {
                Write-Verbose "Failed to parse package.json: $_"
            }
        }
        
        # Version not found - return $null (not an error per spec)
        Write-Verbose "RipGrep version not found in package directory"
        return $null
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Get-RipGrepVersion: Package path not found: '$PackagePath'"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Get-RipGrepVersion: Invalid package path format: '$PackagePath'. Error: $_"
        throw
    }
    catch {
        # Per spec: Binary not found or execution fails should return $null, not throw
        # However, invalid package path errors should still throw
        # If we get here, it's likely a path validation error, so re-throw
        Write-Error "Get-RipGrepVersion: Failed to extract RipGrep version from package. Error: $_"
        throw
    }
}

#endregion

#region Download Infrastructure Functions

function Get-FileWithProgress {
    <#
    .SYNOPSIS
    Download file from URL with progress indication and error handling.
    
    .DESCRIPTION
    Downloads a file from the specified URL to the output path using Invoke-WebRequest.
    Optionally displays progress indication during download. Automatically handles redirects.
    Validates that the downloaded file exists and has a non-zero size after download.
    
    .PARAMETER Url
    The URL of the file to download.
    
    .PARAMETER OutPath
    The path where the downloaded file should be saved.
    
    .PARAMETER ShowProgress
    If specified, displays progress indication during download using Write-Progress.
    
    .OUTPUTS
    void. This function does not return a value.
    
    .EXAMPLE
    Get-FileWithProgress -Url "https://example.com/file.zip" -OutPath ".\file.zip"
    # Downloads file without progress indication
    
    .EXAMPLE
    Get-FileWithProgress -Url "https://example.com/file.zip" -OutPath ".\file.zip" -ShowProgress
    # Downloads file with progress indication
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowProgress
    )
    
    try {
        # Validate URL
        if ([string]::IsNullOrWhiteSpace($Url)) {
            throw "Get-FileWithProgress: URL is null or empty"
        }
        
        # Validate output path
        if ([string]::IsNullOrWhiteSpace($OutPath)) {
            throw "Get-FileWithProgress: Output path is null or empty"
        }
        
        # Expand environment variables in output path
        $OutPath = [System.Environment]::ExpandEnvironmentVariables($OutPath)
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($OutPath)) {
            $OutPath = [System.IO.Path]::GetFullPath($OutPath)
        }
        
        # Ensure output directory exists
        $outDir = [System.IO.Path]::GetDirectoryName($OutPath)
        if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir -PathType Container)) {
            Write-Verbose "Creating output directory: $outDir"
            $null = New-Item -Path $outDir -ItemType Directory -Force -ErrorAction Stop
        }
        
        Write-Verbose "Downloading file from '$Url' to '$OutPath'"
        
        # Show progress if requested
        if ($ShowProgress) {
            Write-Progress -Activity "Downloading File" -Status "Connecting to $Url..." -PercentComplete 0
        }
        
        # Download file using Invoke-WebRequest
        # Invoke-WebRequest automatically handles redirects
        try {
            if ($ShowProgress) {
                Write-Progress -Activity "Downloading File" -Status "Downloading from $Url..." -PercentComplete 50
            }
            
            $response = Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing -ErrorAction Stop
            
            if ($ShowProgress) {
                Write-Progress -Activity "Downloading File" -Status "Download complete" -PercentComplete 100
            }
            
            Write-Verbose "Download completed successfully. HTTP Status: $($response.StatusCode)"
        }
        catch [System.Net.WebException] {
            # Handle HTTP errors
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $statusDescription = $_.Exception.Response.StatusDescription
                if ($ShowProgress) {
                    Write-Progress -Activity "Downloading File" -Completed
                }
                throw "Get-FileWithProgress: HTTP error $statusCode ($statusDescription) when downloading from '$Url'"
            }
            # Handle network errors (connection refused, DNS failure, etc.)
            elseif ($_.Exception.InnerException) {
                if ($ShowProgress) {
                    Write-Progress -Activity "Downloading File" -Completed
                }
                throw "Get-FileWithProgress: Network error when downloading from '$Url'. Error: $($_.Exception.InnerException.Message)"
            }
            else {
                if ($ShowProgress) {
                    Write-Progress -Activity "Downloading File" -Completed
                }
                throw "Get-FileWithProgress: Network error when downloading from '$Url'. Error: $($_.Exception.Message)"
            }
        }
        catch [System.TimeoutException] {
            if ($ShowProgress) {
                Write-Progress -Activity "Downloading File" -Completed
            }
            throw "Get-FileWithProgress: Request to '$Url' timed out"
        }
        catch {
            if ($ShowProgress) {
                Write-Progress -Activity "Downloading File" -Completed
            }
            throw "Get-FileWithProgress: Failed to download from '$Url'. Error: $_"
        }
        
        # Verify file exists
        if (-not (Test-Path -Path $OutPath -PathType Leaf)) {
            if ($ShowProgress) {
                Write-Progress -Activity "Downloading File" -Completed
            }
            throw "Get-FileWithProgress: File was not created at '$OutPath' after download"
        }
        
        # Verify file has non-zero size
        $fileInfo = Get-Item -Path $OutPath -ErrorAction Stop
        if ($fileInfo.Length -eq 0) {
            if ($ShowProgress) {
                Write-Progress -Activity "Downloading File" -Completed
            }
            throw "Get-FileWithProgress: Downloaded file at '$OutPath' has zero size. Download may have failed."
        }
        
        Write-Verbose "File downloaded successfully: $OutPath ($($fileInfo.Length) bytes)"
        
        if ($ShowProgress) {
            Write-Progress -Activity "Downloading File" -Completed
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Get-FileWithProgress: Permission denied when writing to '$OutPath'. Error: $_"
        throw
    }
    catch [System.IO.DirectoryNotFoundException] {
        Write-Error "Get-FileWithProgress: Output directory does not exist for '$OutPath'. Error: $_"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Get-FileWithProgress: Invalid path format: '$OutPath'. Error: $_"
        throw
    }
    catch {
        Write-Error "Get-FileWithProgress: Failed to download file. Error: $_"
        throw
    }
}

function Get-GitHubReleaseAsset {
    <#
    .SYNOPSIS
    Find and download a specific asset from a GitHub release.
    
    .DESCRIPTION
    Fetches release metadata from GitHub API, filters assets by regex pattern,
    and downloads the matching asset. Prefers Windows-specific assets when multiple
    matches are found. Supports both "latest" release and specific release tags.
    
    .PARAMETER Repo
    GitHub repository in format "owner/repo" (e.g., "btc-vision/rust-merkle-tree").
    
    .PARAMETER AssetPattern
    Regex pattern to match asset name (e.g., ".*windows.*\.zip").
    
    .PARAMETER OutPath
    Path where the downloaded asset should be saved.
    
    .PARAMETER ReleaseTag
    Release tag to download from. Use "latest" for the latest release, or a specific
    tag like "v1.2.3". Defaults to "latest".
    
    .OUTPUTS
    void. This function does not return a value.
    
    .EXAMPLE
    Get-GitHubReleaseAsset -Repo "btc-vision/rust-merkle-tree" -AssetPattern ".*windows.*\.zip" -OutPath ".\merkle-tree.zip"
    # Downloads Windows zip asset from latest release
    
    .EXAMPLE
    Get-GitHubReleaseAsset -Repo "user/repo" -AssetPattern ".*\.exe" -OutPath ".\binary.exe" -ReleaseTag "v1.0.0"
    # Downloads exe asset from specific release tag
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Repo,
        
        [Parameter(Mandatory=$true)]
        [string]$AssetPattern,
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath,
        
        [Parameter(Mandatory=$false)]
        [string]$ReleaseTag = "latest"
    )
    
    try {
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($Repo)) {
            throw "Get-GitHubReleaseAsset: Repo parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($AssetPattern)) {
            throw "Get-GitHubReleaseAsset: AssetPattern parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($OutPath)) {
            throw "Get-GitHubReleaseAsset: OutPath parameter is null or empty"
        }
        
        # Validate repo format (should be "owner/repo")
        if ($Repo -notmatch '^[^/]+/[^/]+$') {
            throw "Get-GitHubReleaseAsset: Invalid repo format '$Repo'. Expected format: 'owner/repo'"
        }
        
        # Validate regex pattern
        try {
            $null = [regex]::Match('', $AssetPattern)
        }
        catch {
            throw "Get-GitHubReleaseAsset: Invalid regex pattern '$AssetPattern'. Error: $_"
        }
        
        # Expand environment variables in output path
        $OutPath = [System.Environment]::ExpandEnvironmentVariables($OutPath)
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($OutPath)) {
            $OutPath = [System.IO.Path]::GetFullPath($OutPath)
        }
        
        Write-Verbose "Fetching GitHub release asset from repo '$Repo', tag '$ReleaseTag', pattern '$AssetPattern'"
        
        # Construct GitHub API URL
        if ($ReleaseTag -eq "latest") {
            $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
        }
        else {
            $apiUrl = "https://api.github.com/repos/$Repo/releases/tags/$ReleaseTag"
        }
        
        Write-Verbose "Fetching release metadata from: $apiUrl"
        
        # Fetch release metadata using Invoke-RestMethod
        try {
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        }
        catch [System.Net.WebException] {
            # Handle HTTP errors
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $statusDescription = $_.Exception.Response.StatusDescription
                
                if ($statusCode -eq 404) {
                    throw "Get-GitHubReleaseAsset: Release not found for repo '$Repo', tag '$ReleaseTag'. Error: HTTP $statusCode ($statusDescription)"
                }
                else {
                    throw "Get-GitHubReleaseAsset: GitHub API error for repo '$Repo', tag '$ReleaseTag'. HTTP $statusCode ($statusDescription)"
                }
            }
            # Handle network errors
            elseif ($_.Exception.InnerException) {
                throw "Get-GitHubReleaseAsset: Network error when fetching release metadata from '$apiUrl'. Error: $($_.Exception.InnerException.Message)"
            }
            else {
                throw "Get-GitHubReleaseAsset: Network error when fetching release metadata from '$apiUrl'. Error: $($_.Exception.Message)"
            }
        }
        catch [System.TimeoutException] {
            throw "Get-GitHubReleaseAsset: Request to '$apiUrl' timed out"
        }
        catch {
            throw "Get-GitHubReleaseAsset: Failed to fetch release metadata from '$apiUrl'. Error: $_"
        }
        
        # Check if release has assets
        if (-not $release.assets -or $release.assets.Count -eq 0) {
            throw "Get-GitHubReleaseAsset: Release '$ReleaseTag' for repo '$Repo' has no assets"
        }
        
        Write-Verbose "Found $($release.assets.Count) assets in release"
        
        # Filter assets by regex pattern
        $matchingAssets = @()
        foreach ($asset in $release.assets) {
            if ($asset.name -match $AssetPattern) {
                $matchingAssets += $asset
            }
        }
        
        # Check if any assets matched
        if ($matchingAssets.Count -eq 0) {
            # List available assets for error message
            $availableAssets = $release.assets | ForEach-Object { $_.name } | Sort-Object
            $availableAssetsList = $availableAssets -join ", "
            throw "Get-GitHubReleaseAsset: No assets matching pattern '$AssetPattern' found in release '$ReleaseTag' for repo '$Repo'. Available assets: $availableAssetsList"
        }
        
        Write-Verbose "Found $($matchingAssets.Count) matching asset(s)"
        
        # If multiple matches, prefer Windows-specific assets
        $selectedAsset = $null
        if ($matchingAssets.Count -eq 1) {
            $selectedAsset = $matchingAssets[0]
            Write-Verbose "Selected asset: $($selectedAsset.name)"
        }
        else {
            # Multiple matches - prefer Windows-specific assets
            $windowsAssets = $matchingAssets | Where-Object { 
                $_.name -match '(?i)(windows|win|\.exe|\.msi|\.zip.*win)' 
            }
            
            if ($windowsAssets.Count -gt 0) {
                $selectedAsset = $windowsAssets[0]
                Write-Verbose "Multiple matches found, selected Windows-specific asset: $($selectedAsset.name)"
                if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
                    Write-Warning "Get-GitHubReleaseAsset: Multiple assets matched pattern '$AssetPattern'. Selected Windows-specific asset: $($selectedAsset.name). Other matches: $(($matchingAssets | Where-Object { $_.name -ne $selectedAsset.name } | ForEach-Object { $_.name }) -join ', ')"
                }
            }
            else {
                # No Windows-specific assets, use first match
                $selectedAsset = $matchingAssets[0]
                Write-Verbose "Multiple matches found, no Windows-specific assets, selected first match: $($selectedAsset.name)"
                if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
                    Write-Warning "Get-GitHubReleaseAsset: Multiple assets matched pattern '$AssetPattern'. Selected first match: $($selectedAsset.name). Other matches: $(($matchingAssets | Select-Object -Skip 1 | ForEach-Object { $_.name }) -join ', ')"
                }
            }
        }
        
        # Download the selected asset using Get-FileWithProgress
        Write-Verbose "Downloading asset '$($selectedAsset.name)' from URL: $($selectedAsset.browser_download_url)"
        
        try {
            Get-FileWithProgress -Url $selectedAsset.browser_download_url -OutPath $OutPath -ShowProgress:$false
            Write-Verbose "Successfully downloaded asset '$($selectedAsset.name)' to '$OutPath'"
        }
        catch {
            # Propagate error from Get-FileWithProgress with additional context
            throw "Get-GitHubReleaseAsset: Failed to download asset '$($selectedAsset.name)' from '$($selectedAsset.browser_download_url)'. Error: $_"
        }
    }
    catch {
        Write-Error "Get-GitHubReleaseAsset: Failed to get GitHub release asset. Error: $_"
        throw
    }
}

function Get-CachedBinary {
    <#
    .SYNOPSIS
    Check cache for binary and return path if valid, or $null if not cached.
    
    .DESCRIPTION
    Checks if a binary file exists in the cache directory. If the file exists and
    validation is enabled in the configuration, verifies that the file is readable
    and has a non-zero size. Returns the absolute path to the cached file if valid,
    or $null if not cached or invalid.
    
    .PARAMETER CacheKey
    Cache key identifying the binary file (e.g., "merkle-tree-v1.2.3-windows").
    This will be used as the filename in the cache binaries directory.
    
    .PARAMETER CacheDirectory
    Path to the cache directory root. The binary will be looked for in the
    binaries subdirectory.
    
    .OUTPUTS
    string or $null. Returns the absolute path to the cached file if it exists and
    is valid, or $null if not cached or invalid.
    
    .EXAMPLE
    $cachedPath = Get-CachedBinary -CacheKey "merkle-tree-v1.2.3-windows" -CacheDirectory "C:\cache"
    if ($cachedPath) {
        Write-Host "Found cached binary at: $cachedPath"
    } else {
        Write-Host "Binary not cached"
    }
    
    .EXAMPLE
    $cacheDir = Initialize-CacheDirectory
    $binaryPath = Get-CachedBinary -CacheKey "sqlite3-v5.1.7-windows" -CacheDirectory $cacheDir
    # Checks for cached SQLite3 binary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheKey,
        
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory
    )
    
    try {
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($CacheKey)) {
            throw "Get-CachedBinary: CacheKey parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($CacheDirectory)) {
            throw "Get-CachedBinary: CacheDirectory parameter is null or empty"
        }
        
        # Expand environment variables in cache directory
        $CacheDirectory = [System.Environment]::ExpandEnvironmentVariables($CacheDirectory)
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($CacheDirectory)) {
            $CacheDirectory = [System.IO.Path]::GetFullPath($CacheDirectory)
        }
        
        # Validate cache directory exists
        if (-not (Test-Path -Path $CacheDirectory -PathType Container)) {
            throw "Get-CachedBinary: Cache directory does not exist: '$CacheDirectory'"
        }
        
        # Construct cache file path: $CacheDirectory\binaries\$CacheKey
        $binariesDir = Join-Path -Path $CacheDirectory -ChildPath "binaries"
        $cachedFilePath = Join-Path -Path $binariesDir -ChildPath $CacheKey
        
        Write-Verbose "Checking for cached binary at: $cachedFilePath"
        
        # Check if file exists
        if (-not (Test-Path -Path $cachedFilePath -PathType Leaf)) {
            Write-Verbose "Binary not found in cache: $CacheKey"
            return $null
        }
        
        Write-Verbose "Cached binary found: $cachedFilePath"
        
        # If config has validateOnUse: true, verify file is readable and non-zero size
        try {
            $config = Get-PatcherConfig
            $validateOnUse = $config.cache.validateOnUse
            
            if ($validateOnUse) {
                Write-Verbose "Validation enabled, verifying cached file"
                
                # Verify file is readable
                try {
                    $fileInfo = Get-Item -Path $cachedFilePath -ErrorAction Stop
                }
                catch {
                    Write-Verbose "Cached file is not readable: $_"
                    return $null
                }
                
                # Verify file has non-zero size
                if ($fileInfo.Length -eq 0) {
                    Write-Verbose "Cached file has zero size, treating as cache miss"
                    return $null
                }
                
                Write-Verbose "Cached file validated successfully: $($fileInfo.Length) bytes"
            }
            else {
                Write-Verbose "Validation disabled, skipping file validation"
            }
        }
        catch {
            # If config loading fails, we'll still return the path but log a warning
            Write-Verbose "Failed to load config for validation check, proceeding without validation: $_"
        }
        
        # Return absolute path to cached file
        $absolutePath = [System.IO.Path]::GetFullPath($cachedFilePath)
        Write-Verbose "Returning cached binary path: $absolutePath"
        return $absolutePath
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Get-CachedBinary: Cache directory not found: '$CacheDirectory'"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Get-CachedBinary: Invalid path format. Error: $_"
        throw
    }
    catch {
        Write-Error "Get-CachedBinary: Failed to check cached binary. Error: $_"
        throw
    }
}

function Save-BinaryToCache {
    <#
    .SYNOPSIS
    Save downloaded binary to cache with version-based naming.
    
    .DESCRIPTION
    Copies a binary file from the source path to the cache directory using the
    specified cache key. Ensures the cache directory structure exists before
    copying. Returns the absolute path to the cached file.
    
    .PARAMETER SourcePath
    Path to the source binary file to cache.
    
    .PARAMETER CacheKey
    Cache key to use for the cached file (e.g., "merkle-tree-v1.2.3-windows").
    This will be used as the filename in the cache binaries directory.
    
    .PARAMETER CacheDirectory
    Path to the cache directory root. The binary will be saved in the binaries
    subdirectory.
    
    .OUTPUTS
    string. Returns the absolute path to the cached file.
    
    .EXAMPLE
    $cachedPath = Save-BinaryToCache -SourcePath ".\downloads\binary.exe" -CacheKey "merkle-tree-v1.2.3-windows" -CacheDirectory "C:\cache"
    # Copies binary to cache and returns path
    
    .EXAMPLE
    $cacheDir = Initialize-CacheDirectory
    $binaryPath = Save-BinaryToCache -SourcePath ".\temp\sqlite3.node" -CacheKey "sqlite3-v5.1.7-windows" -CacheDirectory $cacheDir
    # Saves SQLite3 binary to cache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$CacheKey,
        
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory
    )
    
    try {
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($SourcePath)) {
            throw "Save-BinaryToCache: SourcePath parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($CacheKey)) {
            throw "Save-BinaryToCache: CacheKey parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($CacheDirectory)) {
            throw "Save-BinaryToCache: CacheDirectory parameter is null or empty"
        }
        
        # Expand environment variables
        $SourcePath = [System.Environment]::ExpandEnvironmentVariables($SourcePath)
        $CacheDirectory = [System.Environment]::ExpandEnvironmentVariables($CacheDirectory)
        
        # Convert to absolute paths if relative
        if (-not [System.IO.Path]::IsPathRooted($SourcePath)) {
            $SourcePath = [System.IO.Path]::GetFullPath($SourcePath)
        }
        
        if (-not [System.IO.Path]::IsPathRooted($CacheDirectory)) {
            $CacheDirectory = [System.IO.Path]::GetFullPath($CacheDirectory)
        }
        
        # Validate source file exists
        if (-not (Test-Path -Path $SourcePath -PathType Leaf)) {
            throw "Save-BinaryToCache: Source file does not exist: '$SourcePath'"
        }
        
        Write-Verbose "Caching binary from '$SourcePath' with key '$CacheKey'"
        
        # Ensure cache directory exists (call Initialize-CacheDirectory)
        Write-Verbose "Initializing cache directory: $CacheDirectory"
        $initializedCacheDir = Initialize-CacheDirectory -CachePath $CacheDirectory
        
        # Construct destination: $CacheDirectory\binaries\$CacheKey
        $binariesDir = Join-Path -Path $initializedCacheDir -ChildPath "binaries"
        $destinationPath = Join-Path -Path $binariesDir -ChildPath $CacheKey
        
        Write-Verbose "Copying file to cache destination: $destinationPath"
        
        # Copy file from SourcePath to destination
        try {
            # Ensure destination directory exists (should already exist from Initialize-CacheDirectory, but double-check)
            $destDir = [System.IO.Path]::GetDirectoryName($destinationPath)
            if (-not (Test-Path -Path $destDir -PathType Container)) {
                Write-Verbose "Creating destination directory: $destDir"
                $null = New-Item -Path $destDir -ItemType Directory -Force -ErrorAction Stop
            }
            
            # Copy the file
            Copy-Item -Path $SourcePath -Destination $destinationPath -Force -ErrorAction Stop
            
            Write-Verbose "File copied successfully to cache"
        }
        catch [System.UnauthorizedAccessException] {
            throw "Save-BinaryToCache: Permission denied when copying to '$destinationPath'. Error: $_"
        }
        catch [System.IO.DirectoryNotFoundException] {
            throw "Save-BinaryToCache: Destination directory does not exist for '$destinationPath'. Error: $_"
        }
        catch [System.IO.IOException] {
            throw "Save-BinaryToCache: Failed to copy file from '$SourcePath' to '$destinationPath'. Error: $_"
        }
        catch {
            throw "Save-BinaryToCache: Failed to copy file from '$SourcePath' to '$destinationPath'. Error: $_"
        }
        
        # Verify destination file exists
        if (-not (Test-Path -Path $destinationPath -PathType Leaf)) {
            throw "Save-BinaryToCache: File was not copied to destination '$destinationPath'"
        }
        
        # Return absolute path to cached file
        $absolutePath = [System.IO.Path]::GetFullPath($destinationPath)
        Write-Verbose "Binary cached successfully at: $absolutePath"
        return $absolutePath
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Save-BinaryToCache: Source file not found: '$SourcePath'"
        throw
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Save-BinaryToCache: Permission denied. Error: $_"
        throw
    }
    catch [System.IO.DirectoryNotFoundException] {
        Write-Error "Save-BinaryToCache: Directory not found. Error: $_"
        throw
    }
    catch [System.IO.IOException] {
        Write-Error "Save-BinaryToCache: I/O error during copy operation. Error: $_"
        throw
    }
    catch {
        Write-Error "Save-BinaryToCache: Failed to save binary to cache. Error: $_"
        throw
    }
}

#endregion

# Export module members
Export-ModuleMember -Function Get-PatcherConfig, Initialize-CacheDirectory, Get-CursorAgentInstallScript, Get-CursorAgentVersion, Get-Sqlite3Version, Get-MerkleTreeVersion, Get-RipGrepVersion, Get-FileWithProgress, Get-GitHubReleaseAsset, Get-CachedBinary, Save-BinaryToCache
