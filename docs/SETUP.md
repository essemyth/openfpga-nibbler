# Setup: toolchain, Pocket, and debugging

## 1. Software to install (PC)

| What | Why | Notes |
|---|---|---|
| **Quartus Prime Lite** (free) | Compiles the Verilog into an FPGA bitstream | The Pocket's main FPGA is an Intel **Cyclone V 5CEBA4F23C8**. During install, select **Cyclone V device support** (you can skip all other device families). Version **22.1std** is widely used by openFPGA developers; newer Lite releases that still list Cyclone V also work. Download from Intel/Altera's FPGA software download center (free account needed). ~15 GB installed. |
| **Icarus Verilog** or **Verilator** (optional, later) | Fast simulation on the PC without the Pocket | We'll add test benches in `sim/` once there's RTL to test. Simulation is where most bugs get found. |
| **MAME** (you already have 0.289) | Reference behavior | MAME's debugger (`mame nibbler -debug`) lets us compare CPU state, memory, and tile contents against the core. |

Quartus also installs the **USB-Blaster driver** (in `quartus\drivers\usb-blaster*`). If Windows doesn't pick it up automatically, point Device Manager at that folder.

## 2. Hardware for debugging

You do **not** need anything extra to get started. Without JTAG the loop is:
compile, copy `bitstream.rbf_r` to the SD card, launch the core. It works, just slowly.

For real debugging you want **JTAG**:

| Item | Notes |
|---|---|
| **Intel/Altera USB-Blaster** (or **Terasic USB-Blaster**) | Analogue's docs say to use Intel-approved cables only; clones "may have unexpected behavior". The Terasic one is the usual affordable genuine option. USB-Blaster II also works. |
| **Torx T6 screwdriver** | The JTAG header is on the bottom edge, under the rear cover (4 screws). Developer Edition Pockets have a removable door instead. **Don't remove the battery or disassemble further.** Use ESD precautions. |
| **10-pin JTAG ribbon** | Comes with the Blaster. Analogue's [Getting Started](https://www.analogue.co/developer/docs/openfpga/getting-started) page has the diagram showing pin 1. |

What JTAG gets you:
- **Fast reload**: push a new `.sof` in a few seconds while the core runs (`tools\jtag_load.ps1`). Pocket re-initializes the core and reloads the ROM automatically, with no SD card shuffling.
- **SignalTap**: Quartus's built-in logic analyzer. It captures real internal signals (CPU bus, video counters, and so on) from the running FPGA. This is the single most useful debugging tool for hardware cores.

## 3. Pocket settings

On the Pocket: **Tools > Developer** (current firmware has this menu available; update to the latest Analogue OS first):

| Setting | Use |
|---|---|
| **USB SD Access** | Mounts the SD card over USB-C so `tools\deploy.ps1` can copy straight to it. Slow (~700 KB/s), but fine for our ~1 MB package. Analogue+X attaches and Analogue+Y detaches. |
| **Statistics** | Overlay showing video sync rate (should read ~59.84 Hz once our timing is in) and power/temp. |
| **Pause Core Boot** | Halts right after the bitstream loads (press A to continue). Handy for arming SignalTap on reset behavior. |
| **Pause Load Data** | Halts before the ROM is loaded. Arm a SignalTap trigger, then press A to debug ROM loading. |
| **Asset Load Detail** | Shows which file is loading into which slot. |
| **Debug Logging** | Writes a boot log to `/System/Logs/` on the SD card. **First thing to check if the core won't appear or won't start.** |

Only USB SD Access and Builds persist across power cycles. The rest reset when you power off.

## 4. Daily workflow

```powershell
# one-time: build the ROM file from your MAME set (rev 9 by default; -Set nibbler6 for rev 6)
.\tools\build_rom.ps1 -Source <your MAME roms folder>\nibbler

# compile + package (writes pkg\Cores\Essemyth.Nibbler\bitstream.rbf_r)
.\tools\build.ps1

# copy to SD (reader or USB SD Access). Replace E: with your drive letter.
.\tools\deploy.ps1 -Drive E:

# with JTAG: after the core is installed and running, push new builds instantly
.\tools\jtag_load.ps1
```

On the Pocket the core appears under **openFPGA > Arcade > Nibbler**.

## 5. If something goes wrong

- **Core not listed**: a JSON file has a syntax error, or the platform id doesn't match. Check Tools > Developer > Builds, and the boot log.
- **"File not found" / file browser opens**: `nibbler.rom` isn't at `/Assets/nibbler/common/nibbler.rom`, or isn't exactly 65536 bytes.
- **Pocket hangs**: hold power for 5 seconds (undock first if docked).

## References

- [Analogue developer docs](https://www.analogue.co/developer/docs/overview)
- [Getting Started](https://www.analogue.co/developer/docs/openfpga/getting-started) (includes the JTAG header pinout)
- [Debugging Aids](https://www.analogue.co/developer/docs/openfpga/debugging-aids)
- [open-fpga/core-template](https://github.com/open-fpga/core-template) (this project's starting point, v1.3.0)
