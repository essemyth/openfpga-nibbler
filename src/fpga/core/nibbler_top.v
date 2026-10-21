//
// Rock-Ola Nibbler board (MAME: snk6502.cpp, "fantasy" memory map).
// See docs/HARDWARE.md for the memory map and register details.
//
// Everything runs on clk_sys (4 x the 11.289 MHz crystal) with clock enables:
//   ce_pix every 8 clk_sys  (5.6445 MHz)
//   cpu_ce every 32 clk_sys (1.411 MHz)
//
// Pause and save states: the CPU and sound can be frozen at an instruction
// boundary (cpu_run = 0) while the raster keeps running, so the picture stays
// up. See nibbler_savestate.v for the save state flow and the register vector
// layout below.
//
module nibbler_top #(
    parameter PIX_DIV_LOG2 = 3      // clk_sys per pixel = 2^n; simulation uses 0 (CPU:pixel ratio is kept)
) (
    input  wire        clk_sys,
    input  wire        reset,       // synchronous to clk_sys; hold until ROMs are loaded

    // ROM loading and save state buffer, clk_74a domain
    input  wire        clk_74a,
    input  wire        bridge_wr,
    input  wire        bridge_rd,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,
    output wire [31:0] ss_bridge_rd_data,   // reads in 0x4xxxxxxx
    output wire [31:0] hs_bridge_rd_data,   // reads in 0x6xxxxxxx

    // input ports, active high, clk_sys domain
    input  wire [7:0]  in0,
    input  wire [7:0]  in1,
    input  wire [7:0]  in2,
    input  wire [7:0]  dsw,

    input  wire        show_debug,  // overlay the debug text screen
    input  wire        pause,       // freeze the game (Pocket menu open)

    // save states, clk_sys domain (APF handshake, synchronized outside)
    input  wire        ss_start,
    input  wire        ss_load,
    output wire        ss_ack,
    output wire        ss_busy,
    output wire        ss_ok,
    output wire        ss_err,

    output wire [23:0] rgb,
    output wire        de,
    output wire        hs,
    output wire        vs,

    output wire signed [15:0] audio,        // 48 kHz mono
    output wire        audio_valid          // one clk_sys pulse per sample
);

    // --------------------------------------------------------------------
    // Clock enables

    // Reset restarts the raster (at a fixed position, see nibbler_video) with
    // the CPU, so interrupt timing relative to the program matches MAME.
    reg  [4:0] phase = 5'd0;
    reg        cpu_run = 1'b1;              // CPU and sound advance
    reg        raster_hold = 1'b0;          // raster stopped during a save state restore
    wire       ss_restore;
    wire [1023:0] ss_regs_in;

    always @(posedge clk_sys) begin
        if (reset)
            phase <= 5'd0;
        else if (ss_restore)
            phase <= ss_regs_in[95:91];
        else if (!raster_hold)
            phase <= phase + 5'd1;
    end

    wire ce_pix = !raster_hold && (PIX_DIV_LOG2 == 0 ? 1'b1 : phase[(PIX_DIV_LOG2 > 0 ? PIX_DIV_LOG2 - 1 : 0):0] == 0);
    wire cpu_ce = cpu_run && phase[PIX_DIV_LOG2 + 1:0] == 0;   // CPU cycle = 4 pixels

    // 48 kHz audio sample tick in game time: clk_sys is 45.156 MHz on hardware;
    // in simulation each clk_sys stands for 2^(3 - PIX_DIV_LOG2) of those.
    localparam [31:0] SND_INC = 32'd48000 << (3 - PIX_DIV_LOG2);
    reg  [31:0] snd_acc = 32'd0;
    reg         snd_tick = 1'b0;
    reg         snd_hold = 1'b0;        // after a restore, until the CPU is back at the saved point
    always @(posedge clk_sys) begin
        snd_tick <= 1'b0;
        if (ss_restore) begin
            snd_acc <= ss_regs_in[127:96];
        end else if (cpu_run && !snd_hold) begin
            if (snd_acc + SND_INC >= 32'd45156000) begin
                snd_acc  <= snd_acc + SND_INC - 32'd45156000;
                snd_tick <= 1'b1;
            end else begin
                snd_acc  <= snd_acc + SND_INC;
            end
        end
    end

    // --------------------------------------------------------------------
    // CPU

    wire        cpu_rw, cpu_sync, cpu_vp_n;
    wire [15:0] cpu_a;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire [63:0] cpu_regs;           // PC[63:48], S[47:32] (16 bit), P, Y, X, A[7:0]

    // Reads at $4000 and above get one wait state (RDY is pulled for one
    // cycle). Writes are never delayed.
    reg  waited = 1'b0;
    wire slow_read = cpu_rw && cpu_a[15:14] != 2'b00;
    wire cpu_rdy   = !(slow_read && !waited);
    always @(posedge clk_sys)
        if (reset || ss_restore)
            waited <= 1'b0;
        else if (cpu_ce)
            waited <= slow_read && !waited;

    reg irq_n = 1'b1;
    wire nmi_n = !(in2[0] || in2[1]);       // a coin switch pulls NMI

    // Save state restore stub. After a load the CPU is reset and fed this
    // program from the bus (writes are blocked), which rebuilds its registers
    // and jumps back to the saved PC:
    //   FF00  LDX #S-1 / TXS / LDA #A / LDX #X / LDY #Y / PLP / JMP pc
    // PLP's stack read returns the saved P; the reset vector points at FF00.
    reg        stub_active = 1'b0;
    reg  [3:0] stub_rst = 4'd0;
    reg  [1:0] stub_div = 2'd0;
    reg  [7:0] stub_a, stub_x, stub_y, stub_p, stub_s;
    reg [15:0] stub_pc;
    wire       stub_ce = stub_active && stub_rst == 4'd0 && stub_div == 2'd0;
    wire       stub_start, stub_done;

    reg  [7:0] stub_byte;
    always @* begin
        case (cpu_a[7:0])
            8'h00: stub_byte = 8'hA2;           // LDX #
            8'h01: stub_byte = stub_s - 8'd1;
            8'h02: stub_byte = 8'h9A;           // TXS
            8'h03: stub_byte = 8'hA9;           // LDA #
            8'h04: stub_byte = stub_a;
            8'h05: stub_byte = 8'hA2;           // LDX #
            8'h06: stub_byte = stub_x;
            8'h07: stub_byte = 8'hA0;           // LDY #
            8'h08: stub_byte = stub_y;
            8'h09: stub_byte = 8'h28;           // PLP
            8'h0A: stub_byte = 8'h4C;           // JMP
            8'h0B: stub_byte = stub_pc[7:0];
            8'h0C: stub_byte = stub_pc[15:8];
            8'hFC: stub_byte = 8'h00;           // reset vector -> FF00
            8'hFD: stub_byte = 8'hFF;
            default: stub_byte = 8'hEA;
        endcase
    end
    wire [7:0] stub_din = cpu_a[15:8] == 8'hFF ? stub_byte :
                          cpu_a[15:8] == 8'h01 ? stub_p : 8'h00;

    always @(posedge clk_sys) begin
        stub_div <= stub_div + 2'd1;
        if (stub_start) begin
            stub_active <= 1'b1;
            stub_rst    <= 4'd15;
        end else if (stub_active) begin
            if (stub_rst != 4'd0) stub_rst <= stub_rst - 4'd1;
            if (stub_ce && cpu_rw && cpu_a == 16'hFF0C) stub_active <= 1'b0;   // JMP's last operand
        end
    end
    assign stub_done = stub_active && stub_ce && cpu_rw && cpu_a == 16'hFF0C;

    t65_wrap cpu (
        .clk   ( clk_sys ),
        .ce    ( stub_active ? stub_ce : cpu_ce ),
        .res_n ( !(reset || (stub_active && stub_rst != 4'd0)) ),
        .rdy   ( stub_active ? 1'b1 : cpu_rdy ),
        .irq_n ( stub_active ? 1'b1 : irq_n ),
        .nmi_n ( stub_active ? 1'b1 : nmi_n ),
        .rw_n  ( cpu_rw ),
        .sync  ( cpu_sync ),
        .vp_n  ( cpu_vp_n ),
        .addr  ( cpu_a ),
        .din   ( stub_active ? stub_din : cpu_rw ? cpu_din : cpu_dout ),   // T65 wants DO looped back on writes
        .dout  ( cpu_dout ),
        .regs  ( cpu_regs )
    );

    wire cpu_wr = cpu_ce && !cpu_rw;

    // --------------------------------------------------------------------
    // Run control: freeze at an instruction boundary for pause or a save;
    // stop at once for a load.
    //
    // The freeze happens just after an opcode fetch completes, when the
    // previous instruction's results have been written (T65, like the 6502,
    // finishes an instruction during the next opcode fetch). The saved PC is
    // that opcode's address, so a restored CPU fetches it again. To keep the
    // rest of the machine in step:
    //   - the raster and IRQ line saved are the ones from the start of that
    //     fetch; on restore the raster is held still until the CPU is
    //     released, so both resume exactly together
    //   - the sound timer is saved at the freeze, and after a restore it is
    //     held until the CPU has re-fetched up to the same point
    //   - for a save the raster also stops while the state is copied, so
    //     saving does not shift the running game's timing. A menu pause keeps
    //     the raster running so the Pocket always has a picture.

    wire        ss_hold_req, ss_force_stop;
    wire        hs_hold_req;
    wire [31:0] ss_dbg;
    wire [15:0] hs_dbg;
    wire [31:0] ss_dbg_magic, hs_dbg_first;
    wire        hold_req = pause || ss_hold_req || hs_hold_req;
    wire        at_boundary = cpu_ce && cpu_sync && cpu_rdy;
    wire        fetch_start = cpu_ce && cpu_sync && !waited;
    wire [8:0]  h, v;
    reg  [8:0]  fs_h, fs_v, frz_h, frz_v;
    reg  [4:0]  fs_phase, frz_phase;
    reg         fs_irq_n, frz_irq_n;
    reg  [15:0] last_pc = 16'd0;

    always @(posedge clk_sys) begin
        if (fetch_start) begin
            fs_h     <= h;
            fs_v     <= v;
            fs_phase <= phase;
            fs_irq_n <= irq_n;
        end

        if (ss_force_stop) begin
            cpu_run <= 1'b0;
        end else if (reset) begin
            cpu_run <= 1'b1;
        end else if (cpu_run && hold_req && at_boundary) begin
            cpu_run   <= 1'b0;
            // a fetch without a wait state starts and ends on this edge
            frz_h     <= fetch_start ? h     : fs_h;
            frz_v     <= fetch_start ? v     : fs_v;
            frz_phase <= fetch_start ? phase : fs_phase;
            frz_irq_n <= fetch_start ? irq_n : fs_irq_n;
        end else if (!cpu_run && !hold_req && !stub_active) begin
            cpu_run <= 1'b1;
        end

        if (ss_restore)
            raster_hold <= 1'b1;
        else if (cpu_run && hold_req && at_boundary && ss_hold_req && !pause)
            raster_hold <= 1'b1;                // freezing for a save
        else if (!ss_hold_req && !ss_force_stop && !stub_active)
            raster_hold <= 1'b0;

        if (ss_restore)
            snd_hold <= 1'b1;
        else if (at_boundary)
            snd_hold <= 1'b0;

        if (at_boundary || (stub_active && stub_ce && cpu_sync)) last_pc <= cpu_a;
        if (stub_done) last_pc <= stub_pc;
    end

    // --------------------------------------------------------------------
    // Memory bus: the CPU's, or the save state engine's while it is copying

    wire        ss_bus, ss_we, hs_bus, hs_bus_we;
    wire [15:0] ss_a, hs_bus_a;
    wire [7:0]  ss_wd, hs_bus_wd;
    wire [15:0] bus_a  = ss_bus ? ss_a  : hs_bus ? hs_bus_a  : cpu_a;
    wire        bus_we = ss_bus ? ss_we : hs_bus ? hs_bus_we : cpu_wr && !stub_active;
    wire [7:0]  bus_wd = ss_bus ? ss_wd : hs_bus ? hs_bus_wd : cpu_dout;

    // --------------------------------------------------------------------
    // Address decode

    wire sel_ram   = bus_a[15:10] == 6'b0000_00;      // $0000-$03FF
    wire sel_vram2 = bus_a[15:10] == 6'b0000_01;      // $0400-$07FF foreground codes
    wire sel_vram  = bus_a[15:10] == 6'b0000_10;      // $0800-$0BFF background codes
    wire sel_color = bus_a[15:10] == 6'b0000_11;      // $0C00-$0FFF
    wire sel_char  = bus_a[15:12] == 4'h1;            // $1000-$1FFF
    wire sel_rom   = (bus_a >= 16'h3000 && bus_a < 16'hC000) || bus_a[15:12] == 4'hF;

    // $3000-$BFFF -> file 0x0000-0x8FFF; $F000-$FFFF mirrors $8000-$8FFF (vectors)
    wire [15:0] rom_off = cpu_a[15:12] == 4'hF ? {4'h5, cpu_a[11:0]} : cpu_a - 16'h3000;

    // --------------------------------------------------------------------
    // Memories

    // Port A of each RAM is the CPU; port B is the video pipeline. The video
    // needs two color RAM reads and both char RAM bit planes per pixel, so
    // color RAM has a write-only mirror and char RAM is split by plane.

    wire [7:0] ram_q, vram2_q, vram_q, color_q, char_hi_q, char_lo_q, rom_q;

    wire [9:0]  bg_code_addr, bg_color_addr, fg_code_addr, fg_color_addr;
    wire [7:0]  bg_code, bg_color, fg_code, fg_color;
    wire [11:0] gfx_addr;
    wire [7:0]  gfx_hi, gfx_lo;
    wire [10:0] char_addr;
    wire [7:0]  char_hi, char_lo;
    wire [5:0]  prom_addr;
    wire [7:0]  prom_data;
    wire [11:0] snd_rom_addr;
    wire [7:0]  snd_rom_data;
    wire [9:0]  hs_addr;
    wire [7:0]  hs_q;

    dpram #(.AW(10)) work_ram (
        .clk(clk_sys), .we_a(bus_we && sel_ram), .addr_a(bus_a[9:0]), .din_a(bus_wd), .dout_a(ram_q),
        .en_b(1'b1), .addr_b(hs_addr), .dout_b(hs_q)
    );
    dpram #(.AW(10)) vram2_ram (
        .clk(clk_sys), .we_a(bus_we && sel_vram2), .addr_a(bus_a[9:0]), .din_a(bus_wd), .dout_a(vram2_q),
        .en_b(ce_pix), .addr_b(fg_code_addr), .dout_b(fg_code)
    );
    dpram #(.AW(10)) vram_ram (
        .clk(clk_sys), .we_a(bus_we && sel_vram), .addr_a(bus_a[9:0]), .din_a(bus_wd), .dout_a(vram_q),
        .en_b(ce_pix), .addr_b(bg_code_addr), .dout_b(bg_code)
    );
    dpram #(.AW(10)) color_ram (
        .clk(clk_sys), .we_a(bus_we && sel_color), .addr_a(bus_a[9:0]), .din_a(bus_wd), .dout_a(color_q),
        .en_b(ce_pix), .addr_b(bg_color_addr), .dout_b(bg_color)
    );
    dpram #(.AW(10)) color_ram_mirror (
        .clk(clk_sys), .we_a(bus_we && sel_color), .addr_a(bus_a[9:0]), .din_a(bus_wd), .dout_a(),
        .en_b(ce_pix), .addr_b(fg_color_addr), .dout_b(fg_color)
    );
    dpram #(.AW(11)) char_hi_ram (          // $1000-$17FF: high bit plane
        .clk(clk_sys), .we_a(bus_we && sel_char && !bus_a[11]), .addr_a(bus_a[10:0]), .din_a(bus_wd), .dout_a(char_hi_q),
        .en_b(ce_pix), .addr_b(char_addr), .dout_b(char_hi)
    );
    dpram #(.AW(11)) char_lo_ram (          // $1800-$1FFF: low bit plane
        .clk(clk_sys), .we_a(bus_we && sel_char && bus_a[11]), .addr_a(bus_a[10:0]), .din_a(bus_wd), .dout_a(char_lo_q),
        .en_b(ce_pix), .addr_b(char_addr), .dout_b(char_lo)
    );

    nibbler_roms roms (
        .clk_74a        ( clk_74a ),
        .bridge_wr      ( bridge_wr ),
        .bridge_addr    ( bridge_addr ),
        .bridge_wr_data ( bridge_wr_data ),
        .clk_sys        ( clk_sys ),
        .cpu_addr       ( rom_off ),
        .cpu_data       ( rom_q ),
        .vid_en         ( ce_pix ),
        .gfx_addr       ( gfx_addr ),
        .gfx_hi         ( gfx_hi ),
        .gfx_lo         ( gfx_lo ),
        .prom_addr      ( prom_addr ),
        .prom_data      ( prom_data ),
        .snd_addr       ( snd_rom_addr ),
        .snd_data       ( snd_rom_data )
    );

    // --------------------------------------------------------------------
    // Sound ($2100-$2103; $2103 is shared with the video control register)

    wire         sound_idle;
    wire [575:0] sound_ss;

    nibbler_sound sound (
        .clk          ( clk_sys ),
        .reset        ( reset ),
        .tick         ( snd_tick ),
        .wr           ( cpu_wr && !stub_active && cpu_a[15:2] == 14'h0840 ),
        .reg_sel      ( cpu_a[1:0] ),
        .din          ( cpu_dout ),
        .rom_addr     ( snd_rom_addr ),
        .rom_data     ( snd_rom_data ),
        .sample       ( audio ),
        .sample_valid ( audio_valid ),
        .idle         ( sound_idle ),
        .ss_out       ( sound_ss ),
        .ss_restore   ( ss_restore ),
        .ss_in        ( ss_regs_in[895:320] )
    );

    // --------------------------------------------------------------------
    // I/O registers

    reg [4:0] crtc_index;
    reg [7:0] crtc_reg [0:17];
    reg [7:0] ctrl;             // $2103: bits 2-0 back color, bit 3 /char bank, bit 7 flip
    reg [7:0] scroll_x, scroll_y;

    integer i;
    initial begin
        for (i = 0; i < 18; i = i + 1) crtc_reg[i] = 8'd0;
        crtc_index = 5'd0;
        ctrl = 8'd0;
        scroll_x = 8'd0;
        scroll_y = 8'd0;
    end

    always @(posedge clk_sys) begin
        if (ss_restore) begin
            {ctrl, scroll_x, scroll_y}  <= ss_regs_in[159:136];
            crtc_index                  <= ss_regs_in[132:128];
            for (i = 0; i < 18; i = i + 1)
                crtc_reg[i] <= ss_regs_in[160 + i * 8 +: 8];
        end else if (cpu_wr && !stub_active) begin
            case (cpu_a)
                16'h2000: crtc_index <= cpu_dout[4:0];
                16'h2001: if (crtc_index < 5'd18) crtc_reg[crtc_index] <= cpu_dout;
                16'h2103: ctrl <= cpu_dout;
                16'h2200: scroll_x <= cpu_dout;
                16'h2300: scroll_y <= cpu_dout;
                default: ;
            endcase
        end
    end

    // --------------------------------------------------------------------
    // Read mux for the CPU (and the save state engine). Unmapped reads
    // return 0, as in MAME.

    always @* begin
        cpu_din = 8'h00;
        if      (sel_ram)           cpu_din = ram_q;
        else if (sel_vram2)         cpu_din = vram2_q;
        else if (sel_vram)          cpu_din = vram_q;
        else if (sel_color)         cpu_din = color_q;
        else if (sel_char)          cpu_din = bus_a[11] ? char_lo_q : char_hi_q;
        else if (sel_rom)           cpu_din = rom_q;
        else if (bus_a == 16'h2104) cpu_din = in0;
        else if (bus_a == 16'h2105) cpu_din = in1;
        else if (bus_a == 16'h2106) cpu_din = dsw;
        else if (bus_a == 16'h2107) cpu_din = in2;
    end

    // --------------------------------------------------------------------
    // Video

    wire       vblank_start;
    wire       overlay_pix;

    nibbler_video video (
        .clk_sys       ( clk_sys ),
        .reset         ( reset ),
        .ce_pix        ( ce_pix ),
        .ss_restore    ( ss_restore ),
        .ss_h          ( ss_regs_in[81:73] ),
        .ss_v          ( ss_regs_in[72:64] ),
        .h             ( h ),
        .v             ( v ),
        .vblank_start  ( vblank_start ),
        .scroll_x      ( scroll_x ),
        .scroll_y      ( scroll_y ),
        .ctrl          ( ctrl ),
        .bg_code_addr  ( bg_code_addr ),
        .bg_code       ( bg_code ),
        .bg_color_addr ( bg_color_addr ),
        .bg_color      ( bg_color ),
        .fg_code_addr  ( fg_code_addr ),
        .fg_code       ( fg_code ),
        .fg_color_addr ( fg_color_addr ),
        .fg_color      ( fg_color ),
        .gfx_addr      ( gfx_addr ),
        .gfx_hi        ( gfx_hi ),
        .gfx_lo        ( gfx_lo ),
        .char_addr     ( char_addr ),
        .char_hi       ( char_hi ),
        .char_lo       ( char_lo ),
        .prom_addr     ( prom_addr ),
        .prom_data     ( prom_data ),
        .overlay_pix   ( overlay_pix ),
        .show_overlay  ( show_debug ),
        .rgb           ( rgb ),
        .de            ( de ),
        .hs            ( hs ),
        .vs            ( vs )
    );

    // One IRQ per frame at vblank, held until the CPU takes it (MAME HOLD_LINE).
    // T65 drives VP_n low while fetching the IRQ vector.
    always @(posedge clk_sys) begin
        if (reset)
            irq_n <= 1'b1;
        else if (ss_restore)
            irq_n <= ss_regs_in[90];
        else if (vblank_start)
            irq_n <= 1'b0;
        else if (cpu_ce && !cpu_vp_n)
            irq_n <= 1'b1;
    end

    // --------------------------------------------------------------------
    // Save states
    //
    // Register vector, 32-bit words (word n at bits [32n+31:32n]):
    //   0      P, Y, X, A                     (MSB first)
    //   1      0, S, resume PC
    //   2      phase[4:0], IRQ line, 0, h[8:0], v[8:0]
    //   3      48 kHz sample accumulator
    //   4      ctrl, scroll x, scroll y, CRTC index
    //   5-9    CRTC registers 0-17 (register 0 in the low byte)
    //   10-27  sound state (nibbler_sound ss_out)
    //   31     magic, added by nibbler_savestate

    wire [1023:0] ss_regs_out;
    assign ss_regs_out[31:0]    = cpu_regs[31:0];
    assign ss_regs_out[63:32]   = {8'd0, cpu_regs[39:32], last_pc};
    assign ss_regs_out[95:64]   = {frz_phase, frz_irq_n, 8'd0, frz_h, frz_v};
    assign ss_regs_out[127:96]  = snd_acc;      // stopped since the freeze
    assign ss_regs_out[159:128] = {ctrl, scroll_x, scroll_y, 3'd0, crtc_index};
    genvar gi;
    generate
        for (gi = 0; gi < 18; gi = gi + 1) begin : crtc_pack
            assign ss_regs_out[160 + gi * 8 +: 8] = crtc_reg[gi];
        end
    endgenerate
    assign ss_regs_out[319:304] = 16'd0;
    assign ss_regs_out[895:320] = sound_ss;
    assign ss_regs_out[1023:896] = 128'd0;

    always @(posedge clk_sys) begin
        if (ss_restore) begin
            {stub_p, stub_y, stub_x, stub_a} <= ss_regs_in[31:0];
            stub_s  <= ss_regs_in[55:48];
            stub_pc <= ss_regs_in[47:32];
        end
    end

    nibbler_savestate savestate (
        .clk            ( clk_sys ),
        .reset          ( reset ),
        .start          ( ss_start ),
        .load           ( ss_load ),
        .ack            ( ss_ack ),
        .busy           ( ss_busy ),
        .ok             ( ss_ok ),
        .err            ( ss_err ),
        .hold_req       ( ss_hold_req ),
        .force_stop     ( ss_force_stop ),
        .frozen         ( !cpu_run ),
        .sound_idle     ( sound_idle ),
        .ss_bus         ( ss_bus ),
        .ss_a           ( ss_a ),
        .ss_we          ( ss_we ),
        .ss_wd          ( ss_wd ),
        .ss_rd          ( cpu_din ),
        .regs_out       ( ss_regs_out ),
        .regs_in        ( ss_regs_in ),
        .restore        ( ss_restore ),
        .stub_start     ( stub_start ),
        .stub_done      ( stub_done ),
        .clk_74a        ( clk_74a ),
        .bridge_wr      ( bridge_wr ),
        .bridge_rd      ( bridge_rd ),
        .bridge_addr    ( bridge_addr ),
        .bridge_wr_data ( bridge_wr_data ),
        .bridge_rd_data ( ss_bridge_rd_data ),
        .dbg            ( ss_dbg ),
        .dbg_magic      ( ss_dbg_magic )
    );

    // --------------------------------------------------------------------
    // High score save file (work RAM port B)

    nibbler_hiscore hiscore (
        .clk            ( clk_sys ),
        .reset          ( reset ),
        .frame          ( vblank_start ),
        .ram_addr       ( hs_addr ),
        .ram_q          ( hs_q ),
        .hold_req       ( hs_hold_req ),
        .frozen         ( !cpu_run ),
        .bus            ( hs_bus ),
        .bus_a          ( hs_bus_a ),
        .bus_we         ( hs_bus_we ),
        .bus_wd         ( hs_bus_wd ),
        .clk_74a        ( clk_74a ),
        .bridge_wr      ( bridge_wr ),
        .bridge_rd      ( bridge_rd ),
        .bridge_addr    ( bridge_addr ),
        .bridge_wr_data ( bridge_wr_data ),
        .bridge_rd_data ( hs_bridge_rd_data ),
        .dbg            ( hs_dbg ),
        .dbg_first      ( hs_dbg_first )
    );

    // --------------------------------------------------------------------
    // Debug state for the overlay

    reg [15:0] shown_pc = 16'd0;
    reg [15:0] irq_count = 16'd0, frame_count = 16'd0, vram_writes = 16'd0, char_writes = 16'd0;
    reg [7:0]  nmi_count = 8'd0;
    reg        vp_seen = 1'b0;

    always @(posedge clk_sys) begin
        if (vblank_start) begin
            shown_pc <= last_pc;
            frame_count <= frame_count + 16'd1;
        end

        // count each IRQ once (VP_n is low for two cycles)
        if (cpu_ce) begin
            vp_seen <= !cpu_vp_n;
            if (!cpu_vp_n && !vp_seen) irq_count <= irq_count + 16'd1;
            if (cpu_rdy && cpu_rw && cpu_a == 16'hFFFA) nmi_count <= nmi_count + 8'd1;
        end

        if (cpu_wr && (sel_vram2 || sel_vram || sel_color)) vram_writes <= vram_writes + 16'd1;
        if (cpu_wr && sel_char) char_writes <= char_writes + 16'd1;
    end

    debug_overlay overlay (
        .h           ( h ),
        .v           ( v ),
        .pc          ( shown_pc ),
        .irq_count   ( irq_count ),
        .nmi_count   ( nmi_count ),
        .frame_count ( frame_count ),
        .vram_writes ( vram_writes ),
        .char_writes ( char_writes ),
        .ctrl        ( ctrl ),
        .crtc_r0     ( crtc_reg[0] ),
        .crtc_r1     ( crtc_reg[1] ),
        .crtc_r2     ( crtc_reg[2] ),
        .crtc_r4     ( crtc_reg[4] ),
        .crtc_r6     ( crtc_reg[6] ),
        .crtc_r7     ( crtc_reg[7] ),
        .scroll_x    ( scroll_x ),
        .scroll_y    ( scroll_y ),
        .in0         ( in0 ),
        .in2         ( in2 ),
        .dsw         ( dsw ),
        .ss_dbg      ( ss_dbg ),
        .hs_dbg      ( hs_dbg ),
        .ss_magic    ( ss_dbg_magic ),
        .hs_first    ( hs_dbg_first ),
        .pix         ( overlay_pix )
    );

endmodule
