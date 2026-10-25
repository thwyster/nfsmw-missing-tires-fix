param(
    [Parameter(Mandatory)] [string]$GlobalLzc,
    [Parameter(Mandatory)] [string]$DdsDir,
    [Parameter(Mandatory)] [string]$OutLzc,
    [string]$OutBun,
    [string]$TargetTpkPath = 'Global\GlobalTextures.tpk',
    [string[]]$Textures = @('TIRE_STYLE01', 'TIRE_STYLE01_N'),
    [int]$ShiftAlign = 0x800
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Jdlz.ps1"
. "$PSScriptRoot\JdlzCompress.ps1"
Add-Type -TypeDefinition @"
public static class BHash3 { public static uint H(string s){ uint h=0xFFFFFFFF; foreach(char c in s){ h = unchecked(h*33 + (uint)c); } return h; } }
"@
function U32([byte[]]$b, [int]$o) { [BitConverter]::ToUInt32($b, $o) }
function I32([byte[]]$b, [int]$o) { [BitConverter]::ToInt32($b, $o) }
function Chunk([int]$id, [byte[]]$payload) { $r = New-Object byte[] (8 + $payload.Length); [BitConverter]::GetBytes($id).CopyTo($r, 0); [BitConverter]::GetBytes([int]$payload.Length).CopyTo($r, 4); $payload.CopyTo($r, 8); ,$r }
function Concat([object[]]$parts) { $ms = New-Object IO.MemoryStream; foreach ($p in $parts) { $ms.Write($p, 0, $p.Length) }; ,$ms.ToArray() }
function Kids([byte[]]$b, [int]$s) { $r = @{}; $len = I32 $b ($s + 4); $q = $s + 8; while ($q -lt $s + 8 + $len) { $id = I32 $b $q; $sz = I32 $b ($q + 4); if ($id -ne 0) { $r[[int]$id] = @($q, $sz) }; $q += 8 + $sz }; $r }
function Slice([byte[]]$b, [int]$from, [int]$len) { $r = New-Object byte[] $len; [Array]::Copy($b, $from, $r, 0, $len); ,$r }

$lzc = [IO.File]::ReadAllBytes($GlobalLzc)
$g = [Jdlz]::Decompress($lzc, 0)

# find the target TPK by the path in its 0x33310001 header
$tpk = -1; $p = 0
while ($p -lt $g.Length - 8) {
    if ((I32 $g $p) -eq 0xB3300000) {
        $k = Kids $g $p; $ip = $k[[int]0xB3310000][0]; $ik = Kids $g $ip
        $h01 = $ik[0x33310001][0] + 8
        $path = [Text.Encoding]::ASCII.GetString($g, $h01 + 0x20, 0x40) -replace '\x00.*', ''
        if ($path -eq $TargetTpkPath) { $tpk = $p; break }
    }
    $p += 8 + (I32 $g ($p + 4))
}
if ($tpk -lt 0) { throw "TPK '$TargetTpkPath' not found" }
$tpkEnd = $tpk + 8 + (I32 $g ($tpk + 4))
$tk = Kids $g $tpk
$infoP = $tk[[int]0xB3310000][0]; $dataP = $tk[[int]0xB3320000][0]
$leadPad = Slice $g ($tpk + 8) ($infoP - $tpk - 8)
$ik = Kids $g $infoP; $dk = Kids $g $dataP
$hdr01 = Slice $g ($ik[0x33310001][0] + 8) $ik[0x33310001][1]
$n = $ik[0x33310002][1] / 8
if ($ik.ContainsKey(0x33310003)) { throw "Compressed TPK (0x33310003) not supported" }
$payP = $dk[0x33320002][0] + 8; $payLen = $dk[0x33320002][1]

# existing textures
$texs = New-Object System.Collections.Generic.List[object]
$tpl = $null; $tplFmt = $null
for ($i = 0; $i -lt $n; $i++) {
    $hdr = Slice $g ($ik[0x33310004][0] + 8 + $i * 124) 124
    $fmt = Slice $g ($ik[0x33310005][0] + 8 + $i * 32) 32
    $name = [Text.Encoding]::ASCII.GetString($hdr, 0x0C, 24) -replace '\x00.*', ''
    if ($Textures | Where-Object { [BHash3]::H($_) -eq (U32 $hdr 0x24) }) { throw "Textura $name already exists in the TPK" }
    $texs.Add([pscustomobject]@{ Name = $name; Hash = (U32 $hdr 0x24); Hdr = $hdr; Fmt = $fmt; Off = (U32 $hdr 0x30); Size = (U32 $hdr 0x38); New = $false; Data = $null })
    if ($name -eq 'WHITE16X16_PURE_WHITE') { $tpl = $hdr; $tplFmt = $fmt }
}
if (-not $tpl) { throw "Template WHITE16X16_PURE_WHITE not found in this TPK" }

# texture offsets are relative to payload+0x78; existing data is kept byte for byte
$dataEnd = 0; foreach ($t in $texs) { $e = $t.Off + $t.Size; if ($e -gt $dataEnd) { $dataEnd = $e } }
$oldData = Slice $g $payP $payLen   # original payload, including the leading 0x78 bytes
$dms = New-Object IO.MemoryStream; $dms.Write($oldData, 0, $oldData.Length)
foreach ($name in $Textures) {
    $d = [IO.File]::ReadAllBytes((Join-Path $DdsDir "$name.dds"))
    if ([Text.Encoding]::ASCII.GetString($d, 84, 4) -ne 'DXT1') { throw "$name.dds is not DXT1" }
    $w = U32 $d 16; $h = U32 $d 12; $mips = [Math]::Max(1, (U32 $d 28)); $pix = Slice $d 128 ($d.Length - 128)
    $rel = $dms.Length - 0x78
    if ($rel % 0x80) { $padn = 0x80 - ($rel % 0x80); $dms.Write((New-Object byte[] $padn), 0, $padn); $rel += $padn }
    $dms.Write($pix, 0, $pix.Length)
    $hdr = [byte[]]$tpl.Clone()
    for ($i = 0x0C; $i -lt 0x24; $i++) { $hdr[$i] = 0 }
    $nb = [Text.Encoding]::ASCII.GetBytes($name); [Array]::Copy($nb, 0, $hdr, 0x0C, [Math]::Min(24, $nb.Length))
    [BitConverter]::GetBytes([BHash3]::H($name)).CopyTo($hdr, 0x24)
    [BitConverter]::GetBytes([uint32]$rel).CopyTo($hdr, 0x30)
    [BitConverter]::GetBytes([uint32]0).CopyTo($hdr, 0x34)
    [BitConverter]::GetBytes([uint32]$pix.Length).CopyTo($hdr, 0x38)
    [BitConverter]::GetBytes([uint32]0).CopyTo($hdr, 0x3C)
    [BitConverter]::GetBytes([uint32]([Math]::Max(1, $w / 4) * [Math]::Max(1, $h / 4) * 8)).CopyTo($hdr, 0x40)
    [BitConverter]::GetBytes([uint16]$w).CopyTo($hdr, 0x44); [BitConverter]::GetBytes([uint16]$h).CopyTo($hdr, 0x46)
    $hdr[0x48] = [byte][Math]::Log($w, 2); $hdr[0x49] = [byte][Math]::Log($h, 2); $hdr[0x4A] = 0x22; $hdr[0x4E] = [byte]$mips
    $texs.Add([pscustomobject]@{ Name = $name; Hash = [BHash3]::H($name); Hdr = $hdr; Fmt = [byte[]]$tplFmt.Clone(); Off = $rel; Size = $pix.Length; New = $true; Data = $pix })
}
$newPayload = $dms.ToArray()
$sorted = $texs | Sort-Object Hash

$hashTable = Concat ($sorted | ForEach-Object { Concat @([BitConverter]::GetBytes([uint32]$_.Hash), (New-Object byte[] 4)) })
$headers = Concat ($sorted | ForEach-Object { $_.Hdr })
$formats = Concat ($sorted | ForEach-Object { $_.Fmt })
$info = Chunk 0xB3310000 (Concat @((Chunk 0x33310001 $hdr01), (Chunk 0x33310002 $hashTable), (Chunk 0x33310004 $headers), (Chunk 0x33310005 $formats)))

$between = Slice $g $dk[0x33320001][0] ($dk[0x33320002][0] - $dk[0x33320001][0])
$dataBlk = Chunk 0xB3320000 (Concat @($between, (Chunk 0x33320002 $newPayload)))

$abs = $tpk + 8 + $leadPad.Length + $info.Length
$next = $abs + 8; $target = [int]([Math]::Ceiling($next / 0x80) * 0x80)
$pad2 = Chunk 0 (New-Object byte[] ($target - $next))
$tpkNew = Chunk 0xB3300000 (Concat @($leadPad, $info, $pad2, $dataBlk))

# padding after the TPK so the rest of the file shifts by a multiple of $ShiftAlign
$growth = $tpkNew.Length - ($tpkEnd - $tpk)
$tail = @()
if ($tpkEnd -lt $g.Length) {
    $need = ($ShiftAlign - (($growth + 8) % $ShiftAlign)) % $ShiftAlign
    $tail = Chunk 0 (New-Object byte[] $need)
}
$suffix = if ($tpkEnd -lt $g.Length) { Slice $g $tpkEnd ($g.Length - $tpkEnd) } else { New-Object byte[] 0 }
$newRaw = Concat @((Slice $g 0 $tpk), $tpkNew, [byte[]]$tail, $suffix)
$shift = $newRaw.Length - $g.Length
"Target TPK: $TargetTpkPath @0x{0:X} ({1} textures -> {2})" -f $tpk, $n, $sorted.Count
"Rest of file shifted by $shift bytes (multiple of 0x{0:X}: {1})" -f $ShiftAlign, (($shift % $ShiftAlign) -eq 0 -or $tpkEnd -eq $g.Length)
"New texture indices: " + (($sorted | ForEach-Object -Begin { $i = 0 } -Process { if ($_.New) { "$($_.Name)=#$i" }; $i++ }) -join ', ')

$packed = [JdlzC]::Compress($newRaw)
if (-not [Linq.Enumerable]::SequenceEqual([Jdlz]::Decompress($packed, 0), $newRaw)) { throw "JDLZ round-trip check failed" }
"Compressed: $($packed.Length) bytes (decompressed $($newRaw.Length))"
[IO.File]::WriteAllBytes($OutLzc, $packed)
if ($OutBun) { [IO.File]::WriteAllBytes($OutBun, $newRaw) }
"Written: $OutLzc"
