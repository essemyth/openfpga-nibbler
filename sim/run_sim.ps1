<#
.SYNOPSIS
    Compiles the core with Questa and runs the testbench.

.DESCRIPTION
    Default: writes an instruction trace (sim/out/sim_trace.log) for
    sim/compare_trace.ps1.
    With -Frames: saves those frames as sim/out/frame_<n>.ppm instead (frame 1 is
    the first after reset; MAME time t seconds is about frame t * 59.84). Convert
    or compare them with sim/frame_tool.ps1.

.EXAMPLE
    .\sim\run_sim.ps1 -Instructions 200000
.EXAMPLE
    .\sim\run_sim.ps1 -Frames 119,389
#>
param(
    [int]$Instructions = 100000,
    [string]$Frames = '',
    [string]$Inputs = '',            # e.g. "1000:2:02,1001:2:00" (frame:port:hex), see tb_nibbler.sv
    [string]$SsTest = '',            # e.g. "1150,30": save state test, see tb_nibbler.sv
    [string]$HsFile = '',            # high score save file to preload (data slot 2)
    [string]$Rom = (Join-Path $PSScriptRoot '..\pkg\Assets\nibbler\common\nibbler.rom'),
    [string]$QuestaBin = 'C:\altera_lite\25.1std\questa_fse\win64'
)

$ErrorActionPreference = 'Stop'
if (-not $env:SALT_LICENSE_SERVER) {
    $env:SALT_LICENSE_SERVER = [Environment]::GetEnvironmentVariable('SALT_LICENSE_SERVER', 'User')
}

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$core = Join-Path $root 'src\fpga\core'
$apf  = Join-Path $root 'src\fpga\apf'
$out  = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Force $out | Out-Null
$romFull = (Resolve-Path $Rom).Path
$hsFull = if ($HsFile) { (Resolve-Path $HsFile).Path } else { '' }

function Invoke-Q([string]$exe, [string[]]$qargs) {
    $ErrorActionPreference = 'Continue'
    $output = & (Join-Path $QuestaBin $exe) @qargs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $output | Where-Object { $_ -match 'Error|Warning|instructions|ROM loaded|saved frame|save state|high score' -and $_ -notmatch 'Errors: 0' } | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) { throw "$exe failed (exit $code)" }
}

Push-Location $out
try {
    if (Test-Path work) { Remove-Item -Recurse -Force work }
    Invoke-Q 'vlib.exe' @('work')
    Invoke-Q 'vcom.exe' @('-quiet', '-2008',
        "$core\t65\T65_Pack.vhd", "$core\t65\T65_ALU.vhd", "$core\t65\T65_MCode.vhd",
        "$core\t65\T65.vhd", "$core\t65_wrap.vhd")
    Invoke-Q 'vlog.exe' @('-quiet', '-sv',
        "$apf\common.v", "$core\dpram.v", "$core\nibbler_roms.v", "$core\nibbler_video.v",
        "$core\debug_overlay.v", "$core\nibbler_sound.v", "$core\nibbler_savestate.v", "$core\nibbler_hiscore.v", "$core\nibbler_top.v", "$PSScriptRoot\tb_nibbler.sv")

    $simArgs = @('-c', '-quiet', 'tb_nibbler', "+rom=$romFull", "+outdir=$out")
    if ($Frames -or $SsTest) {
        $simArgs += '+trace=none'
        if ($Frames) { $simArgs += "+frames=$Frames" }
        if ($SsTest) { $simArgs += "+ss_test=$SsTest" }
        if ($Inputs) { $simArgs += "+inputs=$Inputs" }
        if ($hsFull) { $simArgs += "+hs_file=$hsFull" }
    } else {
        $simArgs += @("+trace=$out\sim_trace.log", "+instructions=$Instructions")
    }
    Invoke-Q 'vsim.exe' ($simArgs + @('-do', 'run -all; quit -f'))
} finally { Pop-Location }

if (-not $Frames) { Write-Host "Trace: $out\sim_trace.log" }
