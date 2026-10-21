<#
.SYNOPSIS
    Makes sim/data/test.hi, a high score save file for the testbench
    (run_sim.ps1 -HsFile), from the game's default table read out of MAME.

.DESCRIPTION
    Runs MAME for 7 seconds, reads the high score table from RAM ($0290-$02ED),
    then changes the top entry to 77,700 by "CLD" and the second name to "AAA"
    so a restored table is easy to recognise. Needs MAME and the Nibbler ROMs;
    the result is not committed (it is data from the game).

.EXAMPLE
    .\sim\make_test_hi.ps1 -RomPath C:\roms
#>
param(
    [Parameter(Mandatory = $true)][string]$RomPath,
    [string]$Mame = 'mame.exe'
)

$ErrorActionPreference = 'Stop'
$work = Join-Path $PSScriptRoot 'out'
$data = Join-Path $PSScriptRoot 'data'
New-Item -ItemType Directory -Force $work, $data | Out-Null
$table = (Join-Path $work 'hitable.txt').Replace('\', '/')

$lua = @"
sub = emu.add_machine_frame_notifier(function()
  if manager.machine.time:as_double() >= 7.0 then
    local sp = manager.machine.devices[':maincpu'].spaces['program']
    local f = io.open('$table', 'w')
    for a = 0x290, 0x2ED do f:write(string.format('%02X', sp:read_u8(a))) end
    f:close()
    manager.machine:exit()
  end
end)
"@
$luaFile = Join-Path $work 'hitable.lua'
Set-Content $luaFile $lua -Encoding ascii

$ErrorActionPreference = 'Continue'
& $Mame nibbler -rompath $RomPath -autoboot_script $luaFile -sound none -video none `
    -skip_gameinfo -nothrottle -seconds_to_run 20 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

$h = Get-Content $table
$scores = '00777000' + $h.Substring(8, 72)              # 10 x 4 bytes BCD
$names  = '0C150D' + '0A0A0A' + $h.Substring(128 + 12, 48)   # $02D0: 10 x 3 letters
$hex = '4E484931' + $scores + $names                   # "NHI1" + table
$bytes = New-Object byte[] 256
for ($i = 0; $i -lt $hex.Length / 2; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
$out = Join-Path $data 'test.hi'
[IO.File]::WriteAllBytes($out, $bytes)
Write-Host "Wrote $out"
