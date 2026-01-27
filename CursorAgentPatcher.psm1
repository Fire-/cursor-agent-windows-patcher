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
        [Parameter(Mandatory = $false)]
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
        [Parameter(Mandatory = $false)]
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
        [Parameter(Mandatory = $true)]
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
                }
                else {
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
        [Parameter(Mandatory = $true)]
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
        [Parameter(Mandatory = $true)]
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
        [Parameter(Mandatory = $true)]
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
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [string]$OutPath,
        
        [Parameter(Mandatory = $false)]
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

#endregion

#region Download Functions

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

function Get-CursorAgentPackage {
    <#
    .SYNOPSIS
    Download Cursor Agent package for specified version and architecture.
    
    .DESCRIPTION
    Downloads the Cursor Agent package from the official download URL for the
    specified version, source OS, and source architecture. The package is
    downloaded as a tar.gz archive. Validates that the downloaded file exists
    and has a reasonable size (> 1MB) to detect possible corruption.
    
    .PARAMETER Version
    Cursor Agent version string (e.g., "2026.01.23-916f423").
    
    .PARAMETER SourceOs
    Source operating system for the package. Defaults to "darwin" (macOS).
    
    .PARAMETER SourceArch
    Source architecture for the package. Defaults to "arm64".
    
    .PARAMETER OutPath
    Path where the downloaded package should be saved.
    
    .OUTPUTS
    string. Returns the absolute path to the downloaded package file.
    
    .EXAMPLE
    $packagePath = Get-CursorAgentPackage -Version "2026.01.23-916f423" -OutPath ".\packages\cursor-agent.tar.gz"
    # Downloads Cursor Agent package for specified version
    
    .EXAMPLE
    $packagePath = Get-CursorAgentPackage -Version "2026.01.23-916f423" -SourceOs "darwin" -SourceArch "x64" -OutPath ".\packages\cursor-agent.tar.gz"
    # Downloads Cursor Agent package for darwin x64 architecture
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version,
        
        [Parameter(Mandatory=$false)]
        [string]$SourceOs = "darwin",
        
        [Parameter(Mandatory=$false)]
        [string]$SourceArch = "arm64",
        
        [Parameter(Mandatory=$true)]
        [string]$OutPath
    )
    
    try {
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($Version)) {
            throw "Get-CursorAgentPackage: Version parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($SourceOs)) {
            throw "Get-CursorAgentPackage: SourceOs parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($SourceArch)) {
            throw "Get-CursorAgentPackage: SourceArch parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($OutPath)) {
            throw "Get-CursorAgentPackage: OutPath parameter is null or empty"
        }
        
        # Expand environment variables in output path
        $OutPath = [System.Environment]::ExpandEnvironmentVariables($OutPath)
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($OutPath)) {
            $OutPath = [System.IO.Path]::GetFullPath($OutPath)
        }
        
        # Construct URL: https://downloads.cursor.com/lab/$Version/$SourceOs/$SourceArch/agent-cli-package.tar.gz
        $downloadUrl = "https://downloads.cursor.com/lab/$Version/$SourceOs/$SourceArch/agent-cli-package.tar.gz"
        
        Write-Verbose "Downloading Cursor Agent package from: $downloadUrl"
        Write-Verbose "Saving to: $OutPath"
        
        # Validate URL format (basic check)
        if ($downloadUrl -notmatch '^https?://') {
            throw "Get-CursorAgentPackage: Invalid URL format: '$downloadUrl'"
        }
        
        # Download using Get-FileWithProgress
        try {
            Get-FileWithProgress -Url $downloadUrl -OutPath $OutPath -ShowProgress:$false
            Write-Verbose "Package downloaded successfully"
        }
        catch {
            throw "Get-CursorAgentPackage: Failed to download package from '$downloadUrl'. Error: $_"
        }
        
        # Verify file exists
        if (-not (Test-Path -Path $OutPath -PathType Leaf)) {
            throw "Get-CursorAgentPackage: File was not created at '$OutPath' after download"
        }
        
        # Verify file has reasonable size (> 1MB)
        $fileInfo = Get-Item -Path $OutPath -ErrorAction Stop
        $minSizeBytes = 1MB  # 1 megabyte
        
        if ($fileInfo.Length -lt $minSizeBytes) {
            throw "Get-CursorAgentPackage: Downloaded file at '$OutPath' is too small ($($fileInfo.Length) bytes, expected at least $minSizeBytes bytes). File may be corrupted or download may have failed."
        }
        
        Write-Verbose "Package downloaded successfully: $OutPath ($($fileInfo.Length) bytes)"
        
        # Return absolute path to downloaded file
        $absolutePath = [System.IO.Path]::GetFullPath($OutPath)
        return $absolutePath
    }
    catch [System.UriFormatException] {
        Write-Error "Get-CursorAgentPackage: Invalid URL format. Error: $_"
        throw
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Get-CursorAgentPackage: Output directory not found. Error: $_"
        throw
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Get-CursorAgentPackage: Permission denied when writing to '$OutPath'. Error: $_"
        throw
    }
    catch {
        Write-Error "Get-CursorAgentPackage: Failed to download Cursor Agent package. Error: $_"
        throw
    }
}

function Expand-CursorAgentPackage {
    <#
    .SYNOPSIS
    Extract Cursor Agent package archive (.tar.gz) to directory.
    
    .DESCRIPTION
    Extracts a .tar.gz archive containing the Cursor Agent package to the specified
    output directory. Attempts to use 7-Zip if available, otherwise falls back to
    PowerShell's Expand-Archive (which may not support .tar.gz in PowerShell 5.1).
    If no extraction tool is available, throws an error with installation instructions.
    
    .PARAMETER ArchivePath
    Path to the .tar.gz archive file to extract.
    
    .PARAMETER OutDirectory
    Directory where the archive should be extracted.
    
    .OUTPUTS
    string. Returns the absolute path to the extracted directory.
    
    .EXAMPLE
    $extractedPath = Expand-CursorAgentPackage -ArchivePath ".\cursor-agent.tar.gz" -OutDirectory ".\extracted"
    # Extracts the archive to the specified directory
    
    .EXAMPLE
    $extractedPath = Expand-CursorAgentPackage -ArchivePath "C:\packages\agent.tar.gz" -OutDirectory "C:\extracted\agent"
    # Extracts archive using absolute paths
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,
        
        [Parameter(Mandatory=$true)]
        [string]$OutDirectory
    )
    
    try {
        # Validate archive path
        if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
            throw "Expand-CursorAgentPackage: ArchivePath parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($OutDirectory)) {
            throw "Expand-CursorAgentPackage: OutDirectory parameter is null or empty"
        }
        
        # Expand environment variables
        $ArchivePath = [System.Environment]::ExpandEnvironmentVariables($ArchivePath)
        $OutDirectory = [System.Environment]::ExpandEnvironmentVariables($OutDirectory)
        
        # Convert to absolute paths
        if (-not [System.IO.Path]::IsPathRooted($ArchivePath)) {
            $ArchivePath = [System.IO.Path]::GetFullPath($ArchivePath)
        }
        
        if (-not [System.IO.Path]::IsPathRooted($OutDirectory)) {
            $OutDirectory = [System.IO.Path]::GetFullPath($OutDirectory)
        }
        
        # Check if archive exists
        if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
            throw "Expand-CursorAgentPackage: Archive file not found at '$ArchivePath'"
        }
        
        Write-Verbose "Extracting archive from '$ArchivePath' to '$OutDirectory'"
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutDirectory -PathType Container)) {
            Write-Verbose "Creating output directory: $OutDirectory"
            New-Item -Path $OutDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        
        # Check if 7-Zip is available
        $sevenZipPath = $null
        try {
            $sevenZipPath = Get-Command -Name "7z.exe" -ErrorAction Stop | Select-Object -ExpandProperty Source
            Write-Verbose "Found 7-Zip at: $sevenZipPath"
        }
        catch {
            Write-Verbose "7-Zip not found in PATH, will try PowerShell Expand-Archive"
        }
        
        # Try 7-Zip first if available
        if ($null -ne $sevenZipPath) {
            try {
                Write-Verbose "Extracting using 7-Zip..."
                
                # 7-Zip command: 7z x archive.tar.gz -o"output_dir" -y
                # Then extract the .tar file: 7z x archive.tar -o"output_dir" -y
                # For .tar.gz, we need to extract twice: first the .gz, then the .tar
                
                # Create temporary directory for intermediate extraction
                $tempDir = Join-Path -Path $env:TEMP -ChildPath "cursor-agent-extract-$(New-Guid)"
                New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                
                try {
                    # First, extract .gz to get .tar file
                    $tarFile = Join-Path -Path $tempDir -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($ArchivePath))
                    Write-Verbose "Extracting .gz layer to: $tarFile"
                    
                    $processArgs = @(
                        "x",
                        "`"$ArchivePath`"",
                        "-o`"$tempDir`"",
                        "-y"
                    )
                    
                    $process = Start-Process -FilePath $sevenZipPath -ArgumentList $processArgs -Wait -NoNewWindow -PassThru -ErrorAction Stop
                    
                    if ($process.ExitCode -ne 0) {
                        throw "7-Zip extraction failed with exit code $($process.ExitCode)"
                    }
                    
                    # Find the extracted .tar file
                    $extractedTarFile = Get-ChildItem -Path $tempDir -Filter "*.tar" -ErrorAction SilentlyContinue | Select-Object -First 1
                    
                    if ($null -eq $extractedTarFile) {
                        throw "7-Zip did not extract a .tar file from the archive"
                    }
                    
                    Write-Verbose "Found .tar file: $($extractedTarFile.FullName)"
                    
                    # Second, extract .tar to final output directory
                    Write-Verbose "Extracting .tar layer to: $OutDirectory"
                    
                    $processArgs = @(
                        "x",
                        "`"$($extractedTarFile.FullName)`"",
                        "-o`"$OutDirectory`"",
                        "-y"
                    )
                    
                    $process = Start-Process -FilePath $sevenZipPath -ArgumentList $processArgs -Wait -NoNewWindow -PassThru -ErrorAction Stop
                    
                    if ($process.ExitCode -ne 0) {
                        throw "7-Zip .tar extraction failed with exit code $($process.ExitCode)"
                    }
                    
                    Write-Verbose "Archive extracted successfully using 7-Zip"
                }
                finally {
                    # Clean up temporary directory
                    if (Test-Path -Path $tempDir -PathType Container) {
                        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {
                throw "Expand-CursorAgentPackage: Failed to extract archive using 7-Zip. Error: $_"
            }
        }
        else {
            # Try PowerShell Expand-Archive (may not work for .tar.gz in PowerShell 5.1)
            Write-Verbose "Attempting to extract using PowerShell Expand-Archive..."
            
            try {
                # PowerShell 5.1's Expand-Archive may not support .tar.gz
                # We'll try it, but expect it might fail
                Expand-Archive -Path $ArchivePath -DestinationPath $OutDirectory -Force -ErrorAction Stop
                Write-Verbose "Archive extracted successfully using PowerShell Expand-Archive"
            }
            catch {
                # PowerShell Expand-Archive doesn't support .tar.gz in PowerShell 5.1
                $errorMessage = "Expand-CursorAgentPackage: No extraction tool available. PowerShell Expand-Archive does not support .tar.gz files in PowerShell 5.1. " +
                                "Please install 7-Zip (https://www.7-zip.org/) and ensure '7z.exe' is in your PATH, then try again. " +
                                "Error from Expand-Archive: $_"
                throw $errorMessage
            }
        }
        
        # Verify extraction succeeded - check that output directory has content
        $extractedItems = Get-ChildItem -Path $OutDirectory -ErrorAction SilentlyContinue
        if ($null -eq $extractedItems -or $extractedItems.Count -eq 0) {
            throw "Expand-CursorAgentPackage: Extraction completed but output directory '$OutDirectory' is empty. Archive may be corrupted or extraction may have failed."
        }
        
        Write-Verbose "Extraction verified: $($extractedItems.Count) item(s) found in output directory"
        
        # Return absolute path to extracted directory
        return [System.IO.Path]::GetFullPath($OutDirectory)
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "Expand-CursorAgentPackage: Archive file not found at '$ArchivePath'. Error: $_"
        throw
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Expand-CursorAgentPackage: Permission denied when accessing '$ArchivePath' or writing to '$OutDirectory'. Error: $_"
        throw
    }
    catch {
        Write-Error "Expand-CursorAgentPackage: Failed to extract archive. Error: $_"
        throw
    }
}

#endregion

#region Patch Registry

# Patch Registry Data Structure
# Stores all registered patches that can be applied to Cursor Agent files
$script:PatchRegistry = @{}

function Test-PatchRegistry {
    <#
    .SYNOPSIS
    Validate patch registry structure and return validation results.
    
    .DESCRIPTION
    Validates that all patches in the registry have required fields (Description, FilePattern,
    Priority, Apply, Verify), that dependencies reference existing patch IDs, that priorities
    are positive integers, and that Apply and Verify are scriptblocks.
    
    .OUTPUTS
    hashtable. Returns a hashtable with validation results:
    - Valid: boolean indicating if registry is valid
    - Errors: array of error messages (empty if valid)
    
    .EXAMPLE
    $result = Test-PatchRegistry
    if (-not $result.Valid) {
        Write-Error "Registry validation failed: $($result.Errors -join '; ')"
    }
    #>
    [CmdletBinding()]
    param()
    
    $errors = @()
    
    try {
        # Check if registry exists
        if ($null -eq $script:PatchRegistry) {
            $errors += "Patch registry is null"
            return @{ Valid = $false; Errors = $errors }
        }
        
        if ($script:PatchRegistry -isnot [hashtable]) {
            $errors += "Patch registry is not a hashtable"
            return @{ Valid = $false; Errors = $errors }
        }
        
        # Get all patch IDs for dependency validation
        $patchIds = $script:PatchRegistry.Keys
        
        # Validate each patch
        foreach ($patchId in $patchIds) {
            $patch = $script:PatchRegistry[$patchId]
            
            # Check if patch is a hashtable
            if ($patch -isnot [hashtable]) {
                $errors += "Patch '$patchId': Patch entry is not a hashtable"
                continue
            }
            
            # Validate required fields
            $requiredFields = @('Description', 'FilePattern', 'Priority', 'Apply', 'Verify')
            foreach ($field in $requiredFields) {
                if (-not $patch.ContainsKey($field)) {
                    $errors += "Patch '$patchId': Missing required field '$field'"
                }
            }
            
            # Validate Description is a string
            if ($patch.Description -and $patch.Description -isnot [string]) {
                $errors += "Patch '$patchId': Description must be a string"
            }
            
            # Validate FilePattern is a string
            if ($patch.FilePattern -and $patch.FilePattern -isnot [string]) {
                $errors += "Patch '$patchId': FilePattern must be a string"
            }
            
            # Validate Priority is a positive integer
            if ($patch.ContainsKey('Priority')) {
                if ($patch.Priority -isnot [int] -and $patch.Priority -isnot [long] -and $patch.Priority -isnot [System.Int32] -and $patch.Priority -isnot [System.Int64]) {
                    $errors += "Patch '$patchId': Priority must be an integer"
                }
                elseif ($patch.Priority -le 0) {
                    $errors += "Patch '$patchId': Priority must be a positive integer (got $($patch.Priority))"
                }
            }
            
            # Validate Apply is a scriptblock
            if ($patch.Apply -and $patch.Apply -isnot [scriptblock]) {
                $errors += "Patch '$patchId': Apply must be a scriptblock"
            }
            
            # Validate Verify is a scriptblock
            if ($patch.Verify -and $patch.Verify -isnot [scriptblock]) {
                $errors += "Patch '$patchId': Verify must be a scriptblock"
            }
            
            # Validate Dependencies (if present)
            if ($patch.Dependencies) {
                if ($patch.Dependencies -isnot [array]) {
                    $errors += "Patch '$patchId': Dependencies must be an array"
                }
                else {
                    foreach ($depId in $patch.Dependencies) {
                        if ($depId -isnot [string]) {
                            $errors += "Patch '$patchId': Dependency ID must be a string (got: $depId)"
                        }
                        elseif ($depId -notin $patchIds) {
                            $errors += "Patch '$patchId': Dependency '$depId' references non-existent patch ID"
                        }
                    }
                }
            }
        }
        
        # Return validation result
        if ($errors.Count -eq 0) {
            return @{ Valid = $true; Errors = @() }
        }
        else {
            return @{ Valid = $false; Errors = $errors }
        }
    }
    catch {
        Write-Error "Test-PatchRegistry: Failed to validate patch registry. Error: $_"
        return @{ Valid = $false; Errors = @("Validation error: $_") }
    }
}

#endregion

#region Patch System Functions

function Find-FilesMatchingPattern {
    <#
    .SYNOPSIS
    Find all files in directory tree matching a glob pattern.
    
    .DESCRIPTION
    Searches recursively from the root path for files matching the specified
    PowerShell glob pattern. Handles `**` as a recursive wildcard. Returns
    an array of absolute paths to matching files. Returns empty array if
    no matches are found (not an error condition).
    
    .PARAMETER RootPath
    Root directory path to search from.
    
    .PARAMETER Pattern
    PowerShell glob pattern to match (e.g., "**/native.js", "*.js", "**/*.node").
    
    .OUTPUTS
    string[]. Returns an array of absolute paths to matching files, or empty array if no matches.
    
    .EXAMPLE
    $files = Find-FilesMatchingPattern -RootPath ".\package" -Pattern "**/native.js"
    # Finds all native.js files recursively in package directory
    
    .EXAMPLE
    $files = Find-FilesMatchingPattern -RootPath "C:\cursor-agent" -Pattern "*.js"
    # Finds all .js files in cursor-agent directory and subdirectories
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Pattern
    )
    
    try {
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($RootPath)) {
            throw "Find-FilesMatchingPattern: RootPath parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($Pattern)) {
            throw "Find-FilesMatchingPattern: Pattern parameter is null or empty"
        }
        
        # Expand environment variables in root path
        $RootPath = [System.Environment]::ExpandEnvironmentVariables($RootPath)
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($RootPath)) {
            $RootPath = [System.IO.Path]::GetFullPath($RootPath)
        }
        
        # Validate root path exists
        if (-not (Test-Path -Path $RootPath -PathType Container)) {
            throw "Find-FilesMatchingPattern: Root path does not exist or is not a directory: '$RootPath'"
        }
        
        Write-Verbose "Searching for files matching pattern '$Pattern' in directory: $RootPath"
        
        # PowerShell's Get-ChildItem supports glob patterns natively
        # The `**` pattern is supported for recursive searches
        # We'll use -Recurse to search recursively and -Include for pattern matching
        
        # Handle different pattern formats
        # If pattern starts with **/, we need to search recursively from root
        # If pattern contains **, we need recursive search
        # Otherwise, we can use a simpler approach
        
        $matchingFiles = @()
        
        # Check if pattern contains ** for recursive wildcard
        if ($Pattern -match '\*\*') {
            # Pattern contains ** - use recursive search
            # Remove leading **/ if present (we're already searching recursively)
            $searchPattern = $Pattern -replace '^\*\*/', ''
            
            # If pattern is just ** or **/, search all files
            if ($searchPattern -eq '' -or $searchPattern -eq '*') {
                $searchPattern = '*'
            }
            
            Write-Verbose "Using recursive search with pattern: $searchPattern"
            
            # Use Get-ChildItem with -Recurse and -Include
            # -Include works with file names/patterns
            try {
                $files = Get-ChildItem -Path $RootPath -Recurse -File -Include $searchPattern -ErrorAction Stop
                $matchingFiles = $files | ForEach-Object { $_.FullName }
            }
            catch {
                # If -Include doesn't work with the pattern, try -Filter
                # -Filter only works with simple patterns (no **)
                # So we'll need to handle this differently
                Write-Verbose "Include pattern failed, trying alternative approach: $_"
                
                # For patterns with **, we need to search all files and filter manually
                if ($Pattern -match '\*\*') {
                    $allFiles = Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction Stop
                    
                    # Convert glob pattern to regex for matching
                    # Replace ** with .* (matches any path segment)
                    # Replace * with [^/]* (matches any characters except /)
                    # Replace ? with . (matches single character)
                    # Escape other special regex characters
                    $regexPattern = $Pattern
                    $regexPattern = $regexPattern -replace '\.', '\.'  # Escape dots
                    $regexPattern = $regexPattern -replace '\*\*', '.*'  # ** matches any path
                    $regexPattern = $regexPattern -replace '\*', '[^/]*'  # * matches non-slash chars
                    $regexPattern = $regexPattern -replace '\?', '.'  # ? matches single char
                    
                    # For patterns like **/native.js, we need to match against relative path from RootPath
                    foreach ($file in $allFiles) {
                        $relativePath = $file.FullName.Substring($RootPath.Length).TrimStart('\', '/')
                        # Normalize path separators to forward slashes for pattern matching
                        $normalizedPath = $relativePath -replace '\\', '/'
                        
                        if ($normalizedPath -match "^$regexPattern$") {
                            $matchingFiles += $file.FullName
                        }
                    }
                }
            }
        }
        else {
            # Simple pattern without ** - can use -Filter or -Include
            Write-Verbose "Using simple pattern search: $Pattern"
            
            try {
                # Try -Include first (more flexible)
                $files = Get-ChildItem -Path $RootPath -Recurse -File -Include $Pattern -ErrorAction Stop
                $matchingFiles = $files | ForEach-Object { $_.FullName }
            }
            catch {
                # Fallback to -Filter for simple patterns
                Write-Verbose "Include failed, trying Filter: $_"
                $files = Get-ChildItem -Path $RootPath -Recurse -File -Filter $Pattern -ErrorAction Stop
                $matchingFiles = $files | ForEach-Object { $_.FullName }
            }
        }
        
        # Sort results for consistent output
        $matchingFiles = $matchingFiles | Sort-Object
        
        Write-Verbose "Found $($matchingFiles.Count) file(s) matching pattern '$Pattern'"
        
        # Return array of absolute paths (empty array if no matches - not an error)
        return $matchingFiles
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Find-FilesMatchingPattern: Root path not found: '$RootPath'"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Find-FilesMatchingPattern: Invalid path or pattern format. Error: $_"
        throw
    }
    catch {
        Write-Error "Find-FilesMatchingPattern: Failed to find files matching pattern '$Pattern' in '$RootPath'. Error: $_"
        throw
    }
}

function Resolve-PatchDependencies {
    <#
    .SYNOPSIS
    Sort patches by priority and dependencies to determine execution order.
    
    .DESCRIPTION
    Resolves patch dependencies and returns an ordered array of patch IDs that
    ensures patches are executed in the correct order. Patches are sorted by
    priority (lower numbers first), and within the same priority, dependencies
    are executed before dependents (topological sort). Detects and reports
    circular dependencies.
    
    .PARAMETER PatchRegistry
    Hashtable containing the patch registry with patch IDs as keys and patch
    definitions as values.
    
    .OUTPUTS
    array. Returns an ordered array of patch IDs in execution order.
    
    .EXAMPLE
    $orderedPatches = Resolve-PatchDependencies -PatchRegistry $script:PatchRegistry
    # Returns patches sorted by priority and dependencies
    
    .EXAMPLE
    $registry = @{
        "patch-a" = @{ Priority = 2; Dependencies = @("patch-b") }
        "patch-b" = @{ Priority = 1; Dependencies = @() }
    }
    $order = Resolve-PatchDependencies -PatchRegistry $registry
    # Returns: @("patch-b", "patch-a")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PatchRegistry
    )
    
    try {
        # Validate parameter
        if ($null -eq $PatchRegistry) {
            throw "Resolve-PatchDependencies: PatchRegistry parameter is null"
        }
        
        if ($PatchRegistry.Count -eq 0) {
            Write-Verbose "Patch registry is empty, returning empty array"
            return @()
        }
        
        Write-Verbose "Resolving dependencies for $($PatchRegistry.Count) patch(es)"
        
        # Build dependency graph and collect all patch IDs
        $patchIds = $PatchRegistry.Keys | ForEach-Object { $_ }
        $dependencyGraph = @{}
        $priorities = @{}
        
        # Initialize graph and collect priorities
        foreach ($patchId in $patchIds) {
            $patch = $PatchRegistry[$patchId]
            
            if ($null -eq $patch) {
                throw "Resolve-PatchDependencies: Patch '$patchId' is null in registry"
            }
            
            # Get dependencies (default to empty array if not present)
            $dependencies = if ($patch.Dependencies) { $patch.Dependencies } else { @() }
            
            # Validate dependencies exist in registry
            foreach ($depId in $dependencies) {
                if ($depId -notin $patchIds) {
                    throw "Resolve-PatchDependencies: Patch '$patchId' has dependency '$depId' that does not exist in registry"
                }
            }
            
            $dependencyGraph[$patchId] = $dependencies
            
            # Get priority (default to 100 if not present, so it runs last)
            $priority = if ($patch.Priority) { $patch.Priority } else { 100 }
            $priorities[$patchId] = $priority
        }
        
        # Detect circular dependencies using DFS
        Write-Verbose "Detecting circular dependencies"
        $visited = @{}
        $recursionStack = @{}
        
        function Test-CircularDependency {
            param([string]$PatchId, [hashtable]$Graph, [hashtable]$Visited, [hashtable]$RecursionStack, [array]$Path)
            
            $Visited[$PatchId] = $true
            $RecursionStack[$PatchId] = $true
            $newPath = $Path + $PatchId
            
            foreach ($depId in $Graph[$PatchId]) {
                if (-not $Visited[$depId]) {
                    $result = Test-CircularDependency -PatchId $depId -Graph $Graph -Visited $Visited -RecursionStack $RecursionStack -Path $newPath
                    if ($result.Circular) {
                        return $result
                    }
                }
                elseif ($RecursionStack[$depId]) {
                    # Found a cycle
                    $cycleStart = $newPath.IndexOf($depId)
                    $cycle = $newPath[$cycleStart..($newPath.Length - 1)] + $depId
                    return @{ Circular = $true; Cycle = $cycle }
                }
            }
            
            $RecursionStack[$PatchId] = $false
            return @{ Circular = $false }
        }
        
        foreach ($patchId in $patchIds) {
            if (-not $visited[$patchId]) {
                $cycleResult = Test-CircularDependency -PatchId $patchId -Graph $dependencyGraph -Visited $visited -RecursionStack $recursionStack -Path @()
                if ($cycleResult.Circular) {
                    $cycleString = $cycleResult.Cycle -join " -> "
                    throw "Resolve-PatchDependencies: Circular dependency detected: $cycleString"
                }
            }
        }
        
        Write-Verbose "No circular dependencies found"
        
        # Topological sort with priority ordering
        # Strategy:
        # 1. Group patches by priority
        # 2. Within each priority group, perform topological sort
        # 3. Combine groups in priority order
        
        # Group patches by priority
        $priorityGroups = @{}
        foreach ($patchId in $patchIds) {
            $priority = $priorities[$patchId]
            if (-not $priorityGroups.ContainsKey($priority)) {
                $priorityGroups[$priority] = @()
            }
            $priorityGroups[$priority] += $patchId
        }
        
        # Sort priority groups (lower priority first)
        $sortedPriorities = $priorityGroups.Keys | Sort-Object
        
        $orderedPatches = @()
        
        # Process each priority group
        foreach ($priority in $sortedPriorities) {
            $groupPatches = $priorityGroups[$priority]
            Write-Verbose "Processing priority group $priority with $($groupPatches.Count) patch(es)"
            
            # Topological sort within this priority group
            $groupOrdered = @()
            $groupVisited = @{}
            $groupInProgress = @{}
            
            function Invoke-TopologicalSort {
                param([string]$PatchId, [hashtable]$Graph, [hashtable]$Priorities, [int]$CurrentPriority, [hashtable]$Visited, [hashtable]$InProgress, [array]$Result)
                
                if ($Visited[$PatchId]) {
                    return $Result
                }
                
                $InProgress[$PatchId] = $true
                
                # Process dependencies first (only those in the same priority group)
                foreach ($depId in $Graph[$PatchId]) {
                    if ($Priorities[$depId] -eq $CurrentPriority -and -not $Visited[$depId]) {
                        $Result = Invoke-TopologicalSort -PatchId $depId -Graph $Graph -Priorities $Priorities -CurrentPriority $CurrentPriority -Visited $Visited -InProgress $InProgress -Result $Result
                    }
                }
                
                $Visited[$PatchId] = $true
                $InProgress[$PatchId] = $false
                return $Result + $PatchId
            }
            
            foreach ($patchId in $groupPatches) {
                if (-not $groupVisited[$patchId]) {
                    $groupOrdered = Invoke-TopologicalSort -PatchId $patchId -Graph $dependencyGraph -Priorities $priorities -CurrentPriority $priority -Visited $groupVisited -InProgress $groupInProgress -Result $groupOrdered
                }
            }
            
            # Add this group's patches to the ordered list
            $orderedPatches += $groupOrdered
        }
        
        Write-Verbose "Resolved execution order: $($orderedPatches -join ', ')"
        return $orderedPatches
    }
    catch {
        Write-Error "Resolve-PatchDependencies: Failed to resolve patch dependencies. Error: $_"
        throw
    }
}

function Invoke-Patch {
    <#
    .SYNOPSIS
    Apply a single patch to matching files with verification.
    
    .DESCRIPTION
    Finds all files matching the patch's file pattern in the package directory,
    applies the patch to each file, and verifies the patch was applied correctly.
    Supports -WhatIf mode for dry-run operations. Returns detailed results including
    success status, number of files patched, and any errors encountered.
    
    .PARAMETER PatchDefinition
    Hashtable containing the patch definition with the following keys:
    - FilePattern: Glob pattern to match files (e.g., "**/native.js")
    - Apply: Scriptblock that applies the patch (receives file path and context)
    - Verify: Scriptblock that verifies the patch (receives file path and context)
    - Description: Optional description of the patch
    
    .PARAMETER PackagePath
    Path to the extracted package directory where files should be patched.
    
    .PARAMETER Context
    Hashtable containing context information for the patch (e.g., versions, paths).
    This context is passed to both the Apply and Verify scriptblocks.
    
    .PARAMETER WhatIf
    If specified, shows what would be done without actually applying the patch.
    
    .OUTPUTS
    hashtable. Returns a hashtable with the following keys:
    - Success: boolean indicating if all patches succeeded (no errors)
    - FilesPatched: integer count of files successfully patched
    - Errors: array of error messages (empty if no errors)
    
    .EXAMPLE
    $patch = @{
        FilePattern = "**/native.js"
        Apply = { param($file, $ctx) Set-Content -Path $file -Value "patched" }
        Verify = { param($file, $ctx) Test-Path $file }
    }
    $result = Invoke-Patch -PatchDefinition $patch -PackagePath ".\package" -Context @{}
    if ($result.Success) {
        Write-Host "Patched $($result.FilesPatched) files"
    }
    
    .EXAMPLE
    $result = Invoke-Patch -PatchDefinition $patch -PackagePath ".\package" -Context @{} -WhatIf
    # Shows what would be patched without actually applying
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PatchDefinition,
        
        [Parameter(Mandatory=$true)]
        [string]$PackagePath,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    try {
        # Validate parameters
        if ($null -eq $PatchDefinition) {
            throw "Invoke-Patch: PatchDefinition parameter is null"
        }
        
        if ([string]::IsNullOrWhiteSpace($PackagePath)) {
            throw "Invoke-Patch: PackagePath parameter is null or empty"
        }
        
        if ($null -eq $Context) {
            throw "Invoke-Patch: Context parameter is null"
        }
        
        # Validate patch definition has required fields
        if (-not $PatchDefinition.ContainsKey('FilePattern')) {
            throw "Invoke-Patch: PatchDefinition missing required field 'FilePattern'"
        }
        
        if (-not $PatchDefinition.ContainsKey('Apply')) {
            throw "Invoke-Patch: PatchDefinition missing required field 'Apply'"
        }
        
        if (-not $PatchDefinition.ContainsKey('Verify')) {
            throw "Invoke-Patch: PatchDefinition missing required field 'Verify'"
        }
        
        # Validate Apply and Verify are scriptblocks
        if ($PatchDefinition.Apply -isnot [scriptblock]) {
            throw "Invoke-Patch: PatchDefinition.Apply must be a scriptblock"
        }
        
        if ($PatchDefinition.Verify -isnot [scriptblock]) {
            throw "Invoke-Patch: PatchDefinition.Verify must be a scriptblock"
        }
        
        # Expand environment variables in package path
        $PackagePath = [System.Environment]::ExpandEnvironmentVariables($PackagePath)
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($PackagePath)) {
            $PackagePath = [System.IO.Path]::GetFullPath($PackagePath)
        }
        
        # Validate package path exists
        if (-not (Test-Path -Path $PackagePath -PathType Container)) {
            throw "Invoke-Patch: Package path does not exist or is not a directory: '$PackagePath'"
        }
        
        $filePattern = $PatchDefinition.FilePattern
        $description = if ($PatchDefinition.Description) { $PatchDefinition.Description } else { "Patch" }
        
        Write-Verbose "Applying patch '$description' with pattern '$filePattern' to package: $PackagePath"
        
        # Find files matching the pattern using Find-FilesMatchingPattern
        try {
            $matchingFiles = Find-FilesMatchingPattern -RootPath $PackagePath -Pattern $filePattern
        }
        catch {
            throw "Invoke-Patch: Failed to find files matching pattern '$filePattern'. Error: $_"
        }
        
        # Initialize result
        $result = @{
            Success = $true
            FilesPatched = 0
            Errors = @()
        }
        
        # If no files found, return success with 0 files patched (not an error per spec)
        if ($matchingFiles.Count -eq 0) {
            Write-Verbose "No files found matching pattern '$filePattern'"
            return $result
        }
        
        Write-Verbose "Found $($matchingFiles.Count) file(s) matching pattern '$filePattern'"
        
        # Process each matching file
        foreach ($filePath in $matchingFiles) {
            try {
                Write-Verbose "Processing file: $filePath"
                
                if ($WhatIf) {
                    # WhatIf mode: log what would be done
                    if ($PSCmdlet.ShouldProcess($filePath, "Apply patch '$description'")) {
                        Write-Host "What if: Applying patch '$description' to file: $filePath"
                    }
                    # In WhatIf mode, we still count it as "would be patched" but don't actually apply
                    $result.FilesPatched++
                }
                else {
                    # Apply the patch
                    try {
                        Write-Verbose "Calling Apply scriptblock for file: $filePath"
                        $null = & $PatchDefinition.Apply $filePath $Context
                        Write-Verbose "Apply scriptblock completed successfully"
                    }
                    catch {
                        $errorMsg = "Invoke-Patch: Failed to apply patch to file '$filePath'. Error: $_"
                        Write-Error $errorMsg
                        $result.Errors += $errorMsg
                        $result.Success = $false
                        # Continue with next file (per spec: catch, record error, continue)
                        continue
                    }
                    
                    # Verify the patch
                    try {
                        Write-Verbose "Calling Verify scriptblock for file: $filePath"
                        $verifyResult = & $PatchDefinition.Verify $filePath $Context
                        
                        # Verify scriptblock should return $true or a truthy value for success
                        if (-not $verifyResult) {
                            $errorMsg = "Invoke-Patch: Verification failed for file '$filePath'. Verify scriptblock returned: $verifyResult"
                            Write-Warning $errorMsg
                            $result.Errors += $errorMsg
                            $result.Success = $false
                            # Per spec: Verify fails → Record error but don't throw (allow manual inspection)
                            # Continue processing but mark as unsuccessful
                        }
                        else {
                            Write-Verbose "Verification passed for file: $filePath"
                            $result.FilesPatched++
                        }
                    }
                    catch {
                        # Verify scriptblock threw an exception
                        $errorMsg = "Invoke-Patch: Verification scriptblock threw an error for file '$filePath'. Error: $_"
                        Write-Warning $errorMsg
                        $result.Errors += $errorMsg
                        $result.Success = $false
                        # Per spec: Verify fails → Record error but don't throw
                        # Continue processing but mark as unsuccessful
                    }
                }
            }
            catch {
                # Unexpected error processing this file
                $errorMsg = "Invoke-Patch: Unexpected error processing file '$filePath'. Error: $_"
                Write-Error $errorMsg
                $result.Errors += $errorMsg
                $result.Success = $false
                # Continue with next file
                continue
            }
        }
        
        # Log summary
        if ($WhatIf) {
            Write-Verbose "WhatIf: Would patch $($result.FilesPatched) file(s)"
        }
        else {
            if ($result.Success) {
                Write-Verbose "Successfully patched $($result.FilesPatched) file(s)"
            }
            else {
                Write-Verbose "Patched $($result.FilesPatched) file(s) with $($result.Errors.Count) error(s)"
            }
        }
        
        return $result
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "Invoke-Patch: Package path not found: '$PackagePath'"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "Invoke-Patch: Invalid parameter format. Error: $_"
        throw
    }
    catch {
        Write-Error "Invoke-Patch: Failed to apply patch. Error: $_"
        throw
    }
}

#endregion

#region Patch Registration Functions

function Register-PlatformDetectionPatch {
    <#
    .SYNOPSIS
    Register the platform detection patch in the patch registry.
    
    .DESCRIPTION
    Registers the platform detection patch that modifies native.js files to support
    Windows platform by adding a win32 branch. This patch must run first (priority 1)
    before other patches that depend on Windows platform detection.
    
    .EXAMPLE
    Register-PlatformDetectionPatch
    # Registers the platform detection patch in the patch registry
    #>
    [CmdletBinding()]
    param()
    
    try {
        $script:PatchRegistry['platform-detection'] = @{
            Description = "Modify native.js to support Windows platform by adding win32 branch"
            FilePattern = "**/native.js"
            Priority = 1
            Dependencies = @()
            Apply = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Applying platform detection patch to: $FilePath"
                
                # Read file content
                $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
                
                # Detect available loaders by searching for require_merkle_tree_napi_* patterns
                # Pattern: require_merkle_tree_napi_([a-zA-Z0-9_]+)
                $loaderPattern = 'require_merkle_tree_napi_([a-zA-Z0-9_]+)'
                $loaderMatches = [regex]::Matches($content, $loaderPattern)
                
                if ($loaderMatches.Count -eq 0) {
                    throw "Register-PlatformDetectionPatch: No merkle tree loaders found in file '$FilePath'"
                }
                
                # Extract available loader names
                $availableLoaders = $loaderMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
                Write-Verbose "Found available loaders: $($availableLoaders -join ', ')"
                
                # Select best loader:
                # 1. If Windows x64 and darwin-x64 available → use darwin-x64
                # 2. Else if darwin-arm64 available → use darwin-arm64
                # 3. Else use first available loader
                $selectedLoader = $null
                
                # Check for darwin-x64 (preferred for Windows x64)
                if ($availableLoaders -contains 'darwin_x64') {
                    $selectedLoader = 'darwin_x64'
                    Write-Verbose "Selected loader: darwin_x64 (preferred for Windows x64)"
                }
                elseif ($availableLoaders -contains 'darwin-arm64') {
                    $selectedLoader = 'darwin-arm64'
                    Write-Verbose "Selected loader: darwin-arm64 (fallback)"
                }
                else {
                    $selectedLoader = $availableLoaders[0]
                    Write-Verbose "Selected loader: $selectedLoader (first available)"
                }
                
                # Find pattern: } else {\s+throw new Error(`Unsupported platform: ${platform3}`);
                # Need to match the exact pattern with proper escaping
                # Pattern should match: } else { followed by whitespace, then throw new Error(`Unsupported platform: ${platform3}`);
                # Use multiline matching to handle newlines
                $patternToFind = '(?s)\}\s+else\s+\{\s+throw\s+new\s+Error\(`Unsupported\s+platform:\s+\$\{platform3\}`\);'
                
                # Try to find the pattern
                $match = [regex]::Match($content, $patternToFind)
                
                if (-not $match.Success) {
                    # Try a more flexible pattern (allow different whitespace)
                    $flexiblePattern = '(?s)\}\s*else\s*\{\s*throw\s+new\s+Error\([^)]*Unsupported\s+platform[^)]*\);'
                    $match = [regex]::Match($content, $flexiblePattern)
                    
                    if (-not $match.Success) {
                        # Try even more flexible - look for the error message with platform3 variable
                        $errorPattern = '(?s)\}\s*else\s*\{\s*throw\s+new\s+Error\([^)]*\$\{platform3\}[^)]*\);'
                        $match = [regex]::Match($content, $errorPattern)
                        
                        if (-not $match.Success) {
                            throw "Register-PlatformDetectionPatch: Could not find 'Unsupported platform' error pattern in file '$FilePath'"
                        }
                    }
                }
                
                # Build replacement string
                # Note: Using template literal syntax as in the original
                $replacement = "} else if (platform3 === `"win32`") {`n    nativeBinding = require_merkle_tree_napi_$selectedLoader();`n} else {`n    throw new Error(`\`Unsupported platform: \${platform3}\``);`n}"
                
                # Replace the matched pattern
                $newContent = $content.Substring(0, $match.Index) + $replacement + $content.Substring($match.Index + $match.Length)
                
                # Write patched content back
                Set-Content -Path $FilePath -Value $newContent -NoNewline -ErrorAction Stop
                
                Write-Verbose "Platform detection patch applied successfully to: $FilePath"
            }
            Verify = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Verifying platform detection patch for: $FilePath"
                
                # Read file content
                $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
                
                # Check file contains platform3 === "win32"
                if ($content -notmatch 'platform3\s*===\s*"win32"') {
                    Write-Verbose "Verification failed: File does not contain 'platform3 === \"win32\"'"
                    return $false
                }
                
                # Check file contains require_merkle_tree_napi_ (any variant)
                if ($content -notmatch 'require_merkle_tree_napi_') {
                    Write-Verbose "Verification failed: File does not contain 'require_merkle_tree_napi_'"
                    return $false
                }
                
                Write-Verbose "Verification passed for: $FilePath"
                return $true
            }
        }
        
        Write-Verbose "Platform detection patch registered successfully"
    }
    catch {
        Write-Error "Register-PlatformDetectionPatch: Failed to register platform detection patch. Error: $_"
        throw
    }
}

function Register-MerkleTreeModulePatch {
    <#
    .SYNOPSIS
    Register the merkle-tree module replacement patch in the patch registry.
    
    .DESCRIPTION
    Registers the merkle-tree module replacement patch that replaces the macOS
    native module file with a Windows-compatible version. This patch depends on
    platform-detection patch (priority 1) and runs at priority 2.
    
    .EXAMPLE
    Register-MerkleTreeModulePatch
    # Registers the merkle-tree module replacement patch in the patch registry
    #>
    [CmdletBinding()]
    param()
    
    try {
        $script:PatchRegistry['merkle-tree-module'] = @{
            Description = "Replace merkle-tree native module file with Windows version"
            FilePattern = "**/qfpzq242.node"
            Priority = 2
            Dependencies = @('platform-detection')
            Apply = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Applying merkle-tree module replacement patch to: $FilePath"
                
                # Get Windows merkle-tree binary from context
                if (-not $Context.WindowsBinaries) {
                    throw "Register-MerkleTreeModulePatch: Context.WindowsBinaries is missing or null"
                }
                
                if (-not $Context.WindowsBinaries.ContainsKey('merkleTree')) {
                    throw "Register-MerkleTreeModulePatch: Context.WindowsBinaries['merkleTree'] is missing. Available keys: $($Context.WindowsBinaries.Keys -join ', ')"
                }
                
                $windowsBinaryPath = $Context.WindowsBinaries['merkleTree']
                
                if ([string]::IsNullOrWhiteSpace($windowsBinaryPath)) {
                    throw "Register-MerkleTreeModulePatch: Context.WindowsBinaries['merkleTree'] is null or empty"
                }
                
                # Expand environment variables and convert to absolute path
                $windowsBinaryPath = [System.Environment]::ExpandEnvironmentVariables($windowsBinaryPath)
                if (-not [System.IO.Path]::IsPathRooted($windowsBinaryPath)) {
                    $windowsBinaryPath = [System.IO.Path]::GetFullPath($windowsBinaryPath)
                }
                
                # Validate Windows binary exists
                if (-not (Test-Path -Path $windowsBinaryPath -PathType Leaf)) {
                    throw "Register-MerkleTreeModulePatch: Windows binary not found at '$windowsBinaryPath'"
                }
                
                Write-Verbose "Copying Windows binary from '$windowsBinaryPath' to '$FilePath'"
                
                # Get file info for permission preservation
                $sourceFileInfo = Get-Item -Path $windowsBinaryPath -ErrorAction Stop
                $destFileInfo = $null
                
                # Check if destination file exists (to preserve permissions if possible)
                if (Test-Path -Path $FilePath -PathType Leaf) {
                    $destFileInfo = Get-Item -Path $FilePath -ErrorAction Stop
                    Write-Verbose "Destination file exists, will attempt to preserve permissions"
                }
                
                # Copy Windows binary over existing .node file
                try {
                    Copy-Item -Path $windowsBinaryPath -Destination $FilePath -Force -ErrorAction Stop
                    Write-Verbose "File copied successfully"
                }
                catch [System.UnauthorizedAccessException] {
                    throw "Register-MerkleTreeModulePatch: Permission denied when copying to '$FilePath'. Error: $_"
                }
                catch [System.IO.IOException] {
                    throw "Register-MerkleTreeModulePatch: I/O error when copying to '$FilePath'. Error: $_"
                }
                catch {
                    throw "Register-MerkleTreeModulePatch: Failed to copy file from '$windowsBinaryPath' to '$FilePath'. Error: $_"
                }
                
                # Verify destination file exists and has content
                if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    throw "Register-MerkleTreeModulePatch: File was not copied to destination '$FilePath'"
                }
                
                $copiedFileInfo = Get-Item -Path $FilePath -ErrorAction Stop
                if ($copiedFileInfo.Length -eq 0) {
                    throw "Register-MerkleTreeModulePatch: Copied file has zero size at '$FilePath'"
                }
                
                Write-Verbose "Merkle-tree module replacement patch applied successfully. File size: $($copiedFileInfo.Length) bytes"
            }
            Verify = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Verifying merkle-tree module replacement patch for: $FilePath"
                
                # Check file exists
                if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    Write-Verbose "Verification failed: File does not exist at '$FilePath'"
                    return $false
                }
                
                # Check file size > 0
                try {
                    $fileInfo = Get-Item -Path $FilePath -ErrorAction Stop
                    if ($fileInfo.Length -eq 0) {
                        Write-Verbose "Verification failed: File has zero size"
                        return $false
                    }
                    
                    Write-Verbose "File exists and has size: $($fileInfo.Length) bytes"
                }
                catch {
                    Write-Verbose "Verification failed: Could not get file info. Error: $_"
                    return $false
                }
                
                # Optionally: verify file is valid .node module (check magic bytes)
                # Node.js native modules typically start with specific magic bytes
                # For .node files, we can check if it's a valid PE/ELF/Mach-O binary
                # This is optional per spec, so we'll do a basic check
                try {
                    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
                    
                    # Check minimum size (very small files are likely invalid)
                    if ($fileBytes.Length -lt 100) {
                        Write-Verbose "Verification warning: File is very small ($($fileBytes.Length) bytes), may not be valid"
                        # Don't fail verification for this, just warn
                    }
                    
                    # Basic check: .node files are typically binary, not text
                    # Check if file starts with common binary magic bytes
                    # PE (Windows): MZ (0x4D 0x5A)
                    # ELF (Linux): 0x7F 0x45 0x4C 0x46
                    # Mach-O (macOS): 0xFE 0xED 0xFA 0xCE or 0xCF 0xFA 0xED 0xFE
                    if ($fileBytes.Length -ge 4) {
                        $magic1 = $fileBytes[0]
                        $magic2 = $fileBytes[1]
                        $magic3 = if ($fileBytes.Length -ge 3) { $fileBytes[2] } else { 0 }
                        $magic4 = if ($fileBytes.Length -ge 4) { $fileBytes[3] } else { 0 }
                        
                        $isValidBinary = $false
                        
                        # Check for PE (Windows) - MZ header
                        if ($magic1 -eq 0x4D -and $magic2 -eq 0x5A) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid PE (Windows) binary"
                        }
                        # Check for ELF (Linux)
                        elseif ($magic1 -eq 0x7F -and $magic2 -eq 0x45 -and $magic3 -eq 0x4C -and $magic4 -eq 0x46) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid ELF (Linux) binary"
                        }
                        # Check for Mach-O (macOS) - little endian
                        elseif ($magic1 -eq 0xFE -and $magic2 -eq 0xED -and $magic3 -eq 0xFA -and $magic4 -eq 0xCE) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid Mach-O (macOS) binary (little endian)"
                        }
                        # Check for Mach-O (macOS) - big endian
                        elseif ($magic1 -eq 0xCF -and $magic2 -eq 0xFA -and $magic3 -eq 0xED -and $magic4 -eq 0xFE) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid Mach-O (macOS) binary (big endian)"
                        }
                        
                        if (-not $isValidBinary) {
                            Write-Verbose "Verification warning: File does not appear to have standard binary magic bytes, but continuing verification"
                            # Don't fail - some .node files might have different formats
                        }
                    }
                }
                catch {
                    Write-Verbose "Verification warning: Could not read file bytes for magic byte check. Error: $_"
                    # Don't fail verification for this - it's optional
                }
                
                Write-Verbose "Verification passed for: $FilePath"
                return $true
            }
        }
        
        Write-Verbose "Merkle-tree module replacement patch registered successfully"
    }
    catch {
        Write-Error "Register-MerkleTreeModulePatch: Failed to register merkle-tree module replacement patch. Error: $_"
        throw
    }
}

function Register-Sqlite3ModulePatch {
    <#
    .SYNOPSIS
    Register the sqlite3 module replacement patch in the patch registry.
    
    .DESCRIPTION
    Registers the sqlite3 module replacement patch that replaces the macOS
    native module file with a Windows-compatible version. This patch runs at
    priority 2 and has no dependencies.
    
    .EXAMPLE
    Register-Sqlite3ModulePatch
    # Registers the sqlite3 module replacement patch in the patch registry
    #>
    [CmdletBinding()]
    param()
    
    try {
        $script:PatchRegistry['sqlite3-module'] = @{
            Description = "Replace sqlite3 native module file with Windows version"
            FilePattern = "**/kkkzjw1t.node"
            Priority = 2
            Dependencies = @()
            Apply = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Applying sqlite3 module replacement patch to: $FilePath"
                
                # Get Windows sqlite3 binary from context
                if (-not $Context.WindowsBinaries) {
                    throw "Register-Sqlite3ModulePatch: Context.WindowsBinaries is missing or null"
                }
                
                if (-not $Context.WindowsBinaries.ContainsKey('sqlite3')) {
                    throw "Register-Sqlite3ModulePatch: Context.WindowsBinaries['sqlite3'] is missing. Available keys: $($Context.WindowsBinaries.Keys -join ', ')"
                }
                
                $windowsBinaryPath = $Context.WindowsBinaries['sqlite3']
                
                if ([string]::IsNullOrWhiteSpace($windowsBinaryPath)) {
                    throw "Register-Sqlite3ModulePatch: Context.WindowsBinaries['sqlite3'] is null or empty"
                }
                
                # Expand environment variables and convert to absolute path
                $windowsBinaryPath = [System.Environment]::ExpandEnvironmentVariables($windowsBinaryPath)
                if (-not [System.IO.Path]::IsPathRooted($windowsBinaryPath)) {
                    $windowsBinaryPath = [System.IO.Path]::GetFullPath($windowsBinaryPath)
                }
                
                # Validate Windows binary exists
                if (-not (Test-Path -Path $windowsBinaryPath -PathType Leaf)) {
                    throw "Register-Sqlite3ModulePatch: Windows binary not found at '$windowsBinaryPath'"
                }
                
                Write-Verbose "Copying Windows binary from '$windowsBinaryPath' to '$FilePath'"
                
                # Get file info for permission preservation
                $sourceFileInfo = Get-Item -Path $windowsBinaryPath -ErrorAction Stop
                $destFileInfo = $null
                
                # Check if destination file exists (to preserve permissions if possible)
                if (Test-Path -Path $FilePath -PathType Leaf) {
                    $destFileInfo = Get-Item -Path $FilePath -ErrorAction Stop
                    Write-Verbose "Destination file exists, will attempt to preserve permissions"
                }
                
                # Copy Windows binary over existing .node file
                try {
                    Copy-Item -Path $windowsBinaryPath -Destination $FilePath -Force -ErrorAction Stop
                    Write-Verbose "File copied successfully"
                }
                catch [System.UnauthorizedAccessException] {
                    throw "Register-Sqlite3ModulePatch: Permission denied when copying to '$FilePath'. Error: $_"
                }
                catch [System.IO.IOException] {
                    throw "Register-Sqlite3ModulePatch: I/O error when copying to '$FilePath'. Error: $_"
                }
                catch {
                    throw "Register-Sqlite3ModulePatch: Failed to copy file from '$windowsBinaryPath' to '$FilePath'. Error: $_"
                }
                
                # Verify destination file exists and has content
                if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    throw "Register-Sqlite3ModulePatch: File was not copied to destination '$FilePath'"
                }
                
                $copiedFileInfo = Get-Item -Path $FilePath -ErrorAction Stop
                if ($copiedFileInfo.Length -eq 0) {
                    throw "Register-Sqlite3ModulePatch: Copied file has zero size at '$FilePath'"
                }
                
                Write-Verbose "SQLite3 module replacement patch applied successfully. File size: $($copiedFileInfo.Length) bytes"
            }
            Verify = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Verifying sqlite3 module replacement patch for: $FilePath"
                
                # Check file exists
                if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    Write-Verbose "Verification failed: File does not exist at '$FilePath'"
                    return $false
                }
                
                # Check file size > 0
                try {
                    $fileInfo = Get-Item -Path $FilePath -ErrorAction Stop
                    if ($fileInfo.Length -eq 0) {
                        Write-Verbose "Verification failed: File has zero size"
                        return $false
                    }
                    
                    Write-Verbose "File exists and has size: $($fileInfo.Length) bytes"
                }
                catch {
                    Write-Verbose "Verification failed: Could not get file info. Error: $_"
                    return $false
                }
                
                # Optionally: verify file is valid .node module (check magic bytes)
                # Node.js native modules typically start with specific magic bytes
                # For .node files, we can check if it's a valid PE/ELF/Mach-O binary
                # This is optional per spec, so we'll do a basic check
                try {
                    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
                    
                    # Check minimum size (very small files are likely invalid)
                    if ($fileBytes.Length -lt 100) {
                        Write-Verbose "Verification warning: File is very small ($($fileBytes.Length) bytes), may not be valid"
                        # Don't fail verification for this, just warn
                    }
                    
                    # Basic check: .node files are typically binary, not text
                    # Check if file starts with common binary magic bytes
                    # PE (Windows): MZ (0x4D 0x5A)
                    # ELF (Linux): 0x7F 0x45 0x4C 0x46
                    # Mach-O (macOS): 0xFE 0xED 0xFA 0xCE or 0xCF 0xFA 0xED 0xFE
                    if ($fileBytes.Length -ge 4) {
                        $magic1 = $fileBytes[0]
                        $magic2 = $fileBytes[1]
                        $magic3 = if ($fileBytes.Length -ge 3) { $fileBytes[2] } else { 0 }
                        $magic4 = if ($fileBytes.Length -ge 4) { $fileBytes[3] } else { 0 }
                        
                        $isValidBinary = $false
                        
                        # Check for PE (Windows) - MZ header
                        if ($magic1 -eq 0x4D -and $magic2 -eq 0x5A) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid PE (Windows) binary"
                        }
                        # Check for ELF (Linux)
                        elseif ($magic1 -eq 0x7F -and $magic2 -eq 0x45 -and $magic3 -eq 0x4C -and $magic4 -eq 0x46) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid ELF (Linux) binary"
                        }
                        # Check for Mach-O (macOS) - little endian
                        elseif ($magic1 -eq 0xFE -and $magic2 -eq 0xED -and $magic3 -eq 0xFA -and $magic4 -eq 0xCE) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid Mach-O (macOS) binary (little endian)"
                        }
                        # Check for Mach-O (macOS) - big endian
                        elseif ($magic1 -eq 0xCF -and $magic2 -eq 0xFA -and $magic3 -eq 0xED -and $magic4 -eq 0xFE) {
                            $isValidBinary = $true
                            Write-Verbose "File appears to be a valid Mach-O (macOS) binary (big endian)"
                        }
                        
                        if (-not $isValidBinary) {
                            Write-Verbose "Verification warning: File does not appear to have standard binary magic bytes, but continuing verification"
                            # Don't fail - some .node files might have different formats
                        }
                    }
                }
                catch {
                    Write-Verbose "Verification warning: Could not read file bytes for magic byte check. Error: $_"
                    # Don't fail verification for this - it's optional
                }
                
                Write-Verbose "Verification passed for: $FilePath"
                return $true
            }
        }
        
        Write-Verbose "SQLite3 module replacement patch registered successfully"
    }
    catch {
        Write-Error "Register-Sqlite3ModulePatch: Failed to register sqlite3 module replacement patch. Error: $_"
        throw
    }
}

function Register-RipGrepBinaryPatch {
    <#
    .SYNOPSIS
    Register the ripgrep binary replacement patch in the patch registry.
    
    .DESCRIPTION
    Registers the ripgrep binary replacement patch that replaces the macOS
    `rg` binary with a Windows `rg.exe` executable. This patch extracts `rg.exe`
    from a zip file in the context and replaces the original `rg` file.
    This patch runs at priority 2 and has no dependencies.
    
    .EXAMPLE
    Register-RipGrepBinaryPatch
    # Registers the ripgrep binary replacement patch in the patch registry
    #>
    [CmdletBinding()]
    param()
    
    try {
        $script:PatchRegistry['ripgrep-binary'] = @{
            Description = "Replace rg binary with Windows rg.exe"
            FilePattern = "**/rg"
            Priority = 2
            Dependencies = @()
            Apply = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Applying ripgrep binary replacement patch to: $FilePath"
                
                # Get ripgrep zip from context
                if (-not $Context.WindowsBinaries) {
                    throw "Register-RipGrepBinaryPatch: Context.WindowsBinaries is missing or null"
                }
                
                if (-not $Context.WindowsBinaries.ContainsKey('ripgrep')) {
                    throw "Register-RipGrepBinaryPatch: Context.WindowsBinaries['ripgrep'] is missing. Available keys: $($Context.WindowsBinaries.Keys -join ', ')"
                }
                
                $ripgrepZipPath = $Context.WindowsBinaries['ripgrep']
                
                if ([string]::IsNullOrWhiteSpace($ripgrepZipPath)) {
                    throw "Register-RipGrepBinaryPatch: Context.WindowsBinaries['ripgrep'] is null or empty"
                }
                
                # Expand environment variables and convert to absolute path
                $ripgrepZipPath = [System.Environment]::ExpandEnvironmentVariables($ripgrepZipPath)
                if (-not [System.IO.Path]::IsPathRooted($ripgrepZipPath)) {
                    $ripgrepZipPath = [System.IO.Path]::GetFullPath($ripgrepZipPath)
                }
                
                # Validate zip file exists
                if (-not (Test-Path -Path $ripgrepZipPath -PathType Leaf)) {
                    throw "Register-RipGrepBinaryPatch: Ripgrep zip file not found at '$ripgrepZipPath'"
                }
                
                Write-Verbose "Extracting rg.exe from zip: $ripgrepZipPath"
                
                # Create temporary directory for extraction
                $tempExtractDir = Join-Path -Path $env:TEMP -ChildPath "cursor-agent-ripgrep-extract-$(Get-Random)"
                try {
                    # Create temp directory
                    $null = New-Item -Path $tempExtractDir -ItemType Directory -Force -ErrorAction Stop
                    Write-Verbose "Created temporary extraction directory: $tempExtractDir"
                    
                    # Extract zip file
                    try {
                        Expand-Archive -Path $ripgrepZipPath -DestinationPath $tempExtractDir -Force -ErrorAction Stop
                        Write-Verbose "Zip file extracted successfully"
                    }
                    catch {
                        # PowerShell 5.0+ has Expand-Archive, but if it fails, try 7-Zip or other methods
                        throw "Register-RipGrepBinaryPatch: Failed to extract zip file '$ripgrepZipPath'. Error: $_"
                    }
                    
                    # Find rg.exe in extracted directory (may be in subdirectory)
                    $rgExePath = $null
                    
                    # First, try direct path
                    $directPath = Join-Path -Path $tempExtractDir -ChildPath "rg.exe"
                    if (Test-Path -Path $directPath -PathType Leaf) {
                        $rgExePath = $directPath
                        Write-Verbose "Found rg.exe at direct path: $rgExePath"
                    }
                    else {
                        # Search recursively for rg.exe
                        $foundFiles = Get-ChildItem -Path $tempExtractDir -Filter "rg.exe" -Recurse -ErrorAction Stop
                        if ($foundFiles.Count -gt 0) {
                            $rgExePath = $foundFiles[0].FullName
                            Write-Verbose "Found rg.exe at: $rgExePath"
                        }
                        else {
                            throw "Register-RipGrepBinaryPatch: rg.exe not found in extracted zip file '$ripgrepZipPath'"
                        }
                    }
                    
                    # Validate rg.exe exists and has content
                    if (-not (Test-Path -Path $rgExePath -PathType Leaf)) {
                        throw "Register-RipGrepBinaryPatch: rg.exe not found at '$rgExePath' after extraction"
                    }
                    
                    $rgExeInfo = Get-Item -Path $rgExePath -ErrorAction Stop
                    if ($rgExeInfo.Length -eq 0) {
                        throw "Register-RipGrepBinaryPatch: Extracted rg.exe has zero size"
                    }
                    
                    Write-Verbose "Found valid rg.exe: $rgExePath ($($rgExeInfo.Length) bytes)"
                    
                    # Determine destination path (same directory as original rg file, but with .exe extension)
                    $rgDirectory = [System.IO.Path]::GetDirectoryName($FilePath)
                    $rgExeDestination = Join-Path -Path $rgDirectory -ChildPath "rg.exe"
                    
                    Write-Verbose "Copying rg.exe to: $rgExeDestination"
                    
                    # Copy rg.exe to destination
                    try {
                        Copy-Item -Path $rgExePath -Destination $rgExeDestination -Force -ErrorAction Stop
                        Write-Verbose "rg.exe copied successfully"
                    }
                    catch [System.UnauthorizedAccessException] {
                        throw "Register-RipGrepBinaryPatch: Permission denied when copying to '$rgExeDestination'. Error: $_"
                    }
                    catch [System.IO.IOException] {
                        throw "Register-RipGrepBinaryPatch: I/O error when copying to '$rgExeDestination'. Error: $_"
                    }
                    catch {
                        throw "Register-RipGrepBinaryPatch: Failed to copy rg.exe from '$rgExePath' to '$rgExeDestination'. Error: $_"
                    }
                    
                    # Verify rg.exe was copied successfully
                    if (-not (Test-Path -Path $rgExeDestination -PathType Leaf)) {
                        throw "Register-RipGrepBinaryPatch: rg.exe was not copied to destination '$rgExeDestination'"
                    }
                    
                    # Delete original rg file (if it exists)
                    if (Test-Path -Path $FilePath -PathType Leaf) {
                        Write-Verbose "Deleting original rg file: $FilePath"
                        try {
                            Remove-Item -Path $FilePath -Force -ErrorAction Stop
                            Write-Verbose "Original rg file deleted successfully"
                        }
                        catch {
                            Write-Warning "Register-RipGrepBinaryPatch: Failed to delete original rg file '$FilePath'. Error: $_"
                            # Don't throw - the new rg.exe is in place, so this is not critical
                        }
                    }
                    else {
                        Write-Verbose "Original rg file does not exist, skipping deletion"
                    }
                    
                    # Verify final rg.exe exists and has content
                    $finalRgExeInfo = Get-Item -Path $rgExeDestination -ErrorAction Stop
                    if ($finalRgExeInfo.Length -eq 0) {
                        throw "Register-RipGrepBinaryPatch: Final rg.exe has zero size at '$rgExeDestination'"
                    }
                    
                    Write-Verbose "Ripgrep binary replacement patch applied successfully. Final rg.exe size: $($finalRgExeInfo.Length) bytes"
                }
                finally {
                    # Clean up temporary extraction directory
                    if (Test-Path -Path $tempExtractDir -PathType Container) {
                        try {
                            Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Verbose "Cleaned up temporary extraction directory: $tempExtractDir"
                        }
                        catch {
                            Write-Verbose "Failed to clean up temporary directory '$tempExtractDir': $_"
                            # Don't throw - cleanup failure is not critical
                        }
                    }
                }
            }
            Verify = {
                param(
                    [string]$FilePath,
                    [hashtable]$Context
                )
                
                Write-Verbose "Verifying ripgrep binary replacement patch for: $FilePath"
                
                # Note: $FilePath is the original rg path, but we replaced it with rg.exe
                # So we need to check for rg.exe in the same directory
                $rgDirectory = [System.IO.Path]::GetDirectoryName($FilePath)
                $rgExePath = Join-Path -Path $rgDirectory -ChildPath "rg.exe"
                
                # Check rg.exe exists
                if (-not (Test-Path -Path $rgExePath -PathType Leaf)) {
                    Write-Verbose "Verification failed: rg.exe does not exist at '$rgExePath'"
                    return $false
                }
                
                # Check file size > 0
                try {
                    $fileInfo = Get-Item -Path $rgExePath -ErrorAction Stop
                    if ($fileInfo.Length -eq 0) {
                        Write-Verbose "Verification failed: rg.exe has zero size"
                        return $false
                    }
                    
                    Write-Verbose "rg.exe exists and has size: $($fileInfo.Length) bytes"
                }
                catch {
                    Write-Verbose "Verification failed: Could not get file info. Error: $_"
                    return $false
                }
                
                # Optionally: try to execute rg.exe --version to verify it's valid
                try {
                    Write-Verbose "Attempting to execute rg.exe --version for verification"
                    $versionOutput = & $rgExePath --version 2>&1
                    
                    if ($LASTEXITCODE -eq 0 -or $versionOutput -match 'ripgrep') {
                        Write-Verbose "rg.exe executed successfully. Version output: $($versionOutput -join ' ')"
                        return $true
                    }
                    else {
                        Write-Verbose "Verification warning: rg.exe --version returned unexpected output or exit code"
                        # Don't fail verification - file exists and has size, which is the main requirement
                        return $true
                    }
                }
                catch {
                    Write-Verbose "Verification warning: Could not execute rg.exe --version. Error: $_"
                    # Don't fail verification - execution test is optional per spec
                    # File exists and has size, which is the main requirement
                    return $true
                }
            }
        }
        
        Write-Verbose "Ripgrep binary replacement patch registered successfully"
    }
    catch {
        Write-Error "Register-RipGrepBinaryPatch: Failed to register ripgrep binary replacement patch. Error: $_"
        throw
    }
}

function Register-StandardPatches {
    <#
    .SYNOPSIS
    Initialize patch registry with all standard patches.
    
    .DESCRIPTION
    Registers all standard patches (platform-detection, merkle-tree-module,
    sqlite3-module, ripgrep-binary) in the patch registry. This function
    should be called to initialize the patch system before applying patches.
    After registration, validates the registry structure to ensure all
    patches are correctly defined with proper dependencies.
    
    .EXAMPLE
    Register-StandardPatches
    # Registers all standard patches in the patch registry
    
    .EXAMPLE
    Register-StandardPatches
    $result = Test-PatchRegistry
    if (-not $result.Valid) {
        Write-Error "Patch registry validation failed: $($result.Errors -join '; ')"
    }
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Registering all standard patches"
        
        # Register all standard patches (Specs 17-20)
        # Order matters for dependencies - register platform-detection first
        Register-PlatformDetectionPatch
        Register-MerkleTreeModulePatch
        Register-Sqlite3ModulePatch
        Register-RipGrepBinaryPatch
        
        Write-Verbose "All standard patches registered. Validating registry structure..."
        
        # Validate registry structure after registration
        $validationResult = Test-PatchRegistry
        
        if (-not $validationResult.Valid) {
            $errorMessages = $validationResult.Errors -join "; "
            throw "Register-StandardPatches: Patch registry validation failed after registration. Errors: $errorMessages"
        }
        
        Write-Verbose "Patch registry validation passed. Registered $($script:PatchRegistry.Count) patch(es)"
        
        # Log registered patches
        $patchIds = $script:PatchRegistry.Keys | Sort-Object
        Write-Verbose "Registered patches: $($patchIds -join ', ')"
    }
    catch {
        Write-Error "Register-StandardPatches: Failed to register standard patches. Error: $_"
        throw
    }
}

#endregion

#region Workflow Functions

function Get-WindowsArchitecture {
    <#
    .SYNOPSIS
    Detect Windows system architecture (x64 or arm64).
    
    .DESCRIPTION
    Detects the Windows system architecture by checking environment variables
    and runtime information. Always returns a value (never throws), defaulting
    to x64 if detection fails.
    
    .OUTPUTS
    string. Returns "x64" or "arm64".
    
    .EXAMPLE
    $arch = Get-WindowsArchitecture
    Write-Host "Windows architecture: $arch"
    #>
    [CmdletBinding()]
    param()
    
    try {
        # Default fallback
        $windowsArch = "x64"
        
        # Check PROCESSOR_ARCHITECTURE environment variable
        $procArch = $env:PROCESSOR_ARCHITECTURE
        if ($procArch -eq "AMD64") {
            $windowsArch = "x64"
        }
        elseif ($procArch -eq "ARM64") {
            $windowsArch = "arm64"
        }
        else {
            # Fallback: Use RuntimeInformation
            try {
                $runtimeArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
                if ($runtimeArch -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
                    $windowsArch = "arm64"
                }
                elseif ($runtimeArch -eq [System.Runtime.InteropServices.Architecture]::X64) {
                    $windowsArch = "x64"
                }
            }
            catch {
                Write-Verbose "Get-WindowsArchitecture: Failed to detect architecture using RuntimeInformation, defaulting to x64: $_"
            }
        }
        
        Write-Verbose "Detected Windows architecture: $windowsArch"
        return $windowsArch
    }
    catch {
        # Never throw - always return a value
        Write-Verbose "Get-WindowsArchitecture: Failed to detect Windows architecture, defaulting to x64: $_"
        return "x64"
    }
}

function New-PatchContext {
    <#
    .SYNOPSIS
    Build context hashtable with all information needed for patches.
    
    .DESCRIPTION
    Creates a comprehensive context object containing package path, Cursor Agent version,
    Windows architecture, dependency versions, and paths to Windows binaries. Automatically
    detects Windows architecture, extracts dependency versions from package if not provided,
    and downloads/caches Windows binaries as needed.
    
    .PARAMETER PackagePath
    Path to the extracted Cursor Agent package directory.
    
    .PARAMETER CursorAgentVersion
    Version of the Cursor Agent (e.g., "2026.01.23-916f423").
    
    .PARAMETER DependencyVersions
    Optional hashtable with dependency versions. If not provided or missing versions,
    will attempt to extract from package. Format: @{ sqlite3 = "5.1.7"; merkleTree = "1.2.3"; ripgrep = "13.0.0" }
    
    .PARAMETER CacheDirectory
    Path to the cache directory for storing downloaded binaries.
    
    .OUTPUTS
    hashtable. Returns a context object with the following structure:
    - PackagePath: Path to extracted package
    - CursorAgentVersion: Cursor Agent version string
    - WindowsArchitecture: "x64" or "arm64"
    - DependencyVersions: Hashtable with sqlite3, merkleTree, ripgrep versions
    - WindowsBinaries: Hashtable with paths to cached Windows binaries
    - CacheDirectory: Cache directory path
    
    .EXAMPLE
    $context = New-PatchContext -PackagePath ".\cursor-agent-2026.01.23-916f423" -CursorAgentVersion "2026.01.23-916f423" -CacheDirectory "C:\cache"
    # Builds context with all required information for patching
    
    .EXAMPLE
    $context = New-PatchContext -PackagePath ".\package" -CursorAgentVersion "2026.01.23-916f423" -DependencyVersions @{ sqlite3 = "5.1.7" } -CacheDirectory "C:\cache"
    # Builds context with pre-provided SQLite3 version, extracts others from package
    #>
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
    
    try {
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($PackagePath)) {
            throw "New-PatchContext: PackagePath parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($CursorAgentVersion)) {
            throw "New-PatchContext: CursorAgentVersion parameter is null or empty"
        }
        
        if ([string]::IsNullOrWhiteSpace($CacheDirectory)) {
            throw "New-PatchContext: CacheDirectory parameter is null or empty"
        }
        
        # Expand environment variables and convert to absolute paths
        $PackagePath = [System.Environment]::ExpandEnvironmentVariables($PackagePath)
        if (-not [System.IO.Path]::IsPathRooted($PackagePath)) {
            $PackagePath = [System.IO.Path]::GetFullPath($PackagePath)
        }
        
        $CacheDirectory = [System.Environment]::ExpandEnvironmentVariables($CacheDirectory)
        if (-not [System.IO.Path]::IsPathRooted($CacheDirectory)) {
            $CacheDirectory = [System.IO.Path]::GetFullPath($CacheDirectory)
        }
        
        # Validate package path exists
        if (-not (Test-Path -Path $PackagePath -PathType Container)) {
            throw "New-PatchContext: Package path does not exist or is not a directory: '$PackagePath'"
        }
        
        Write-Verbose "Building patch context for package: $PackagePath"
        Write-Verbose "Cursor Agent version: $CursorAgentVersion"
        
        # Step 1: Detect Windows architecture
        $windowsArch = Get-WindowsArchitecture
        
        # Step 2: Extract dependency versions if not provided
        Write-Verbose "Extracting dependency versions from package (if not provided)"
        
        $dependencyVersions = @{}
        
        # SQLite3 version
        if ($DependencyVersions.ContainsKey("sqlite3") -and -not [string]::IsNullOrWhiteSpace($DependencyVersions["sqlite3"])) {
            $dependencyVersions["sqlite3"] = $DependencyVersions["sqlite3"]
            Write-Verbose "Using provided SQLite3 version: $($dependencyVersions['sqlite3'])"
        }
        else {
            try {
                $sqlite3Version = Get-Sqlite3Version -PackagePath $PackagePath
                if ($sqlite3Version) {
                    $dependencyVersions["sqlite3"] = $sqlite3Version
                    Write-Verbose "Extracted SQLite3 version from package: $sqlite3Version"
                }
                else {
                    Write-Verbose "SQLite3 version not found in package, will use default from config"
                }
            }
            catch {
                Write-Verbose "Failed to extract SQLite3 version from package: $_"
            }
        }
        
        # Merkle Tree version
        if ($DependencyVersions.ContainsKey("merkleTree") -and -not [string]::IsNullOrWhiteSpace($DependencyVersions["merkleTree"])) {
            $dependencyVersions["merkleTree"] = $DependencyVersions["merkleTree"]
            Write-Verbose "Using provided Merkle Tree version: $($dependencyVersions['merkleTree'])"
        }
        else {
            try {
                $merkleTreeVersion = Get-MerkleTreeVersion -PackagePath $PackagePath
                if ($merkleTreeVersion) {
                    $dependencyVersions["merkleTree"] = $merkleTreeVersion
                    Write-Verbose "Extracted Merkle Tree version from package: $merkleTreeVersion"
                }
                else {
                    Write-Verbose "Merkle Tree version not found in package, will use default from config"
                }
            }
            catch {
                Write-Verbose "Failed to extract Merkle Tree version from package: $_"
            }
        }
        
        # RipGrep version
        if ($DependencyVersions.ContainsKey("ripgrep") -and -not [string]::IsNullOrWhiteSpace($DependencyVersions["ripgrep"])) {
            $dependencyVersions["ripgrep"] = $DependencyVersions["ripgrep"]
            Write-Verbose "Using provided RipGrep version: $($dependencyVersions['ripgrep'])"
        }
        else {
            try {
                $ripgrepVersion = Get-RipGrepVersion -PackagePath $PackagePath
                if ($ripgrepVersion) {
                    $dependencyVersions["ripgrep"] = $ripgrepVersion
                    Write-Verbose "Extracted RipGrep version from package: $ripgrepVersion"
                }
                else {
                    Write-Verbose "RipGrep version not found in package, will use default from config"
                }
            }
            catch {
                Write-Verbose "Failed to extract RipGrep version from package: $_"
            }
        }
        
        # Step 3: Load configuration for binary download info
        Write-Verbose "Loading configuration for binary download information"
        $config = Get-PatcherConfig
        
        # Ensure cache directory exists
        Initialize-CacheDirectory -CacheDirectory $CacheDirectory | Out-Null
        
        # Step 4: Download/cache Windows binaries
        Write-Verbose "Downloading/caching Windows binaries"
        $windowsBinaries = @{}
        
        # Helper function to get binary download info from config
        function Get-BinaryDownloadInfo {
            param(
                [string]$DependencyName,
                [string]$Version
            )
            
            $depConfig = $config.versionMappings.$DependencyName
            if (-not $depConfig) {
                return $null
            }
            
            # Try version-specific config first
            if ($Version -and $depConfig.$Version -and $depConfig.$Version.windowsBinary) {
                return $depConfig.$Version.windowsBinary
            }
            
            # Fallback to default
            if ($depConfig.default -and $depConfig.default.windowsBinary) {
                return $depConfig.default.windowsBinary
            }
            
            return $null
        }
        
        # SQLite3 binary
        try {
            $sqlite3Version = $dependencyVersions["sqlite3"]
            $cacheKey = if ($sqlite3Version) { "sqlite3-v$sqlite3Version-windows" } else { "sqlite3-latest-windows" }
            
            # Check cache first
            $cachedPath = Get-CachedBinary -CacheKey $cacheKey -CacheDirectory $CacheDirectory
            if ($cachedPath) {
                $windowsBinaries["sqlite3"] = $cachedPath
                Write-Verbose "Using cached SQLite3 binary: $cachedPath"
            }
            else {
                # Download and cache
                $downloadInfo = Get-BinaryDownloadInfo -DependencyName "sqlite3" -Version $sqlite3Version
                if ($downloadInfo) {
                    Write-Verbose "Downloading SQLite3 binary from GitHub"
                    $tempPath = Join-Path -Path $env:TEMP -ChildPath "sqlite3-$(New-Guid).node"
                    
                    Get-GitHubReleaseAsset -Repo $downloadInfo.repo -AssetPattern $downloadInfo.assetPattern -OutPath $tempPath -ReleaseTag $downloadInfo.releaseTag
                    
                    $cachedPath = Save-BinaryToCache -SourcePath $tempPath -CacheKey $cacheKey -CacheDirectory $CacheDirectory
                    $windowsBinaries["sqlite3"] = $cachedPath
                    
                    # Clean up temp file
                    Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
                    Write-Verbose "Downloaded and cached SQLite3 binary: $cachedPath"
                }
                else {
                    throw "New-PatchContext: No download configuration found for SQLite3 (version: $sqlite3Version)"
                }
            }
        }
        catch {
            Write-Error "New-PatchContext: Failed to get SQLite3 binary. Error: $_"
            throw
        }
        
        # Merkle Tree binary
        try {
            $merkleTreeVersion = $dependencyVersions["merkleTree"]
            $cacheKey = if ($merkleTreeVersion) { "merkle-tree-v$merkleTreeVersion-windows" } else { "merkle-tree-latest-windows" }
            
            # Check cache first
            $cachedPath = Get-CachedBinary -CacheKey $cacheKey -CacheDirectory $CacheDirectory
            if ($cachedPath) {
                $windowsBinaries["merkleTree"] = $cachedPath
                Write-Verbose "Using cached Merkle Tree binary: $cachedPath"
            }
            else {
                # Download and cache
                $downloadInfo = Get-BinaryDownloadInfo -DependencyName "merkleTree" -Version $merkleTreeVersion
                if ($downloadInfo) {
                    Write-Verbose "Downloading Merkle Tree binary from GitHub"
                    $tempPath = Join-Path -Path $env:TEMP -ChildPath "merkle-tree-$(New-Guid).node"
                    
                    Get-GitHubReleaseAsset -Repo $downloadInfo.repo -AssetPattern $downloadInfo.assetPattern -OutPath $tempPath -ReleaseTag $downloadInfo.releaseTag
                    
                    $cachedPath = Save-BinaryToCache -SourcePath $tempPath -CacheKey $cacheKey -CacheDirectory $CacheDirectory
                    $windowsBinaries["merkleTree"] = $cachedPath
                    
                    # Clean up temp file
                    Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
                    Write-Verbose "Downloaded and cached Merkle Tree binary: $cachedPath"
                }
                else {
                    throw "New-PatchContext: No download configuration found for Merkle Tree (version: $merkleTreeVersion)"
                }
            }
        }
        catch {
            Write-Error "New-PatchContext: Failed to get Merkle Tree binary. Error: $_"
            throw
        }
        
        # RipGrep binary (zip file)
        try {
            $ripgrepVersion = $dependencyVersions["ripgrep"]
            $cacheKey = if ($ripgrepVersion) { "ripgrep-v$ripgrepVersion-windows.zip" } else { "ripgrep-latest-windows.zip" }
            
            # Check cache first
            $cachedPath = Get-CachedBinary -CacheKey $cacheKey -CacheDirectory $CacheDirectory
            if ($cachedPath) {
                $windowsBinaries["ripgrep"] = $cachedPath
                Write-Verbose "Using cached RipGrep binary: $cachedPath"
            }
            else {
                # Download and cache
                $downloadInfo = Get-BinaryDownloadInfo -DependencyName "ripgrep" -Version $ripgrepVersion
                if ($downloadInfo) {
                    Write-Verbose "Downloading RipGrep binary from GitHub"
                    $tempPath = Join-Path -Path $env:TEMP -ChildPath "ripgrep-$(New-Guid).zip"
                    
                    Get-GitHubReleaseAsset -Repo $downloadInfo.repo -AssetPattern $downloadInfo.assetPattern -OutPath $tempPath -ReleaseTag $downloadInfo.releaseTag
                    
                    $cachedPath = Save-BinaryToCache -SourcePath $tempPath -CacheKey $cacheKey -CacheDirectory $CacheDirectory
                    $windowsBinaries["ripgrep"] = $cachedPath
                    
                    # Clean up temp file
                    Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
                    Write-Verbose "Downloaded and cached RipGrep binary: $cachedPath"
                }
                else {
                    throw "New-PatchContext: No download configuration found for RipGrep (version: $ripgrepVersion)"
                }
            }
        }
        catch {
            Write-Error "New-PatchContext: Failed to get RipGrep binary. Error: $_"
            throw
        }
        
        # Step 5: Build context hashtable
        $context = @{
            PackagePath = $PackagePath
            CursorAgentVersion = $CursorAgentVersion
            WindowsArchitecture = $windowsArch
            DependencyVersions = $dependencyVersions
            WindowsBinaries = $windowsBinaries
            CacheDirectory = $CacheDirectory
        }
        
        Write-Verbose "Patch context built successfully"
        Write-Verbose "  PackagePath: $($context.PackagePath)"
        Write-Verbose "  CursorAgentVersion: $($context.CursorAgentVersion)"
        Write-Verbose "  WindowsArchitecture: $($context.WindowsArchitecture)"
        Write-Verbose "  DependencyVersions: $($context.DependencyVersions | ConvertTo-Json -Compress)"
        Write-Verbose "  WindowsBinaries: $($context.WindowsBinaries.Keys -join ', ')"
        
        return $context
    }
    catch {
        Write-Error "New-PatchContext: Failed to build patch context. Error: $_"
        throw
    }
}

function Write-PatchStateMarker {
    <#
    .SYNOPSIS
    Write patch state marker file to track patched installations.
    
    .DESCRIPTION
    Creates a JSON marker file (.cursor-agent-patched) in the installation directory
    to track which patches were applied, when, and with what versions.
    
    .PARAMETER InstallationPath
    Path to the installation directory where marker file should be written.
    
    .PARAMETER CursorAgentVersion
    Version of the Cursor Agent that was patched.
    
    .PARAMETER AppliedPatches
    Array of patch IDs that were applied.
    
    .PARAMETER PatchResults
    Hashtable with patch results for each applied patch.
    
    .PARAMETER DependencyVersions
    Hashtable with dependency versions used during patching.
    
    .PARAMETER PatcherVersion
    Version of the patcher tool. Defaults to "1.0.0".
    
    .PARAMETER PatchHash
    Optional hash of patch configuration. If not provided, will be calculated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath,
        
        [Parameter(Mandatory=$true)]
        [string]$CursorAgentVersion,
        
        [Parameter(Mandatory=$true)]
        [string[]]$AppliedPatches,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$PatchResults,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$DependencyVersions,
        
        [Parameter(Mandatory=$false)]
        [string]$PatcherVersion = "1.0.0",
        
        [Parameter(Mandatory=$false)]
        [string]$PatchHash
    )
    
    try {
        # Validate installation path
        if (-not (Test-Path -Path $InstallationPath -PathType Container)) {
            throw "Write-PatchStateMarker: Installation path does not exist: '$InstallationPath'"
        }
        
        # Calculate patch hash if not provided
        if ([string]::IsNullOrWhiteSpace($PatchHash)) {
            $hashContent = "$PatcherVersion|$($AppliedPatches -join ',')|$($DependencyVersions | ConvertTo-Json -Compress)"
            $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashContent)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $hashString = [System.BitConverter]::ToString($sha256.ComputeHash($hashBytes)).Replace("-", "").ToLower()
            $PatchHash = "sha256:$hashString"
        }
        
        # Build marker structure
        $marker = @{
            cursorAgentVersion = $CursorAgentVersion
            patchTimestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            patcherVersion = $PatcherVersion
            appliedPatches = $AppliedPatches
            patchResults = $PatchResults
            dependencyVersions = $DependencyVersions
            patchHash = $PatchHash
        }
        
        # Convert to JSON
        $jsonContent = $marker | ConvertTo-Json -Depth 10
        
        # Write marker file
        $markerPath = Join-Path -Path $InstallationPath -ChildPath ".cursor-agent-patched"
        Set-Content -Path $markerPath -Value $jsonContent -Encoding UTF8 -ErrorAction Stop
        
        Write-Verbose "Patch state marker written to: $markerPath"
    }
    catch {
        Write-Error "Write-PatchStateMarker: Failed to write patch state marker. Error: $_"
        throw
    }
}

function Read-PatchStateMarker {
    <#
    .SYNOPSIS
    Read patch state marker file from installation directory.
    
    .DESCRIPTION
    Reads and parses the .cursor-agent-patched marker file if it exists.
    Returns $null if marker file is not found or invalid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath
    )
    
    try {
        $markerPath = Join-Path -Path $InstallationPath -ChildPath ".cursor-agent-patched"
        
        if (-not (Test-Path -Path $markerPath -PathType Leaf)) {
            Write-Verbose "Patch state marker not found: $markerPath"
            return $null
        }
        
        $jsonContent = Get-Content -Path $markerPath -Raw -ErrorAction Stop
        $marker = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        
        # Convert to hashtable
        $result = @{
            cursorAgentVersion = $marker.cursorAgentVersion
            patchTimestamp = $marker.patchTimestamp
            patcherVersion = $marker.patcherVersion
            appliedPatches = $marker.appliedPatches
            patchResults = $marker.patchResults
            dependencyVersions = $marker.dependencyVersions
            patchHash = $marker.patchHash
        }
        
        Write-Verbose "Patch state marker read successfully from: $markerPath"
        return $result
    }
    catch {
        Write-Verbose "Failed to read patch state marker: $_"
        return $null
    }
}

function Test-InstallationPatched {
    <#
    .SYNOPSIS
    Test if an installation has been patched.
    
    .DESCRIPTION
    Checks if the installation has a patch state marker and verifies all required
    patches are present. Optionally verifies files exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath,
        
        [Parameter(Mandatory=$false)]
        [string[]]$RequiredPatches = @(
            "platform-detection",
            "merkle-tree-module",
            "sqlite3-module",
            "ripgrep-binary"
        ),
        
        [Parameter(Mandatory=$false)]
        [switch]$VerifyFiles
    )
    
    try {
        $result = @{
            IsPatched = $false
            MissingPatches = @()
            MarkerData = $null
            VerificationResults = @{}
        }
        
        # Read marker file
        $markerData = Read-PatchStateMarker -InstallationPath $InstallationPath
        
        if ($null -eq $markerData) {
            Write-Verbose "Installation is not patched (no marker file)"
            return $result
        }
        
        $result.MarkerData = $markerData
        
        # Check if all required patches are present
        $appliedPatches = $markerData.appliedPatches
        $missingPatches = @()
        
        foreach ($requiredPatch in $RequiredPatches) {
            if ($appliedPatches -notcontains $requiredPatch) {
                $missingPatches += $requiredPatch
            }
        }
        
        if ($missingPatches.Count -gt 0) {
            $result.MissingPatches = $missingPatches
            Write-Verbose "Installation is partially patched. Missing patches: $($missingPatches -join ', ')"
            return $result
        }
        
        $result.IsPatched = $true
        
        # Optional file verification
        if ($VerifyFiles) {
            # Basic file existence checks
            $verificationResults = @{
                PlatformDetectionPresent = $false
                MerkleTreeBinaryExists = $false
                Sqlite3BinaryExists = $false
                RipGrepBinaryExists = $false
            }
            
            # Check platform detection (search for win32 in native.js files)
            $nativeFiles = Find-FilesMatchingPattern -RootPath $InstallationPath -Pattern "**/native.js"
            foreach ($file in $nativeFiles) {
                $content = Get-Content -Path $file -Raw -ErrorAction SilentlyContinue
                if ($content -match 'platform3\s*===\s*["'']win32["'']') {
                    $verificationResults.PlatformDetectionPresent = $true
                    break
                }
            }
            
            # Check binary files exist
            $merkleTreeFiles = Find-FilesMatchingPattern -RootPath $InstallationPath -Pattern "**/qfpzq242.node"
            $verificationResults.MerkleTreeBinaryExists = ($merkleTreeFiles.Count -gt 0)
            
            $sqlite3Files = Find-FilesMatchingPattern -RootPath $InstallationPath -Pattern "**/kkkzjw1t.node"
            $verificationResults.Sqlite3BinaryExists = ($sqlite3Files.Count -gt 0)
            
            $ripgrepFiles = Find-FilesMatchingPattern -RootPath $InstallationPath -Pattern "**/rg.exe"
            $verificationResults.RipGrepBinaryExists = ($ripgrepFiles.Count -gt 0)
            
            $result.VerificationResults = $verificationResults
        }
        
        return $result
    }
    catch {
        Write-Error "Test-InstallationPatched: Failed to test installation. Error: $_"
        throw
    }
}

function New-CursorAgentLauncher {
    <#
    .SYNOPSIS
    Generate cursor-agent launcher script with update interception support.
    
    .DESCRIPTION
    Creates a batch script that launches cursor-agent using Bun (or Node.js fallback).
    In standard mode, simply invokes the index.js file. In update interception mode,
    intercepts update/upgrade commands and triggers auto-patching after updates.
    
    .PARAMETER InstallPath
    Path to the installed cursor-agent directory containing index.js.
    
    .PARAMETER LauncherName
    Name of the launcher script file. Defaults to "cursor-agent.bat".
    
    .PARAMETER RealCursorAgentPath
    Path to real cursor-agent executable for passthrough in interception mode.
    If not provided, will attempt to find in PATH.
    
    .PARAMETER EnableUpdateInterception
    Enable update interception mode. When enabled, intercepts update/upgrade commands
    and triggers auto-patching. Requires Spec 037 (Invoke-CursorAgentUpdateWithPatch)
    to be fully functional.
    
    .OUTPUTS
    string. Returns the absolute path to the created launcher script.
    
    .EXAMPLE
    $launcherPath = New-CursorAgentLauncher -InstallPath ".\cursor-agent"
    # Creates standard launcher script
    
    .EXAMPLE
    $launcherPath = New-CursorAgentLauncher -InstallPath ".\cursor-agent" -EnableUpdateInterception
    # Creates launcher with update interception enabled
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallPath,
        
        [Parameter(Mandatory=$false)]
        [string]$LauncherName = "cursor-agent.bat",
        
        [Parameter(Mandatory=$false)]
        [string]$RealCursorAgentPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$EnableUpdateInterception
    )
    
    try {
        # Validate install path
        if ([string]::IsNullOrWhiteSpace($InstallPath)) {
            throw "New-CursorAgentLauncher: InstallPath parameter is null or empty"
        }
        
        $InstallPath = [System.Environment]::ExpandEnvironmentVariables($InstallPath)
        if (-not [System.IO.Path]::IsPathRooted($InstallPath)) {
            $InstallPath = [System.IO.Path]::GetFullPath($InstallPath)
        }
        
        if (-not (Test-Path -Path $InstallPath -PathType Container)) {
            throw "New-CursorAgentLauncher: Install path does not exist: '$InstallPath'"
        }
        
        $indexJsPath = Join-Path -Path $InstallPath -ChildPath "index.js"
        if (-not (Test-Path -Path $indexJsPath -PathType Leaf)) {
            throw "New-CursorAgentLauncher: index.js not found in install path: '$InstallPath'"
        }
        
        # Generate launcher script
        $launcherPath = Join-Path -Path $InstallPath -ChildPath $LauncherName
        
        if ($EnableUpdateInterception) {
            # Update interception mode
            Write-Verbose "Creating launcher with update interception enabled"
            
            # Determine patcher module path
            $patcherModulePath = Join-Path -Path $InstallPath -ChildPath "CursorAgentPatcher.psm1"
            if (-not (Test-Path -Path $patcherModulePath -PathType Leaf)) {
                Write-Warning "New-CursorAgentLauncher: Patcher module not found at '$patcherModulePath'. Update interception may not work correctly."
            }
            
            # Create PowerShell wrapper script
            $wrapperScriptName = "cursor-agent-wrapper.ps1"
            $wrapperScriptPath = Join-Path -Path $InstallPath -ChildPath $wrapperScriptName
            
            # Build wrapper script content
            $wrapperContent = @"
# cursor-agent-wrapper.ps1
# PowerShell wrapper for cursor-agent with update interception

param([string[]]`$args)

# Import patcher module
`$modulePath = Join-Path `$PSScriptRoot "CursorAgentPatcher.psm1"
if (Test-Path `$modulePath) {
    Import-Module `$modulePath -ErrorAction SilentlyContinue
}

# Check if update/upgrade command
if (`$args.Count -gt 0 -and (`$args[0] -eq "update" -or `$args[0] -eq "upgrade")) {
    # Intercept update command
    # Note: Requires Spec 037 (Invoke-CursorAgentUpdateWithPatch) to be fully functional
    try {
        if (Get-Command Invoke-CursorAgentUpdateWithPatch -ErrorAction SilentlyContinue) {
            `$updateArgs = if (`$args.Count -gt 1) { `$args[1..(`$args.Length-1)] } else { @() }
            `$result = Invoke-CursorAgentUpdateWithPatch -UpdateArguments `$updateArgs
            
            if (`$result.UpdateSuccess) {
                if (`$result.PatchSuccess) {
                    Write-Host "Update and patch completed successfully!" -ForegroundColor Green
                    exit 0
                } else {
                    Write-Warning "Update succeeded but patching failed. Run patch manually."
                    exit 1
                }
            } else {
                Write-Error "Update failed: `$(`$result.UpdateError)"
                exit `$result.UpdateExitCode
            }
        } else {
            Write-Warning "Update interception not fully implemented (Spec 037 required). Running update without auto-patch."
            # Fall through to normal execution
        }
    } catch {
        Write-Warning "Update interception failed: `$_. Running update without auto-patch."
        # Fall through to normal execution
    }
}

# Pass through to real cursor-agent or execute directly
`$realPath = "$RealCursorAgentPath"
if (-not [string]::IsNullOrWhiteSpace(`$realPath) -and (Test-Path `$realPath)) {
    & `$realPath @args
    exit `$LASTEXITCODE
} else {
    # Fallback: try to find in PATH
    `$cmd = Get-Command cursor-agent -ErrorAction SilentlyContinue
    if (`$cmd) {
        & `$cmd.Source @args
        exit `$LASTEXITCODE
    } else {
        # Execute directly using Bun/Node
        `$indexJs = Join-Path `$PSScriptRoot "index.js"
        if (Test-Path `$indexJs) {
            bun `$indexJs @args 2>`$null
            if (`$LASTEXITCODE -ne 0) {
                node `$indexJs @args
            }
            exit `$LASTEXITCODE
        } else {
            Write-Error "Cannot find cursor-agent executable or index.js"
            exit 1
        }
    }
}
"@
            
            # Write wrapper script
            Set-Content -Path $wrapperScriptPath -Value $wrapperContent -Encoding UTF8 -ErrorAction Stop
            Write-Verbose "Wrapper script created: $wrapperScriptPath"
            
            # Create batch file that calls wrapper
            $scriptContent = @"
@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0$wrapperScriptName" %*
"@
        }
        else {
            # Standard mode
            Write-Verbose "Creating standard launcher script"
            $scriptContent = @"
@echo off
cd /d "%~dp0"
bun index.js %* 2>nul || node index.js %*
"@
        }
        
        Set-Content -Path $launcherPath -Value $scriptContent -Encoding ASCII -ErrorAction Stop
        
        Write-Verbose "Launcher script created: $launcherPath"
        return $launcherPath
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error "New-CursorAgentLauncher: Install path not found: '$InstallPath'"
        throw
    }
    catch [System.ArgumentException] {
        Write-Error "New-CursorAgentLauncher: Invalid path format. Error: $_"
        throw
    }
    catch {
        Write-Error "New-CursorAgentLauncher: Failed to create launcher script. Error: $_"
        throw
    }
}

function Invoke-CursorAgentPatch {
    <#
    .SYNOPSIS
    Orchestrate complete patching workflow from download to installation.
    
    .DESCRIPTION
    Main workflow function that downloads, extracts, patches, and installs Cursor Agent
    for Windows. Supports both standard mode (download/extract) and in-place patching
    mode (patch existing installation).
    
    .PARAMETER Version
    Optional Cursor Agent version. If not provided, will be auto-detected.
    
    .PARAMETER InstallPath
    Installation path for the patched package. Defaults to config value.
    
    .PARAMETER WhatIf
    Show what would be done without actually performing operations.
    
    .PARAMETER PatchExistingInstallation
    Path to already-extracted installation. If provided, skips download/extract steps.
    
    .PARAMETER Force
    Re-patch even if installation is already patched.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Version,
        
        [Parameter(Mandatory=$false)]
        [string]$InstallPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf,
        
        [Parameter(Mandatory=$false)]
        [string]$PatchExistingInstallation,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        Write-Verbose "Starting Cursor Agent patching workflow"
        
        # Step 1: Load configuration
        $config = Get-PatcherConfig
        Write-Verbose "Configuration loaded"
        
        # Step 2: Initialize cache
        $cacheDir = Initialize-CacheDirectory -CacheDirectory $config.cache.directory
        Write-Verbose "Cache directory initialized: $cacheDir"
        
        # Determine mode
        $inPlaceMode = -not [string]::IsNullOrWhiteSpace($PatchExistingInstallation)
        
        if ($inPlaceMode) {
            # In-Place Patching Mode
            Write-Verbose "In-place patching mode: $PatchExistingInstallation"
            
            # Validate installation path
            $installationPath = [System.Environment]::ExpandEnvironmentVariables($PatchExistingInstallation)
            if (-not [System.IO.Path]::IsPathRooted($installationPath)) {
                $installationPath = [System.IO.Path]::GetFullPath($installationPath)
            }
            
            if (-not (Test-Path -Path $installationPath -PathType Container)) {
                throw "Invoke-CursorAgentPatch: Installation path does not exist: '$installationPath'"
            }
            
            $indexJsPath = Join-Path -Path $installationPath -ChildPath "index.js"
            if (-not (Test-Path -Path $indexJsPath -PathType Leaf)) {
                throw "Invoke-CursorAgentPatch: index.js not found in installation path: '$installationPath'"
            }
            
            # Check if already patched
            if (-not $Force) {
                $patchStatus = Test-InstallationPatched -InstallationPath $installationPath
                if ($patchStatus.IsPatched) {
                    Write-Host "Installation is already patched. Use -Force to re-patch." -ForegroundColor Yellow
                    return @{
                        Success = $true
                        AlreadyPatched = $true
                        Message = "Installation already patched"
                    }
                }
            }
            
            # Extract version from installation (try package.json)
            $packageJsonPath = Join-Path -Path $installationPath -ChildPath "package.json"
            $cursorAgentVersion = $null
            if (Test-Path -Path $packageJsonPath -PathType Leaf) {
                try {
                    $packageJson = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json
                    $cursorAgentVersion = $packageJson.version
                }
                catch {
                    Write-Verbose "Failed to read version from package.json: $_"
                }
            }
            
            if ([string]::IsNullOrWhiteSpace($cursorAgentVersion)) {
                # Try to extract from install script as fallback
                try {
                    $installScript = Get-CursorAgentInstallScript
                    $cursorAgentVersion = Get-CursorAgentVersion -InstallScript $installScript
                }
                catch {
                    Write-Warning "Could not determine Cursor Agent version, using 'unknown'"
                    $cursorAgentVersion = "unknown"
                }
            }
            
            # Build patch context
            $context = New-PatchContext -PackagePath $installationPath -CursorAgentVersion $cursorAgentVersion -CacheDirectory $cacheDir
            
            # Register patches
            Register-StandardPatches
            
            # Resolve patch order
            $patchOrder = Resolve-PatchDependencies
            
            # Apply patches
            $allPatchResults = @{}
            $allAppliedPatches = @()
            
            foreach ($patchId in $patchOrder) {
                $patch = $script:PatchRegistry[$patchId]
                Write-Verbose "Applying patch: $patchId"
                
                $patchResult = Invoke-Patch -PatchDefinition $patch -PackagePath $installationPath -Context $context -WhatIf:$WhatIf
                
                $allPatchResults[$patchId] = @{
                    success = $patchResult.Success
                    filesModified = @() # Would need to track this in Invoke-Patch
                    errors = $patchResult.Errors
                }
                
                if ($patchResult.Success) {
                    $allAppliedPatches += $patchId
                }
            }
            
            # Write patch state marker
            if (-not $WhatIf) {
                Write-PatchStateMarker -InstallationPath $installationPath -CursorAgentVersion $cursorAgentVersion -AppliedPatches $allAppliedPatches -PatchResults $allPatchResults -DependencyVersions $context.DependencyVersions
            }
            
            return @{
                Success = $true
                Mode = "InPlace"
                InstallationPath = $installationPath
                AppliedPatches = $allAppliedPatches
                PatchResults = $allPatchResults
            }
        }
        else {
            # Standard Mode
            Write-Verbose "Standard patching mode"
            
            # Step 3: Get Cursor Agent version
            if ([string]::IsNullOrWhiteSpace($Version)) {
                Write-Verbose "Auto-detecting Cursor Agent version"
                $installScript = Get-CursorAgentInstallScript
                $Version = Get-CursorAgentVersion -InstallScript $installScript
            }
            Write-Verbose "Cursor Agent version: $Version"
            
            # Step 4: Download package
            $packagePath = $null
            if (-not $WhatIf) {
                $packageOutPath = Join-Path -Path $cacheDir -ChildPath "packages\cursor-agent-$Version.tar.gz"
                $packagePath = Get-CursorAgentPackage -Version $Version -SourceOs $config.cursorAgent.sourceOs -SourceArch $config.cursorAgent.sourceArch -OutPath $packageOutPath
                Write-Verbose "Package downloaded: $packagePath"
            }
            else {
                Write-Host "What if: Would download package for version $Version"
            }
            
            # Step 5: Extract package
            $extractedPath = $null
            if (-not $WhatIf -and $packagePath) {
                $extractDir = Join-Path -Path $env:TEMP -ChildPath "cursor-agent-extract-$(New-Guid)"
                $extractedPath = Expand-CursorAgentPackage -PackagePath $packagePath -OutputDirectory $extractDir
                Write-Verbose "Package extracted: $extractedPath"
            }
            else {
                Write-Host "What if: Would extract package"
            }
            
            if ($WhatIf) {
                return @{
                    Success = $true
                    Mode = "Standard"
                    WhatIf = $true
                    Version = $Version
                }
            }
            
            # Step 6: Build patch context
            $context = New-PatchContext -PackagePath $extractedPath -CursorAgentVersion $Version -CacheDirectory $cacheDir
            
            # Step 7: Register patches
            Register-StandardPatches
            
            # Step 8: Resolve patch order
            $patchOrder = Resolve-PatchDependencies
            
            # Step 9: Apply patches
            $allPatchResults = @{}
            $allAppliedPatches = @()
            
            foreach ($patchId in $patchOrder) {
                $patch = $script:PatchRegistry[$patchId]
                Write-Verbose "Applying patch: $patchId"
                
                $patchResult = Invoke-Patch -PatchDefinition $patch -PackagePath $extractedPath -Context $context -WhatIf:$WhatIf
                
                $allPatchResults[$patchId] = @{
                    success = $patchResult.Success
                    filesModified = @()
                    errors = $patchResult.Errors
                }
                
                if ($patchResult.Success) {
                    $allAppliedPatches += $patchId
                }
            }
            
            # Step 10: Copy patched package to install path
            if ([string]::IsNullOrWhiteSpace($InstallPath)) {
                $InstallPath = $config.installation.defaultPath
            }
            $InstallPath = [System.Environment]::ExpandEnvironmentVariables($InstallPath)
            if (-not [System.IO.Path]::IsPathRooted($InstallPath)) {
                $InstallPath = [System.IO.Path]::GetFullPath($InstallPath)
            }
            
            Write-Verbose "Copying patched package to: $InstallPath"
            if (Test-Path -Path $InstallPath) {
                Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
            }
            Copy-Item -Path $extractedPath -Destination $InstallPath -Recurse -Force -ErrorAction Stop
            
            # Step 11: Create launcher script
            if ($config.installation.createLauncher) {
                New-CursorAgentLauncher -InstallPath $InstallPath -LauncherName $config.installation.launcherName | Out-Null
            }
            
            # Step 12: Write patch state marker
            Write-PatchStateMarker -InstallationPath $InstallPath -CursorAgentVersion $Version -AppliedPatches $allAppliedPatches -PatchResults $allPatchResults -DependencyVersions $context.DependencyVersions
            
            # Cleanup temp extraction directory
            Remove-Item -Path $extractedPath -Recurse -Force -ErrorAction SilentlyContinue
            
            return @{
                Success = $true
                Mode = "Standard"
                Version = $Version
                InstallationPath = $InstallPath
                AppliedPatches = $allAppliedPatches
                PatchResults = $allPatchResults
            }
        }
    }
    catch {
        Write-Error "Invoke-CursorAgentPatch: Failed to complete patching workflow. Error: $_"
        throw
    }
}

function Invoke-PatchExistingInstallation {
    <#
    .SYNOPSIS
    Patch an existing cursor-agent installation.
    
    .DESCRIPTION
    Convenience wrapper that calls Invoke-CursorAgentPatch with -PatchExistingInstallation.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    return Invoke-CursorAgentPatch -PatchExistingInstallation $InstallationPath -Force:$Force
}

function Resolve-LauncherTarget {
    <#
    .SYNOPSIS
    Resolve the target path of a cursor-agent launcher (symlink, shortcut, or script).
    
    .DESCRIPTION
    Attempts multiple methods to resolve the actual target path of a launcher:
    - PowerShell link resolution (symlinks/junctions)
    - Windows shortcut (.lnk) files
    - Script file parsing (bash/PowerShell scripts)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LauncherPath
    )
    
    try {
        if (-not (Test-Path -Path $LauncherPath)) {
            throw "Resolve-LauncherTarget: Launcher path does not exist: '$LauncherPath'"
        }
        
        $launcherItem = Get-Item -Path $LauncherPath -Force -ErrorAction Stop
        
        # Method 1: PowerShell Link Resolution (symlinks/junctions)
        if ($launcherItem.LinkType) {
            $target = $launcherItem.Target
            if ($target) {
                Write-Verbose "Resolved via link type '$($launcherItem.LinkType)': $target"
                return $target
            }
        }
        
        # Method 2: Windows Shortcut (.lnk files)
        if ($LauncherPath -match '\.lnk$') {
            try {
                $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop
                $shortcut = $shell.CreateShortcut($LauncherPath)
                $target = $shortcut.TargetPath
                if ($target) {
                    Write-Verbose "Resolved via Windows shortcut: $target"
                    return $target
                }
            }
            catch {
                Write-Verbose "Failed to resolve via shortcut: $_"
            }
        }
        
        # Method 3: Read Script Content (bash/PowerShell scripts)
        if ($launcherItem.Extension -in @('.sh', '.ps1', '.bat', '.cmd', '') -or $null -eq $launcherItem.Extension) {
            try {
                $scriptContent = Get-Content -Path $LauncherPath -Raw -ErrorAction Stop
                
                # Look for patterns like: exec "$SCRIPT_DIR/index.js" or node "$SCRIPT_DIR/index.js"
                $patterns = @(
                    'exec\s+["'']\$SCRIPT_DIR/index\.js["'']',
                    'node\s+["'']\$SCRIPT_DIR/index\.js["'']',
                    'bun\s+["'']\$SCRIPT_DIR/index\.js["'']',
                    'exec\s+["'']([^"'']+)/index\.js["'']',
                    'node\s+["'']([^"'']+)/index\.js["'']',
                    'bun\s+["'']([^"'']+)/index\.js["'']'
                )
                
                foreach ($pattern in $patterns) {
                    if ($scriptContent -match $pattern) {
                        if ($Matches[1]) {
                            # Absolute path found
                            $target = $Matches[1] + '\index.js'
                            if (Test-Path -Path $target) {
                                Write-Verbose "Resolved via script pattern '$pattern': $target"
                                return $target
                            }
                        }
                        else {
                            # Need to resolve $SCRIPT_DIR
                            if ($scriptContent -match '\$SCRIPT_DIR\s*=\s*["'']([^"'']+)["'']') {
                                $scriptDir = $Matches[1]
                                $target = Join-Path -Path $scriptDir -ChildPath 'index.js'
                                if (Test-Path -Path $target) {
                                    Write-Verbose "Resolved via script with SCRIPT_DIR: $target"
                                    return $target
                                }
                            }
                            # Try relative to launcher directory
                            $launcherDir = Split-Path -Path $LauncherPath -Parent
                            $target = Join-Path -Path $launcherDir -ChildPath 'index.js'
                            if (Test-Path -Path $target) {
                                Write-Verbose "Resolved via script relative path: $target"
                                return $target
                            }
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Failed to parse script content: $_"
            }
        }
        
        # Method 4: Junction/Symlink via cmd dir
        try {
            $dirOutput = cmd /c "dir `"$LauncherPath`" /A:L" 2>&1
            if ($dirOutput -match '<SYMLINK|JUNCTION>') {
                # Try to extract target from output or use Get-Item with -Force
                $targetItem = Get-Item -Path $LauncherPath -Force -ErrorAction Stop
                if ($targetItem.Target) {
                    Write-Verbose "Resolved via junction/symlink: $($targetItem.Target)"
                    return $targetItem.Target
                }
            }
        }
        catch {
            Write-Verbose "Failed to resolve via dir command: $_"
        }
        
        # If all methods fail, throw
        throw "Resolve-LauncherTarget: Could not resolve target for launcher: '$LauncherPath'"
    }
    catch {
        Write-Error "Resolve-LauncherTarget: Failed to resolve launcher target. Error: $_"
        throw
    }
}

function Get-CursorAgentVersionDirectory {
    <#
    .SYNOPSIS
    Detect the cursor-agent version directory by resolving the launcher symlink/shortcut target.
    
    .DESCRIPTION
    Finds the cursor-agent launcher (cursor-agent or agent in PATH or common locations),
    resolves its target (symlink, shortcut, or script), and extracts the version directory
    path from the target.
    
    .PARAMETER LauncherPath
    Optional: specific launcher path. If not provided, searches PATH and common locations.
    
    .OUTPUTS
    string. Returns the absolute path to the version directory.
    
    .EXAMPLE
    $versionDir = Get-CursorAgentVersionDirectory
    # Returns: "C:\Users\user\.local\share\cursor-agent\versions\2026.01.23-916f423"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$LauncherPath
    )
    
    try {
        # Step 1: Find Launcher
        if ([string]::IsNullOrWhiteSpace($LauncherPath)) {
            # Search PATH for cursor-agent or agent
            $launcherCommands = @('cursor-agent', 'agent')
            $foundLauncher = $null
            
            foreach ($cmd in $launcherCommands) {
                try {
                    $command = Get-Command -Name $cmd -ErrorAction Stop
                    $foundLauncher = $command.Source
                    Write-Verbose "Found launcher in PATH: $foundLauncher"
                    break
                }
                catch {
                    # Continue searching
                }
            }
            
            # If not found in PATH, check common locations
            if (-not $foundLauncher) {
                $commonPaths = @(
                    "$env:USERPROFILE\.local\bin\cursor-agent",
                    "$env:USERPROFILE\.local\bin\agent",
                    "$env:LOCALAPPDATA\cursor-agent\bin\cursor-agent",
                    "$env:LOCALAPPDATA\cursor-agent\bin\agent"
                )
                
                foreach ($path in $commonPaths) {
                    if (Test-Path -Path $path) {
                        $foundLauncher = $path
                        Write-Verbose "Found launcher in common location: $foundLauncher"
                        break
                    }
                }
            }
            
            if (-not $foundLauncher) {
                throw "Get-CursorAgentVersionDirectory: Cannot find cursor-agent launcher. Searched PATH and common locations: $($commonPaths -join ', ')"
            }
            
            $LauncherPath = $foundLauncher
        }
        
        # Validate launcher exists
        if (-not (Test-Path -Path $LauncherPath)) {
            throw "Get-CursorAgentVersionDirectory: Launcher path does not exist: '$LauncherPath'"
        }
        
        # Step 2: Resolve Target
        $targetPath = Resolve-LauncherTarget -LauncherPath $LauncherPath
        
        if (-not $targetPath) {
            # Fallback: Try to find versions directory
            Write-Verbose "Symlink resolution failed, trying fallback strategy"
            
            # Get parent directory of launcher
            $launcherDir = Split-Path -Path $LauncherPath -Parent
            
            # Search for versions directory in common locations
            $versionsDirs = @(
                "$env:USERPROFILE\.local\share\cursor-agent\versions",
                "$env:LOCALAPPDATA\cursor-agent\versions"
            )
            
            foreach ($versionsDir in $versionsDirs) {
                if (Test-Path -Path $versionsDir -PathType Container) {
                    # Find newest directory by modification time
                    $versionDirs = Get-ChildItem -Path $versionsDir -Directory | Sort-Object LastWriteTime -Descending
                    if ($versionDirs.Count -gt 0) {
                        $targetPath = $versionDirs[0].FullName
                        Write-Verbose "Using fallback: newest version directory: $targetPath"
                        break
                    }
                }
            }
            
            if (-not $targetPath) {
                throw "Get-CursorAgentVersionDirectory: Could not resolve version directory. Launcher: '$LauncherPath'"
            }
        }
        
        # Step 3: Extract Version Directory
        # Target typically points to: VERSIONS_DIR/VERSION/cursor-agent or VERSIONS_DIR/VERSION/agent
        # Or directly to: VERSIONS_DIR/VERSION/index.js
        $versionDir = $null
        
        if (Test-Path -Path $targetPath -PathType Leaf) {
            # Target is a file (e.g., index.js), get parent directory
            $versionDir = Split-Path -Path $targetPath -Parent
        }
        elseif (Test-Path -Path $targetPath -PathType Container) {
            # Target is already a directory
            $versionDir = $targetPath
        }
        else {
            # Target path doesn't exist, try parent
            $versionDir = Split-Path -Path $targetPath -Parent
        }
        
        # Step 4: Validate Installation
        if (-not (Test-Path -Path $versionDir -PathType Container)) {
            throw "Get-CursorAgentVersionDirectory: Version directory does not exist: '$versionDir'"
        }
        
        $indexJsPath = Join-Path -Path $versionDir -ChildPath 'index.js'
        if (-not (Test-Path -Path $indexJsPath -PathType Leaf)) {
            throw "Get-CursorAgentVersionDirectory: Invalid installation - index.js not found in: '$versionDir'"
        }
        
        # Return absolute path
        $absoluteVersionDir = (Resolve-Path -Path $versionDir).Path
        Write-Verbose "Resolved version directory: $absoluteVersionDir"
        return $absoluteVersionDir
    }
    catch {
        Write-Error "Get-CursorAgentVersionDirectory: Failed to detect version directory. Error: $_"
        throw
    }
}

function Invoke-CursorAgentUpdateWithPatch {
    <#
    .SYNOPSIS
    Intercept cursor-agent update command, execute the real update, then automatically patch the newly updated version.
    
    .DESCRIPTION
    Finds the real cursor-agent executable, executes the update command, waits for symlink update,
    detects the new version directory, checks if already patched, and patches if needed.
    
    .PARAMETER UpdateArguments
    Additional arguments to pass to cursor-agent update command.
    
    .PARAMETER WhatIf
    If specified, shows what would be done without actually executing.
    
    .PARAMETER Force
    Force re-patch even if already patched.
    
    .OUTPUTS
    hashtable. Returns result summary with UpdateSuccess, UpdateExitCode, UpdateError, PatchSuccess,
    PatchResult, VersionDirectory, and AlreadyPatched fields.
    
    .EXAMPLE
    $result = Invoke-CursorAgentUpdateWithPatch
    if ($result.UpdateSuccess -and $result.PatchSuccess) {
        Write-Host "Update and patch completed successfully!"
    }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$UpdateArguments,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    $result = @{
        UpdateSuccess = $false
        UpdateExitCode = -1
        UpdateError = $null
        PatchSuccess = $false
        PatchResult = $null
        VersionDirectory = $null
        AlreadyPatched = $false
    }
    
    try {
        # Step 1: Find the real cursor-agent executable/script
        $launcherCommands = @('cursor-agent', 'agent')
        $foundLauncher = $null
        
        foreach ($cmd in $launcherCommands) {
            try {
                $command = Get-Command -Name $cmd -ErrorAction Stop
                $foundLauncher = $command.Source
                Write-Verbose "Found cursor-agent launcher: $foundLauncher"
                break
            }
            catch {
                # Continue searching
            }
        }
        
        # If not found in PATH, check common locations
        if (-not $foundLauncher) {
            $commonPaths = @(
                "$env:USERPROFILE\.local\bin\cursor-agent",
                "$env:USERPROFILE\.local\bin\agent",
                "$env:LOCALAPPDATA\cursor-agent\bin\cursor-agent",
                "$env:LOCALAPPDATA\cursor-agent\bin\agent"
            )
            
            foreach ($path in $commonPaths) {
                if (Test-Path -Path $path) {
                    $foundLauncher = $path
                    Write-Verbose "Found cursor-agent launcher in common location: $foundLauncher"
                    break
                }
            }
        }
        
        if (-not $foundLauncher) {
            throw "Invoke-CursorAgentUpdateWithPatch: Cannot find cursor-agent executable. Searched PATH and common locations. Please ensure cursor-agent is installed and in your PATH."
        }
        
        # Step 2: Execute cursor-agent update command
        Write-Verbose "Executing: $foundLauncher update $($UpdateArguments -join ' ')"
        
        if ($WhatIf) {
            Write-Host "WhatIf: Would execute: $foundLauncher update $($UpdateArguments -join ' ')" -ForegroundColor Yellow
            $result.UpdateSuccess = $true
            $result.UpdateExitCode = 0
            return $result
        }
        
        $processArgs = @('update') + $UpdateArguments
        $process = Start-Process -FilePath $foundLauncher -ArgumentList $processArgs -Wait -PassThru -NoNewWindow
        
        $result.UpdateExitCode = $process.ExitCode
        
        # Step 3: Check exit code
        if ($result.UpdateExitCode -ne 0) {
            $result.UpdateSuccess = $false
            $result.UpdateError = "cursor-agent update exited with code $($result.UpdateExitCode)"
            Write-Warning "Update command failed: $($result.UpdateError)"
            return $result
        }
        
        $result.UpdateSuccess = $true
        Write-Verbose "Update command completed successfully"
        
        # Step 4: Wait briefly for symlink update to complete
        Start-Sleep -Milliseconds 300
        
        # Step 5: Detect new version directory
        try {
            $versionDirectory = Get-CursorAgentVersionDirectory
            $result.VersionDirectory = $versionDirectory
            Write-Verbose "Detected version directory: $versionDirectory"
        }
        catch {
            Write-Warning "Invoke-CursorAgentUpdateWithPatch: Failed to detect version directory after update. Error: $_"
            $result.UpdateError = "Update succeeded but version detection failed: $_"
            return $result
        }
        
        # Step 6: Check if already patched
        try {
            $patchStatus = Test-InstallationPatched -InstallationPath $versionDirectory
            $result.AlreadyPatched = $patchStatus.IsPatched
            
            if ($result.AlreadyPatched -and -not $Force) {
                Write-Verbose "Installation is already patched. Skipping patching (use -Force to re-patch)."
                $result.PatchSuccess = $true
                return $result
            }
        }
        catch {
            Write-Warning "Invoke-CursorAgentUpdateWithPatch: Failed to check patch status. Error: $_"
            # Continue with patching anyway
        }
        
        # Step 7: Patch the new version
        try {
            Write-Verbose "Patching installation at: $versionDirectory"
            $patchResult = Invoke-PatchExistingInstallation -InstallationPath $versionDirectory -Force:$Force
            $result.PatchResult = $patchResult
            $result.PatchSuccess = $true
            Write-Verbose "Patching completed successfully"
        }
        catch {
            Write-Error "Invoke-CursorAgentUpdateWithPatch: Patching failed. Error: $_"
            $result.PatchSuccess = $false
            $result.PatchResult = @{
                Success = $false
                Error = $_.ToString()
            }
            return $result
        }
        
        return $result
    }
    catch {
        Write-Error "Invoke-CursorAgentUpdateWithPatch: Failed to execute update with patch workflow. Error: $_"
        $result.UpdateError = $_.ToString()
        $result.UpdateSuccess = $false
        return $result
    }
}

#endregion

# Export module members
# Only export public API functions - all helper functions remain internal
Export-ModuleMember -Function Get-PatcherConfig, Get-CursorAgentVersion, Invoke-CursorAgentPatch, New-CursorAgentLauncher, Get-WindowsArchitecture, Get-CursorAgentVersionDirectory, Invoke-CursorAgentUpdateWithPatch
