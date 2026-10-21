//
// Save states (Pocket "Memories" and sleep/wake).
//
// APF protocol (core_bridge_cmd): savestate_start / savestate_load rise; the
// core acks, holds busy while working, then holds ok (or err) until the next
// request. For a save, APF afterwards reads savestate_size bytes over the
// bridge from savestate_addr; for a load, APF has already written the data
// there before raising savestate_load.
//
// The state is transferred at bridge 0x40000000 (two 16 KB buffers, one per
// direction):
//   0x0000-0x1FFF  RAM, laid out at its CPU addresses ($0000-$1FFF):
//                  work RAM, videoram2, videoram, colorram, char RAM
//   0x2000-0x207F  32 words of registers (see nibbler_top), word 31 = "NIB1"
//
// Saving: request a freeze at the next instruction boundary, wait for the
// sound sequencer to finish its sample, copy RAM and registers into the
// buffer, release. Loading: check the magic word first, stop the CPU at once,
// copy the buffer back into RAM, hand the registers to the board (restore),
// then run the CPU restore stub (nibbler_top) and release.
//
module nibbler_savestate (
    input  wire          clk,
    input  wire          reset,

    // APF handshake, clk domain (synchronized outside)
    input  wire          start,
    input  wire          load,
    output reg           ack = 1'b0,
    output reg           busy = 1'b0,
    output reg           ok = 1'b0,
    output reg           err = 1'b0,

    // board control
    output reg           hold_req = 1'b0,   // freeze the CPU at an instruction boundary
    output reg           force_stop = 1'b0, // stop the CPU now (load)
    input  wire          frozen,
    input  wire          sound_idle,

    // memory bus, owned while ss_bus is high
    output reg           ss_bus = 1'b0,
    output reg  [15:0]   ss_a = 16'd0,
    output reg           ss_we = 1'b0,
    output reg  [7:0]    ss_wd = 8'd0,
    input  wire [7:0]    ss_rd,             // one cycle after ss_a, through the RAM

    // registers
    input  wire [1023:0] regs_out,
    output reg  [1023:0] regs_in = 1024'd0,
    output reg           restore = 1'b0,
    output reg           stub_start = 1'b0,
    input  wire          stub_done,

    // bridge side of the transfer buffer
    input  wire          clk_74a,
    input  wire          bridge_wr,
    input  wire          bridge_rd,
    input  wire [31:0]   bridge_addr,
    input  wire [31:0]   bridge_wr_data,
    output reg  [31:0]   bridge_rd_data,

    // for the debug overlay: state, flags, request/completion counters
    output wire [31:0]   dbg,
    output wire [31:0]   dbg_magic      // marker word found by the last load
);

    localparam [31:0] MAGIC = 32'h4E494231;     // "NIB1"

    // ------------------------------------------------------------------
    // Transfer buffer: 4096 words, bridge port on clk_74a, engine port on clk

    // Two one-way buffers (simple dual-port, dual-clock block RAMs): the
    // engine writes save_buf and APF reads it; APF writes load_buf and the
    // engine reads it.
    reg [31:0] save_buf [0:4095];
    reg [31:0] load_buf [0:4095];

    reg  [11:0] b_addr = 12'd0;
    reg         b_we = 1'b0;
    reg  [31:0] b_wd = 32'd0;
    reg  [31:0] b_q;

    always @(posedge clk) begin
        if (b_we) save_buf[b_addr] <= b_wd;
        b_q <= load_buf[b_addr];
    end

    // Bridge reads: APF takes the data for a read during a following read
    // transaction (observed: states saved with data that follows the address
    // come out one word early). So on each read strobe, latch the word for that
    // strobe's address and hold it until the next strobe; re-reads of the same
    // address then return the same word too.
    //
    // APF may write the state for a load before or after raising
    // savestate_load, so loading waits until the last word has been written
    // (data_ready), which is cleared again once a load is done.
    reg  [31:0] save_q;
    reg         data_ready_74 = 1'b0;
    reg         ready_clear_toggle = 1'b0;
    reg  [2:0]  ready_clear_s = 3'd0;
    always @(posedge clk_74a) begin
        ready_clear_s <= {ready_clear_s[1:0], ready_clear_toggle};
        if (bridge_wr && bridge_addr[31:28] == 4'h4) begin
            load_buf[bridge_addr[13:2]] <= bridge_wr_data;
            if (bridge_addr[13:2] == 12'h83F) data_ready_74 <= 1'b1;
        end else if (ready_clear_s[2] != ready_clear_s[1]) begin
            data_ready_74 <= 1'b0;
        end
        save_q <= save_buf[bridge_addr[13:2]];
        if (bridge_rd) bridge_rd_data <= save_q;
    end

    reg  [2:0]  data_ready_s = 3'd0;
    always @(posedge clk) data_ready_s <= {data_ready_s[1:0], data_ready_74};
    wire        data_ready = data_ready_s[2];
    reg  [26:0] load_wait = 27'd0;
    reg  [31:0] magic_seen = 32'd0;      // debug: marker word found by the last load
    assign dbg_magic = magic_seen;

    // ------------------------------------------------------------------
    // Sequencer

    localparam S_IDLE        = 0,
               S_SAVE_FREEZE = 1,
               S_SAVE_ADDR   = 2, S_SAVE_W1 = 3, S_SAVE_CAP = 4,
               S_SAVE_REGS   = 5,
               S_LOAD_CHECK  = 6, S_LOAD_CHECK_W = 7, S_LOAD_CHECK_Q = 8,
               S_LOAD_FREEZE = 9,
               S_LOAD_RD     = 10, S_LOAD_W1 = 11, S_LOAD_WR = 12,
               S_LOAD_REGS   = 13, S_LOAD_REGS_W = 14, S_LOAD_REGS_Q = 15,
               S_RESTORE     = 16, S_STUB = 17, S_STUB_WAIT = 18,
               S_DONE        = 19;

    reg [4:0]  state = S_IDLE;
    reg [3:0]  n_save_req = 4'd0, n_save_done = 4'd0, n_load_req = 4'd0, n_load_done = 4'd0;
    assign dbg = {state, start, load, ack, busy, ok, err, frozen, sound_idle, 3'd0,
                  n_save_req, n_save_done, n_load_req, n_load_done};
    reg        start_prev = 1'b0, load_prev = 1'b0;
    reg [13:0] i;               // byte index into RAM
    reg [5:0]  w;               // register word index
    reg [31:0] word;
    reg [1:0]  k;

    always @(posedge clk) begin
        start_prev <= start;
        load_prev  <= load;
        ss_we      <= 1'b0;
        b_we       <= 1'b0;
        restore    <= 1'b0;
        stub_start <= 1'b0;

        if (!start && !load) ack <= 1'b0;

        case (state)
            S_IDLE: begin
                if (start && !start_prev) begin
                    n_save_req <= n_save_req + 4'd1;
                    ack <= 1'b1;
                    ok  <= 1'b0;
                    err <= 1'b0;
                    if (reset) begin
                        err <= 1'b1;                // nothing running to save
                    end else begin
                        busy     <= 1'b1;
                        hold_req <= 1'b1;
                        state    <= S_SAVE_FREEZE;
                    end
                end else if (load && !load_prev) begin
                    n_load_req <= n_load_req + 4'd1;
                    ack   <= 1'b1;
                    ok    <= 1'b0;
                    err   <= 1'b0;
                    busy  <= 1'b1;
                    state <= S_LOAD_CHECK;
                end
            end

            // ---- save ------------------------------------------------------
            S_SAVE_FREEZE: if (frozen && sound_idle) begin
                ss_bus <= 1'b1;
                i      <= 14'd0;
                state  <= S_SAVE_ADDR;
            end
            S_SAVE_ADDR: begin
                ss_a  <= {2'b00, i};
                state <= S_SAVE_W1;
            end
            S_SAVE_W1: state <= S_SAVE_CAP;
            S_SAVE_CAP: begin
                word <= {word[23:0], ss_rd};
                if (i[1:0] == 2'd3) begin
                    b_addr <= i[13:2];
                    b_wd   <= {word[23:0], ss_rd};
                    b_we   <= 1'b1;
                end
                if (i == 14'h1FFF) begin
                    w     <= 6'd0;
                    state <= S_SAVE_REGS;
                end else begin
                    i     <= i + 14'd1;
                    state <= S_SAVE_ADDR;
                end
            end
            S_SAVE_REGS: begin
                b_addr <= 12'h800 + w;
                b_wd   <= w == 6'd31 ? MAGIC : regs_out[w * 32 +: 32];
                b_we   <= 1'b1;
                if (w == 6'd31) begin
                    n_save_done <= n_save_done + 4'd1;
                    state <= S_DONE;
                end
                w <= w + 6'd1;
            end

            // ---- load ------------------------------------------------------
            // wait for the state data (and for the CPU to be out of reset, for
            // the stub); give up waiting after about 1.5 s and check anyway
            S_LOAD_CHECK: begin
                load_wait <= load_wait + 27'd1;
                if (!reset && (data_ready || load_wait[26])) begin
                    load_wait <= 27'd0;
                    b_addr    <= 12'h81F;
                    state     <= S_LOAD_CHECK_W;
                end
            end
            S_LOAD_CHECK_W: state <= S_LOAD_CHECK_Q;
            S_LOAD_CHECK_Q: begin
                magic_seen <= b_q;
                ready_clear_toggle <= ~ready_clear_toggle;     // the next load waits for new data
                if (b_q != MAGIC) begin
                    err   <= 1'b1;              // not one of ours: change nothing
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end else begin
                    force_stop <= 1'b1;
                    hold_req   <= 1'b1;
                    state      <= S_LOAD_FREEZE;
                end
            end
            S_LOAD_FREEZE: if (frozen && sound_idle) begin
                ss_bus <= 1'b1;
                i      <= 14'd0;
                state  <= S_LOAD_RD;
            end
            S_LOAD_RD: begin
                b_addr <= i[13:2];
                state  <= S_LOAD_W1;
            end
            S_LOAD_W1: begin
                k     <= 2'd0;
                state <= S_LOAD_WR;
            end
            S_LOAD_WR: begin
                // b_q holds the word; write its bytes, most significant first
                ss_a  <= {2'b00, i[13:2], k};
                ss_wd <= b_q[31 - k * 8 -: 8];
                ss_we <= 1'b1;
                k     <= k + 2'd1;
                if (k == 2'd3) begin
                    if (i[13:2] == 12'h7FF) begin
                        w     <= 6'd0;
                        state <= S_LOAD_REGS;
                    end else begin
                        i     <= i + 14'd4;
                        state <= S_LOAD_RD;
                    end
                end
            end
            S_LOAD_REGS: begin
                b_addr <= 12'h800 + w;
                state  <= S_LOAD_REGS_W;
            end
            S_LOAD_REGS_W: state <= S_LOAD_REGS_Q;
            S_LOAD_REGS_Q: begin
                regs_in[w * 32 +: 32] <= b_q;
                if (w == 6'd31) begin
                    state <= S_RESTORE;
                end else begin
                    w     <= w + 6'd1;
                    state <= S_LOAD_REGS;
                end
            end
            S_RESTORE: begin
                restore <= 1'b1;
                ss_bus  <= 1'b0;
                state   <= S_STUB;
            end
            S_STUB: begin
                stub_start <= 1'b1;
                state      <= S_STUB_WAIT;
            end
            S_STUB_WAIT: if (stub_done) begin
                n_load_done <= n_load_done + 4'd1;
                state <= S_DONE;
            end

            S_DONE: begin
                ss_bus     <= 1'b0;
                hold_req   <= 1'b0;
                force_stop <= 1'b0;
                busy       <= 1'b0;
                ok         <= 1'b1;
                state      <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end

endmodule
