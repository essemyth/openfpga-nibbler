//
// Single-clock dual-port RAM: port A read/write (CPU), port B read-only (video,
// high score monitor). One cycle read latency on both ports; port B only reads
// when en_b is high, so the video pipeline can advance on its pixel enable.
// Powers up zeroed, as MAME does.
//
// (Keep port B read-only: with writes on both ports Quartus no longer maps
// this to block RAM.)
//
module dpram #(
    parameter AW = 10,
    parameter DW = 8
) (
    input  wire          clk,

    input  wire          we_a,
    input  wire [AW-1:0] addr_a,
    input  wire [DW-1:0] din_a,
    output reg  [DW-1:0] dout_a,

    input  wire          en_b,
    input  wire [AW-1:0] addr_b,
    output reg  [DW-1:0] dout_b
);

    reg [DW-1:0] mem [0:(1<<AW)-1];

    integer i;
    initial for (i = 0; i < (1<<AW); i = i + 1) mem[i] = {DW{1'b0}};

    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end

    always @(posedge clk)
        if (en_b) dout_b <= mem[addr_b];

endmodule
