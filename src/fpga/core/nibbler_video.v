//
// Video: raster timing and the two tile layers.
//
// Timing (MAME / the board's MC6845 setup): 360 x 262 pixel clocks per frame,
// 256 x 224 active, pixel clock = clk_sys / 8 = 5.6445 MHz, 59.84 Hz.
// The CRTC registers the game writes are fixed, so the raster is generated
// directly rather than by an MC6845 model.
//
// Layers (32 x 32 tiles of 8 x 8, 2 bits per pixel):
//   background  codes from videoram ($0800), colors from colorram bits 5-3,
//               pixels from the gfx ROMs, scrolled by $2200/$2300,
//               character bank and pen-0 color from $2103
//   foreground  codes from videoram2 ($0400), colors from colorram bits 2-0,
//               pixels from character RAM, pen 0 transparent, not scrolled
//
// The pipeline advances once per pixel (ce_pix), so it works at any clock
// ratio. Every RAM read port is enabled by ce_pix, which makes each RAM one
// pipeline stage:
//   A  h, v           -> tile code / color RAM addresses
//   B  codes, colors  -> pattern ROM / char RAM addresses
//   C  pattern bytes  -> pick pen, color PROM address
//   D  PROM byte      -> RGB (registered on the next ce_pix)
// so the picture leaves 3 pixels after h/v; sync and DE are delayed to match.
//
module nibbler_video #(
    // Raster position at reset. The real board's phase depends on the power-on
    // CRTC state; this one matches MAME's (after its CRTC reconfigure settles)
    // so traces stay comparable cycle for cycle. See docs/HARDWARE.md.
    parameter RESET_H = 9'd52,
    parameter RESET_V = 9'd25
) (
    input  wire        clk_sys,
    input  wire        reset,
    input  wire        ce_pix,

    input  wire        ss_restore,      // save state load: set the raster position
    input  wire [8:0]  ss_h,
    input  wire [8:0]  ss_v,

    output reg  [8:0]  h = 9'd0,
    output reg  [8:0]  v = 9'd0,
    output wire        vblank_start,    // one ce_pix at the first non-active line

    // registers
    input  wire [7:0]  scroll_x,
    input  wire [7:0]  scroll_y,
    input  wire [7:0]  ctrl,            // bits 2-0 back color, bit 3 /char bank

    // video memories (read ports enabled by ce_pix, one stage of latency)
    output wire [9:0]  bg_code_addr,
    input  wire [7:0]  bg_code,
    output wire [9:0]  bg_color_addr,
    input  wire [7:0]  bg_color,
    output wire [9:0]  fg_code_addr,
    input  wire [7:0]  fg_code,
    output wire [9:0]  fg_color_addr,
    input  wire [7:0]  fg_color,
    output wire [11:0] gfx_addr,
    input  wire [7:0]  gfx_hi,
    input  wire [7:0]  gfx_lo,
    output wire [10:0] char_addr,
    input  wire [7:0]  char_hi,
    input  wire [7:0]  char_lo,
    output wire [5:0]  prom_addr,
    input  wire [7:0]  prom_data,

    input  wire        overlay_pix,     // debug text, aligned with h/v
    input  wire        show_overlay,

    output reg  [23:0] rgb,
    output reg         de,
    output reg         hs,
    output reg         vs
);

    localparam H_TOTAL = 360, H_ACTIVE = 256, HS_X = 300;
    localparam V_TOTAL = 262, V_ACTIVE = 224, VS_Y = 240;

    wire active = h < H_ACTIVE && v < V_ACTIVE;
    assign vblank_start = ce_pix && h == 9'd0 && v == V_ACTIVE;

    always @(posedge clk_sys) begin
        if (reset) begin
            h <= RESET_H;
            v <= RESET_V;
        end else if (ss_restore) begin
            h <= ss_h;
            v <= ss_v;
        end else if (ce_pix) begin
            if (h == H_TOTAL - 1) begin
                h <= 9'd0;
                v <= v == V_TOTAL - 1 ? 9'd0 : v + 9'd1;
            end else begin
                h <= h + 9'd1;
            end
        end
    end

    wire       charbank  = !ctrl[3];
    wire [2:0] backcolor = ctrl[2:0];

    // A: tile addresses. The background is scrolled: screen (x, y) shows
    // background pixel (x + scroll_x, y + scroll_y).
    wire [7:0] bx = h[7:0] + scroll_x;
    wire [7:0] by = v[7:0] + scroll_y;

    assign bg_code_addr  = {by[7:3], bx[7:3]};
    assign bg_color_addr = {by[7:3], bx[7:3]};
    assign fg_code_addr  = {v[7:3], h[7:3]};
    assign fg_color_addr = {v[7:3], h[7:3]};

    // B: pattern addresses, 8 bytes per character
    reg [2:0] b_bgx, b_bgy, b_fgx, b_fgy;
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            b_bgx <= bx[2:0];
            b_bgy <= by[2:0];
            b_fgx <= h[2:0];
            b_fgy <= v[2:0];
        end
    end

    assign gfx_addr  = {charbank, bg_code, b_bgy};
    assign char_addr = {fg_code, b_fgy};

    // C: pens (leftmost pixel is bit 7) and the color PROM address.
    // PROM 0x00-0x1F: foreground; 0x20-0x3F: background, where pen 0 shows
    // the back color register instead of its own entry.
    reg [2:0] c_bgx, c_fgx, c_bgcol, c_fgcol;
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            c_bgx   <= b_bgx;
            c_fgx   <= b_fgx;
            c_bgcol <= bg_color[5:3];
            c_fgcol <= fg_color[2:0];
        end
    end

    wire [1:0] bg_pen = {gfx_hi[~c_bgx], gfx_lo[~c_bgx]};
    wire [1:0] fg_pen = {char_hi[~c_fgx], char_lo[~c_fgx]};

    assign prom_addr = fg_pen != 2'd0 ? {1'b0, c_fgcol, fg_pen} :
                       bg_pen != 2'd0 ? {1'b1, c_bgcol, bg_pen} :
                                        {1'b1, backcolor, 2'b00};

    // D: PROM byte to RGB, using the board's resistor weights
    function [23:0] pal_rgb(input [7:0] p);
        reg [7:0] r, g, b;
        begin
            r = (p[0] ? 8'h21 : 8'h00) + (p[1] ? 8'h47 : 8'h00) + (p[2] ? 8'h97 : 8'h00);
            g = (p[3] ? 8'h21 : 8'h00) + (p[4] ? 8'h47 : 8'h00) + (p[5] ? 8'h97 : 8'h00);
            b = (p[6] ? 8'h52 : 8'h00) + (p[7] ? 8'hAD : 8'h00);
            pal_rgb = {r, g, b};
        end
    endfunction

    // sync, DE and overlay follow the pixel through the same 3 stages
    reg [3:0] dly1, dly2, dly3;     // {active, hs, vs, overlay}
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            dly1 <= {active, h == HS_X, h == HS_X - 10 && v == VS_Y, overlay_pix && show_overlay};
            dly2 <= dly1;
            dly3 <= dly2;

            de <= dly3[3];
            hs <= dly3[2];
            vs <= dly3[1];
            if (!dly3[3])
                rgb <= 24'h000000;
            else if (dly3[0])
                rgb <= 24'hFFFFFF;
            else
                rgb <= pal_rgb(prom_data);
        end
    end

endmodule
