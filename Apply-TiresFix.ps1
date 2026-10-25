param(
    [Parameter(Mandatory)] [string]$GameDir,
    [Parameter(Mandatory)] [string]$UnlimiterTexturesDir
)
$ErrorActionPreference = 'Stop'
$global = Join-Path $GameDir 'GLOBAL'
$lzc = Get-ChildItem $global -Filter 'GLOBALB.LZC' | Select-Object -First 1
if (-not $lzc) { throw "GLOBAL\GLOBALB.LZC not found in '$GameDir'" }
foreach ($t in 'TIRE_STYLE01.dds', 'TIRE_STYLE01_N.dds') {
    if (-not (Test-Path (Join-Path $UnlimiterTexturesDir $t))) { throw "$t not found in '$UnlimiterTexturesDir'" }
}
$bun = Join-Path $global 'GLOBALB.BUN'
$bak = "$($lzc.FullName).tiresfix.bak"
if (Test-Path $bak) { throw "Backup already exists ($bak). The fix looks applied already; run Restore-TiresFix.ps1 first." }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tiresfix_" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $p = @{ GlobalLzc = $lzc.FullName; DdsDir = $UnlimiterTexturesDir; OutLzc = (Join-Path $tmp 'GLOBALB.LZC') }
    if (Test-Path $bun) { $p.OutBun = Join-Path $tmp 'GLOBALB.BUN' }
    & (Join-Path $PSScriptRoot 'InjectTiresV2.ps1') @p

    Copy-Item $lzc.FullName $bak
    if (Test-Path $bun) { Copy-Item $bun "$bun.tiresfix.bak" }
    Copy-Item (Join-Path $tmp 'GLOBALB.LZC') $lzc.FullName -Force
    if (Test-Path $bun) { Copy-Item (Join-Path $tmp 'GLOBALB.BUN') $bun -Force }
    "Done. Backup: $bak"
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
