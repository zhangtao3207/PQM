param(
    [Parameter(Mandatory = $true)]
    [string]$Script
)

$ErrorActionPreference = 'Stop'
$xsct = 'D:/zt/Xilinx/SDK/2018.3/bin/xsct.bat'

if (-not (Test-Path -LiteralPath $xsct)) {
    throw "Xilinx SDK 2018.3 XSCT not found: $xsct"
}

if (-not (Test-Path -LiteralPath $Script)) {
    throw "Tcl script not found: $Script"
}

$resolvedScript = (Resolve-Path -LiteralPath $Script).Path
$env:PQM_REPO_ROOT = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = & $xsct $resolvedScript 2>&1
$exitCode = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }
if ($exitCode -ne 0 -or (($output -join "`n") -match '(?m)^\s+while executing\s*$')) {
    throw "XSCT script failed: $resolvedScript"
}
