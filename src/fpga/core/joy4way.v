//
// 4-way joystick from a D-pad. Only one direction is ever active, like the
// 4-way stick on the Nibbler cabinet. When a second direction is pressed
// (rolling onto a diagonal), the newly pressed one wins, which makes turning
// corners feel natural; when the active direction is released, any direction
// still held takes over.
//
module joy4way (
    input  wire       clk,
    input  wire [3:0] in,       // {right, left, down, up}
    output reg  [3:0] out = 4'd0
);

    reg [3:0] prev = 4'd0;

    // lowest set bit
    function [3:0] pick(input [3:0] d);
        pick = d & (~d + 4'd1);
    endfunction

    wire [3:0] pressed = in & ~prev;

    always @(posedge clk) begin
        prev <= in;
        if (pressed != 4'd0)
            out <= pick(pressed);
        else if ((out & in) == 4'd0)
            out <= pick(in);
    end

endmodule
