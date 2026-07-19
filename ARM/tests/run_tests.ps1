$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$gcc = 'D:/zt/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'
$buildDir = Join-Path $repoRoot 'ARM/test_build'
$driverDir = Join-Path $repoRoot 'ARM/app/src/drivers/pqm_axi'
$touchDir = Join-Path $repoRoot 'ARM/app/src/drivers/pqm_touch'
$waveformDir = Join-Path $repoRoot 'ARM/app/src/services/waveform'
$measurementDir = Join-Path $repoRoot 'ARM/app/src/services/measurement'

if (-not (Test-Path -LiteralPath $gcc)) {
    throw "MinGW GCC not found: $gcc"
}

$env:PATH = "$(Split-Path -Parent $gcc);$env:PATH"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

function Invoke-NativeTest {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [string]$IncludeDirectory,
        [Parameter(Mandatory = $true)] [string[]]$Sources
    )

    $testBinary = Join-Path $buildDir "$Name.exe"
    & $gcc -std=c11 -Wall -Wextra -Werror -I $IncludeDirectory $Sources -o $testBinary
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to compile $Name host tests"
    }

    & $testBinary
    if ($LASTEXITCODE -ne 0) {
        throw "$Name host tests failed"
    }
}

Invoke-NativeTest -Name 'test_pqm_axi' -IncludeDirectory $driverDir -Sources @(
    (Join-Path $repoRoot 'ARM/tests/test_pqm_axi.c'),
    (Join-Path $driverDir 'pqm_axi.c')
)
Invoke-NativeTest -Name 'test_pqm_waveform' -IncludeDirectory $waveformDir -Sources @(
    (Join-Path $repoRoot 'ARM/tests/test_pqm_waveform.c'),
    (Join-Path $waveformDir 'pqm_waveform.c')
)
Invoke-NativeTest -Name 'test_pqm_touch' -IncludeDirectory $touchDir -Sources @(
    (Join-Path $repoRoot 'ARM/tests/test_pqm_touch.c'),
    (Join-Path $touchDir 'pqm_touch_protocol.c')
)
Invoke-NativeTest -Name 'test_pqm_measurement' -IncludeDirectory $measurementDir -Sources @(
    (Join-Path $repoRoot 'ARM/tests/test_pqm_measurement.c'),
    (Join-Path $measurementDir 'pqm_measurement.c')
)
