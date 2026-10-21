<#
.SYNOPSIS
    Converts between PNG and the Pocket's graphic asset format (platform images,
    core icons).

.DESCRIPTION
    Pocket format (Analogue "Graphical Asset Formats"): 16 bits per pixel,
    brightness in the upper 8 bits (0xFF00 = fully on), stored big-endian (the
    brightness byte comes first; checked against the template's images), image
    stored rotated 90 degrees counter-clockwise. Platform images are 521x165,
    core icons 36x36.

    -ToPng  decodes a .bin to an upright PNG (Width/Height are the upright size)
    -ToBin  encodes an upright PNG (converted to grayscale) to a .bin

.EXAMPLE
    .\tools\pocket_image.ps1 -ToBin art\platform.png -Out pkg\Platforms\_images\nibbler.bin
    .\tools\pocket_image.ps1 -ToPng pkg\Cores\Essemyth.Nibbler\icon.bin -Width 36 -Height 36 -Out icon.png
#>
param(
    [string]$ToPng,
    [string]$ToBin,
    [int]$Width,
    [int]$Height,
    [Parameter(Mandatory = $true)][string]$Out
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Full([string]$p) {
    if ([IO.Path]::IsPathRooted($p)) { return $p }
    return Join-Path (Get-Location).Path $p
}

if ($ToPng) {
    $bytes = [IO.File]::ReadAllBytes((Full $ToPng))
    if (-not $Width -or -not $Height) { throw 'Give -Width and -Height (upright size)' }
    if ($bytes.Length -ne $Width * $Height * 2) { throw "Size mismatch: $($bytes.Length) bytes for ${Width}x$Height" }
    # stored rotated 90 CCW: stored width = upright height
    $sw = $Height; $sh = $Width
    $stored = New-Object Drawing.Bitmap $sw, $sh
    for ($y = 0; $y -lt $sh; $y++) {
        for ($x = 0; $x -lt $sw; $x++) {
            $i = ($y * $sw + $x) * 2
            $v = $bytes[$i]                         # upper byte, stored first
            $stored.SetPixel($x, $y, [Drawing.Color]::FromArgb($v, $v, $v))
        }
    }
    $stored.RotateFlip([Drawing.RotateFlipType]::Rotate90FlipNone)    # undo the CCW rotation
    $stored.Save((Full $Out), [Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Wrote $Out ($($stored.Width)x$($stored.Height))"
} elseif ($ToBin) {
    $img = New-Object Drawing.Bitmap((Full $ToBin))
    $img.RotateFlip([Drawing.RotateFlipType]::Rotate270FlipNone)      # rotate 90 CCW for storage
    $data = New-Object byte[] ($img.Width * $img.Height * 2)
    for ($y = 0; $y -lt $img.Height; $y++) {
        for ($x = 0; $x -lt $img.Width; $x++) {
            $c = $img.GetPixel($x, $y)
            $v = [int][Math]::Round(0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
            $i = ($y * $img.Width + $x) * 2
            $data[$i] = [byte]$v
            $data[$i + 1] = 0
        }
    }
    [IO.File]::WriteAllBytes((Full $Out), $data)
    Write-Host "Wrote $Out ($($img.Height)x$($img.Width) upright, $($data.Length) bytes)"
} else {
    throw 'Give -ToPng or -ToBin'
}
