`ifndef ADD_V
`define ADD_V

// simple adders

module half_adder (
    input  wire a,   // first input
    input  wire b,   // second input
    input  wire en,  // output enable gate
    output reg out, // output
    output reg cout // carry output
);
    always @(a, b, en) begin
        if(en == 1'b0) begin
            out = 1'bZ;
            cout = 1'bZ;
        end else begin
            out = a ^ b;
            cout = a & b;
        end
    end
endmodule

module full_adder (
    input  wire a,   // first input
    input  wire b,   // second input
    input  wire cin, // carry input
    input  wire en,  // output enable gate
    output reg out, // output
    output reg cout // carry output
);
    always @(a, b, cin, en) begin
        if(en == 1'b0) begin
            out = 1'bZ;
            cout = 1'bZ;
        end else begin
            out = (a ^ b ^ cin);
            cout = ((a ^ b) & cin) | (a & b);
        end
    end
endmodule

`endif  // ADD_V
