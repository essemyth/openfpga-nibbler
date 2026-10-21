<#
.SYNOPSIS
    Runs MAME with the same scripted inputs as a simulation and saves snapshots
    of the same frames, for sim/frame_tool.ps1.

.DESCRIPTION
    Frame numbering follows the testbench: sim frame N is MAME screen
    frame_number N - 1 when snapshotted, and an input event for sim frame N is
    applied at MAME frame_number N (both take effect at the same vblank IRQ).

.EXAMPLE
    .\sim\mame_capture.ps1 -RomPath C:\roms -Frames 1040,1200 -Inputs "1000:2:02,1001:2:00" -Out C:\snaps
    # writes C:\snaps\mame_1040.png, mame_1200.png
#>
param(
    [Parameter(Mandatory = $true)][string]$RomPath,     # folder containing nibbler/ (rev 9 files)
    [Parameter(Mandatory = $true)][string]$Frames,
    [string]$Inputs = '',
    [string]$Out = (Join-Path $PSScriptRoot 'out'),
    [string]$Mame = 'mame.exe',             # path to MAME if it isn't on PATH
    [string]$Machine = 'nibbler'            # MAME machine, e.g. nibbler6 for rev 6
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$outLua = ((Resolve-Path $Out).Path).Replace('\', '/')

$events = @()
if ($Inputs) {
    foreach ($e in $Inputs.Split(',')) {
        $f, $p, $v = $e.Split(':')
        $events += "{ $f, ':IN$p', 0x$v }"
    }
}
$snaps = ($Frames.Split(',') | ForEach-Object { "[$([int]$_ - 1)] = $_" }) -join ', '

$lua = @"
local events = { $($events -join ', ') }
local snaps = { $snaps }
local remaining = 0
for _ in pairs(snaps) do remaining = remaining + 1 end
local ei = 1
sub = emu.add_machine_frame_notifier(function()
  local fn = manager.machine.screens[':screen']:frame_number()
  while ei <= #events and events[ei][1] <= fn do
    local port = manager.machine.ioport.ports[events[ei][2]]
    for _, field in pairs(port.fields) do
      field:set_value((events[ei][3] & field.mask) ~= 0 and 1 or 0)
    end
    ei = ei + 1
  end
  if snaps[fn] then
    manager.machine.screens[':screen']:snapshot('$outLua/mame_' .. snaps[fn] .. '.png')
    remaining = remaining - 1
    if remaining == 0 then manager.machine:exit() end
  end
end)
"@
$luaFile = Join-Path $Out 'mame_capture.lua'
Set-Content $luaFile $lua -Encoding ascii

$ErrorActionPreference = 'Continue'
& $Mame $Machine -rompath $RomPath -autoboot_script $luaFile -sound none -skip_gameinfo `
    -window -nomax -frameskip 0 -nothrottle -cfg_directory (Join-Path $Out 'mame_cfg') `
    -nvram_directory (Join-Path $Out 'mame_nvram') 2>&1 | Out-Null
Get-ChildItem $Out -Filter 'mame_*.png' | ForEach-Object { Write-Host "Wrote $($_.FullName)" }
