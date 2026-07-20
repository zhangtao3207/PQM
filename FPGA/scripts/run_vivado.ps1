param(
    [Parameter(Mandatory = $true)]
    [string]$Script
)

$ErrorActionPreference = 'Stop'
$vivado = 'D:/zt/Xilinx/Vivado/2018.3/bin/vivado.bat'

if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado 2018.3 not found: $vivado"
}

if (-not (Test-Path -LiteralPath $Script)) {
    throw "Tcl script not found: $Script"
}

$resolvedScript = (Resolve-Path -LiteralPath $Script).Path
if (-not $env:PQM_REPO_ROOT) {
    $env:PQM_REPO_ROOT = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
}
if (-not $env:HOME) {
    $env:HOME = $env:USERPROFILE
}
& $vivado -mode batch -nojournal -nolog -source $resolvedScript
exit $LASTEXITCODE
