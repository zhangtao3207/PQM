# 调用 XSCT 生成并编译 PQM2 应用。
#
# 用法（在仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File scripts\build_app.ps1
#
# 注意：不要用 $ErrorActionPreference='Stop' 包住原生命令。XSCT 里的编译器
# 只要往 stderr 写一行告警，PowerShell 就会抛 NativeCommandError 并中止，
# 看起来像"构建什么都没做"。这里显式把 stderr 并进 stdout 再判断退出码。

param(
    [string]$XsctPath
)

function Resolve-Xsct {
    $candidates = @()
    if ($XsctPath) { $candidates += $XsctPath }
    if ($env:XILINX_VITIS) { $candidates += (Join-Path $env:XILINX_VITIS 'bin\xsct.bat') }
    $onPath = Get-Command xsct.bat -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    $candidates += 'D:\zt\Xilinx\Vitis\2022.2\bin\xsct.bat'
    $candidates += 'D:\Xilinx\Vitis\2022.2\bin\xsct.bat'
    $candidates += 'C:\Xilinx\Vitis\2022.2\bin\xsct.bat'
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "XSCT 2022.2 not found. Pass -XsctPath or set XILINX_VITIS. Tried: $($candidates -join '; ')"
}

$xsct = Resolve-Xsct
$script = Join-Path $PSScriptRoot 'create_workspace.tcl'
if (-not (Test-Path -LiteralPath $script)) {
    throw "Tcl script not found: $script"
}

Write-Host "XSCT : $xsct"
Write-Host "脚本 : $script"

$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = & $xsct $script 2>&1
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previous

$output | ForEach-Object { Write-Host $_ }

if ($exitCode -ne 0 -or (($output -join "`n") -match '(?m)^\s+while executing\s*$') -or
    (($output -join "`n") -match 'ERROR ')) {
    throw "XSCT script failed: $script (exit $exitCode)"
}

$elf = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\vitis_ws\pqm2_app\Debug\pqm2_app.elf'
if (-not (Test-Path -LiteralPath $elf)) {
    throw "ELF not produced: $elf"
}
$info = Get-Item -LiteralPath $elf
Write-Host ("ELF  : {0}  {1} B  {2}" -f $info.FullName, $info.Length, $info.LastWriteTime)
