# 生成 Zynq SD 卡启动镜像 BOOT.BIN（FSBL + 比特流 + 应用 ELF）。
#
# 用法（仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File scripts\build_boot_image.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_boot_image.ps1 -CopyTo F:\
#
# 前置产物（缺一不可，三者必须出自同一次构建）：
#   vivado\pqm2_meas.bit                                <- vivado\scripts\build_meas.tcl
#   build\vitis_ws_meas\...\zynq_fsbl.elf               <- 平台自带，create_workspace_meas.tcl 会编译
#   build\vitis_ws_meas\pqm2_app\Debug\pqm2_app.elf     <- scripts\build_app.ps1
#
# 为什么必须配套：应用 ELF 引用的 axi_gpio_0(0x41200000)、clk_wiz_0(0x43C00000)
# 只存在于测量版 BD 里，配别的比特流会全黑屏（只剩背光）。
#
# 组件顺序与旧工程 FPGA\ZYNQ固化脚本\bootbin.bif 一致：
#   [bootloader] zynq_fsbl.elf / 比特流 / 应用 ELF
# bootgen 自己会识别 .bit 与 .elf，所以后两项不写关键字。

param(
    [string]$BootgenPath,
    [string]$CopyTo
)

$ErrorActionPreference = 'Continue'

function Fail($msg) { Write-Host "ERROR: $msg"; exit 1 }

$repo = Split-Path $PSScriptRoot -Parent

function Resolve-Bootgen {
    param([string]$Explicit)
    $candidates = @()
    if ($Explicit) { $candidates += $Explicit }
    if ($env:XILINX_VITIS) { $candidates += (Join-Path $env:XILINX_VITIS 'bin\bootgen.bat') }
    $onPath = Get-Command bootgen.bat -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    $candidates += 'D:\zt\Xilinx\Vitis\2022.2\bin\bootgen.bat'
    $candidates += 'D:\zt\Xilinx\Vivado\2022.2\bin\bootgen.bat'
    $candidates += 'C:\Xilinx\Vitis\2022.2\bin\bootgen.bat'
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    Fail "找不到 bootgen.bat。用 -BootgenPath 指定，或设 XILINX_VITIS。已试过: $($candidates -join '; ')"
}

# 找 FSBL。Vitis 2022.2 的平台会顺带把 FSBL 编出来，但**文件名有 fsbl.elf 与
# zynq_fsbl.elf 两种、位置也有两处**（平台目录 pqm2_hw\zynq_fsbl\ 与导出目录里的
# boot\），所以先按已知位置取（优先平台目录那份），找不到再退化成搜索。
# 实测本工程产出的是 fsbl.elf，不是 zynq_fsbl.elf。
function Find-Fsbl {
    param([string]$Ws)
    $known = @(
        (Join-Path $Ws 'pqm2_hw\zynq_fsbl\fsbl.elf'),
        (Join-Path $Ws 'pqm2_hw\zynq_fsbl\zynq_fsbl.elf'),
        (Join-Path $Ws 'pqm2_hw\export\pqm2_hw\sw\pqm2_hw\boot\zynq_fsbl.elf'),
        (Join-Path $Ws 'pqm2_hw\export\pqm2_hw\sw\pqm2_hw\boot\fsbl.elf')
    )
    foreach ($c in $known) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
    }
    if (-not (Test-Path -LiteralPath $Ws)) { Fail "FSBL：目录不存在 $Ws（先跑 scripts\build_app.ps1）" }
    $hits = @(Get-ChildItem -LiteralPath $Ws -Recurse -Include 'zynq_fsbl.elf','fsbl.elf' -File -ErrorAction SilentlyContinue)
    if ($hits.Count -eq 0) { Fail "FSBL：在 $Ws 下找不到 zynq_fsbl.elf / fsbl.elf（先跑 scripts\build_app.ps1）" }
    Write-Host "FSBL：已知位置都没命中，搜索到 $($hits.Count) 个，取最近修改的那个："
    $hits | ForEach-Object { Write-Host "    $($_.FullName)" }
    return ($hits | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

$bootgen = Resolve-Bootgen -Explicit $BootgenPath
Write-Host "bootgen : $bootgen"

# 1) 比特流：优先仓库根的 vivado\pqm2_meas.bit，退而求 Vitis 工作区里那份
$bitCandidates = @(
    (Join-Path $repo 'vivado\pqm2_meas.bit'),
    (Join-Path $repo 'build\vitis_ws_meas\pqm2_hw\hw\pqm2_meas.bit')
)
$bit = $null
foreach ($c in $bitCandidates) { if (Test-Path -LiteralPath $c -PathType Leaf) { $bit = (Resolve-Path -LiteralPath $c).Path; break } }
if (-not $bit) {
    Fail "找不到 pqm2_meas.bit（试过: $($bitCandidates -join '; ')）。先跑 vivado\scripts\build_meas.tcl"
}

# 2) FSBL：平台自带（见 Find-Fsbl 的说明）
$ws     = Join-Path $repo 'build\vitis_ws_meas'
$fsbl   = Find-Fsbl -Ws $ws

# 3) 应用 ELF
$app = Join-Path $ws 'pqm2_app\Debug\pqm2_app.elf'
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) {
    Fail "找不到应用 ELF: $app（先跑 scripts\build_app.ps1）"
}

foreach ($f in @($bit, $fsbl, $app)) {
    $i = Get-Item -LiteralPath $f
    Write-Host ("  {0,12:N0} B  {1}" -f $i.Length, $f)
}

# 4) 暂存到 export\boot\，文件名固定，.bif 里就只写裸文件名 —— 不依赖 bootgen 对相对/绝对路径的处理
$stage = Join-Path $repo 'export\boot'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath $fsbl -Destination (Join-Path $stage 'zynq_fsbl.elf') -Force
Copy-Item -LiteralPath $bit  -Destination (Join-Path $stage 'pqm2_meas.bit') -Force
Copy-Item -LiteralPath $app  -Destination (Join-Path $stage 'pqm2_app.elf')  -Force

$bif = Join-Path $stage 'bootbin.bif'
$bifText = @'
the_ROM_image:
{
 [bootloader] zynq_fsbl.elf
 pqm2_meas.bit
 pqm2_app.elf
}
'@
[System.IO.File]::WriteAllText($bif, $bifText, (New-Object System.Text.UTF8Encoding($false)))

$out = Join-Path $stage 'BOOT.BIN'
Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue

Write-Host "`n=== bootgen ==="
$old = Get-Location
Set-Location $stage
$log = & $bootgen -image bootbin.bif -arch zynq -o BOOT.BIN -w on 2>&1
$code = $LASTEXITCODE
Set-Location $old
$log | ForEach-Object { Write-Host "  $_" }

if ($code -ne 0 -or -not (Test-Path -LiteralPath $out)) { Fail "bootgen 失败（exit $code）" }

$info = Get-Item -LiteralPath $out
$hash = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash
Write-Host ("`nBOOT.BIN : {0}  {1:N0} B  SHA256 {2}" -f $info.FullName, $info.Length, $hash)

# 5) 可选：拷到目标（例如 SD 卡 F:\），先备份同名旧文件
if ($CopyTo) {
    if (-not (Test-Path -LiteralPath $CopyTo)) { Fail "目标不存在: $CopyTo" }
    $dest = Join-Path $CopyTo 'BOOT.BIN'
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
        $stamp = (Get-Item -LiteralPath $dest).LastWriteTime.ToString('yyyyMMdd-HHmmss')
        $backup = Join-Path $stage "BOOT.BIN.bak-$stamp"
        Copy-Item -LiteralPath $dest -Destination $backup -Force
        Write-Host "已备份旧文件 -> $backup"
    }
    Copy-Item -LiteralPath $out -Destination $dest -Force
    $dstHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
    Write-Host ("已写入 {0}  {1:N0} B  SHA256 {2}" -f $dest, (Get-Item -LiteralPath $dest).Length, $dstHash)
    if ($dstHash -ne $hash) { Fail "写入后校验不一致" }
    Write-Host "校验一致。"
}

Write-Host "done"
