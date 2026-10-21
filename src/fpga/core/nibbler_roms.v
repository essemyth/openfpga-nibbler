//
// ROM storage. APF writes nibbler.rom (data slot 1) over the bridge, one 32-bit
// big-endian word at a time: file byte N+0 arrives in bits [31:24], N+3 in [7:0].
// Each ROM region gets its own block RAM so the CPU and video can read in parallel.
//
// File layout (see docs/HARDWARE.md and tools/build_rom.ps1):
//   0x0000-0x8FFF  CPU program ($3000-$BFFF)
//   0x9000-0x9FFF  gfx ic50 (BG high bit plane)
//   0xA000-0xAFFF  gfx ic51 (BG low bit plane)
//   0xB000-0xBFFF  sound ic52 (0xB000), ic53 (0xB800)
//   0xC000-0xC03F  color PROMs (FG then BG)
//
// Read ports have one clk_sys of latency; video ports only read on vid_en.
//
module nibbler_roms (
    // bridge write side, clk_74a domain
    input  wire        clk_74a,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,

    // read side, clk_sys domain
    input  wire        clk_sys,
    input  wire [15:0] cpu_addr,        // file offset, 0x0000-0x8FFF
    output wire [7:0]  cpu_data,

    input  wire        vid_en,
    input  wire [11:0] gfx_addr,        // code * 8 + row
    output wire [7:0]  gfx_hi,
    output wire [7:0]  gfx_lo,
    input  wire [5:0]  prom_addr,
    output wire [7:0]  prom_data,

    input  wire [11:0] snd_addr,
    output wire [7:0]  snd_data
);

    wire in_rom = bridge_wr && bridge_addr[31:16] == 16'h0000;

    rom_store #(.ADDR(14), .DEPTH(9216)) cpu_rom (
        .clk_w(clk_74a), .we(in_rom && bridge_addr[15:12] <= 4'h8),
        .waddr(bridge_addr[15:2]), .wdata(bridge_wr_data),
        .clk_r(clk_sys), .en(1'b1), .raddr(cpu_addr), .q(cpu_data)
    );

    rom_store #(.ADDR(10)) gfx_hi_rom (
        .clk_w(clk_74a), .we(in_rom && bridge_addr[15:12] == 4'h9),
        .waddr(bridge_addr[11:2]), .wdata(bridge_wr_data),
        .clk_r(clk_sys), .en(vid_en), .raddr(gfx_addr), .q(gfx_hi)
    );

    rom_store #(.ADDR(10)) gfx_lo_rom (
        .clk_w(clk_74a), .we(in_rom && bridge_addr[15:12] == 4'hA),
        .waddr(bridge_addr[11:2]), .wdata(bridge_wr_data),
        .clk_r(clk_sys), .en(vid_en), .raddr(gfx_addr), .q(gfx_lo)
    );

    rom_store #(.ADDR(10)) snd_rom (
        .clk_w(clk_74a), .we(in_rom && bridge_addr[15:12] == 4'hB),
        .waddr(bridge_addr[11:2]), .wdata(bridge_wr_data),
        .clk_r(clk_sys), .en(1'b1), .raddr(snd_addr), .q(snd_data)
    );

    rom_store #(.ADDR(4)) prom (
        .clk_w(clk_74a), .we(in_rom && bridge_addr[15:6] == 10'b1100_0000_00),
        .waddr(bridge_addr[5:2]), .wdata(bridge_wr_data),
        .clk_r(clk_sys), .en(vid_en), .raddr(prom_addr), .q(prom_data)
    );

endmodule


//
// One ROM region: written as 32-bit big-endian words from the bridge clock,
// read as bytes on clk_r (one cycle latency, only when en is high).
//
module rom_store #(
    parameter ADDR  = 10,               // word address bits
    parameter DEPTH = 1 << ADDR
) (
    input  wire            clk_w,
    input  wire            we,
    input  wire [ADDR-1:0] waddr,
    input  wire [31:0]     wdata,

    input  wire            clk_r,
    input  wire            en,
    input  wire [ADDR+1:0] raddr,       // byte address
    output wire [7:0]      q
);

    reg [31:0] mem [0:DEPTH-1];

    always @(posedge clk_w)
        if (we) mem[waddr] <= wdata;

    reg [31:0] word;
    reg [1:0]  sel;
    always @(posedge clk_r) begin
        if (en) begin
            word <= mem[raddr[ADDR+1:2]];
            sel  <= raddr[1:0];
        end
    end

    assign q = sel == 2'd0 ? word[31:24] :
               sel == 2'd1 ? word[23:16] :
               sel == 2'd2 ? word[15:8]  :
                             word[7:0];

endmodule
