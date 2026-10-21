//
// Unit test for joy4way: newest direction wins, release falls back to a
// direction still held, never more than one output.
// Run: vlog joy4way.v tb_joy4way.sv; vsim -c tb_joy4way -do "run -all"
//
`timescale 1ns/1ps

module tb_joy4way;

    reg        clk = 0;
    reg  [3:0] in = 0;          // {right, left, down, up}
    wire [3:0] out;
    int        errors = 0;

    always #5 clk = ~clk;

    joy4way dut (.clk(clk), .in(in), .out(out));

    localparam UP = 4'b0001, DOWN = 4'b0010, LEFT = 4'b0100, RIGHT = 4'b1000;

    task automatic step(input [3:0] keys, input [3:0] want, input string what);
        in = keys;
        @(posedge clk); @(posedge clk); #1;
        if (out !== want) begin
            $display("FAIL %s: in=%b out=%b expected=%b", what, keys, out, want);
            errors++;
        end
    endtask

    initial begin
        step(0,            0,     "idle");
        step(UP,           UP,    "press up");
        step(UP | RIGHT,   RIGHT, "roll onto up+right: newest (right) wins");
        step(RIGHT,        RIGHT, "release up");
        step(RIGHT | DOWN, DOWN,  "roll onto right+down: down wins");
        step(RIGHT | DOWN, DOWN,  "hold diagonal: stays down");
        step(RIGHT,        RIGHT, "release down: falls back to right");
        step(0,            0,     "release all");
        step(LEFT | DOWN,  DOWN,  "two at once: one of them (lowest bit)");
        step(LEFT,         LEFT,  "release down");
        step(0,            0,     "release all");
        if (errors == 0) $display("PASS: joy4way");
        $finish;
    end

endmodule
