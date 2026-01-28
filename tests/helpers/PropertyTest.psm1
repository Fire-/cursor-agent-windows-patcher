# PropertyTest.psm1
# Property-based testing framework for PowerShell (similar to FsCheck/QuickCheck)

<#
.SYNOPSIS
Property-based testing framework for PowerShell.

.DESCRIPTION
Provides property-based testing capabilities similar to FsCheck/QuickCheck.
Generates random test inputs, runs tests, and shrinks counterexamples to minimal cases.
#>

#region Generators

# Random number generator (seeded for reproducibility)
$script:Random = New-Object System.Random

function Set-TestSeed {
    <#
    .SYNOPSIS
    Set the random seed for deterministic test generation.
    #>
    param([int]$Seed)
    $script:Random = New-Object System.Random $Seed
}

function Gen-Integer {
    <#
    .SYNOPSIS
    Generate random integers in a range.
    
    .PARAMETER Min
    Minimum value (default: -1000)
    
    .PARAMETER Max
    Maximum value (default: 1000)
    #>
    param(
        [int]$Min = -1000,
        [int]$Max = 1000
    )
    
    $obj = [PSCustomObject]@{
        Type     = 'Integer'
        Min      = $Min
        Max      = $Max
        Generate = {
            param([System.Random]$rng)
            return $rng.Next($Min, $Max + 1)
        }
        Shrink   = {
            param($value)
            $shrinks = @()
            if ($value -ne 0) {
                $shrinks += 0
            }
            if ($value -gt $Min) {
                $shrinks += [Math]::Max($Min, $value - 1)
            }
            if ($value -lt $Max) {
                $shrinks += [Math]::Min($Max, $value + 1)
            }
            return $shrinks
        }
    }
    $obj.PSTypeNames.Add('PropertyTest.Generator')
    return $obj
}

function Gen-String {
    <#
    .SYNOPSIS
    Generate random strings with constraints.
    
    .PARAMETER MinLength
    Minimum string length (default: 0)
    
    .PARAMETER MaxLength
    Maximum string length (default: 100)
    
    .PARAMETER CharSet
    Characters to use (default: alphanumeric)
    #>
    param(
        [int]$MinLength = 0,
        [int]$MaxLength = 100,
        [string]$CharSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    )
    
    $obj = [PSCustomObject]@{
        Type      = 'String'
        MinLength = $MinLength
        MaxLength = $MaxLength
        CharSet   = $CharSet
        Generate  = {
            param([System.Random]$rng)
            $length = $rng.Next($MinLength, $MaxLength + 1)
            $chars = $CharSet.ToCharArray()
            $result = ''
            for ($i = 0; $i -lt $length; $i++) {
                $result += $chars[$rng.Next($chars.Length)]
            }
            return $result
        }
        Shrink    = {
            param($value)
            $shrinks = @()
            if ($value.Length -gt $MinLength) {
                # Remove characters from end
                $shrinks += $value.Substring(0, [Math]::Max($MinLength, $value.Length - 1))
                # Remove characters from beginning
                if ($value.Length -gt 1) {
                    $shrinks += $value.Substring(1)
                }
                # Remove middle character
                if ($value.Length -gt 2) {
                    $mid = [Math]::Floor($value.Length / 2)
                    $shrinks += $value.Substring(0, $mid) + $value.Substring($mid + 1)
                }
            }
            return $shrinks
        }
    }
    $obj.PSTypeNames.Add('PropertyTest.Generator')
    return $obj
}

function Gen-VersionString {
    <#
    .SYNOPSIS
    Generate version strings like "2025.08.15-dbc8d73"
    #>
    $obj = [PSCustomObject]@{
        Type     = 'VersionString'
        Generate = {
            param([System.Random]$rng)
            $year = $rng.Next(2020, 2030)
            $month = $rng.Next(1, 13).ToString('00')
            $day = $rng.Next(1, 29).ToString('00')
            $hash = ''
            $hexChars = '0123456789abcdef'
            for ($i = 0; $i -lt 7; $i++) {
                $hash += $hexChars[$rng.Next($hexChars.Length)]
            }
            return "$year.$month.$day-$hash"
        }
        Shrink   = {
            param($value)
            $shrinks = @()
            # Try shorter hash
            if ($value -match '^(\d{4}\.\d{2}\.\d{2}-)([a-f0-9]+)$') {
                $prefix = $Matches[1]
                $hash = $Matches[2]
                if ($hash.Length -gt 1) {
                    $shrinks += $prefix + $hash.Substring(0, $hash.Length - 1)
                }
            }
            return $shrinks
        }
    }
    $obj.PSTypeNames.Add('PropertyTest.Generator')
    return $obj
}

function Gen-SemanticVersion {
    <#
    .SYNOPSIS
    Generate semantic versions like "5.1.7"
    #>
    $obj = [PSCustomObject]@{
        Type     = 'SemanticVersion'
        Generate = {
            param([System.Random]$rng)
            $major = $rng.Next(0, 100)
            $minor = $rng.Next(0, 100)
            $patch = $rng.Next(0, 100)
            return "$major.$minor.$patch"
        }
        Shrink   = {
            param($value)
            $shrinks = @()
            if ($value -match '^(\d+)\.(\d+)\.(\d+)$') {
                $major = [int]$Matches[1]
                $minor = [int]$Matches[2]
                $patch = [int]$Matches[3]
                if ($patch -gt 0) {
                    $shrinks += "$major.$minor.$($patch - 1)"
                }
                if ($minor -gt 0) {
                    $shrinks += "$major.$($minor - 1).0"
                }
                if ($major -gt 0) {
                    $shrinks += "$($major - 1).0.0"
                }
            }
            return $shrinks
        }
    }
    $obj.PSTypeNames.Add('PropertyTest.Generator')
    return $obj
}

function Gen-FilePath {
    <#
    .SYNOPSIS
    Generate valid file paths.
    #>
    param(
        [string]$BasePath = $env:TEMP
    )
    
    $obj = [PSCustomObject]@{
        Type     = 'FilePath'
        BasePath = $BasePath
        Generate = {
            param([System.Random]$rng)
            $nameGen = Gen-String -MinLength 1 -MaxLength 20 -CharSet 'abcdefghijklmnopqrstuvwxyz0123456789'
            $name = & $nameGen.Generate $rng
            $ext = @('.txt', '.json', '.ps1', '.js', '.node', '.exe')[$rng.Next(6)]
            return Join-Path -Path $BasePath -ChildPath "$name$ext"
        }
        Shrink   = {
            param($value)
            $shrinks = @()
            $dir = Split-Path -Path $value -Parent
            $name = [System.IO.Path]::GetFileNameWithoutExtension($value)
            if ($name.Length -gt 1) {
                $ext = [System.IO.Path]::GetExtension($value)
                $shrinks += Join-Path -Path $dir -ChildPath "$($name.Substring(0, $name.Length - 1))$ext"
            }
            return $shrinks
        }
    }
    $obj.PSTypeNames.Add('PropertyTest.Generator')
    return $obj
}

function Gen-JSON {
    <#
    .SYNOPSIS
    Generate valid JSON structures.
    #>
    param(
        [int]$MaxDepth = 3
    )
    
    $obj = [PSCustomObject]@{
        Type     = 'JSON'
        MaxDepth = $MaxDepth
        Generate = {
            param([System.Random]$rng, [int]$depth = 0)
            if ($depth -ge $MaxDepth) {
                # Leaf: return simple value
                $types = @('string', 'number', 'boolean', 'null')
                $type = $types[$rng.Next($types.Length)]
                switch ($type) {
                    'string' { 
                        $strGen = Gen-String -MaxLength 20
                        return & $strGen.Generate $rng
                    }
                    'number' { return $rng.Next(-100, 100) }
                    'boolean' { return $rng.Next(2) -eq 1 }
                    'null' { return $null }
                }
            }
            else {
                $structure = $rng.Next(3)
                switch ($structure) {
                    0 {
                        # Object
                        $obj = @{}
                        $count = $rng.Next(0, 5)
                        for ($i = 0; $i -lt $count; $i++) {
                            $keyGen = Gen-String -MaxLength 10
                            $key = & $keyGen.Generate $rng
                            $jsonGen = Gen-JSON -MaxDepth $MaxDepth
                            $obj[$key] = & $jsonGen.Generate $rng ($depth + 1)
                        }
                        return $obj
                    }
                    1 {
                        # Array
                        $arr = @()
                        $count = $rng.Next(0, 5)
                        for ($i = 0; $i -lt $count; $i++) {
                            $jsonGen = Gen-JSON -MaxDepth $MaxDepth
                            $arr += & $jsonGen.Generate $rng ($depth + 1)
                        }
                        return $arr
                    }
                    2 {
                        # Simple value
                        $jsonGen = Gen-JSON -MaxDepth 0
                        return & $jsonGen.Generate $rng $MaxDepth
                    }
                }
            }
        }
        Shrink   = {
            param($value)
            $shrinks = @()
            if ($value -is [hashtable]) {
                # Remove keys
                if ($value.Count -gt 0) {
                    $keys = $value.Keys | Get-Random -Count ([Math]::Min(1, $value.Count))
                    $shrunk = $value.Clone()
                    foreach ($key in $keys) {
                        $shrunk.Remove($key)
                    }
                    $shrinks += $shrunk
                }
            }
            elseif ($value -is [array]) {
                # Remove elements
                if ($value.Length -gt 0) {
                    $shrinks += $value[0..($value.Length - 2)]
                }
            }
            return $shrinks
        }
    }
    $obj.PSTypeNames.Add('PropertyTest.Generator')
    return $obj
}

function Gen-Choice {
    <#
    .SYNOPSIS
    Choose from an array of values.
    #>
    param([array]$Values)
    
    $obj = [PSCustomObject]@{
        Type     = 'Choice'
        Values   = $Values
        Generate = {
            param([System.Random]$rng)
            return $Values[$rng.Next($Values.Length)]
        }
        Shrink   = {
            param($value)
            $index = [array]::IndexOf($Values, $value)
            $shrinks = @()
            if ($index -gt 0) {
                $shrinks += $Values[$index - 1]
            }
            if ($index -lt $Values.Length - 1) {
                $shrinks += $Values[$index + 1]
            }
            return $shrinks
        }
    }
    $obj.PSTypeNames.Add('PropertyTest.Generator')
    return $obj
}

#endregion

#region Property Testing

function Property {
            <#
    .SYNOPSIS
    Define and run a property-based test.
    
    .PARAMETER Name
    Name of the property test.
    
    .PARAMETER Test
    Scriptblock containing the test logic. Parameters should match ForAll keys.
    
    .PARAMETER ForAll
    Hashtable mapping parameter names to generators.
    
    .PARAMETER Tests
    Number of test cases to generate (default: 100)
    
    .PARAMETER Seed
    Random seed for reproducibility (optional)
    
    .EXAMPLE
    Property "Addition is commutative" {
        param($a, $b)
        ($a + $b) | Should -Be ($b + $a)
    } -ForAll @{
        a = Gen-Integer -Min 0 -Max 100
        b = Gen-Integer -Min 0 -Max 100
    }
    #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, Position = 0)]
                [string]$Name,
        
                [Parameter(Mandatory = $true, Position = 1)]
                [scriptblock]$Test,
        
                [Parameter(Mandatory = $true)]
                [hashtable]$ForAll,
        
                [int]$Tests = 100,
        
                [int]$Seed
            )
    
            if ($Seed) {
                Set-TestSeed -Seed $Seed
            }
    
            $rng = $script:Random
            $failures = @()
            
            for ($i = 0; $i -lt $Tests; $i++) {
                # Generate test inputs
                $inputs = @{}
                foreach ($paramName in $ForAll.Keys) {
                    $generator = $ForAll[$paramName]
                    if ($generator.PSTypeNames -contains 'PropertyTest.Generator') {
                        # Use & operator instead of .Invoke() to get string, not Collection
                        $generatedValue = & $generator.Generate $rng
                        $inputs[$paramName] = $generatedValue
                    }
                    else {
                        $inputs[$paramName] = $generator
                    }
                }
        
                # Run test
                try {
                    # Invoke test with named parameters using splatting
                    & $Test @inputs | Out-Null
                }
                catch {
                    $failure = @{
                        TestCase = $i
                        Inputs = $inputs.Clone()
                        Error = $_.Exception.Message
                        ShrunkInputs = $null
                    }
            
                    # Attempt to shrink counterexample
                    $failure.ShrunkInputs = Shrink-Counterexample -Inputs $inputs -Generators $ForAll -Test $Test -OriginalError $_.Exception.Message
            
                    $failures += $failure
                    break # Stop on first failure (can be configured to continue)
                }
            }
            
            if ($failures.Count -eq 0) {
                Write-Host "[PASS] Property '$Name' passed $Tests tests" -ForegroundColor Green
                return @{
                    Success = $true
                    TestsRun = $Tests
                    Failures = @()
                }
            }
            else {
                $failure = $failures[0]
                Write-Host "[FAIL] Property '$Name' failed" -ForegroundColor Red
                Write-Host "  Inputs: $($failure.Inputs | ConvertTo-Json -Compress)" -ForegroundColor Yellow
                if ($failure.ShrunkInputs) {
                    Write-Host "  Shrunk: $($failure.ShrunkInputs | ConvertTo-Json -Compress)" -ForegroundColor Yellow
                }
                Write-Host "  Error: $($failure.Error)" -ForegroundColor Red
        
                return @{
                    Success  = $false
                    TestsRun = $failure.TestCase + 1
                    Failures = $failures
                }
            }
        }

        function Shrink-Counterexample {
                <#
    .SYNOPSIS
    Shrink a counterexample to minimal case.
    #>
                param(
                    [hashtable]$Inputs,
                    [hashtable]$Generators,
                    [scriptblock]$Test,
                    [string]$OriginalError
                )
    
                $current = $Inputs.Clone()
                $improved = $true
                
                while ($improved) {
                    $improved = $false
        
                    # Create a copy of keys to iterate over (avoid modification during enumeration)
                    $paramNames = @($current.Keys)
                    foreach ($paramName in $paramNames) {
                        $generator = $Generators[$paramName]
                        if ($generator.PSTypeNames -contains 'PropertyTest.Generator') {
                            $shrinks = & $generator.Shrink $current[$paramName]
            
                            foreach ($shrunk in $shrinks) {
                                $testInputs = $current.Clone()
                                $testInputs[$paramName] = $shrunk
                
                                try {
                                    # Invoke test with named parameters using splatting
                                    & $Test @testInputs | Out-Null
                                    # Test passed with shrunk input, so this shrink is invalid
                                    continue
                                }
                                catch {
                                    # Test still fails, accept shrink
                                    $current[$paramName] = $shrunk
                                    $improved = $true
                                    break
                                }
                            }
                        }
                    }
                }
    
                return $current
        }

#endregion

# Export module members
Export-ModuleMember -Function Property, Gen-Integer, Gen-String, Gen-VersionString, Gen-SemanticVersion, Gen-FilePath, Gen-JSON, Gen-Choice, Set-TestSeed
