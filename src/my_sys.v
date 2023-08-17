module systolic_cell (
    input clk,
    input rst_n,
    input [15:0] A, B,
    input [31:0] prevC,
    output [15:0] oldA, oldB,
    output [31:0] C
);

reg [15:0] A_reg = 16'd0, B_reg = 16'd0;
wire [31:0] product;

bfloat16_multiplier mul (.A(A), .B(B), .result(product));
float32_adder adder (.A(product), .B(prevC), .result(C));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        A_reg <= 16'd0;
        B_reg <= 16'd0;
    end else begin
        A_reg <= A;
        B_reg <= B;
    end
end

assign oldA = A_reg;
assign oldB = B_reg;

endmodule
