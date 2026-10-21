# Nibbler for Analogue Pocket

An openFPGA core for the Analogue Pocket that recreates the arcade hardware of
**Nibbler** (Rock-Ola, 1982): the 6502 CPU, video, and the custom tone, SN76477
and analog sound circuits.

**Version 1.0.0**

> **This core was developed entirely by AI.** All of the FPGA design, the tools,
> the simulations and this documentation were written by Claude (Anthropic's AI
> model, using Claude Code). The project owner, Essemyth, directed the work,
> made the decisions, and tested the builds on a real Analogue Pocket. Bugs found
> on the device were diagnosed and fixed by the AI from logs, screenshots and
> save files read off the Pocket's SD card. See
> [How this was made](#how-this-was-made).

## Features

- Cycle-accurate 6502 board timing, video and sound, checked against MAME frame
  by frame and sample by sample (see [Accuracy](#accuracy))
- Save states (Pocket Memories) and sleep/wake
- High scores saved to the SD card
- Pauses while the Pocket menu is open
- Cabinet DIP switches in the core menu
- Rev 9 (default) and rev 6 ROM support

## Installation

1. Download the latest release zip and extract it to the root of your Pocket's
   SD card. It adds `Cores/Essemyth.Nibbler/` and the files in `Platforms/`.
2. Make the ROM file (below) and copy it to `/Assets/nibbler/common/` on the SD card.
3. On the Pocket: **openFPGA > Arcade > Nibbler**.

### Making the ROM file

The core needs a single file, `nibbler.rom`, combined from a MAME Nibbler ROM set
that you supply (no ROM data is included in this project). MAME sets come as
separate chip files (`g-0960-52.ic12`, `ic7`, ...) in a folder or zip; the
script below finds each chip by its checksum and assembles them, so file names
don't matter.

From a copy of this repository, in PowerShell (built into Windows; on macOS or
Linux use PowerShell 7):

```powershell
# rev 9 (MAME "nibbler"), the default
.\tools\build_rom.ps1 -Source <path to the nibbler folder or nibbler.zip>

# rev 6 (MAME "nibbler6"), optional. A split set keeps the chips rev 6 shares
# with rev 9 in the parent, so give both:
.\tools\build_rom.ps1 -Source <nibbler6 set>,<nibbler set> -Set nibbler6
```

Sources can be folders or zips, and you can list several. The files are written
to `pkg/Assets/nibbler/common/` (`nibbler.rom`, `nibbler6.rom`). If chips are
missing, the script stops and lists their checksums.

To play rev 6, choose `nibbler6.rom` from the core's menu on the Pocket
(**Nibbler ROM**). The choice is remembered.

## Controls

| Pocket | Arcade |
|---|---|
| D-pad | 4-way joystick: when you roll across a diagonal, the direction pressed last wins |
| Select | Coin |
| Start | 1 player start |
| Y | 2 players start |

## Core menu

| Setting | |
|---|---|
| Reset Game | Restarts the game |
| Lives | 3 / 4 / 5 / 6 (rev 6: 2 / 3 / 4 / 5) |
| Difficulty | Easy / Hard (rev 6: this switch is "Pause at Corners"; Easy = pausing on) |
| Coinage | 1 coin 1 credit, 2 coins 1 credit, and two bonus settings |
| Free Play | |
| Service Mode | The game's test screens |
| Debug Overlay | Live CPU and core state, for development |

Lives, Difficulty, Coinage, Free Play and Service Mode are the cabinet's DIP
switches. As on the real machine, the game may only pick up a change after
**Reset Game**.

## Save states, sleep and high scores

- **Memories** (save states) and **sleep** work at any point in the game. A
  state belongs to the ROM revision it was made with; don't load a rev 9 state
  while running rev 6.
- **High scores** are saved to `/Saves/nibbler/common/nibbler.hi` when you leave
  the core with **Quit** from the Pocket menu, and restored the next time it starts
  (a few seconds in, once the game has set up its table). Turning the Pocket off
  without quitting doesn't save them.

## Known limitations

- Cocktail cabinet mode (screen flip for player 2) is not implemented.
- The menu labels follow rev 9; rev 6's meanings are noted above.

## Accuracy

The core implements the board as MAME's `snk6502` driver documents it, and was
checked against MAME 0.289 in simulation:

- The 805,000-instruction power-up self-test runs instruction for instruction
  and cycle for cycle as in MAME, wait states included.
- Diagnostics, high score, title and gameplay screens are pixel-identical to
  MAME, for rev 9 and rev 6.
- The coin sound matches MAME sample for sample; music matches in pitch,
  waveform and level; the death sound matches in level and decay.
- After about a thousand frames of play, MAME's snake can be one movement step
  behind the core. That comes from rounding in MAME's timekeeping; the core keeps
  the board's exact clock ratio (one frame = 23,580 CPU cycles).

Details are in [docs/HARDWARE.md](docs/HARDWARE.md).

## Building from source

Intel/Altera Quartus Prime Lite (with Cyclone V support) builds the core;
Questa (installed with Quartus) runs the simulations. See
[docs/SETUP.md](docs/SETUP.md) for the toolchain, Pocket developer settings and
the build/deploy workflow.

```powershell
.\tools\build.ps1                  # compile; writes pkg/Cores/Essemyth.Nibbler/bitstream.rbf_r
.\tools\deploy.ps1 -Drive E:       # copy pkg/ to an SD card
.\tools\package.ps1                # release zip in release/ (never includes ROM data)
```

```
src/fpga/core/   the Nibbler board (nibbler_top.v and modules), Pocket glue (core_top.v), T65 CPU
src/fpga/apf/    Analogue Pocket framework (from the core template)
pkg/             SD card layout: core definition, platform files
tools/           ROM builder, build, deploy, package, image converter
sim/             Questa testbenches and MAME comparison scripts
art/             platform image and icon sources
docs/            SETUP, HARDWARE (reference and findings), ROADMAP
```

## How this was made

Claude built the core in milestones, starting from Analogue's template, with
MAME's source and MAME itself as the reference for the original hardware:

1. Video timing and ROM loading, then the 6502 CPU and memory map
2. Tile layers and palette, then controls and DIP switches
3. Sound, then save states, sleep, high scores and packaging

Each step was checked in simulation before it reached the Pocket: instruction
traces, screen captures and audio recorded from MAME were compared with the
simulated core (`sim/`), and the core was then tested on the device. The
problems that only showed up on hardware (how the Pocket times bridge reads,
resets around save state loads, and sizes save files) are written up in
[docs/HARDWARE.md](docs/HARDWARE.md).

## Credits

- Hardware documentation: MAME's `snk6502` driver and devices (Nicola Salmoria,
  Dan Boris and the MAME contributors), used as the reference throughout.
- Built on Analogue's [openFPGA core template](https://github.com/open-fpga/core-template).
- The save state protocol notes owe a lot to agg23's
  [openfpga-NES](https://github.com/agg23/openfpga-NES).
- 6502 CPU: **T65**, from [mist-devel/T65](https://github.com/mist-devel/T65),
  unmodified, in `src/fpga/core/t65/`.
  Copyright (c) 2002...2015 Daniel Wallner, Mike Johnson, Wolfgang Scherr,
  Morten Leikvoll. All rights reserved. Used under its BSD-style license; the full
  notice is in [src/fpga/core/t65/README](src/fpga/core/t65/README).

## License

MIT, see [LICENSE](LICENSE). The T65 CPU core and Analogue's framework files
keep their own licenses, listed there.

## Legal

Nibbler is a trademark of its respective owner. This project is not affiliated
with or endorsed by Rock-Ola, SNK or Analogue, and includes no ROM data.

Analogue's Development program was created to further video game hardware
preservation with FPGA technology. Analogue Developers have access to Analogue
Pocket I/O's so Developers can utilize cartridge adapters or interface with other
pieces of original or bespoke hardware to support legacy media. Analogue does not
support or endorse the unauthorized use or distribution of material protected by
copyright or other intellectual property rights.
