//
// Unit test for nibbler_sound: replays a sequence of sound register writes
// (frame-timed, as logged from MAME) and records the output to audio.raw.
// Default sequence: the death sound (bomb + tune 6) from a MAME game, frames
// 2181-2382, with the waveform register set earlier in that game.
//
// Plusargs: +rom=<nibbler.rom> +outdir=<dir>
//
`timescale 1ns/1ps

module tb_sound;

    reg clk = 0;
    always #5 clk = ~clk;

    reg        reset = 1;
    reg        tick = 0;
    reg        wr = 0;
    reg  [1:0] reg_sel = 0;
    reg  [7:0] din = 0;
    wire [11:0] rom_addr;
    reg  [7:0]  rom_data;
    wire signed [15:0] sample;
    wire        sample_valid;

    nibbler_sound dut (
        .clk(clk), .reset(reset), .tick(tick),
        .wr(wr), .reg_sel(reg_sel), .din(din),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .sample(sample), .sample_valid(sample_valid)
    );

    byte rom [0:65535];
    always @(posedge clk) rom_data <= rom[16'hB000 + rom_addr];

    string rom_path, outdir;
    int fd_rom, fd_out;
    int n_samples = 0;

    // samples per frame at 59.844 Hz
    function int frame_to_sample(real f);
        return int'(f * 48000.0 / 59.844);
    endfunction

    task automatic write_reg(input [1:0] r, input [7:0] d);
        @(posedge clk); reg_sel <= r; din <= d; wr <= 1;
        @(posedge clk); wr <= 0;
    endtask

    // one 48 kHz tick every 128 clocks (the sequencer needs ~60)
    always begin
        repeat (127) @(posedge clk);
        tick <= 1;
        @(posedge clk);
        tick <= 0;
    end

    always @(posedge clk) begin
        if (sample_valid) begin
            $fwrite(fd_out, "%c%c", sample[7:0], sample[15:8]);
            n_samples++;
        end
    end

    task automatic wait_samples(int n);
        while (n_samples < n) @(posedge clk);
    endtask

    initial begin
        if (!$value$plusargs("rom=%s", rom_path)) rom_path = "nibbler.rom";
        if (!$value$plusargs("outdir=%s", outdir)) outdir = ".";
        fd_rom = $fopen(rom_path, "rb");
        void'($fread(rom, fd_rom));
        $fclose(fd_rom);
        fd_out = $fopen($sformatf("%s/audio.raw", outdir), "wb");

        repeat (4) @(posedge clk);
        reset <= 0;

        // state from earlier in the game
        write_reg(2, 8'h66);
        write_reg(3, 8'h00);
        write_reg(1, 8'h00);
        write_reg(0, 8'h00);

        wait_samples(frame_to_sample(20));              // a little silence first
        write_reg(0, 8'h80);                            // frame 2181: bomb on
        write_reg(1, 8'h0E);                            //             tune 6
        wait_samples(frame_to_sample(20 + 2357 - 2181));
        write_reg(1, 8'h00);                            // frame 2357: tune off
        wait_samples(frame_to_sample(20 + 2382 - 2181));
        write_reg(0, 8'h00);                            // frame 2382: bomb off
        wait_samples(frame_to_sample(20 + 2420 - 2181));

        $fclose(fd_out);
        $display("tb_sound: %0d samples", n_samples);
        $finish;
    end

endmodule
