param(
    [string]$TimingReport,
    [string]$UtilizationReport,
    [string]$HierarchyReport
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

if (-not $TimingReport) {
    $TimingReport = Join-Path $repoRoot 'FPGA/export/reports/timing_summary.rpt'
}
if (-not $UtilizationReport) {
    $UtilizationReport = Join-Path $repoRoot 'FPGA/export/reports/utilization_placed.rpt'
}
if (-not $HierarchyReport) {
    $HierarchyReport = Join-Path $repoRoot 'FPGA/export/reports/utilization_hierarchical.rpt'
}
foreach ($report in @($TimingReport, $UtilizationReport, $HierarchyReport)) {
    if (-not (Test-Path -LiteralPath $report)) {
        throw "Required report not found: $report"
    }
}

$timingText = Get-Content -Raw -LiteralPath $TimingReport
$timingMatch = [regex]::Match(
    $timingText,
    '(?ms)WNS\(ns\).*?\r?\n\s*-+.*?\r?\n\s*(?<wns>-?\d+(?:\.\d+)?)')
if (-not $timingMatch.Success) {
    throw "Unable to parse WNS from $TimingReport"
}
$wns = [double]::Parse(
    $timingMatch.Groups['wns'].Value,
    [Globalization.CultureInfo]::InvariantCulture)

$utilizationText = Get-Content -Raw -LiteralPath $UtilizationReport
$lutMatch = [regex]::Match(
    $utilizationText,
    '(?m)^\|\s*Slice LUTs\s*\|\s*(?<used>\d+)\s*\|.*\|\s*(?<percent>\d+(?:\.\d+)?)\s*\|')
if (-not $lutMatch.Success) {
    throw "Unable to parse Slice LUT utilization from $UtilizationReport"
}
$lutUsed = [int]$lutMatch.Groups['used'].Value
$lutPercent = [double]::Parse(
    $lutMatch.Groups['percent'].Value,
    [Globalization.CultureInfo]::InvariantCulture)

Write-Host ("PQM routed report: WNS={0:F3} ns, LUT={1} ({2:F2}%)" -f `
    $wns, $lutUsed, $lutPercent)
if ($wns -lt 0.0) {
    throw ("Timing gate failed: WNS {0:F3} ns is negative" -f $wns)
}
if ($lutPercent -ge 55.0) {
    throw ("Resource gate failed: LUT utilization {0:F2}% is not below 55%" -f `
        $lutPercent)
}

$hierarchyText = Get-Content -Raw -LiteralPath $HierarchyReport
$obsoleteHierarchy = @(
    'pqm_legacy_core',
    'g_legacy_measurement_display',
    'g_legacy_interfaces',
    'u_lcd_display',
    'u_touch_top',
    'u_uart_measurement_streamer'
)
foreach ($name in $obsoleteHierarchy) {
    if ($hierarchyText -match [regex]::Escape($name)) {
        throw "Default PS hierarchy still contains obsolete instance: $name"
    }
}

Write-Host 'PQM_SOC_REPORT_CHECK_PASS'
