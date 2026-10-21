//
// Nibbler sound: the SNK custom tone generator plus the SN76477 "bomb" noise,
// computed one 48 kHz sample at a time following MAME's snk6502_a.cpp
// (fantasy/nibbler sound), sn76477.cpp and the fantasy discrete netlist.
//
// Tone channels. MAME's channel 0 reads an empty ROM area on Nibbler (silent),
// so only channels 1 and 2 are built (called A and B here):
//   A  tunes in ic52, base ($2101 & 7) * 256, on when $2101 bit 3,
//      waveform weights from $2102 bits 7-4
//   B  tunes in ic53, base (($2103 >> 4) & 7) * 256, on when $2100 bit 4,
//      square waveform
// Each channel steps through its 256-byte tune at the 41.6 Hz note clock. A
// note byte d (other than $FF) advances a 16-step waveform at
// 344 kHz / (256 - d); MAME interpolates linearly between steps.
//
// Bomb ($2100 bit 7): SN76477 31-bit noise (3244 Hz clock) through its noise
// filter hysteresis gates an RC envelope (1 ms attack to 2.9 V, 43 ms decay),
// then a multiple-feedback band-pass (260 Hz, Q 3.8, gain -29.5, clipped at
// +10.5 / -12 V) and three RC low-pass filters (723, 1644, 2411 Hz).
//
// Mix (MAME speaker, both routes at 0.5):
//   sample = tone_sum * 0.5 * 32768 / 3768 + bomb_volts * 32760 / 12 * 0.5
//
// Bomb-chain voltages are signed Q8.24 (the noise filter cap is Q16.16);
// filter coefficients are signed Q2.28, rounded to nearest. The resonant
// band-pass needs the extra precision: at Q16.16 it settles into a small limit
// cycle instead of decaying to silence. One shared multiplier; a sample takes
// about 60 clocks.
//
module nibbler_sound (
    input  wire               clk,
    input  wire               reset,
    input  wire               tick,         // one pulse per 48 kHz sample

    input  wire               wr,           // CPU write to $2100-$2103
    input  wire [1:0]         reg_sel,
    input  wire [7:0]         din,

    output reg  [11:0]        rom_addr,     // ic52 at 0x000, ic53 at 0x800
    input  wire [7:0]         rom_data,     // one cycle latency

    output reg  signed [15:0] sample = 16'sd0,
    output reg                sample_valid = 1'b0,

    // save states: the complete state as one vector; restore loads it
    output wire               idle,         // between samples (state is consistent)
    output wire [575:0]       ss_out,
    input  wire               ss_restore,
    input  wire [575:0]       ss_in
);

    // ------------------------------------------------------------------
    // Constants (computed with MAME's formulas at 48 kHz, see docs)

    localparam integer TONE_EXPIRE   = 75618461;    // (1 / 41.6 Hz) * 48000 * 65536
    localparam integer NOISE_FREQ    = 3244;        // 339100000 * 470k^-0.8849
    localparam integer FORM_SCALE    = 409;         // 65535 / 160

    localparam signed [31:0] V_2_9    = 32'sd48653926;   // RCDISC2 charge target (TTL 1 - 0.5 V), Q8.24
    localparam signed [31:0] V_RAIL_P = 32'sd176160768;  // 12 V - 1.5 V
    localparam signed [31:0] V_RAIL_N = -32'sd201326592; // -12 V
    localparam signed [31:0] NF_CHG   = 32'sd103211;    // noise filter cap, V per sample, Q16.16
    localparam signed [31:0] NF_DIS   = 32'sd111432;
    localparam signed [31:0] NF_HIGH  = 32'sd219546;    // 3.35 V
    localparam signed [31:0] NF_LOW   = 32'sd48497;     // 0.74 V
    localparam signed [31:0] NF_MAX   = 32'sd327680;    // 5 V

    localparam signed [31:0] K_ENV_DIS = 32'sd130024;   // 1 - exp(-1 / (48k * 43k * 1u))
    localparam signed [31:0] K_ENV_CHG = 32'sd5534554;  // 1 - exp(-1 / (48k * 1k * 1u))
    localparam signed [31:0] K_BP_A1   = -32'sd534192322;
    localparam signed [31:0] K_BP_A2   = 32'sd266066667;
    localparam signed [31:0] K_BP_B0   = -32'sd34942205; // b2 = -b0, b1 = 0
    localparam signed [31:0] K_RC1     = 32'sd24253534;  // 22k, 10n
    localparam signed [31:0] K_RC2     = 32'sd51978846;  // 44k, 2.2n
    localparam signed [31:0] K_RC3     = 32'sd72662827;  // 66k, 1n

    localparam signed [31:0] K_TONE_OUT = 32'sd284963;   // 0.5 * 32768 / 3768, Q16
    localparam signed [31:0] K_BOMB_OUT = 32'sd1365;     // 32760 / 12 * 0.5

    // waveform step per sample for note byte d: 469674 / (256 - d)
    reg [19:0] step_lut [0:255];
    integer i;
    initial for (i = 0; i < 256; i = i + 1) step_lut[i] = 469674 / (256 - i);

    // ------------------------------------------------------------------
    // Channel state (index 0 = A, 1 = B)

    reg        mute   [0:1];
    reg [7:0]  offset [0:1];
    reg [2:0]  base   [0:1];
    reg [19:0] step   [0:1];
    reg [19:0] cur    [0:1];        // MAME sample_cur; only the low 20 bits matter
    reg [3:0]  mask_a;              // channel A waveform weights select
    reg        bomb_en;
    reg [31:0] tone_clock;

    // MAME build_waveform() for the shaped channel: weights of the four
    // waveform counter bits, centred on zero
    function signed [15:0] form_a(input [3:0] m, input [3:0] idx);
        integer b0, b1, b2, b3, base_v, data;
        begin
            b3 = (m[0] || m[1]) ? 8 : m[2] ? 4 : m[3] ? 2 : 0;
            b2 = m[2] ? 8 : (m[1] || m[3]) ? 4 : 0;
            b1 = m[3] ? 8 : m[2] ? 4 : m[1] ? 2 : 0;
            b0 = b1 / 2;
            if (b0 + b1 + b2 + b3 < 16) begin
                b0 = b0 * 2; b1 = b1 * 2; b2 = b2 * 2; b3 = b3 * 2;
            end
            base_v = (b0 + b1 + b2 + b3 + 1) / 2;
            data = (idx[0] ? b0 : 0) + (idx[1] ? b1 : 0) + (idx[2] ? b2 : 0) + (idx[3] ? b3 : 0);
            form_a = (data - base_v) * FORM_SCALE;
        end
    endfunction

    function signed [15:0] form_b(input [3:0] idx);
        form_b = (idx[3] ? 7 : -8) * FORM_SCALE;
    endfunction

    function signed [15:0] form(input ch, input [3:0] idx);
        form = ch ? form_b(idx) : form_a(mask_a, idx);
    endfunction

    // ------------------------------------------------------------------
    // Bomb state

    reg [30:0]        rng;
    reg signed [31:0] noise_count;
    reg signed [31:0] nf_cap;
    reg               noise_bit;        // filtered noise: SN76477 output polarity
    reg signed [31:0] env;
    reg signed [31:0] bp_x1, bp_x2, bp_y1, bp_y2;
    reg signed [31:0] rc1, rc2, rc3;

    // ------------------------------------------------------------------
    // Shared multiplier: operands set in one state, product ready two later

    reg  signed [35:0] mul_a;
    reg  signed [35:0] mul_b;
    reg  signed [71:0] prod;
    always @(posedge clk) prod <= mul_a * mul_b;

    // ------------------------------------------------------------------
    // Sequencer

    localparam S_IDLE = 0,
               S_TONE_ADDR = 1, S_TONE_WAIT = 2, S_TONE_STEP = 3,
               S_TONE_MUL1 = 4, S_TONE_MUL2 = 5, S_TONE_ACC1 = 6, S_TONE_ACC2 = 7,
               S_CLOCK = 8,
               S_NOISE = 9,
               S_ENV_MUL = 10, S_ENV_W1 = 11, S_ENV_ACC = 12,
               S_BP_M0 = 13, S_BP_M1 = 14, S_BP_M2 = 15, S_BP_M3 = 16,
               S_BP_A0 = 17, S_BP_A1 = 18, S_BP_A2 = 19, S_BP_SUM = 20,
               S_RC_MUL = 21, S_RC_W1 = 22, S_RC_ACC = 23,
               S_OUT_M0 = 24, S_OUT_M1 = 25, S_OUT_W = 26, S_OUT_A0 = 27, S_OUT_A1 = 28;

    reg  [4:0]         state = S_IDLE;
    reg                ch;
    reg  [1:0]         rc_n;
    reg  signed [31:0] tone_data;
    reg  [19:0]        cur_pos;
    reg  signed [15:0] f_prev, f_cur;
    reg  signed [71:0] acc;
    reg  signed [31:0] node11;
    reg  signed [31:0] bomb_v;

    wire signed [31:0] rc_in   = rc_n == 2'd0 ? bp_y1 : rc_n == 2'd1 ? rc1 : rc2;
    wire signed [31:0] rc_out  = rc_n == 2'd0 ? rc1   : rc_n == 2'd1 ? rc2 : rc3;
    wire signed [31:0] rc_k    = rc_n == 2'd0 ? K_RC1 : rc_n == 2'd1 ? K_RC2 : K_RC3;
    // round to nearest so the filters settle at 0 V rather than creeping below it
    wire signed [31:0] prod_q28 = (prod + 72'sd134217728) >>> 28;

    // clamp a wide sum to 16 bits
    function signed [15:0] sat16(input signed [47:0] x);
        sat16 = x > 48'sd32767 ? 16'sh7FFF : x < -48'sd32768 ? 16'sh8000 : x[15:0];
    endfunction

    // ------------------------------------------------------------------
    // Save state vector (509 bits used), most significant first

    assign idle = state == S_IDLE;
    assign ss_out = {67'd0, mute[1], mute[0], offset[0], offset[1], base[0], base[1],
                     step[0], step[1], cur[0], cur[1], mask_a, bomb_en, tone_clock, rng,
                     noise_count, nf_cap, noise_bit, env, bp_x1, bp_x2, bp_y1, bp_y2,
                     rc1, rc2, rc3, sample};

    always @(posedge clk) begin
        sample_valid <= 1'b0;

        if (ss_restore) begin : restore
            reg [575:0] t;
            t = ss_in;
            sample      <= t[15:0];  t = t >> 16;
            rc3         <= t[31:0];  t = t >> 32;
            rc2         <= t[31:0];  t = t >> 32;
            rc1         <= t[31:0];  t = t >> 32;
            bp_y2       <= t[31:0];  t = t >> 32;
            bp_y1       <= t[31:0];  t = t >> 32;
            bp_x2       <= t[31:0];  t = t >> 32;
            bp_x1       <= t[31:0];  t = t >> 32;
            env         <= t[31:0];  t = t >> 32;
            noise_bit   <= t[0];     t = t >> 1;
            nf_cap      <= t[31:0];  t = t >> 32;
            noise_count <= t[31:0];  t = t >> 32;
            rng         <= t[30:0];  t = t >> 31;
            tone_clock  <= t[31:0];  t = t >> 32;
            bomb_en     <= t[0];     t = t >> 1;
            mask_a      <= t[3:0];   t = t >> 4;
            cur[1]      <= t[19:0];  t = t >> 20;
            cur[0]      <= t[19:0];  t = t >> 20;
            step[1]     <= t[19:0];  t = t >> 20;
            step[0]     <= t[19:0];  t = t >> 20;
            base[1]     <= t[2:0];   t = t >> 3;
            base[0]     <= t[2:0];   t = t >> 3;
            offset[1]   <= t[7:0];   t = t >> 8;
            offset[0]   <= t[7:0];   t = t >> 8;
            mute[0]     <= t[0];     t = t >> 1;
            mute[1]     <= t[0];
            state       <= S_IDLE;
        end else if (reset) begin
            state       <= S_IDLE;
            mute[0]     <= 1'b1;  mute[1]   <= 1'b1;
            offset[0]   <= 8'd0;  offset[1] <= 8'd0;
            base[0]     <= 3'd0;  base[1]   <= 3'd0;
            step[0]     <= 20'd0; step[1]   <= 20'd0;
            cur[0]      <= 20'd0; cur[1]    <= 20'd0;
            mask_a      <= 4'd1;
            bomb_en     <= 1'b0;
            tone_clock  <= 32'd0;
            rng         <= 31'd0;
            noise_count <= 32'sd0;
            nf_cap      <= 32'sd0;
            noise_bit   <= 1'b0;
            env         <= 32'sd0;
            bp_x1 <= 0; bp_x2 <= 0; bp_y1 <= 0; bp_y2 <= 0;
            rc1 <= 0; rc2 <= 0; rc3 <= 0;
            sample      <= 16'sd0;
        end else begin

            // register writes (MAME fantasy_sound_device::sound_w)
            if (wr) begin
                case (reg_sel)
                    2'd0: begin
                        if (din[4]) begin
                            if (mute[1]) offset[1] <= 8'd0;
                            mute[1] <= 1'b0;
                        end else begin
                            mute[1] <= 1'b1;
                            offset[1] <= 8'd0;
                        end
                        bomb_en <= din[7];
                    end
                    2'd1: begin
                        base[0] <= din[2:0];
                        if (din[3]) begin
                            if (mute[0]) offset[0] <= 8'd0;
                            mute[0] <= 1'b0;
                        end else begin
                            mute[0] <= 1'b1;
                            offset[0] <= 8'd0;
                        end
                    end
                    2'd2: mask_a <= din[7:4];
                    2'd3: base[1] <= din[6:4];
                endcase
            end

            case (state)
                S_IDLE: if (tick) begin
                    ch        <= 1'b0;
                    tone_data <= 32'sd0;
                    state     <= S_TONE_ADDR;
                end

                // ---- tone channels ----------------------------------------
                S_TONE_ADDR: begin
                    rom_addr <= {ch, base[ch], offset[ch]};
                    state    <= S_TONE_WAIT;
                end
                S_TONE_WAIT: state <= S_TONE_STEP;
                S_TONE_STEP: begin
                    // validate_tone_channel(): only while playing
                    if (!mute[ch])
                        step[ch] <= rom_data == 8'hFF ? 20'd0 : step_lut[rom_data];
                    state <= S_TONE_MUL1;
                end
                S_TONE_MUL1: begin
                    if (mute[ch] || step[ch] == 20'd0) begin
                        state <= ch ? S_CLOCK : S_TONE_ADDR;
                        ch    <= 1'b1;
                    end else begin
                        cur_pos <= cur[ch] + step[ch];
                        state   <= S_TONE_MUL2;
                    end
                end
                S_TONE_MUL2: begin
                    f_prev  <= form(ch, cur[ch][19:16]);
                    f_cur   <= form(ch, cur_pos[19:16]);
                    cur[ch] <= cur_pos;
                    mul_a   <= form(ch, cur[ch][19:16]);
                    mul_b   <= 36'sd65536 - cur_pos[15:0];
                    state   <= S_TONE_ACC1;
                end
                S_TONE_ACC1: begin
                    mul_a <= f_cur;
                    mul_b <= cur_pos[15:0];
                    state <= S_TONE_ACC2;
                end
                S_TONE_ACC2: begin
                    acc   <= prod;                      // prev * (1 - frac)
                    state <= 5'd29;
                end
                5'd29: begin
                    tone_data <= tone_data + ((acc + prod) >>> 16);
                    state     <= ch ? S_CLOCK : S_TONE_ADDR;
                    ch        <= 1'b1;
                end

                // ---- note clock --------------------------------------------
                S_CLOCK: begin
                    if (tone_clock + 32'd65536 >= TONE_EXPIRE) begin
                        offset[0]  <= offset[0] + 8'd1;
                        offset[1]  <= offset[1] + 8'd1;
                        tone_clock <= tone_clock + 32'd65536 - TONE_EXPIRE;
                    end else begin
                        tone_clock <= tone_clock + 32'd65536;
                    end
                    state <= S_NOISE;
                end

                // ---- SN76477 noise and filter ------------------------------
                S_NOISE: begin : noise
                    reg        out_bit;
                    reg [30:0] r;
                    reg signed [31:0] cnt, cap;
                    r   = rng;
                    cnt = noise_count;
                    out_bit = 1'b0;
                    if (cnt <= NOISE_FREQ) begin
                        cnt = cnt + 32'sd48000;
                        out_bit = r[28] ^ r[0];
                        if ((r & 31'h1000001f) == 31'd0) out_bit = 1'b1;
                        r = {out_bit, r[30:1]};
                    end else begin
                        out_bit = rng[30];          // last generated bit
                    end
                    noise_count <= cnt - NOISE_FREQ;
                    rng <= r;

                    cap = out_bit ? nf_cap + NF_CHG : nf_cap - NF_DIS;
                    if (cap > NF_MAX) cap = NF_MAX;
                    if (cap < 0) cap = 0;
                    nf_cap <= cap;
                    if (cap >= NF_HIGH)     noise_bit <= 1'b0;
                    else if (cap <= NF_LOW) noise_bit <= 1'b1;

                    // envelope: RCDISC2
                    mul_a <= (bomb_en ? V_2_9 : 32'sd0) - env;
                    mul_b <= bomb_en ? K_ENV_CHG : K_ENV_DIS;
                    state <= S_ENV_W1;
                end
                S_ENV_W1: state <= S_ENV_ACC;
                S_ENV_ACC: begin
                    env    <= env + prod_q28;
                    node11 <= noise_bit ? env + prod_q28 : 32'sd0;
                    state  <= S_BP_M0;
                end

                // ---- band-pass biquad --------------------------------------
                S_BP_M0: begin mul_a <= node11; mul_b <= K_BP_B0;  state <= S_BP_M1; end
                S_BP_M1: begin mul_a <= bp_x2;  mul_b <= -K_BP_B0; state <= S_BP_M2; end
                S_BP_M2: begin mul_a <= bp_y1;  mul_b <= -K_BP_A1; acc <= prod; state <= S_BP_M3; end
                S_BP_M3: begin mul_a <= bp_y2;  mul_b <= -K_BP_A2; acc <= acc + prod; state <= S_BP_A0; end
                S_BP_A0: begin acc <= acc + prod; state <= S_BP_A1; end
                S_BP_A1: begin acc <= acc + prod; state <= S_BP_SUM; end
                S_BP_SUM: begin : bp
                    reg signed [71:0] y;
                    y = (acc + 72'sd134217728) >>> 28;
                    if (y > V_RAIL_P) y = V_RAIL_P;
                    if (y < V_RAIL_N) y = V_RAIL_N;
                    bp_y2 <= bp_y1;
                    bp_y1 <= y[31:0];
                    bp_x2 <= bp_x1;
                    bp_x1 <= node11;
                    rc_n  <= 2'd0;
                    state <= S_RC_MUL;
                end

                // ---- RC low-pass x3 ----------------------------------------
                S_RC_MUL: begin
                    mul_a <= rc_in - rc_out;
                    mul_b <= rc_k;
                    state <= S_RC_W1;
                end
                S_RC_W1: state <= S_RC_ACC;
                S_RC_ACC: begin
                    case (rc_n)
                        2'd0: rc1 <= rc1 + prod_q28;
                        2'd1: rc2 <= rc2 + prod_q28;
                        default: rc3 <= rc3 + prod_q28;
                    endcase
                    if (rc_n == 2'd2) begin
                        state <= S_OUT_M0;
                    end else begin
                        rc_n  <= rc_n + 2'd1;
                        state <= S_RC_MUL;
                    end
                end

                // ---- mix ---------------------------------------------------
                S_OUT_M0: begin mul_a <= tone_data; mul_b <= K_TONE_OUT; state <= S_OUT_M1; end
                S_OUT_M1: begin mul_a <= rc3;       mul_b <= K_BOMB_OUT; state <= S_OUT_W; end
                S_OUT_W:  begin acc <= prod;  state <= S_OUT_A0; end
                S_OUT_A0: begin acc <= acc + (prod >>> 8); state <= S_OUT_A1; end    // Q8.24 -> Q16
                S_OUT_A1: begin
                    sample       <= sat16(acc >>> 16);
                    sample_valid <= 1'b1;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
