//
// High score saving. The board has no battery-backed RAM; this keeps the
// high score table in a save file, using the RAM locations from MAME's
// hiscore plugin (hiscore.dat, "nibbler"):
//   $0290-$02B7  scores (40 bytes), valid once $0290 = $00 and $02B7 = $00
//   $02D0-$02ED  names  (30 bytes), valid once $02D0 = $13 and $02ED = $14
//
// Save file (data slot 2, bridge 0x60000000, 256 bytes, big-endian words):
//   0-3    "NHI1"
//   4-43   scores
//   44-73  names
//
// Once per frame:
//   - until the game has set up its default table (check bytes hold for
//     SETTLE_FRAMES frames), the loaded file is passed through to the save
//     buffer unchanged, so leaving early never loses scores
//   - then the saved table, if the file has one, is written into RAM once
//   - from then on the RAM table is copied to the save buffer, which APF
//     writes to the SD card when the core exits
//
// The table is watched through work RAM's second (read-only) port, so the
// CPU is never stalled for that. The one-time restore writes through the main
// memory bus while the CPU is frozen at an instruction boundary for a moment.
//
module nibbler_hiscore (
    input  wire        clk,
    input  wire        reset,
    input  wire        frame,           // one pulse per frame

    output reg  [9:0]  ram_addr = 10'd0,    // work RAM port B (read)
    input  wire [7:0]  ram_q,               // one cycle after ram_addr

    output reg         hold_req = 1'b0,    // restore: freeze the CPU
    input  wire        frozen,
    output reg         bus = 1'b0,         // restore: own the memory bus
    output reg  [15:0] bus_a = 16'd0,
    output reg         bus_we = 1'b0,
    output reg  [7:0]  bus_wd = 8'd0,

    // bridge side, clk_74a
    input  wire        clk_74a,
    input  wire        bridge_wr,
    input  wire        bridge_rd,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,
    output reg  [31:0] bridge_rd_data,

    output wire [15:0] dbg,             // for the debug overlay
    output reg  [31:0] dbg_first = 32'd0 // first word of the loaded file
);

    localparam [31:0] MAGIC = 32'h4E484931;     // "NHI1"
    localparam [3:0]  SETTLE_FRAMES = 4'd10;

    // file byte n (4-73) -> RAM address
    function [9:0] ram_of(input [6:0] n);
        ram_of = n < 7'd44 ? 10'h290 + (n - 7'd4) : 10'h2D0 + (n - 7'd44);
    endfunction

    // check byte c -> RAM address, expected value
    function [9:0] chk_addr(input [1:0] c);
        chk_addr = c == 2'd0 ? 10'h290 : c == 2'd1 ? 10'h2B7 : c == 2'd2 ? 10'h2D0 : 10'h2ED;
    endfunction
    function [7:0] chk_want(input [1:0] c);
        chk_want = c == 2'd2 ? 8'h13 : c == 2'd3 ? 8'h14 : 8'h00;
    endfunction

    // ------------------------------------------------------------------
    // Buffers (one per direction): APF writes load_buf at boot and reads
    // save_buf when the core exits

    reg [31:0] load_buf [0:63];
    reg [31:0] save_buf [0:63];

    // power up empty (no marker), as block RAM does on the FPGA; without a
    // save file APF leaves load_buf untouched
    integer b;
    initial for (b = 0; b < 64; b = b + 1) begin
        load_buf[b] = 32'd0;
        save_buf[b] = 32'd0;
    end

    // bridge reads: latch on the read strobe, see nibbler_savestate
    reg [31:0] save_q;
    always @(posedge clk_74a) begin
        if (bridge_wr && bridge_addr[31:28] == 4'h6)
            load_buf[bridge_addr[7:2]] <= bridge_wr_data;
        save_q <= save_buf[bridge_addr[7:2]];
        if (bridge_rd) bridge_rd_data <= save_q;
    end

    reg  [5:0]  l_addr = 6'd0;
    reg  [31:0] l_q;
    reg  [5:0]  s_addr = 6'd0;
    reg  [31:0] s_wd = 32'd0;
    reg         s_we = 1'b0;

    always @(posedge clk) begin
        l_q <= load_buf[l_addr];
        if (s_we) save_buf[s_addr] <= s_wd;
    end

    // ------------------------------------------------------------------
    // Sequencer

    localparam S_IDLE   = 0,
               S_CHK_A  = 1,  S_CHK_W  = 2,  S_CHK_C  = 3,
               S_PASS_A = 4,  S_PASS_W = 5,  S_PASS_C = 6,
               S_MAG_W  = 7,  S_MAG_C  = 8,
               S_RST_A  = 9,  S_RST_W  = 10, S_RST_C  = 11,
               S_CPY_A  = 12, S_CPY_W  = 13, S_CPY_C  = 14,
               S_RST_HOLD = 15, S_RST_END = 16;

    reg [4:0]  state = S_IDLE;
    reg [1:0]  c;
    reg        chk_ok;
    reg [3:0]  settle = 4'd0;
    reg        restored = 1'b0;     // saved table written, or there was none
    reg [6:0]  n;                   // file byte, or buffer word in the pass loop
    reg [31:0] word;

    reg [4:0]  n_restores = 5'd0;
    assign dbg = {restored, state, settle, chk_ok, n_restores};

    always @(posedge clk) begin
        bus_we <= 1'b0;
        s_we   <= 1'b0;

        if (reset) begin
            state    <= S_IDLE;
            settle   <= 4'd0;
            restored <= 1'b0;
            hold_req <= 1'b0;
            bus      <= 1'b0;
        end else begin
            case (state)
                S_IDLE: if (frame) begin
                    if (restored) begin
                        s_addr <= 6'd0;
                        s_wd   <= MAGIC;
                        s_we   <= 1'b1;
                        n      <= 7'd4;
                        state  <= S_CPY_A;
                    end else begin
                        c      <= 2'd0;
                        chk_ok <= 1'b1;
                        state  <= S_CHK_A;
                    end
                end

                // ---- has the game set up its default table? -------------
                S_CHK_A: begin ram_addr <= chk_addr(c); state <= S_CHK_W; end
                S_CHK_W: state <= S_CHK_C;
                S_CHK_C: begin
                    if (ram_q != chk_want(c)) chk_ok <= 1'b0;
                    if (c == 2'd3) begin
                        n     <= 7'd0;
                        state <= S_PASS_A;
                    end else begin
                        c     <= c + 2'd1;
                        state <= S_CHK_A;
                    end
                end

                // ---- meanwhile pass the loaded file through --------------
                S_PASS_A: begin l_addr <= n[5:0]; state <= S_PASS_W; end
                S_PASS_W: state <= S_PASS_C;
                S_PASS_C: begin
                    s_addr <= n[5:0];
                    s_wd   <= l_q;
                    s_we   <= 1'b1;
                    if (n == 7'd63) begin
                        if (!chk_ok) begin
                            settle <= 4'd0;
                            state  <= S_IDLE;
                        end else if (settle != SETTLE_FRAMES) begin
                            settle <= settle + 4'd1;
                            state  <= S_IDLE;
                        end else begin
                            l_addr <= 6'd0;
                            state  <= S_MAG_W;
                        end
                    end else begin
                        n     <= n + 7'd1;
                        state <= S_PASS_A;
                    end
                end

                // ---- write the saved table into RAM, once ----------------
                S_MAG_W: state <= S_MAG_C;
                S_MAG_C: begin
                    dbg_first <= l_q;
                    if (l_q != MAGIC) begin
                        restored <= 1'b1;           // no saved scores yet
                        state    <= S_IDLE;
                    end else begin
                        hold_req <= 1'b1;
                        state    <= S_RST_HOLD;
                    end
                end
                S_RST_HOLD: if (frozen) begin
                    bus   <= 1'b1;
                    n     <= 7'd4;
                    state <= S_RST_A;
                end
                S_RST_A: begin l_addr <= n[6:2]; state <= S_RST_W; end
                S_RST_W: state <= S_RST_C;
                S_RST_C: begin
                    bus_a  <= {6'd0, ram_of(n)};
                    bus_wd <= l_q[8 * (3 - n[1:0]) +: 8];
                    bus_we <= 1'b1;
                    if (n == 7'd73) begin
                        restored <= 1'b1;
                        n_restores <= n_restores + 5'd1;
                        state    <= S_RST_END;
                    end else begin
                        n     <= n + 7'd1;
                        state <= S_RST_A;
                    end
                end

                // ---- copy the RAM table to the save buffer ---------------
                // bytes 4-75; 74 and 75 are padding
                S_CPY_A: begin ram_addr <= ram_of(n); state <= S_CPY_W; end
                S_CPY_W: state <= S_CPY_C;
                S_CPY_C: begin : cpy
                    reg [7:0] b;
                    b = n <= 7'd73 ? ram_q : 8'h00;
                    word <= {word[23:0], b};
                    if (n[1:0] == 2'd3) begin
                        s_addr <= n[6:2];
                        s_wd   <= {word[23:0], b};
                        s_we   <= 1'b1;
                    end
                    if (n == 7'd75) begin
                        state <= S_IDLE;
                    end else begin
                        n     <= n + 7'd1;
                        state <= S_CPY_A;
                    end
                end

                S_RST_END: begin                    // let the last write land
                    bus      <= 1'b0;
                    hold_req <= 1'b0;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
