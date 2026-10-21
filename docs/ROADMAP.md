# Roadmap

## Done (1.0.0)

- **M0** Toolchain: Quartus build, SD layout, template core on the Pocket
- **M1** Nibbler video timing and ROM loading
- **M2** 6502 CPU and memory map (boot self-test matches MAME cycle for cycle)
- **M3** Tile layers and palette (pixel-identical to MAME)
- **M4** 4-way joystick, coin, DIP switches in the core menu
- **M5** Sound: tone channels, SN76477 noise, discrete filters (matches MAME)
- **M6** Save states and sleep, menu pause, high score saving, platform image
  and icon, rev 6 support, release packaging

## Possible later work

- Cocktail mode (screen flip for player 2)
- MRA files, so ROM managers can build `nibbler.rom` without the PowerShell script
- Rev 6 menu labels (the DIP switch meanings differ from rev 9)
