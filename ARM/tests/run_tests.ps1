$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$gcc = 'D:/zt/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe'
$buildDir = Join-Path $repoRoot 'ARM/test_build'
$driverDir = Join-Path $repoRoot 'ARM/app/src/drivers/pqm_axi'
$testSource = Join-Path $repoRoot 'ARM/tests/test_pqm_axi.c'
$driverSource = Join-Path $driverDir 'pqm_axi.c'
$testBinary = Join-Path $buildDir 'test_pqm_axi.exe'

if (-not (Test-Path -LiteralPath $gcc)) {
    throw "MinGW GCC not found: $gcc"
}

$env:PATH = "$(Split-Path -Parent $gcc);$env:PATH"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

& $gcc -std=c11 -Wall -Wextra -Werror -I $driverDir $testSource $driverSource -o $testBinary
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to compile pqm_axi host tests'
}

& $testBinary
if ($LASTEXITCODE -ne 0) {
    throw 'pqm_axi host tests failed'
}
