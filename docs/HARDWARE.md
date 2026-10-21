# Nibbler hardware reference

Primary source: MAME 0.289 `src/mame/snk/snk6502.cpp`, `snk6502_v.cpp`, `snk6502_a.cpp`
([tag mame0289](https://github.com/mamedev/mame/tree/mame0289/src/mame/snk)). MAME calls this
the "Fantasy" board variant of SNK's 6502 hardware. Items marked **verify** still need
confirming against schematics or real hardware.

## Clocks

| Signal | Derivation | Frequency |
|---|---|---|
| Master crystal | | 11.289 MHz |
| Pixel clock | XTAL / 2 | 5.6445 MHz |
| CPU (6502) | XTAL / 8 | 1.411 MHz |
| MC6845 CRTC character clock | XTAL / 16 | 705.6 kHz (8-pixel characters) |

Reads at addresses **$4000 and above** get one wait state (RDY is pulled on φ2). Writes don't.

## Video timing

- 360 × 262 total, **256 × 224 active**, 59.844 Hz. The CRTC registers are programmed by the game.
- The monitor is rotated (**ROT90** in MAME), so the game is portrait on screen. On Pocket this is `"rotation": 90` in video.json (confirmed on device in M1: 270 showed the image upside down).

## Interrupts and boot

- Vectors: NMI `$3000`, RESET `$3004`, IRQ `$3009`.
- **IRQ**: one per frame at the start of vblank (line 224), held until the CPU takes it.
  The game runs a ~3 second self-test (about 805,000 instructions) with interrupts
  disabled; the IRQ already pending from the first vblank fires right after its `cli`.
  Afterwards, IRQs come every 23,580 CPU cycles (one frame).
- **Raster phase vs. the CPU.** The game programs the MC6845 once at boot (R13 down to
  R0, from a table at `$7F05`: `2C 20 25 04 1F 06 1C 1D 00 07 00 00 03 FF`). That matches
  our fixed raster: 45 chars x 8 = 360 wide, 32 rows x 8 + 6 = 262 lines, 256 x 224
  displayed, vsync at line 232. On real hardware, where the raster is relative to the
  program depends on the CRTC's power-on state. In MAME it settles (after a reconfigure
  artifact one frame after the CRTC writes) so that vblank starts 17,901 CPU cycles
  into each 23,580-cycle frame, counted from reset. The core starts its raster at
  line 25, pixel 52 on reset to land on the same phase, so whole-game traces can be
  compared with MAME cycle for cycle.
- **NMI**: asserted while a coin input is active (coin 1 or coin 2).

## CPU memory map

| Address | R/W | Function |
|---|---|---|
| `$0000-$03FF` | RW | Work RAM (1 KB) |
| `$0400-$07FF` | RW | `videoram2`: **foreground** tile codes (32×32) |
| `$0800-$0BFF` | RW | `videoram`: **background** tile codes (32×32) |
| `$0C00-$0FFF` | RW | Color RAM: bits 2-0 = FG color, bits 5-3 = BG color |
| `$1000-$1FFF` | RW | Character RAM: the FG character set, written by the CPU |
| `$2000` | W | MC6845 address register |
| `$2001` | W | MC6845 data register |
| `$2100-$2102` | W | Sound control |
| `$2103` | W | Bits 2-0: background color. Bit 3 (**inverted**): BG character bank. Bit 7: flip screen. Also routed to sound. |
| `$2104` | R | IN0: P1 joystick |
| `$2105` | R | IN1: P2 joystick (cocktail) |
| `$2106` | R | DSW |
| `$2107` | R | IN2: coins/starts |
| `$2200` | W | BG scroll X |
| `$2300` | W | BG scroll Y |
| `$2400` | W | Speech (unused on Nibbler) |
| `$3000-$BFFF` | R | Program ROM (36 KB) |
| `$F000-$FFFF` | R | Mirror of ROM `$8000-$8FFF`, which holds the reset/IRQ/NMI vectors |

## Tilemaps

Both layers are 32×32 tiles of 8×8 pixels, row-major (`index = row*32 + col`), 2 bits per pixel.

- **Background**: code = `videoram[i] + 256 * charbank`, color = `colorram[i][5:3]`. Pixels come from the gfx ROMs (512 characters). Plane order: **ic50 = high bit, ic51 = low bit**. Scrolls with `$2200`/`$2300`.
- **Foreground**: code = `videoram2[i]`, color = `colorram[i][2:0]`. Pixels come from **char RAM**, with `$1000-$17FF` = high bit plane and `$1800-$1FFF` = low bit plane. Pen 0 is transparent. Doesn't scroll.
- 8 consecutive bytes per character (one per row). The leftmost pixel is bit 7.
- FG is drawn over BG.

## Palette (64 entries from two 32-byte PROMs)

- Entries `$00-$1F` (ic7): FG, indexed `color*4 + pen`.
- Entries `$20-$3F` (ic6): BG, indexed `$20 + color*4 + pen`.
- BG **pen 0** doesn't use its own entry. It uses entry `$20 + 4*backcolor`, where backcolor is `$2103` bits 2-0.
- Byte format, with resistor weights:
  - R = bits 0,1,2 → `0x21, 0x47, 0x97`
  - G = bits 3,4,5 → `0x21, 0x47, 0x97`
  - B = bits 6,7 → `0x52, 0xAD`

## Inputs (all active-high)

| Port | Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bits 3-0 |
|---|---|---|---|---|---|
| IN0 | P1 Left | P1 Right | P1 Up | P1 Down | debug (0) |
| IN1 | P2 Left | P2 Right | P2 Up | P2 Down | debug (0) |
| IN2 | Start 1 | Start 2 | - | - | bit 1 Coin 1, bit 0 Coin 2 |

The joystick is **4-way**. The core will need to filter Pocket D-pad diagonals.

## DIP switches (DSW at `$2106`; 0 = factory default)

| Bits | Rev 9 (`nibbler`) | Rev 6 (`nibbler6`) |
|---|---|---|
| 1-0 | Lives 3/4/5/6 | Lives 2/3/4/5 |
| 2 | Difficulty Easy/Hard | Pause at corners (0 = On) |
| 3 | Upright/Cocktail | same |
| 4 | Service mode | same |
| 5 | Free play | same |
| 7-6 | Coinage: 00 = 1C1C, 01 = 2C1C, 10 = 1C1C (2/3), 11 = 2C1C (4/3) | same |

## Sound (`nibbler_sound_device` in snk6502_a.cpp)

- Two custom tone channels. Each plays a waveform read from ic52/ic53, controlled via `$2100-$2103`.
- One **SN76477** complex sound generator, plus discrete circuitry.
- Details get worked out at the sound milestone. The tone channels carry the music and come first. The SN76477 effects are the hardest part of the whole core.

## Packed ROM file (`nibbler.rom`, 64 KB, built by tools/build_rom.ps1)

| File offset | Contents |
|---|---|
| `0x0000-0x8FFF` | CPU `$3000-$BFFF` |
| `0x9000-0x9FFF` | gfx ic50 (BG high plane) |
| `0xA000-0xAFFF` | gfx ic51 (BG low plane) |
| `0xB000-0xB7FF` | sound ic52 |
| `0xB800-0xBFFF` | sound ic53 |
| `0xC000-0xC01F` | PROM ic7 (FG palette) |
| `0xC020-0xC03F` | PROM ic6 (BG palette) |
| `0xC040-0xFFFF` | zero padding |

## Verifying against MAME: limits

The core keeps the board's exact clock relationship: one frame is exactly 23,580 CPU
cycles, because the CPU (XTAL/8) and the CRTC (XTAL/16) share one crystal. MAME converts
both clocks to rounded attosecond times, and its raster creeps about 0.75 CPU cycles
later per million CPU cycles (visible in a `beamy`/`beamx` debugger trace). Nibbler
paces the snake with CPU busy-wait loops, so after roughly a thousand frames MAME's
snake can be one movement step behind the core. Comparisons with MAME are exact for
the boot, attract mode and game start (sim/run_sim.ps1 + sim/mame_capture.ps1), but
long gameplay runs are expected to drift apart by that much.

## Sound as built (src/fpga/core/nibbler_sound.v)

The core computes MAME's model one 48 kHz sample at a time:

- Note clock 41.6 Hz (MAME's measured value for Fantasy/Nibbler; the 555 formula
  gives 39 Hz). Tone base clock 344 kHz ("adjusted" in MAME): waveform step rate is
  344 kHz / (256 - note byte); $FF is a rest.
- Channel 0 reads an empty ROM area on Nibbler and is silent; it is not built.
- What the game uses (from a logged MAME game): channel A ($2101 = $08-$0E) for
  music and jingles, waveform register $2102 = $66, channel B ($2100 bit 4,
  $2103 = $10) for the coin sound, and the bomb ($2100 = $80) with tune 6 for the
  death sound.
- Checked against MAME recordings: the coin sound matches sample for sample
  (correlation 0.996-1.0); music matches in pitch, waveform and level, offset in
  phase because MAME applies register writes at the start of each audio block;
  the death sound matches MAME's loudness throughout and decays the same way (the
  noise itself is random).

## Save states, pause and high scores (core features, not original hardware)

- **Save states / sleep**: `src/fpga/core/nibbler_savestate.v`. The CPU is frozen at an
  instruction boundary; RAM ($0000-$1FFF) and a 32-word register vector (CPU registers,
  raster position, IRQ line, sound generator and filter state, video registers) go to
  bridge 0x40000000 (8448 bytes). A load rebuilds the CPU registers with a tiny program
  fed to the CPU from the bus (LDX/TXS/LDA/LDX/LDY/PLP/JMP). Verified in simulation:
  save, run 30 frames, load, run the same 30 frames gives an identical machine state
  (all RAM and registers) and identical pictures.
- **Pause**: the CPU and sound freeze while the Pocket menu is open; the raster keeps
  running so the screen stays up.
- **High scores**: `src/fpga/core/nibbler_hiscore.v`, data slot 2 (`nibbler.hi`),
  RAM table at $0290 (scores, 4 bytes each) and $02D0 (names, 3 bytes each,
  A = $0A ... Z = $23), from MAME's hiscore.dat. The saved table is written in once the
  game has set up its default table; afterwards the table is copied to the save file
  buffer every frame.

## Pocket (APF) behaviour learned on device

- **Bridge reads are taken from a following transaction** (at least for bulk transfers
  such as save states and save file readback). A core that answers with data for the
  current address delivers every word one position early. Latch the word for the
  address on each `bridge_rd` strobe and hold it until the next strobe (as agg23's NES
  core does with a FIFO). Bridge writes carry their own address and data.
- **APF enters/exits reset around save state loads and wake from sleep.** Obeying it
  wipes the restored state. The core starts once the ROM is loaded (and reset is
  released, or a state load arrives) and ignores APF reset afterwards; "Reset Game"
  in the core menu restarts it.
- **Nonvolatile slot size**: with no save file APF records the slot size as 0 and
  saves nothing on exit; the core keeps the High Scores slot's data table entry at
  256 bytes.
- Memories `.sta` files: a header, then the state at offset 0x254; the header's word
  at offset 8 is the end of the state data.
