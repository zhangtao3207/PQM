# ============================================================================
# 解析 scripts/flash_meas.tcl 用 JTAG 抓下来的共享内存（每行 "字索引 十六进制值"），
# 按 ABI 打印出来。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\report_shm.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\report_shm.ps1 -Words <f1> [-Words2 <f2>]
#
# ABI（与 pl/rtl/PSInterface/pqm_shared_memory_map.vh 一致）：
#   word 0x00..0x05 头；0x10..0x1D 标量快照（工程量 x100）；
#   0x1E 告警；0x1F 有效位；0x80..0x84 命令/响应；
#   0xA0 丢样本计数；0x400 / 0xC00 两个谐波 bank，各 64 条 x 4 字。
# ============================================================================
param(
    [string]$Words  = "C:\Users\zhangtao\Desktop\PQM2\export\shm_words_1.txt",
    [string]$Words2 = "C:\Users\zhangtao\Desktop\PQM2\export\shm_words_2.txt"
)

function Read-Words([string]$path) {
    if (-not (Test-Path $path)) { throw "找不到抓取文件: $path" }
    $w = New-Object 'uint32[]' 16384
    $seen = 0
    foreach ($line in (Get-Content -LiteralPath $path)) {
        $line = $line.Trim()
        if ($line -eq "") { continue }
        $p = $line -split '\s+'
        if ($p.Count -lt 2) { continue }
        $idx = [int]$p[0]
        $w[$idx] = [Convert]::ToUInt32($p[1], 16)
        $seen++
    }
    Write-Host ("  （读入 {0} 个字：{1}）" -f $seen, $path)
    return $w
}
function As-Signed([uint32]$v) { if ($v -ge 2147483648) { return ([int64]$v - 4294967296) } return [int64]$v }
function Fmt-X100([int64]$v) {
    # 注意：PowerShell 的 [int] 是"四舍六入五成双"，对 49.9 会得到 50，
    # 直接把 4990（=49.90）印成 50.90。这里必须显式向下取整。
    $neg = $v -lt 0
    $a = [Math]::Abs($v)
    $whole = [Math]::Floor($a / 100)
    $frac = $a % 100
    $s = "{0}.{1:d2}" -f [int64]$whole, [int64]$frac
    if ($neg) { return "-$s" } else { return $s }
}

Write-Host "==== PS/PL 共享内存实测（JTAG 抓取）===="
$w1 = Read-Words $Words

$magic = $w1[0x00]; $abi = $w1[0x01]; $status = $w1[0x02]
$snapseq = $w1[0x03]; $harmgen = $w1[0x04]; $caps = $w1[0x05]
Write-Host ""
Write-Host "---- 头部 ----"
Write-Host ("  magic      word0x00 = 0x{0:X8}  ({1})" -f $magic, $(if ($magic -eq 0x50514D31) { "PQM1 正确" } else { "不符，期望 0x50514D31" }))
Write-Host ("  abi        word0x01 = 0x{0:X8}  ({1})" -f $abi, $(if (($abi -band 0xFFFF0000) -eq 0x00010000) { "v1.x 正确" } else { "不符，期望 0x00010000" }))
Write-Host ("  status     word0x02 = 0x{0:X8}  snap_valid={1} bank={2} harm_valid={3}" -f $status, ($status -band 1), (($status -shr 1) -band 1), (($status -shr 2) -band 1))
Write-Host ("  snap_seq   word0x03 = {0}" -f $snapseq)
Write-Host ("  harm_gen   word0x04 = {0}" -f $harmgen)
Write-Host ("  caps       word0x05 = 0x{0:X8}" -f $caps)
Write-Host ("  drop_count word0xA0 = {0}" -f $w1[0xA0])
Write-Host ("  cmd req/arg/seq     = 0x{0:X8} / {1} / {2}" -f $w1[0x80], $w1[0x81], $w1[0x82])
Write-Host ("  cmd resp/resp_seq   = 0x{0:X8} / {1}" -f $w1[0x83], $w1[0x84])

$valid = $w1[0x1F]
$alarm = $w1[0x1E]
Write-Host ""
Write-Host "---- 标量快照（word 0x10..0x1D，工程量 x100）----"
$names = @(
    @{ n = "Frequency        Hz"; w = 0x14; b = 0x020 },
    @{ n = "U RMS             V"; w = 0x10; b = 0x001 },
    @{ n = "I RMS             A"; w = 0x11; b = 0x001 },
    @{ n = "U P-P             V"; w = 0x12; b = 0x004 },
    @{ n = "I P-P             A"; w = 0x13; b = 0x008 },
    @{ n = "Phase           deg"; w = 0x15; b = 0x010 },
    @{ n = "Active P          W"; w = 0x16; b = 0x040 },
    @{ n = "Reactive Q      var"; w = 0x17; b = 0x040 },
    @{ n = "Apparent S       VA"; w = 0x18; b = 0x040 },
    @{ n = "Power factor       "; w = 0x19; b = 0x040 },
    @{ n = "THD-U             %"; w = 0x1A; b = 0x080 },
    @{ n = "THD-I             %"; w = 0x1B; b = 0x100 },
    @{ n = "DC-U              %"; w = 0x1C; b = 0x200 },
    @{ n = "DC-I              %"; w = 0x1D; b = 0x400 }
)
foreach ($e in $names) {
    $raw = As-Signed $w1[$e.w]
    $ok = if (($valid -band $e.b) -ne 0) { "OK " } else { "-- " }
    Write-Host ("  [{0}] {1} = {2}   (raw {3})" -f $ok, $e.n, (Fmt-X100 $raw), $raw)
}
Write-Host ("  validity word0x1F = 0x{0:X8} ; alarm word0x1E = 0x{1:X8} (bit0 alarm_active={2})" -f $valid, $alarm, ($alarm -band 1))

foreach ($bank in @( @{ i = 0; base = 0x400 }, @{ i = 1; base = 0xC00 } )) {
    $base = $bank.base
    $present = 0
    Write-Host ""
    Write-Host ("---- 谐波 bank{0}（word 0x{1:X} 起，每条 4 字：U 占比 / I 占比 / phase / flags）----" -f $bank.i, $base)
    Write-Host "  idx |   U %   |   I %   | phase deg | flags"
    for ($k = 0; $k -lt 64; $k++) {
        $o = $base + 4 * $k
        $u = $w1[$o] -band 0xFFFF
        $i = $w1[$o + 1] -band 0xFFFF
        $p = As-Signed $w1[$o + 2]
        $f = $w1[$o + 3] -band 0xFF
        if (($f -band 1) -ne 0) { $present++ }
        Write-Host ("  {0,3} | {1,7} | {2,7} | {3,9} | 0x{4:X2}" -f $k, (Fmt-X100 $u), (Fmt-X100 $i), (Fmt-X100 $p), $f)
    }
    Write-Host ("  bank{0}: 64 条中 present(flags bit0)=1 的有 {1} 条" -f $bank.i, $present)
}

if (Test-Path $Words2) {
    $w2 = Read-Words $Words2
    Write-Host ""
    Write-Host "==== 与第二次抓取对比（间隔约 1 秒，确认读到的是活数据）===="
    Write-Host ("  snap_seq : {0}  ->  {1}" -f $w1[0x03], $w2[0x03])
    Write-Host ("  harm_gen : {0}  ->  {1}" -f $w1[0x04], $w2[0x04])
    Write-Host ("  status   : 0x{0:X8} -> 0x{1:X8}" -f $w1[0x02], $w2[0x02])
    if ($w1[0x03] -eq $w2[0x03] -and $w1[0x04] -eq $w2[0x04]) {
        Write-Host "  注意：两次计数器都没变——数据没有在推进，需检查 PL 测量链是否真的在跑。"
    } else {
        Write-Host "  计数器在推进：读取的是运行时数据。"
    }
} else {
    Write-Host ""
    Write-Host "（未找到第二次抓取，跳过推进性检查：$Words2）"
}
