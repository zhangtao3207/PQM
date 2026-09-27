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
$modelRoot = Join-Path $simRoot 'models'
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
    $tests = Get-ChildItem -Path $simRoot -Recurse -File -Include 'tb_*.v', 'tb_*.sv' |
        ForEach-Object { [pscustomobject]@{ Name = $_.BaseName.Substring(3); Group = $_.Directory.Name } }
} elseif ($Test) {
    $tb = Get-ChildItem -Path $simRoot -Recurse -File -Include "tb_$Test.v", "tb_$Test.sv" |
        Select-Object -First 1
    if (-not $tb) { throw "Testbench not found: pl/sim/**/tb_$Test.v|.sv" }
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
    # testbench 允许是 .v 或 SystemVerilog 的 .sv
    $testbench = Join-Path $simRoot (Join-Path $group "tb_$name.v")
    if (-not (Test-Path -LiteralPath $testbench)) {
        $testbench = Join-Path $simRoot (Join-Path $group "tb_$name.sv")
    }
    # 被测模块允许放在组目录的任意子目录下（DataProcessor 保留了旧工程的分层）
    $groupRoot = Join-Path $rtlRoot $group
    $dut = Get-ChildItem -Path $groupRoot -Recurse -Filter "$name.v" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $buildDir = Join-Path $buildRoot $name
    $logPath = Join-Path $logRoot "xsim_$name.log"

    Write-Host ""
    Write-Host "=== $name ($group) ==="

    # 允许只有 testbench、没有自研 RTL 的用例（例如直接对 IP 仿真模型做的探针用例）：
    # 组名在 pl/rtl 下不存在时，只编模型 + testbench。
    $hasGroupRtl = Test-Path -LiteralPath $groupRoot

    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    Set-Content -LiteralPath $logPath -Value "=== xsim $name ===" -Encoding UTF8

    # 行为级 IP 仿真模型与它们需要的数据文件。
    #   - pl/sim/models/ 下的模型：所有用例都编（递归收集，子目录也算）。
    #     例：rom_atan_lut_1024/ 放真 IP 仿真网表 rom_atan_lut_1024.v、它依赖的
    #     blk_mem_gen_v8_4.v，以及运行时要读的初始化文件 rom_atan_lut_1024.mif。
    #   - 更重的模型（例如 xfft 的加密 VHDL，十几 MB）由用例按需引入：在
    #     pl/sim/<组>/tb_<用例>.models.txt 里逐行写仓库相对目录。
    # .v 走 xvlog，.vhd/.vhdl 走 xvhdl，其余扩展名当作仿真运行时读取的数据文件（$readmemh / $fscanf）复制进 build 目录。
    $modelDirs = @()
    if (Test-Path -LiteralPath $modelRoot) { $modelDirs += $modelRoot }
    $modelManifest = Join-Path $simRoot (Join-Path $group "tb_$name.models.txt")
    if (Test-Path -LiteralPath $modelManifest) {
        foreach ($line in (Get-Content -LiteralPath $modelManifest)) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $d = Join-Path $repoRoot $t
            if (-not (Test-Path -LiteralPath $d)) { throw "模型清单里的目录不存在：$t（来自 $modelManifest）" }
            $modelDirs += $d
        }
    }
    $modelSrcV   = @()
    $modelSrcVhd = @()
    $modelData   = @()
    foreach ($d in $modelDirs) {
        # 注意：这里不能用 -Include。<本脚本由 powershell -File 跑在 Windows PowerShell 5.1 下，
        # 5.1 的 `Get-ChildItem -Path <dir>\* -Recurse -Include` 不会深入子目录
        # （DataProcessor 这种分层目录只会找到根下 1 个文件），且是**静默**少找；
        # 先递归再用 Where-Object 过滤在 5.1 与 7.x 下行为一致。
        $modelSrcV   += @(Get-ChildItem -Path $d -Recurse -File |
            Where-Object { $_.Extension -in @('.v', '.sv') } | ForEach-Object { $_.FullName })
        $modelSrcVhd += @(Get-ChildItem -Path $d -Recurse -File |
            Where-Object { $_.Extension -in @('.vhd', '.vhdl') } | ForEach-Object { $_.FullName })
        $modelData   += @(Get-ChildItem -Path $d -Recurse -File |
            Where-Object { $_.Extension -notin @('.v', '.vhd', '.vhdl', '.sv') } | ForEach-Object { $_.FullName })
    }
    foreach ($f in $modelData) { Copy-Item -LiteralPath $f -Destination $buildDir -Force }


    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location $buildDir
    try {
        # 整组 RTL 一起编（递归）：被测模块可能有子模块，旧工程还保留了分层目录。
        # 依赖 IP 的模块（xfft / rom_atan_lut 等）只做语法分析，不会进到 xelab 的层次里。
        $groupRtl = @()
        if ($hasGroupRtl) {
            # 同上：5.1 下用 -Include 会漏掉子目录，这里改成递归后过滤。
            $groupRtl = @(Get-ChildItem -Path $groupRoot -Recurse -File |
                Where-Object { $_.Extension -in @('.v', '.sv') } |
                ForEach-Object { $_.FullName })
            if (-not $groupRtl) { throw "组内没有 RTL 文件：$groupRoot" }
        }
        $incArgs = @()
        if ($hasGroupRtl) {
            foreach ($d in @($groupRoot) + (Get-ChildItem -Path $groupRoot -Recurse -Directory | ForEach-Object { $_.FullName })) {
                $incArgs += @('-i', $d)
            }
        }
        # VHDL 先编（Xilinx 的 IP 仿真源是加密 VHDL），再编 Verilog，两门语言都落在 xil_defaultlib 里。
        if ($modelSrcVhd.Count -gt 0) {
            Invoke-Tool 'xvhdl' (@('-work', 'xil_defaultlib') + $modelSrcVhd) $logPath
        }
        Invoke-Tool 'xvlog' (@('-sv', '-work', 'xil_defaultlib') + $incArgs + $groupRtl + $modelSrcV + @($testbench)) $logPath
        $elabArgs = @("xil_defaultlib.tb_$name", '-s', "sim_$name", '-L', 'xil_defaultlib')
        if ($Debug) { $elabArgs += @('--debug', 'typical') }
        Invoke-Tool 'xelab' $elabArgs $logPath
        Invoke-Tool 'xsim' @("sim_$name", '-runall') $logPath

        # xsim -runall 即使碰到 $fatal 也返回退出码 0，不能只看退出码。
        # 必须自己看日志：既要没有 FAIL/Fatal，也要确实打印了 PASS: <模块>。
        $logText = Get-Content -LiteralPath $logPath -Raw
        if ($logText -match [regex]::Escape('FAIL:') -or
            $logText -match [regex]::Escape('Fatal:') -or
            $logText -match [regex]::Escape('ERROR:')) {
            throw "日志里出现 FAIL/Fatal/ERROR（xsim 退出码不可靠，故不信它）；详见 $logPath"
        }
        if ($logText -notmatch [regex]::Escape("PASS: $name")) {
            throw "日志里找不到 'PASS: $name'，无法判定通过；详见 $logPath"
        }
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
