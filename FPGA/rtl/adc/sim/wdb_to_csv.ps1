param(
    [string]$WdbPath = "C:\Users\zhangtao\Desktop\PQM\FPGA\prj\PQM.sim\sim_1\behav\xsim\ADC_DRIVER_TB_behav.wdb",
    [string]$CsvPath = "C:\Users\zhangtao\Desktop\PQM\FPGA\rtl\adc\sim\sim_all.csv",
    [string]$Snapshot = "",
    [string]$Scope = "/ADC_DRIVER_TB",
    [string]$Step = "10ns"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $WdbPath)) {
    throw "WDB not found: $WdbPath"
}

if ([string]::IsNullOrWhiteSpace($Snapshot)) {
    $Snapshot = [System.IO.Path]::GetFileNameWithoutExtension($WdbPath)
}

$xsimDir = Split-Path -Parent $WdbPath
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tclPath = Join-Path $scriptDir "wdb_to_csv.tcl"

if (-not (Test-Path -LiteralPath $tclPath)) {
    throw "Tcl script not found: $tclPath"
}

$xsimBat = "D:\zt\Xilinx\Vivado\2018.3\bin\xsim.bat"
if (-not (Test-Path -LiteralPath $xsimBat)) {
    if ($env:XILINX_VIVADO) {
        $candidate = Join-Path $env:XILINX_VIVADO "bin\xsim.bat"
        if (Test-Path -LiteralPath $candidate) {
            $xsimBat = $candidate
        }
        else {
            throw "xsim.bat not found at $candidate"
        }
    }
    else {
        throw "xsim.bat not found and XILINX_VIVADO is not set."
    }
}

$env:CSV_OUT = $CsvPath
$env:CSV_SCOPE = $Scope
$env:CSV_STEP = $Step

$tclPathForXsim = ((Resolve-Path -LiteralPath $tclPath).Path) -replace '\\','/'
$csvPathForCheck = $CsvPath

Push-Location $xsimDir
try {
    if (Test-Path -LiteralPath $csvPathForCheck) {
        Remove-Item -LiteralPath $csvPathForCheck -Force
    }

    & $xsimBat $Snapshot -tclbatch $tclPathForXsim -log "wdb_to_csv.log"
    if ($LASTEXITCODE -ne 0) {
        throw "xsim export failed, see $xsimDir\\wdb_to_csv.log"
    }
    if (-not (Test-Path -LiteralPath $csvPathForCheck)) {
        throw "xsim finished but CSV was not generated."
    }
}
finally {
    Pop-Location
    Remove-Item Env:CSV_OUT -ErrorAction SilentlyContinue
    Remove-Item Env:CSV_SCOPE -ErrorAction SilentlyContinue
    Remove-Item Env:CSV_STEP -ErrorAction SilentlyContinue
}

Write-Host "CSV written to: $CsvPath"
