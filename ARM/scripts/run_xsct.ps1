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
& $xsct $resolvedScript
exit $LASTEXITCODE
