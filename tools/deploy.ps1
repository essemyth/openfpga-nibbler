<#
.SYNOPSIS
    Copies the core package (pkg/) onto the Pocket's SD card.

.DESCRIPTION
    Works with the SD card in a reader, or with the Pocket mounted over USB
    (Tools > Developer > USB SD Access). USB transfers are slow (~700 KB/s);
    the full package is ~1 MB so this takes a couple of seconds.

.EXAMPLE
    .\tools\deploy.ps1 -Drive E:
#>
param(
    [Parameter(Mandatory = $true)][string]$Drive
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$dest = $Drive.TrimEnd('\') + '\'

if (-not (Test-Path (Join-Path $dest 'Cores'))) {
    throw "$dest doesn't look like a Pocket SD card (no Cores folder)."
}

foreach ($dir in 'Cores', 'Platforms', 'Assets') {
    $src = Join-Path $root "pkg\$dir"
    Get-ChildItem $src -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' } | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length + 1)
        $target = Join-Path $dest "$dir\$rel"
        $targetDir = Split-Path $target -Parent
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force $targetDir | Out-Null }
        Copy-Item $_.FullName $target -Force
        Write-Host "  $dir\$rel"
    }
}
Write-Host "Deployed to $dest"
