$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$xsctRunner = Join-Path $PSScriptRoot 'run_xsct.ps1'
$fsblScript = Join-Path $PSScriptRoot 'build_boot_image.tcl'
$bootgen = 'D:/zt/Xilinx/SDK/2018.3/bin/bootgen.bat'
$bifFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'FPGA') `
    -Recurse -Filter 'bootbin.bif')
if ($bifFiles.Count -ne 1) {
    throw "Expected one bootbin.bif under FPGA, found $($bifFiles.Count)"
}
$bifFile = $bifFiles[0].FullName
$outputDir = $bifFiles[0].DirectoryName
$bootFile = Join-Path $outputDir 'BOOT.bin'

foreach ($required in @($xsctRunner, $fsblScript, $bootgen, $bifFile,
        (Join-Path $repoRoot 'FPGA/export/pqm_soc.bit'),
        (Join-Path $repoRoot 'ARM/sdk_workspace/pqm_freertos/Release/pqm_freertos.elf'))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required boot input not found: $required"
    }
}

& $xsctRunner -Script $fsblScript
if ($LASTEXITCODE -ne 0) {
    throw 'FSBL build failed.'
}

Push-Location $outputDir
try {
    & $bootgen -image 'bootbin.bif' -arch zynq -o 'BOOT.bin' -w on
    if ($LASTEXITCODE -ne 0) {
        throw 'Bootgen failed.'
    }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $bootFile)) {
    throw "BOOT.bin was not produced: $bootFile"
}
Write-Host "Built PQM boot image: $bootFile"
