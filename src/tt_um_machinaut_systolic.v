`default_nettype none

module tt_um_machinaut_systolic (
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire reset = ! rst_n;
    // inputs a, b
    wire [5:0] a;
    wire [5:0] b;
    assign a = ui_in[5:0];
    assign b[1:0] = ui_in[7:6];
    assign b[5:2] = uio_in[3:0];
    // output c
    reg [11:0] c;
    assign uo_out[7:0] = c[7:0];
    assign uio_out[7:4] = c[11:8];
    assign uio_out[3:0] = 0;  // unused

    // High bits are output, low bits are input
    assign uio_oe = 8'b11110000;

    always @(posedge clk) begin
        // if reset
        if (reset) begin
            // Set all memory to zero
            c <= 0;
        end else begin
            // Multiply
            c <= a * b;
        end
    end

endmodule
