<#
.SYNOPSIS
    Loads the compiled .sof onto a running Pocket over JTAG (USB-Blaster).

.DESCRIPTION
    The core must already be installed on the SD card and launched on the Pocket
    (APF needs the JSON definitions). After loading, APF re-initializes the core
    and reloads its data slots automatically.

.EXAMPLE
    .\tools\jtag_load.ps1
#>
param(
    [string]$Cable = 'USB-Blaster',
    [string]$QuartusBin
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$sof = Join-Path $root 'src\fpga\output_files\ap_core.sof'

if (-not $QuartusBin) {
    $cmd = Get-Command quartus_pgm.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $QuartusBin = Split-Path $cmd.Source -Parent
    } else {
        $QuartusBin = Get-ChildItem 'C:\intelFPGA_lite', 'C:\altera_lite' -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'quartus\bin64' } |
            Where-Object { Test-Path (Join-Path $_ 'quartus_pgm.exe') } |
            Select-Object -First 1
        if (-not $QuartusBin) { throw 'quartus_pgm not found. Pass -QuartusBin.' }
    }
}

$pgm = Join-Path $QuartusBin 'quartus_pgm.exe'
& $pgm -l
& $pgm -c $Cable -m jtag -o "p;$sof"
if ($LASTEXITCODE -ne 0) { throw "JTAG programming failed (exit $LASTEXITCODE)" }
