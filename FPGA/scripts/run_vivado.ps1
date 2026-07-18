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
& $vivado -mode batch -nojournal -nolog -source $resolvedScript
exit $LASTEXITCODE
