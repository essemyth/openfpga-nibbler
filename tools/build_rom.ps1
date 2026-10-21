<#
.SYNOPSIS
    Builds the single nibbler.rom file the core loads, from a MAME Nibbler ROM set.

.DESCRIPTION
    Accepts a MAME ROM folder or .zip. Files are matched by CRC32, so filenames
    don't matter. Output layout (64 KB, see docs/HARDWARE.md):

        0x0000-0x8FFF  Main CPU ROM   (CPU $3000-$BFFF)
        0x9000-0xAFFF  Background tile graphics (ic50, ic51)
        0xB000-0xBFFF  Sound waveform ROMs (ic52 @ 0xB000, ic53 @ 0xB800)
        0xC000-0xC03F  Color PROMs (fg ic7 @ 0xC000, bg ic6 @ 0xC020)
        0xC040-0xFFFF  Padding (0x00)

    By default the output goes to pkg\Assets\nibbler\common\, as nibbler.rom for
    rev 9 (the core's default) or nibbler6.rom for rev 6 (choose it in the
    core's menu on the Pocket).

.EXAMPLE
    .\tools\build_rom.ps1 -Source C:\roms\nibbler                 # rev 9 -> nibbler.rom
.EXAMPLE
    .\tools\build_rom.ps1 -Source C:\roms\nibbler6 -Set nibbler6  # rev 6 -> nibbler6.rom
.EXAMPLE
    .\tools\build_rom.ps1 -Source C:\roms\nibbler6.zip,C:\roms\nibbler.zip -Set nibbler6   # split set + parent
#>
param(
    [Parameter(Mandatory = $true)][string[]]$Source,     # folders and/or zips
    [ValidateSet('nibbler', 'nibbler6')][string]$Set = 'nibbler',
    [string]$Out
)

$ErrorActionPreference = 'Stop'

if (-not $Out) {
    $name = if ($Set -eq 'nibbler6') { 'nibbler6.rom' } else { 'nibbler.rom' }
    $Out = Join-Path $PSScriptRoot "..\pkg\Assets\nibbler\common\$name"
}

Add-Type -TypeDefinition @'
public static class Crc32 {
    static readonly uint[] T = Make();
    static uint[] Make() {
        var t = new uint[256];
        for (uint i = 0; i < 256; i++) {
            uint c = i;
            for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            t[i] = c;
        }
        return t;
    }
    public static uint Compute(byte[] d) {
        uint c = 0xFFFFFFFFu;
        foreach (byte b in d) c = T[(c ^ b) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFFu;
    }
}
'@

# CRC32 -> offset in output file. From MAME 0.289 snk6502.cpp ROM_START blocks.
$common = [ordered]@{
    '7205fb8d' = 0x6000  # g-0960-54.ic15  CPU $9000
    '4bb39815' = 0x7000  # g-0960-55.ic16  CPU $A000
    'ed680f19' = 0x8000  # g-0960-56.ic17  CPU $B000
    '01d4d0c2' = 0x9000  # g-0960-57.ic50  gfx
    'feff7faf' = 0xA000  # g-0960-58.ic51  gfx
    '87d67dee' = 0xB000  # g-0959-44.ic52  sound
    '33189917' = 0xB800  # g-0959-45.ic53  sound
    'a5709ff3' = 0xC000  # g-0708-05.ic7   fg color PROM
    'dacd592d' = 0xC020  # g-0708-04.ic6   bg color PROM
}
$program = @{
    # rev 9, set 1
    'nibbler'  = [ordered]@{
        '6dfa1be5' = 0x0000  # g-0960-52.ic12  CPU $3000
        '808e1a03' = 0x1000  # g-0960-48.ic7   CPU $4000
        '1571d4a2' = 0x2000  # g-0960-49.ic8   CPU $5000
        'a599df10' = 0x3000  # g-0960-50.ic9   CPU $6000
        'a6b5abe5' = 0x4000  # g-0960-51.ic10  CPU $7000
        '9f537185' = 0x5000  # g-0960-53.ic14  CPU $8000 (+ vectors at $F000)
    }
    # rev 6
    'nibbler6' = [ordered]@{
        'ac6a802b' = 0x0000  # ic12
        '35971364' = 0x1000  # ic7
        '6b33b806' = 0x2000  # ic8
        '91a4f98d' = 0x3000  # ic9
        'a151d934' = 0x4000  # ic10
        '063f05cc' = 0x5000  # ic14
    }
}
$wanted = [ordered]@{}
foreach ($k in $program[$Set].Keys) { $wanted[$k] = $program[$Set][$k] }
foreach ($k in $common.Keys) { $wanted[$k] = $common[$k] }

# Collect every file in the sources by CRC. Several sources can be given, e.g.
# a split rev 6 set plus its parent: -Source nibbler6.zip,nibbler.zip
$found = @{}
foreach ($src in $Source) {
    if ((Get-Item $src).PSIsContainer) {
        foreach ($f in Get-ChildItem $src -File) {
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            $found[('{0:x8}' -f [Crc32]::Compute($bytes))] = @{ Name = $f.Name; Data = $bytes }
        }
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $src))
        try {
            foreach ($e in $zip.Entries) {
                if ($e.Length -eq 0) { continue }
                $ms = New-Object IO.MemoryStream
                $s = $e.Open(); $s.CopyTo($ms); $s.Close()
                $bytes = $ms.ToArray()
                $found[('{0:x8}' -f [Crc32]::Compute($bytes))] = @{ Name = $e.FullName; Data = $bytes }
            }
        } finally { $zip.Dispose() }
    }
}

$image = New-Object byte[] 0x10000
$missing = @()
foreach ($crc in $wanted.Keys) {
    if (-not $found.ContainsKey($crc)) { $missing += $crc; continue }
    $data = $found[$crc].Data
    [Array]::Copy($data, 0, $image, $wanted[$crc], $data.Length)
    Write-Host ('  {0,-16} crc {1} -> 0x{2:X4}' -f $found[$crc].Name, $crc, $wanted[$crc])
}
if ($missing.Count -gt 0) {
    throw "Set '$Set' is incomplete. Missing CRC32: $($missing -join ', ')"
}

$outDir = Split-Path $Out -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
[IO.File]::WriteAllBytes($Out, $image)
Write-Host "Wrote $((Resolve-Path $Out).Path) ($Set, $($image.Length) bytes)"
