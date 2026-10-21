<#
.SYNOPSIS
    Generates the platform image and author icon as PNGs, then encodes them into
    the Pocket format with tools\pocket_image.ps1.

.DESCRIPTION
    platform.png  521x165: the game's own title logo (cropped from a title screen
                  frame rendered by the core in simulation, sim/out/frame_987.png),
                  scaled 3x, white on black as Pocket platform images usually are.
    icon.png      36x36: original pixel art (a snake shaped like an S), drawn on an
                  18x18 grid at 2x2 pixels as Analogue recommends.

.EXAMPLE
    .\art\make_art.ps1 -TitleFrame sim\out\frame_987.png
#>
param(
    [string]$TitleFrame = (Join-Path $PSScriptRoot '..\sim\out\frame_987.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Resolve-Path (Join-Path $PSScriptRoot '..')

# ---- platform image ---------------------------------------------------------
# logo letters occupy x 24-191, y 38-86 of the upright title screen (the TM mark
# to the right is left out)
$src = New-Object Drawing.Bitmap((Resolve-Path $TitleFrame).Path)
$lx = 24; $ly = 38; $lw = 168; $lh = 49; $scale = 3
$plat = New-Object Drawing.Bitmap 521, 165
$g = [Drawing.Graphics]::FromImage($plat)
$g.Clear([Drawing.Color]::Black)
$ox = [int]((521 - $lw * $scale) / 2)
$oy = [int]((165 - $lh * $scale) / 2)
for ($y = 0; $y -lt $lh; $y++) {
    for ($x = 0; $x -lt $lw; $x++) {
        $c = $src.GetPixel($lx + $x, $ly + $y)
        if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) {
            $g.FillRectangle([Drawing.Brushes]::White, $ox + $x * $scale, $oy + $y * $scale, $scale, $scale)
        }
    }
}
$src.Dispose()
$platPng = Join-Path $PSScriptRoot 'platform.png'
$plat.Save($platPng, [Drawing.Imaging.ImageFormat]::Png)

# ---- author icon ------------------------------------------------------------
# Drawn on an 18x18 grid from rectangles: a 3-cell-thick S with the head at
# the top right (eye, tongue) and the tail tapering off at the bottom left.
$on = @(
    @(5, 2, 8, 3),      # top stroke
    @(3, 3, 3, 5),      # upper left bend
    @(4, 7, 10, 3),     # middle stroke
    @(13, 8, 3, 6),     # lower right bend
    @(4, 12, 10, 3),    # bottom stroke
    @(12, 1, 5, 5),     # head
    @(17, 3, 1, 1),     # tongue
    @(2, 13, 2, 1),     # tail
    @(1, 14, 1, 1)      # tail tip
)
$off = @(
    @(3, 3), @(3, 7), @(4, 9),      # round the bends
    @(15, 8), @(15, 13), @(13, 14),
    @(12, 1), @(16, 1), @(16, 5),   # round the head
    @(14, 2)                        # eye
)
$icon = New-Object Drawing.Bitmap 36, 36
$gi = [Drawing.Graphics]::FromImage($icon)
$gi.Clear([Drawing.Color]::Black)
foreach ($r in $on)  { $gi.FillRectangle([Drawing.Brushes]::White, $r[0] * 2, $r[1] * 2, $r[2] * 2, $r[3] * 2) }
foreach ($p in $off) { $gi.FillRectangle([Drawing.Brushes]::Black, $p[0] * 2, $p[1] * 2, 2, 2) }
$iconPng = Join-Path $PSScriptRoot 'icon.png'
$icon.Save($iconPng, [Drawing.Imaging.ImageFormat]::Png)

# ---- encode -----------------------------------------------------------------
$tool = Join-Path $root 'tools\pocket_image.ps1'
& $tool -ToBin $platPng -Out (Join-Path $root 'pkg\Platforms\_images\nibbler.bin')
& $tool -ToBin $iconPng -Out (Join-Path $root 'pkg\Cores\Essemyth.Nibbler\icon.bin')
