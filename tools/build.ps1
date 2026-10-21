<#
.SYNOPSIS
    Compiles the FPGA project with Quartus and produces the Pocket bitstream.

.DESCRIPTION
    1. Runs a full Quartus compile of src/fpga/ap_core.qpf.
    2. Bit-reverses output_files/ap_core.rbf into pkg/Cores/Essemyth.Nibbler/bitstream.rbf_r
       (APF loads bitstreams with each byte's bit order reversed).
    The .sof (for JTAG loading) stays in src/fpga/output_files/.

.EXAMPLE
    .\tools\build.ps1            # compile + package
    .\tools\build.ps1 -SkipCompile  # just re-make bitstream.rbf_r from an existing .rbf
#>
param(
    [switch]$SkipCompile,
    [string]$QuartusBin
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$fpga = Join-Path $root 'src\fpga'

function Find-QuartusBin {
    $cmd = Get-Command quartus_sh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source -Parent }
    $roots = @('C:\intelFPGA_lite', 'C:\altera_lite', 'C:\intelFPGA', 'C:\altera')
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        $hit = Get-ChildItem $r -Directory | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'quartus\bin64' } |
            Where-Object { Test-Path (Join-Path $_ 'quartus_sh.exe') } |
            Select-Object -First 1
        if ($hit) { return $hit }
    }
    throw 'Quartus not found. Install Quartus Prime Lite or pass -QuartusBin <path to quartus\bin64>.'
}

if (-not $SkipCompile) {
    if (-not $QuartusBin) { $QuartusBin = Find-QuartusBin }
    Write-Host "Using Quartus in $QuartusBin"
    Push-Location $fpga
    # Quartus writes harmless notes to stderr; under 'Stop', PowerShell 5.1 turns
    # those into fatal errors when output is redirected. Rely on the exit code.
    $ErrorActionPreference = 'Continue'
    try {
        & (Join-Path $QuartusBin 'quartus_sh.exe') --flow compile ap_core 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { throw "Quartus compile failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
        $ErrorActionPreference = 'Stop'
    }
}

Add-Type -TypeDefinition @'
public static class BitRev {
    public static byte[] Reverse(byte[] d) {
        var o = new byte[d.Length];
        for (int i = 0; i < d.Length; i++) {
            int b = d[i], r = 0;
            for (int k = 0; k < 8; k++) { r = (r << 1) | (b & 1); b >>= 1; }
            o[i] = (byte)r;
        }
        return o;
    }
}
'@

$rbf = Join-Path $fpga 'output_files\ap_core.rbf'
$out = Join-Path $root 'pkg\Cores\Essemyth.Nibbler\bitstream.rbf_r'
[IO.File]::WriteAllBytes($out, [BitRev]::Reverse([IO.File]::ReadAllBytes($rbf)))
Write-Host "Wrote $out"
