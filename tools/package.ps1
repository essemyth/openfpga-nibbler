<#
.SYNOPSIS
    Builds the release zip: the SD card files a user extracts onto their Pocket.

.DESCRIPTION
    Contents (Analogue's layout, nothing outside the folders the Pocket uses):
        Cores/Essemyth.Nibbler/    core definition JSONs, icon.bin, bitstream.rbf_r
        Platforms/nibbler.json
        Platforms/_images/nibbler.bin
    No ROM data is included: users build nibbler.rom from their own MAME set.
    The zip is named Essemyth.Nibbler_<version>_<date>.zip from core.json and is
    written to release/.

.EXAMPLE
    .\tools\build.ps1; .\tools\package.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$coreDir = Join-Path $root 'pkg\Cores\Essemyth.Nibbler'
$core = (Get-Content (Join-Path $coreDir 'core.json') -Raw | ConvertFrom-Json).core.metadata

$bitstream = Join-Path $coreDir 'bitstream.rbf_r'
if (-not (Test-Path $bitstream)) { throw 'No bitstream.rbf_r: run tools\build.ps1 first.' }
$age = (Get-Date) - (Get-Item $bitstream).LastWriteTime
Write-Host ("Bitstream built {0:N0} minutes ago" -f $age.TotalMinutes)

$stage = Join-Path $root 'release\stage'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force (Join-Path $stage 'Cores\Essemyth.Nibbler'), (Join-Path $stage 'Platforms\_images') | Out-Null

Get-ChildItem $coreDir -File | Where-Object { $_.Name -ne '.gitkeep' } |
    Copy-Item -Destination (Join-Path $stage 'Cores\Essemyth.Nibbler')
Copy-Item (Join-Path $root 'pkg\Platforms\nibbler.json') (Join-Path $stage 'Platforms')
Copy-Item (Join-Path $root 'pkg\Platforms\_images\nibbler.bin') (Join-Path $stage 'Platforms\_images')

# safety: never ship ROM data
$bad = Get-ChildItem $stage -Recurse -File | Where-Object { $_.Extension -in '.rom', '.zip', '.hi', '.sta' }
if ($bad) { throw "Refusing to package: $($bad.FullName -join ', ')" }

$zip = Join-Path $root ("release\Essemyth.Nibbler_{0}_{1}.zip" -f $core.version, $core.date_release)
if (Test-Path $zip) { Remove-Item $zip }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# add entries one by one with '/' separators (Windows PowerShell's
# CreateFromDirectory writes '\', which other systems don't treat as folders)
$fs = [IO.File]::Open($zip, [IO.FileMode]::CreateNew)
$archive = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $name = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $name) | Out-Null
}
$archive.Dispose()
$fs.Dispose()
Remove-Item -Recurse -Force $stage

$z = [IO.Compression.ZipFile]::OpenRead($zip)
$z.Entries | ForEach-Object { Write-Host "  $($_.FullName)  ($($_.Length) bytes)" }
$z.Dispose()
Write-Host "Wrote $zip"
