//
// Testbench: loads nibbler.rom over the bridge (as APF does), releases reset,
// logs every executed instruction as "PC cycle" for comparison against a MAME
// trace (sim/compare_trace.ps1), and can save frames as images.
//
// Plusargs:
//   +rom=<path>        packed ROM (tools/build_rom.ps1 output)
//   +trace=<path>      instruction trace file ("none" to disable)
//   +instructions=<n>  stop after n instructions (default 100000)
//   +frames=<a,b,...>  save these frames (1 = first frame after reset) as
//                      <outdir>/frame_<n>.ppm, native 256x224 orientation;
//                      the run stops after the last one
//   +outdir=<path>     directory for frame images (default .)
//   +inputs=<f:p:hh,...>  at the vblank after frame f, set input port p (0-2 =
//                      IN0-IN2) to hex value hh. MAME applies the same event
//                      at screen frame_number f (see sim/mame_inputs.lua).
//
`timescale 1ns/1ps

module tb_nibbler;

    parameter PIX_DIV_LOG2 = 0;     // pixel every clk_sys, CPU every 4: 8x faster than hardware, same CPU:video ratio

    reg clk_sys = 0;
    reg clk_74a = 0;
    always #11.07 clk_sys = ~clk_sys;   // 45.156 MHz
    always #6.734 clk_74a = ~clk_74a;   // 74.25 MHz

    reg         reset = 1;
    reg         bridge_wr = 0;
    reg         bridge_rd = 0;
    reg  [31:0] bridge_addr = 0;
    reg  [31:0] bridge_wr_data = 0;
    reg  [7:0]  in0 = 0, in1 = 0, in2 = 0;
    reg         ss_start = 0, ss_load = 0;
    wire        ss_busy, ss_ok, ss_err;
    wire [31:0] ss_rd_data, hs_rd_data;

    wire [23:0] rgb;
    wire        de, hs, vs;
    wire signed [15:0] audio;
    wire        audio_valid;

    nibbler_top #(.PIX_DIV_LOG2(PIX_DIV_LOG2)) dut (
        .clk_sys        ( clk_sys ),
        .reset          ( reset ),
        .clk_74a        ( clk_74a ),
        .bridge_wr      ( bridge_wr ),
        .bridge_rd      ( bridge_rd ),
        .bridge_addr    ( bridge_addr ),
        .bridge_wr_data ( bridge_wr_data ),
        .in0            ( in0 ),
        .in1            ( in1 ),
        .in2            ( in2 ),
        .dsw            ( 8'h00 ),
        .show_debug     ( 1'b0 ),
        .pause          ( 1'b0 ),
        .ss_bridge_rd_data ( ss_rd_data ),
        .hs_bridge_rd_data ( hs_rd_data ),
        .ss_start       ( ss_start ),
        .ss_load        ( ss_load ),
        .ss_ack         ( ),
        .ss_busy        ( ss_busy ),
        .ss_ok          ( ss_ok ),
        .ss_err         ( ss_err ),
        .rgb            ( rgb ),
        .de             ( de ),
        .hs             ( hs ),
        .vs             ( vs ),
        .audio          ( audio ),
        .audio_valid    ( audio_valid )
    );

    string rom_path, trace_path, frames_arg, inputs_arg, outdir, hs_path;
    typedef struct { int frame; int port; int value; } input_event_t;
    input_event_t input_events [$];
    int    max_instr;
    int    fd_rom, fd_trace;
    byte   rom [0:65535];
    int    dump_frames [$];

    longint cpu_cycles = 0;
    int     instr = 0;

    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) rom_path = "nibbler.rom";
        if (!$value$plusargs("trace=%s", trace_path)) trace_path = "sim_trace.log";
        if (!$value$plusargs("instructions=%d", max_instr)) max_instr = 100000;
        if (!$value$plusargs("outdir=%s", outdir)) outdir = ".";
        if ($value$plusargs("frames=%s", frames_arg)) begin
            automatic int n = 0;
            for (int i = 0; i <= frames_arg.len(); i++) begin
                if (i == frames_arg.len() || frames_arg[i] == ",") begin
                    dump_frames.push_back(n);
                    n = 0;
                end else begin
                    n = n * 10 + (frames_arg[i] - "0");
                end
            end
            max_instr = 0;      // frames decide when to stop
        end
        if ($test$plusargs("ss_test")) max_instr = 0;      // the save state test decides when to stop
        if ($value$plusargs("inputs=%s", inputs_arg)) begin
            automatic int f = 0, p = 0, val = 0, field = 0;
            for (int i = 0; i <= inputs_arg.len(); i++) begin
                if (i == inputs_arg.len() || inputs_arg[i] == ",") begin
                    input_events.push_back('{f, p, val});
                    f = 0; p = 0; val = 0; field = 0;
                end else if (inputs_arg[i] == ":") begin
                    field++;
                end else if (field == 0) begin
                    f = f * 10 + (inputs_arg[i] - "0");
                end else if (field == 1) begin
                    p = inputs_arg[i] - "0";
                end else begin
                    val = val * 16 + (inputs_arg[i] <= "9" ? inputs_arg[i] - "0" : (inputs_arg[i] | 8'h20) - "a" + 10);
                end
            end
        end

        fd_rom = $fopen(rom_path, "rb");
        if (fd_rom == 0) $fatal(1, "cannot open %s", rom_path);
        void'($fread(rom, fd_rom));
        $fclose(fd_rom);

        fd_trace = trace_path == "none" ? 0 : $fopen(trace_path, "w");

        // load the ROM regions, big-endian words, like the APF bridge
        repeat (4) @(posedge clk_74a);
        for (int a = 0; a < 'hC040; a += 4) begin
            @(posedge clk_74a);
            bridge_addr    <= a;
            bridge_wr_data <= {rom[a], rom[a+1], rom[a+2], rom[a+3]};
            bridge_wr      <= 1;
            @(posedge clk_74a);
            bridge_wr      <= 0;
        end

        // optional high score save file (data slot 2), loaded before reset
        // exit as APF does
        if ($value$plusargs("hs_file=%s", hs_path)) begin
            automatic byte hs [0:255];
            automatic int fd_hs;
            fd_hs = $fopen(hs_path, "rb");
            if (fd_hs == 0) $fatal(1, "cannot open %s", hs_path);
            void'($fread(hs, fd_hs));
            $fclose(fd_hs);
            for (int a = 0; a < 256; a += 4) begin
                @(posedge clk_74a);
                bridge_addr    <= 32'h60000000 + a;
                bridge_wr_data <= {hs[a], hs[a+1], hs[a+2], hs[a+3]};
                bridge_wr      <= 1;
                @(posedge clk_74a);
                bridge_wr      <= 0;
            end
            $display("high score file %s loaded", hs_path);
        end

        repeat (8) @(posedge clk_sys);
        reset <= 0;
        $display("ROM loaded, reset released at %t", $time);
    end

    // Log each instruction at its (completed) opcode fetch. When the CPU takes
    // an interrupt, the opcode fetch it discards is logged too; MAME's trace
    // does the same (followed by "interrupted at ...").
    always @(posedge clk_sys) begin
        if (!reset && dut.cpu_ce) begin
            if (dut.cpu_sync && dut.cpu_rdy) begin
                if (fd_trace) $fdisplay(fd_trace, "%04X %0d", dut.cpu_a, cpu_cycles);
                instr++;
                if (max_instr > 0 && instr >= max_instr) begin
                    $display("%0d instructions, %0d CPU cycles", instr, cpu_cycles);
                    if (fd_trace) $fclose(fd_trace);
                    $finish;
                end
            end
            cpu_cycles++;
        end
    end

    // Audio capture: every 48 kHz sample, little-endian int16, to <outdir>/audio.raw
    int fd_audio = 0;
    always @(posedge clk_sys) begin
        if (!reset && audio_valid) begin
            if (fd_audio == 0) fd_audio = $fopen($sformatf("%s/audio.raw", outdir), "wb");
            $fwrite(fd_audio, "%c%c", audio[7:0], audio[15:8]);
        end
    end

    // Frame capture: frames are counted from vsync; pixels are taken at each
    // pixel enable while DE is high.
    reg [23:0] fb [0:223][0:255];
    int frame = 0, px = 0, py = 0;
    bit line_had_de = 0;

    task automatic save_frame(int n);
        save_frame_named($sformatf("%0d", n));
    endtask

    task automatic save_frame_named(string name);
        int fd = $fopen($sformatf("%s/frame_%s.ppm", outdir, name), "wb");
        $fwrite(fd, "P6\n256 224\n255\n");
        for (int y = 0; y < 224; y++)
            for (int x = 0; x < 256; x++)
                $fwrite(fd, "%c%c%c", fb[y][x][23:16], fb[y][x][15:8], fb[y][x][7:0]);
        $fclose(fd);
        $display("saved frame %s (%0d instructions)", name, instr);
    endtask

    always @(posedge clk_sys) begin
        if (!reset && dut.ce_pix) begin
            // Input events for frame N apply at the start of the vblank after
            // frame N's vsync, which is when MAME's frame notifier for
            // frame_number N runs (before that vblank's IRQ).
            if (dut.vblank_start) begin
                while (input_events.size() > 0 && input_events[0].frame == frame - 1) begin
                    case (input_events[0].port)
                        0: in0 <= input_events[0].value;
                        1: in1 <= input_events[0].value;
                        2: in2 <= input_events[0].value;
                    endcase
                    void'(input_events.pop_front());
                end
            end
            if (vs) begin
                if (dump_frames.size() > 0 && frame == dump_frames[0]) begin
                    save_frame(frame);
                    void'(dump_frames.pop_front());
                    if (dump_frames.size() == 0 && !$test$plusargs("ss_test")) begin
                        if (fd_trace) $fclose(fd_trace);
                        if (fd_audio) $fclose(fd_audio);
                        $finish;
                    end
                end
                frame++;
                py = 0;
            end
            if (hs) begin
                if (line_had_de) py++;
                px = 0;
                line_had_de = 0;
            end
            if (de) begin
                if (py < 224 && px < 256) fb[py][px] = rgb;
                px++;
                line_had_de = 1;
            end
        end
    end

    // Save state test (+ss_test=N,K): save at frame N (S1); save again K frames
    // later (S2); load S1; after the same K frames save again (S3). An exact
    // restore makes S3 identical to S2. Frames at S2 and S3 are written as
    // frame_ss_a.ppm / frame_ss_b.ppm. No input events may follow frame N.
    localparam SS_WORDS = 'h840;
    reg [31:0] ss_s1 [0:SS_WORDS-1];
    reg [31:0] ss_s2 [0:SS_WORDS-1];
    reg [31:0] ss_s3 [0:SS_WORDS-1];

    task automatic wait_vs();
        @(posedge clk_sys iff (dut.ce_pix && vs));
    endtask

    // A bridge read as APF's io_bridge_peripheral does it: address, a few
    // cycles, then the read strobe; the core holds that word from the strobe
    // on (APF takes it during the following transaction).
    task automatic bridge_read(input [31:0] addr, output [31:0] data);
        @(posedge clk_74a) bridge_addr <= addr;
        repeat (4) @(posedge clk_74a);
        bridge_rd <= 1;
        @(posedge clk_74a) bridge_rd <= 0;
        repeat (2) @(posedge clk_74a);
        data = addr[31:28] == 4'h4 ? ss_rd_data : hs_rd_data;
    endtask

    task automatic ss_save(output reg [31:0] img [0:SS_WORDS-1]);
        ss_start = 1;
        @(posedge clk_sys iff ss_busy);
        @(posedge clk_sys iff (!ss_busy && (ss_ok || ss_err)));
        ss_start = 0;
        if (ss_err) $display("save state: save reported an error");
        for (int w = 0; w < SS_WORDS; w++) begin
            bridge_read(32'h40000000 + w * 4, img[w]);
        end
    endtask

    task automatic ss_restore(input reg [31:0] img [0:SS_WORDS-1]);
        for (int w = 0; w < SS_WORDS; w++) begin
            @(posedge clk_74a);
            bridge_addr    <= 32'h40000000 + w * 4;
            bridge_wr_data <= img[w];
            bridge_wr      <= 1;
            @(posedge clk_74a);
            bridge_wr      <= 0;
        end
        ss_load = 1;
        @(posedge clk_sys iff ss_busy);
        @(posedge clk_sys iff (!ss_busy && (ss_ok || ss_err)));
        ss_load = 0;
        if (ss_err) $display("save state: load reported an error");
    endtask

    string ss_arg;
    initial begin
        int n, k, diffs;
        if ($value$plusargs("ss_test=%s", ss_arg)) begin
            void'($sscanf(ss_arg, "%d,%d", n, k));
            @(negedge reset);
            while (frame < n) wait_vs();
            ss_save(ss_s1);
            $display("save state: S1 saved at frame %0d", frame);
            repeat (k) wait_vs();
            ss_save(ss_s2);
            save_frame_named("ss_a");
            $display("save state: S2 saved at frame %0d", frame);
            ss_restore(ss_s1);
            $display("save state: S1 loaded");
            repeat (k) wait_vs();
            ss_save(ss_s3);
            save_frame_named("ss_b");
            diffs = 0;
            for (int w = 0; w < SS_WORDS; w++) begin
                if (ss_s2[w] !== ss_s3[w]) begin
                    if (diffs < 12) $display("save state: S2/S3 differ at byte 0x%04X: %08X vs %08X", w * 4, ss_s2[w], ss_s3[w]);
                    diffs++;
                end
            end
            $display("save state: %s (%0d of %0d words differ)", diffs == 0 ? "EXACT" : "MISMATCH", diffs, SS_WORDS);

            // what APF would write to the high score save file on exit
            begin
                automatic int fd_hso;
                fd_hso = $fopen($sformatf("%s/hiscore_out.bin", outdir), "wb");
                for (int w = 0; w < 64; w++) begin
                    automatic reg [31:0] d;
                    bridge_read(32'h60000000 + w * 4, d);
                    $fwrite(fd_hso, "%c%c%c%c", d[31:24], d[23:16], d[15:8], d[7:0]);
                end
                $fclose(fd_hso);
                $display("high score buffer written to hiscore_out.bin");
            end

            if (fd_audio) $fclose(fd_audio);
            $finish;
        end
    end


endmodule
