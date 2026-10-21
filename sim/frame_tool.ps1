<#
.SYNOPSIS
    Converts a simulated frame (PPM, native 256x224) to an upright PNG, and
    optionally compares it with a MAME snapshot.

.DESCRIPTION
    The game's monitor is rotated 90 degrees clockwise (MAME ROT90), and MAME
    snapshots are saved upright (224x256), so the frame is rotated the same way
    before saving or comparing.

.EXAMPLE
    .\sim\frame_tool.ps1 -Ppm sim\out\frame_389.ppm -Mame C:\snaps\t06.5.png
#>
param(
    [Parameter(Mandatory = $true)][string]$Ppm,
    [string]$Mame,
    [string]$Png
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# .NET resolves relative paths against its own working directory, so use full paths
$Ppm = (Resolve-Path $Ppm).Path
if (-not $Png) { $Png = [IO.Path]::ChangeExtension($Ppm, '.png') }
elseif (-not [IO.Path]::IsPathRooted($Png)) { $Png = Join-Path (Get-Location).Path $Png }

$bytes = [IO.File]::ReadAllBytes($Ppm)
# header "P6\n256 224\n255\n"
$nl = 0; $pos = 0
while ($nl -lt 3) { if ($bytes[$pos] -eq 10) { $nl++ }; $pos++ }
$bmp = New-Object Drawing.Bitmap 256, 224
for ($y = 0; $y -lt 224; $y++) {
    for ($x = 0; $x -lt 256; $x++) {
        $i = $pos + ($y * 256 + $x) * 3
        $bmp.SetPixel($x, $y, [Drawing.Color]::FromArgb($bytes[$i], $bytes[$i + 1], $bytes[$i + 2]))
    }
}
$bmp.RotateFlip([Drawing.RotateFlipType]::Rotate90FlipNone)
$bmp.Save($Png, [Drawing.Imaging.ImageFormat]::Png)
Write-Host "Wrote $Png"

if ($Mame) {
    $ref = New-Object Drawing.Bitmap((Resolve-Path $Mame).Path)
    if ($ref.Width -ne $bmp.Width -or $ref.Height -ne $bmp.Height) {
        throw "Size differs: sim $($bmp.Width)x$($bmp.Height), MAME $($ref.Width)x$($ref.Height)"
    }
    $diff = New-Object Drawing.Bitmap $bmp.Width, $bmp.Height
    $count = 0
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $a = $bmp.GetPixel($x, $y); $b = $ref.GetPixel($x, $y)
            if ($a.ToArgb() -ne $b.ToArgb()) {
                $count++
                $diff.SetPixel($x, $y, [Drawing.Color]::Red)
            } else {
                $g = [int](($a.R + $a.G + $a.B) / 6)
                $diff.SetPixel($x, $y, [Drawing.Color]::FromArgb($g, $g, $g))
            }
        }
    }
    $diffPng = [IO.Path]::ChangeExtension($Png, '.diff.png')
    $diff.Save($diffPng, [Drawing.Imaging.ImageFormat]::Png)
    Write-Host "$count of $($bmp.Width * $bmp.Height) pixels differ from MAME (red in $diffPng)"
}
