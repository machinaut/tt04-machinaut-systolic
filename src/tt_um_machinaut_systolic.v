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
    wire [7:0] data_in;
    wire [6:0] addr;
    wire save;
    assign addr = ui_in[6:0];
    assign save = ui_in[7];
    assign data_in = uio_in;

    // All bidirectional IOs are inputs by default
    assign uio_oe = 8'b00000000;
    assign uio_out = 8'b00000000;  // TODO: this seems like it would create errors

    // Register array
    reg [7:0] mem [0:3];
    // Data out
    reg [7:0] data_out;
    assign uo_out = data_out;

    always @(posedge clk or posedge reset) begin
        // if reset
        if (reset) begin
            // Set all memory to zero
            mem[0] <= 0;
            mem[1] <= 0;
            mem[2] <= 0;
            mem[3] <= 0;
        end else begin
            // if save is high
            if (save) begin
                // save data_in to mem
                mem[addr] <= data_in;
            end
            // read from mem to data_out
            data_out <= mem[0];
        end
    end

endmodule
