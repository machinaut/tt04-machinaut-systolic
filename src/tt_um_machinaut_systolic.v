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
    // Unused for now
    assign uio_oe[7:4] = 4'b0000;  // Set IO directions for unused pins
    assign uio_out[7:2] = 6'b000000;  // Set IO values for unused pins

    // Systolic Data and Control
    reg [3:0] count;  // Counts to block size
    reg [0:15][3:0] col_buf_in;   // Column Input Buffer
    reg [0:15] col_ctrl_buf_in;   // Column Control Input Buffer
    reg [0:15][3:0] row_buf_in;   // Row Input Buffer
    reg [0:15] row_ctrl_buf_in;   // Row Control Input Buffer
    reg [0:15][3:0] col_buf_out;  // Column Output Buffer
    reg [0:15] col_ctrl_buf_out;  // Column Control Output Buffer
    reg [0:15][3:0] row_buf_out;  // Row Output Buffer
    reg [0:15] row_ctrl_buf_out;  // Row Control Output Buffer
    wire [3:0] col_in;  // Column Input
    wire col_ctrl_in;   // Column Control Input
    wire [3:0] row_in;  // Row Input
    wire row_ctrl_in;   // Row Control Input
    reg [3:0] col_out;  // Column Output
    reg col_ctrl_out;   // Column Control Output
    reg [3:0] row_out;  // Row Output
    reg row_ctrl_out;   // Row Control Output
    assign col_in = ui_in[7:4];
    assign col_ctrl_in = uio_in[3];
    assign row_in = ui_in[3:0];
    assign row_ctrl_in = uio_in[2];
    assign uo_out[7:4] = col_out;
    assign uio_out[1] = col_ctrl_out;
    assign uo_out[3:0] = row_out;
    assign uio_out[0] = row_ctrl_out;
    assign uio_oe[3:0] = 4'b0011;  // Set IO directions for controls

    // Read and handle input on rising edge of clock
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            count <= 0;
            col_buf_in <= 0;
            col_ctrl_buf_in <= 0;
            row_buf_in <= 0;
            row_ctrl_buf_in <= 0;
            col_buf_out <= 0;
            col_ctrl_buf_out <= 0;
            row_buf_out <= 0;
            row_ctrl_buf_out <= 0;
        end else begin
            // Count up to block size
            count <= count + 1;
            // Read from input buffers
            case (count)
                'h0: begin col_buf_in['h0] <= col_in; col_ctrl_buf_in['h0] <= col_ctrl_in; row_buf_in['h0] <= row_in; row_ctrl_buf_in['h0] <= row_ctrl_in; end
                'h1: begin col_buf_in['h1] <= col_in; col_ctrl_buf_in['h1] <= col_ctrl_in; row_buf_in['h1] <= row_in; row_ctrl_buf_in['h1] <= row_ctrl_in; end
                'h2: begin col_buf_in['h2] <= col_in; col_ctrl_buf_in['h2] <= col_ctrl_in; row_buf_in['h2] <= row_in; row_ctrl_buf_in['h2] <= row_ctrl_in; end
                'h3: begin col_buf_in['h3] <= col_in; col_ctrl_buf_in['h3] <= col_ctrl_in; row_buf_in['h3] <= row_in; row_ctrl_buf_in['h3] <= row_ctrl_in; end
                'h4: begin col_buf_in['h4] <= col_in; col_ctrl_buf_in['h4] <= col_ctrl_in; row_buf_in['h4] <= row_in; row_ctrl_buf_in['h4] <= row_ctrl_in; end
                'h5: begin col_buf_in['h5] <= col_in; col_ctrl_buf_in['h5] <= col_ctrl_in; row_buf_in['h5] <= row_in; row_ctrl_buf_in['h5] <= row_ctrl_in; end
                'h6: begin col_buf_in['h6] <= col_in; col_ctrl_buf_in['h6] <= col_ctrl_in; row_buf_in['h6] <= row_in; row_ctrl_buf_in['h6] <= row_ctrl_in; end
                'h7: begin col_buf_in['h7] <= col_in; col_ctrl_buf_in['h7] <= col_ctrl_in; row_buf_in['h7] <= row_in; row_ctrl_buf_in['h7] <= row_ctrl_in; end
                'h8: begin col_buf_in['h8] <= col_in; col_ctrl_buf_in['h8] <= col_ctrl_in; row_buf_in['h8] <= row_in; row_ctrl_buf_in['h8] <= row_ctrl_in; end
                'h9: begin col_buf_in['h9] <= col_in; col_ctrl_buf_in['h9] <= col_ctrl_in; row_buf_in['h9] <= row_in; row_ctrl_buf_in['h9] <= row_ctrl_in; end
                'hA: begin col_buf_in['hA] <= col_in; col_ctrl_buf_in['hA] <= col_ctrl_in; row_buf_in['hA] <= row_in; row_ctrl_buf_in['hA] <= row_ctrl_in; end
                'hB: begin col_buf_in['hB] <= col_in; col_ctrl_buf_in['hB] <= col_ctrl_in; row_buf_in['hB] <= row_in; row_ctrl_buf_in['hB] <= row_ctrl_in; end
                'hC: begin col_buf_in['hC] <= col_in; col_ctrl_buf_in['hC] <= col_ctrl_in; row_buf_in['hC] <= row_in; row_ctrl_buf_in['hC] <= row_ctrl_in; end
                'hD: begin col_buf_in['hD] <= col_in; col_ctrl_buf_in['hD] <= col_ctrl_in; row_buf_in['hD] <= row_in; row_ctrl_buf_in['hD] <= row_ctrl_in; end
                'hE: begin col_buf_in['hE] <= col_in; col_ctrl_buf_in['hE] <= col_ctrl_in; row_buf_in['hE] <= row_in; row_ctrl_buf_in['hE] <= row_ctrl_in; end
                'hF: begin
                    // Clear buffers
                    col_buf_in <= 0;
                    col_ctrl_buf_in <= 0;
                    row_buf_in <= 0;
                    row_ctrl_buf_in <= 0;
                    // Swap Buffers
                    col_buf_out <= {col_buf_in[0:14], col_in};
                    col_ctrl_buf_out <= {col_ctrl_buf_in[0:14], col_ctrl_in};
                    row_buf_out <= {row_buf_in[0:14], row_in};
                    row_ctrl_buf_out <= {row_ctrl_buf_in[0:14], row_ctrl_in};
                end
            endcase
        end
    end

    // Write to output on falling edge of clock
    always @(negedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            col_out <= 0;
            col_ctrl_out <= 0;
            row_out <= 0;
            row_ctrl_out <= 0;
        end else begin
            // Write from output buffers
            case (count)
                'h0: begin col_out <= col_buf_out['h0]; col_ctrl_out <= col_ctrl_buf_out['h0]; row_out <= row_buf_out['h0]; row_ctrl_out <= row_ctrl_buf_out['h0]; end
                'h1: begin col_out <= col_buf_out['h1]; col_ctrl_out <= col_ctrl_buf_out['h1]; row_out <= row_buf_out['h1]; row_ctrl_out <= row_ctrl_buf_out['h1]; end
                'h2: begin col_out <= col_buf_out['h2]; col_ctrl_out <= col_ctrl_buf_out['h2]; row_out <= row_buf_out['h2]; row_ctrl_out <= row_ctrl_buf_out['h2]; end
                'h3: begin col_out <= col_buf_out['h3]; col_ctrl_out <= col_ctrl_buf_out['h3]; row_out <= row_buf_out['h3]; row_ctrl_out <= row_ctrl_buf_out['h3]; end
                'h4: begin col_out <= col_buf_out['h4]; col_ctrl_out <= col_ctrl_buf_out['h4]; row_out <= row_buf_out['h4]; row_ctrl_out <= row_ctrl_buf_out['h4]; end
                'h5: begin col_out <= col_buf_out['h5]; col_ctrl_out <= col_ctrl_buf_out['h5]; row_out <= row_buf_out['h5]; row_ctrl_out <= row_ctrl_buf_out['h5]; end
                'h6: begin col_out <= col_buf_out['h6]; col_ctrl_out <= col_ctrl_buf_out['h6]; row_out <= row_buf_out['h6]; row_ctrl_out <= row_ctrl_buf_out['h6]; end
                'h7: begin col_out <= col_buf_out['h7]; col_ctrl_out <= col_ctrl_buf_out['h7]; row_out <= row_buf_out['h7]; row_ctrl_out <= row_ctrl_buf_out['h7]; end
                'h8: begin col_out <= col_buf_out['h8]; col_ctrl_out <= col_ctrl_buf_out['h8]; row_out <= row_buf_out['h8]; row_ctrl_out <= row_ctrl_buf_out['h8]; end
                'h9: begin col_out <= col_buf_out['h9]; col_ctrl_out <= col_ctrl_buf_out['h9]; row_out <= row_buf_out['h9]; row_ctrl_out <= row_ctrl_buf_out['h9]; end
                'hA: begin col_out <= col_buf_out['hA]; col_ctrl_out <= col_ctrl_buf_out['hA]; row_out <= row_buf_out['hA]; row_ctrl_out <= row_ctrl_buf_out['hA]; end
                'hB: begin col_out <= col_buf_out['hB]; col_ctrl_out <= col_ctrl_buf_out['hB]; row_out <= row_buf_out['hB]; row_ctrl_out <= row_ctrl_buf_out['hB]; end
                'hC: begin col_out <= col_buf_out['hC]; col_ctrl_out <= col_ctrl_buf_out['hC]; row_out <= row_buf_out['hC]; row_ctrl_out <= row_ctrl_buf_out['hC]; end
                'hD: begin col_out <= col_buf_out['hD]; col_ctrl_out <= col_ctrl_buf_out['hD]; row_out <= row_buf_out['hD]; row_ctrl_out <= row_ctrl_buf_out['hD]; end
                'hE: begin col_out <= col_buf_out['hE]; col_ctrl_out <= col_ctrl_buf_out['hE]; row_out <= row_buf_out['hE]; row_ctrl_out <= row_ctrl_buf_out['hE]; end
                'hF: begin col_out <= col_buf_out['hF]; col_ctrl_out <= col_ctrl_buf_out['hF]; row_out <= row_buf_out['hF]; row_ctrl_out <= row_ctrl_buf_out['hF]; end
            endcase
        end
    end

endmodule
