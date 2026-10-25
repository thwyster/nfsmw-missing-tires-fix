param([Parameter(Mandatory)] [string]$GameDir)
$ErrorActionPreference = 'Stop'
$global = Join-Path $GameDir 'GLOBAL'
$restored = 0
foreach ($bak in Get-ChildItem $global -Filter '*.tiresfix.bak') {
    $orig = $bak.FullName -replace '\.tiresfix\.bak$', ''
    Copy-Item $bak.FullName $orig -Force
    Remove-Item $bak.FullName
    "Restored $orig"
    $restored++
}
if ($restored -eq 0) { "No backup found; nothing to restore." }
