//
// Debug text screen: live CPU and hardware state, drawn upright for the
// rotated (portrait) display.
//
// The monitor is rotated 90 degrees clockwise, so native pixel (h, v) appears
// at portrait position (x, y) = (223 - v, h). Text is laid out in portrait
// space: 14 x 16 cells of 16 x 16 pixels, 5x7 glyphs drawn at 2x.
//
module debug_overlay (
    input  wire [8:0]  h,
    input  wire [8:0]  v,

    input  wire [15:0] pc,
    input  wire [15:0] irq_count,
    input  wire [7:0]  nmi_count,
    input  wire [15:0] frame_count,
    input  wire [15:0] vram_writes,
    input  wire [15:0] char_writes,
    input  wire [7:0]  ctrl,
    input  wire [7:0]  crtc_r0, crtc_r1, crtc_r2, crtc_r4, crtc_r6, crtc_r7,
    input  wire [7:0]  scroll_x, scroll_y,
    input  wire [7:0]  in0, in2, dsw,
    input  wire [31:0] ss_dbg,         // save state controller
    input  wire [15:0] hs_dbg,         // high score saver
    input  wire [31:0] ss_magic,       // marker word found by the last state load
    input  wire [31:0] hs_first,       // first word of the loaded high score file

    output wire        pix
);

    wire [7:0] x = 8'd223 - v[7:0];
    wire [7:0] y = h[7:0];

    wire [3:0] col = x[7:4];
    wire [3:0] row = y[7:4];
    wire [2:0] gx  = x[3:1];        // 0-7, glyph columns 1-5
    wire [2:0] gy  = y[3:1];        // 0-7, glyph rows 0-6

    function [7:0] hexc(input [3:0] n);
        hexc = n < 4'd10 ? "0" + n : "A" + (n - 4'd10);
    endfunction
    function [15:0] hex2(input [7:0] n);
        hex2 = {hexc(n[7:4]), hexc(n[3:0])};
    endfunction
    function [31:0] hex4(input [15:0] n);
        hex4 = {hex2(n[15:8]), hex2(n[7:0])};
    endfunction

    // one 14-character line per row
    reg [8*14-1:0] line;
    always @* begin
        case (row)
            4'd0:  line = "NIBBLER DEBUG ";
            4'd2:  line = {"PC    ", hex4(pc), "    "};
            4'd3:  line = {"IRQ   ", hex4(irq_count), "    "};
            4'd4:  line = {"NMI   ", hex2(nmi_count), "      "};
            4'd5:  line = {"FRAME ", hex4(frame_count), "    "};
            4'd6:  line = {"VRAM  ", hex4(vram_writes), "    "};
            4'd7:  line = {"CHAR  ", hex4(char_writes), "    "};
            4'd8:  line = {"CTRL  ", hex2(ctrl), "      "};
            4'd9:  line = {"R0 ", hex2(crtc_r0), " R1 ", hex2(crtc_r1), "   "};
            4'd10: line = {"R2 ", hex2(crtc_r2), " R4 ", hex2(crtc_r4), "   "};
            4'd11: line = {"R6 ", hex2(crtc_r6), " R7 ", hex2(crtc_r7), "   "};
            4'd12: line = {"SM ", hex4(ss_magic[31:16]), hex4(ss_magic[15:0]), "   "};
            4'd13: line = {"HF ", hex4(hs_first[31:16]), hex4(hs_first[15:0]), "   "};
            4'd14: line = {"SS ", hex4(ss_dbg[31:16]), " ", hex4(ss_dbg[15:0]), " "};
            4'd15: line = {"HS ", hex4(hs_dbg), "       "};
            default: line = "              ";
        endcase
    end

    wire [7:0] ch = col < 4'd14 ? line[8*(13 - col) +: 8] : " ";

    // 5x7 font, rows top to bottom, bit 4 = leftmost pixel
    function [34:0] glyph(input [7:0] c);
        case (c)
            "0": glyph = {5'b01110, 5'b10001, 5'b10011, 5'b10101, 5'b11001, 5'b10001, 5'b01110};
            "1": glyph = {5'b00100, 5'b01100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110};
            "2": glyph = {5'b01110, 5'b10001, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b11111};
            "3": glyph = {5'b11111, 5'b00010, 5'b00100, 5'b00010, 5'b00001, 5'b10001, 5'b01110};
            "4": glyph = {5'b00010, 5'b00110, 5'b01010, 5'b10010, 5'b11111, 5'b00010, 5'b00010};
            "5": glyph = {5'b11111, 5'b10000, 5'b11110, 5'b00001, 5'b00001, 5'b10001, 5'b01110};
            "6": glyph = {5'b00110, 5'b01000, 5'b10000, 5'b11110, 5'b10001, 5'b10001, 5'b01110};
            "7": glyph = {5'b11111, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b01000, 5'b01000};
            "8": glyph = {5'b01110, 5'b10001, 5'b10001, 5'b01110, 5'b10001, 5'b10001, 5'b01110};
            "9": glyph = {5'b01110, 5'b10001, 5'b10001, 5'b01111, 5'b00001, 5'b00010, 5'b01100};
            "A": glyph = {5'b01110, 5'b10001, 5'b10001, 5'b10001, 5'b11111, 5'b10001, 5'b10001};
            "B": glyph = {5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10001, 5'b10001, 5'b11110};
            "C": glyph = {5'b01110, 5'b10001, 5'b10000, 5'b10000, 5'b10000, 5'b10001, 5'b01110};
            "D": glyph = {5'b11100, 5'b10010, 5'b10001, 5'b10001, 5'b10001, 5'b10010, 5'b11100};
            "E": glyph = {5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b10000, 5'b10000, 5'b11111};
            "F": glyph = {5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b10000, 5'b10000, 5'b10000};
            "G": glyph = {5'b01110, 5'b10001, 5'b10000, 5'b10111, 5'b10001, 5'b10001, 5'b01111};
            "H": glyph = {5'b10001, 5'b10001, 5'b10001, 5'b11111, 5'b10001, 5'b10001, 5'b10001};
            "I": glyph = {5'b01110, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110};
            "L": glyph = {5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b11111};
            "M": glyph = {5'b10001, 5'b11011, 5'b10101, 5'b10101, 5'b10001, 5'b10001, 5'b10001};
            "N": glyph = {5'b10001, 5'b10001, 5'b11001, 5'b10101, 5'b10011, 5'b10001, 5'b10001};
            "P": glyph = {5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10000, 5'b10000, 5'b10000};
            "Q": glyph = {5'b01110, 5'b10001, 5'b10001, 5'b10001, 5'b10101, 5'b10010, 5'b01101};
            "R": glyph = {5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10100, 5'b10010, 5'b10001};
            "S": glyph = {5'b01111, 5'b10000, 5'b10000, 5'b01110, 5'b00001, 5'b00001, 5'b11110};
            "T": glyph = {5'b11111, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100};
            "U": glyph = {5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01110};
            "V": glyph = {5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01010, 5'b00100};
            default: glyph = 35'd0;
        endcase
    endfunction

    wire [34:0] g = glyph(ch);
    wire [4:0]  glyph_row = g[5*(6 - gy) +: 5];
    assign pix = gx >= 3'd1 && gx <= 3'd5 && gy <= 3'd6 && glyph_row[3'd5 - gx];

endmodule
