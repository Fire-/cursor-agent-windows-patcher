<#
.SYNOPSIS
Run integration tests in fail-fast order.

.DESCRIPTION
Runs selected integration test cases one at a time and stops immediately on the
first failure. This avoids waiting through long network-heavy scenarios after a
critical dependency/bootstrap failure.

.NOTES
Designed for Pester 3.x.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TestFile = (Join-Path $PSScriptRoot "end-to-end-patching.tests.ps1"),
    
    [Parameter(Mandatory = $false)]
    [string]$CriticalTestFile = (Join-Path $PSScriptRoot "critical-bootstrap.tests.ps1"),
    
    [Parameter(Mandatory = $false)]
    [string]$CompatibilityTestFile = (Join-Path $PSScriptRoot "version-compatibility.tests.ps1"),
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipCompatibility
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $TestFile -PathType Leaf)) {
    throw "run-end-to-end-failfast.ps1: Test file not found: '$TestFile'"
}
if (-not (Test-Path -Path $CriticalTestFile -PathType Leaf)) {
    throw "run-end-to-end-failfast.ps1: Critical test file not found: '$CriticalTestFile'"
}
if (-not $SkipCompatibility -and -not (Test-Path -Path $CompatibilityTestFile -PathType Leaf)) {
    throw "run-end-to-end-failfast.ps1: Compatibility test file not found: '$CompatibilityTestFile'"
}

Write-Host "Running integration tests in fail-fast mode..." -ForegroundColor Cyan
Write-Host "Critical test file: $CriticalTestFile" -ForegroundColor DarkCyan
Write-Host "Full test file: $TestFile" -ForegroundColor DarkCyan
if (-not $SkipCompatibility) {
    Write-Host "Compatibility test file: $CompatibilityTestFile" -ForegroundColor DarkCyan
}

Write-Host ""
Write-Host "=== Running critical bootstrap tests ===" -ForegroundColor Yellow
$criticalResult = Invoke-Pester -Path $CriticalTestFile -PassThru

if ($null -eq $criticalResult -or $criticalResult.TotalCount -eq 0) {
    throw "run-end-to-end-failfast.ps1: Critical test run matched zero tests."
}

if ($criticalResult.FailedCount -gt 0) {
    Write-Host "FAILED: Critical bootstrap test(s)" -ForegroundColor Red
    Write-Host "Stopping on first failure (fail-fast)." -ForegroundColor Red
    exit 1
}

Write-Host "PASSED: Critical bootstrap test(s)" -ForegroundColor Green

Write-Host ""
Write-Host "=== Running remaining integration tests ===" -ForegroundColor Yellow
$remainingResult = Invoke-Pester -Path $TestFile -PassThru

if ($null -eq $remainingResult) {
    throw "run-end-to-end-failfast.ps1: Invoke-Pester returned no result for non-critical tests."
}

if ($remainingResult.FailedCount -gt 0) {
    Write-Host "FAILED: Remaining integration tests" -ForegroundColor Red
    exit 1
}

if ($remainingResult.TotalCount -eq 0) {
    Write-Host "No non-critical integration tests matched." -ForegroundColor Yellow
}

if (-not $SkipCompatibility) {
    Write-Host ""
    Write-Host "=== Running compatibility matrix tests ===" -ForegroundColor Yellow
    $compatResult = Invoke-Pester -Path $CompatibilityTestFile -PassThru
    
    if ($null -eq $compatResult -or $compatResult.TotalCount -eq 0) {
        throw "run-end-to-end-failfast.ps1: Compatibility test run matched zero tests."
    }
    
    if ($compatResult.FailedCount -gt 0) {
        Write-Host "FAILED: Compatibility matrix tests" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "PASSED: Compatibility matrix tests" -ForegroundColor Green
}

Write-Host ""
Write-Host "All fail-fast integration tests passed." -ForegroundColor Green
exit 0
