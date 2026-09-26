# 用 Vivado 自带的 xsim 跑 PQM2 的 PL 单元仿真。
#
# 用法（在仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All
#   powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -Test pqm_shared_memory_bridge
#   powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All -Debug
#
# 约定：testbench 放 pl/sim/<组>/tb_<模块>.v，被测模块放 pl/rtl/<组>/<模块>.v，两处组名一致。
# 生成物落在 pl/sim/build/（已 gitignore），日志落在 export/xsim_<模块>.log。
#
# 注意：不要用 $ErrorActionPreference='Stop' 包住原生命令——仿真器往 stderr 写一行
# 告警就会让 PowerShell 抛 NativeCommandError。这里显式收 stderr 再判退出码。

param(
    [string]$Test,
    [switch]$All,
    [switch]$Debug
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$simRoot  = Join-Path $repoRoot 'pl\sim'
$rtlRoot  = Join-Path $repoRoot 'pl\rtl'
$buildRoot = Join-Path $simRoot 'build'
$logRoot  = Join-Path $repoRoot 'export'

function Resolve-VivadoBin {
    $candidates = @()
    if ($env:XILINX_VIVADO) { $candidates += (Join-Path $env:XILINX_VIVADO 'bin') }
    $onPath = Get-Command xvlog.bat -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += (Split-Path $onPath.Source -Parent) }
    $candidates += 'D:\zt\Xilinx\Vivado\2022.2\bin'
    $candidates += 'D:\Xilinx\Vivado\2022.2\bin'
    $candidates += 'C:\Xilinx\Vivado\2022.2\bin'
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'xvlog.bat'))) { return $c }
    }
    throw "Vivado xsim not found. Set XILINX_VIVADO or add xvlog.bat to PATH. Tried: $($candidates -join '; ')"
}

function Invoke-Tool {
    param([string]$Name, [string[]]$Arguments, [string]$LogPath)
    $exe = Join-Path $vivadoBin "$Name.bat"
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $exe @Arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    Add-Content -LiteralPath $LogPath -Value $output
    if ($code -ne 0) {
        throw "$Name failed (exit $code); full output in $LogPath"
    }
}

$vivadoBin = Resolve-VivadoBin
Write-Host "xsim : $vivadoBin"

# 收集要跑的用例：tb_<模块>.v 的 <模块> 就是用例名，并在同名的 rtl 组目录下找被测模块。
if ($All) {
    $tests = Get-ChildItem -Path $simRoot -Recurse -Filter 'tb_*.v' -File |
        ForEach-Object { [pscustomobject]@{ Name = $_.BaseName.Substring(3); Group = $_.Directory.Name } }
} elseif ($Test) {
    $tb = Get-ChildItem -Path $simRoot -Recurse -Filter "tb_$Test.v" -File | Select-Object -First 1
    if (-not $tb) { throw "Testbench not found: pl/sim/**/tb_$Test.v" }
    $tests = @([pscustomobject]@{ Name = $Test; Group = $tb.Directory.Name })
} else {
    throw 'Specify -Test <module> or -All'
}

if (-not $tests) { throw "No testbenches found under $simRoot" }

New-Item -ItemType Directory -Force -Path $buildRoot, $logRoot | Out-Null

$failures = 0
foreach ($t in $tests) {
    $name = $t.Name
    $group = $t.Group
    $testbench = Join-Path $simRoot (Join-Path $group "tb_$name.v")
    $dut = Join-Path $rtlRoot (Join-Path $group "$name.v")
    $incDir = Join-Path $rtlRoot $group
    $buildDir = Join-Path $buildRoot $name
    $logPath = Join-Path $logRoot "xsim_$name.log"

    Write-Host ""
    Write-Host "=== $name ($group) ==="

    if (-not (Test-Path -LiteralPath $dut)) {
        Write-Host "SKIP: 被测模块不存在 $dut"
        continue
    }

    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    Set-Content -LiteralPath $logPath -Value "=== xsim $name ===" -Encoding UTF8

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location $buildDir
    try {
        Invoke-Tool 'xvlog' @('-work', 'xil_defaultlib', '-i', $incDir, $dut, $testbench) $logPath
        $elabArgs = @("xil_defaultlib.tb_$name", '-s', "sim_$name")
        if ($Debug) { $elabArgs += @('--debug', 'typical') }
        Invoke-Tool 'xelab' $elabArgs $logPath
        Invoke-Tool 'xsim' @("sim_$name", '-runall') $logPath
        $watch.Stop()
        Write-Host ("PASS  {0:N1} 秒   日志 {1}" -f $watch.Elapsed.TotalSeconds, $logPath)
    } catch {
        $watch.Stop()
        $failures++
        Write-Host ("FAIL  {0:N1} 秒   {1}" -f $watch.Elapsed.TotalSeconds, $_.Exception.Message)
        $tail = Get-Content -LiteralPath $logPath -Tail 15 -ErrorAction SilentlyContinue
        $tail | ForEach-Object { Write-Host "    $_" }
    } finally {
        Pop-Location
    }
}

Write-Host ""
if ($failures -ne 0) {
    throw "$failures 个用例失败"
}
Write-Host "全部用例通过"
