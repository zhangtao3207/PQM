param(
    [string]$Test,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$xilinxBin = 'D:/zt/Xilinx/Vivado/2018.3/bin'
$xvlog = Join-Path $xilinxBin 'xvlog.bat'
$xelab = Join-Path $xilinxBin 'xelab.bat'
$xsim = Join-Path $xilinxBin 'xsim.bat'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$simRoot = Join-Path $repoRoot 'FPGA/sim/PSInterface'
$rtlRoot = Join-Path $repoRoot 'FPGA/rtl/PSInterface'
$buildRoot = Join-Path $repoRoot 'FPGA/sim/build'

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado simulator tool not found: $tool"
    }
}

if ($All) {
    if (-not (Test-Path -LiteralPath $simRoot)) {
        throw "No PS interface tests found: $simRoot"
    }
    $tests = Get-ChildItem -LiteralPath $simRoot -Filter 'tb_*.v' |
        ForEach-Object { $_.BaseName.Substring(3) }
    if (-not $tests) {
        throw "No PS interface tests found: $simRoot"
    }
} elseif ($Test) {
    $tests = @($Test)
} else {
    throw 'Specify -Test <module> or -All'
}

foreach ($name in $tests) {
    $testbench = Join-Path $simRoot "tb_$name.v"
    $dut = Join-Path $rtlRoot "$name.v"
    if (-not (Test-Path -LiteralPath $testbench)) {
        throw "Testbench not found: $testbench"
    }
    if (-not (Test-Path -LiteralPath $dut)) {
        throw "DUT not found: $dut"
    }

    $buildDir = Join-Path $buildRoot $name
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

    Push-Location $buildDir
    try {
        & $xvlog -work xil_defaultlib $dut $testbench
        if ($LASTEXITCODE -ne 0) { throw "xvlog failed for $name" }

        $snapshot = "sim_$name"
        & $xelab "xil_defaultlib.tb_$name" -s $snapshot --debug typical
        if ($LASTEXITCODE -ne 0) { throw "xelab failed for $name" }

        & $xsim $snapshot -runall
        if ($LASTEXITCODE -ne 0) { throw "xsim failed for $name" }
    } finally {
        Pop-Location
    }
}
