# 把旧工程 Vivado 生成的 COE 转成 $readmemh 能直接读的 .mem（每行一个十六进制数）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File pl\scripts\coe_to_mem.ps1 `
#       -Coe <输入.coe> -Mem <输出.mem> [-HexWidth 4]
#
# 只处理 memory_initialization_radix=10 或 16 的 COE；COE 里的注释行（以 ; 开头）
# 与 memory_initialization_vector= 行会被跳过。

param(
    [Parameter(Mandatory = $true)][string]$Coe,
    [Parameter(Mandatory = $true)][string]$Mem,
    [int]$HexWidth = 4
)

$text = Get-Content -LiteralPath $Coe

$radix = 10
foreach ($line in $text) {
    if ($line -match '^\s*memory_initialization_radix\s*=\s*(\d+)') {
        $radix = [int]$Matches[1]
    }
}

$values = New-Object System.Collections.Generic.List[long]
foreach ($line in $text) {
    $t = $line.Trim()
    if ($t.StartsWith(';') -or $t.StartsWith('//') -or $t -eq '') { continue }
    if ($t -match 'memory_initialization_vector') { continue }
    if ($t -match 'memory_initialization_radix') { continue }
    $t = $t.TrimEnd(',').TrimEnd(';')
    if ($t -eq '') { continue }
    if ($radix -eq 10) {
        if ($t -notmatch '^\d+$') { throw "无法解析的十进制数据行：$line" }
        $values.Add([long]$t)
    } else {
        if ($t -notmatch '^[0-9a-fA-F]+$') { throw "无法解析的十六进制数据行：$line" }
        $values.Add([System.Convert]::ToInt64($t, 16))
    }
}

if ($values.Count -eq 0) { throw "COE 里没有解析到任何数据：$Coe" }

$format = '{0:x' + $HexWidth + '}'
$out = New-Object System.Collections.Generic.List[string]
foreach ($v in $values) { $out.Add(($format -f $v)) }

Set-Content -LiteralPath $Mem -Value $out -Encoding ASCII
Write-Host ("已写出 {0} 个 {1} 位十六进制数 -> {2}" -f $values.Count, ($HexWidth * 4), $Mem)
