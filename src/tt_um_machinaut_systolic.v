`default_nettype none

// 1-bit 16-to-1 mux
module mux1b16t1 (
    input  wire [15:0] in,  // 16 inputs
    input  wire [3:0]  addr,  // 4-bit address
    output wire        out  // 1 output
);
    assign out = (addr == 0) ? in[15] : (addr == 1) ? in[14] : (addr == 2) ? in[13] : (addr == 3) ? in[12] : (addr == 4) ? in[11] : (addr == 5) ? in[10] : (addr == 6) ? in[9] : (addr == 7) ? in[8] : (addr == 8) ? in[7] : (addr == 9) ? in[6] : (addr == 10) ? in[5] : (addr == 11) ? in[4] : (addr == 12) ? in[3] : (addr == 13) ? in[2] : (addr == 14) ? in[1] : in[0];
endmodule

// 4-bit 16-to-1 mux
module mux4b16t1 (
    input  wire [63:0] in,  // 16 inputs
    input  wire [3:0]  addr,  // 4-bit address
    output wire [3:0]  out  // 4 outputs
);
    assign out = (addr == 0) ? in[63:60] : (addr == 1) ? in[59:56] : (addr == 2) ? in[55:52] : (addr == 3) ? in[51:48] : (addr == 4) ? in[47:44] : (addr == 5) ? in[43:40] : (addr == 6) ? in[39:36] : (addr == 7) ? in[35:32] : (addr == 8) ? in[31:28] : (addr == 9) ? in[27:24] : (addr == 10) ? in[23:20] : (addr == 11) ? in[19:16] : (addr == 12) ? in[15:12] : (addr == 13) ? in[11:8] : (addr == 14) ? in[7:4] : in[3:0];
endmodule


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
    // UIO assignments for now:
    // 7:4 - reserved for future JTAG implementation, left input for now
    // 3 - column control input
    // 2 - row control input
    // 1 - column control output
    // 0 - row control output
    assign uio_oe[7:0] = 8'b00000011;  // Set IO directions
    assign uio_out[7:2] = 6'b000000;  // Unused outputs

    // Systolic Data and Control
    // reg [0:15][3:0] col_buf_in;   // Column Input Buffer
    reg [63:0] col_buf_in;   // Column Input Buffer
    reg [15:0] col_ctrl_buf_in;   // Column Control Input Buffer
    reg [63:0] row_buf_in;   // Row Input Buffer
    reg [15:0] row_ctrl_buf_in;   // Row Control Input Buffer
    reg [63:0] col_buf_out;  // Column Output Buffer
    reg [15:0] col_ctrl_buf_out;  // Column Control Output Buffer
    reg [63:0] row_buf_out;  // Row Output Buffer
    reg [15:0] row_ctrl_buf_out;  // Row Control Output Buffer
    wire [3:0] col_in;  // Column Input
    wire col_ctrl_in;   // Column Control Input
    wire [3:0] row_in;  // Row Input
    wire row_ctrl_in;   // Row Control Input
    reg [3:0] col_out;  // Column Output
    reg col_ctrl_out;   // Column Control Output
    reg [3:0] row_out;  // Row Output
    reg row_ctrl_out;   // Row Control Output
    wire [3:0] col_out_mux;
    wire col_ctrl_out_mux;
    wire [3:0] row_out_mux;
    wire row_ctrl_out_mux;
    assign col_in = ui_in[7:4];
    assign col_ctrl_in = uio_in[3];
    assign row_in = ui_in[3:0];
    assign row_ctrl_in = uio_in[2];
    assign uo_out[7:4] = col_out;
    assign uio_out[1] = col_ctrl_out;
    assign uo_out[3:0] = row_out;
    assign uio_out[0] = row_ctrl_out;

    // Multiply-Add
    reg [63:0] A;  // 4-vector of BF16 values - read in column
    reg [63:0] B;  // 4-vector of BF16 values - read in row
    reg [511:0] C;  // 16-vector of FP32 values - accumulated

    // State
    reg [3:0] count;       // Counts to block size (not part of state debug readout)
    reg [3:0] pipe_count;  // Pipeline state -- when running continuous, should match counter
    reg continuous;        // Pipeline state -- whether we're running continuously this block
    reg col_shift_done;    // Whether we've finished shifting the column (and now passing data)
    reg row_shift_done;    // Whether we've finished shifting the row (and now passing data)

    // Addresses (in Hex)
    // * 01 - Internal State
    // * 02 - A (Math Vector)
    // * 04 - B (Math Vector)
    // * 08-0F - C (Math Vector)
    // * 1x - Pipeline Stage x

    // Pipeline Stage States   
    // Fused Multiply Add: C <= A * B + C
    // Debug Concat Xor: C <= A.B ^ C
    // Value bits:
    //    1 - sign bit
    //   11 - signed exponent
    //   28 - signed Q (2.23) with guard, round, sticky
    //    4 - flag bits (nan, inf, zero, sub)
    //   20 - unused
    reg [63:0] pipe_state [0:15];

    // Genvars
    genvar i;

    // Zero array of pipe_state regs
    generate
        for (i = 0; i < 16; i++) begin
            always @(posedge clk) begin
                if (!rst_n) begin
                    pipe_state[i] <= 0;
                end else begin
                    // write from column or row
                    // xor now to cause synthesis
                    if (count == 15) begin  // At end of block
                        if (col_ctrl_buf_in[5]) begin  // If the shift-in bit is set
                            if (col_ctrl_buf_in[15:8] == 'h10 + i) begin  // If the address matches
                                pipe_state[i] <= pipe_state[i] ^ {col_buf_in[63:4], col_in};
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    // Read and handle input on rising edge of clock
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            A <= 0;
            B <= 0;
            C <= 0;
        end else begin
            // write from column or row
            // xor now to cause synthesis
            if (count == 15) begin  // At end of block
                if (col_ctrl_buf_in[5]) begin  // If the shift-in bit is set
                    if (col_ctrl_buf_in[15:8] == 'h02) begin
                        A <= A ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h04) begin
                        B <= B ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h08) begin
                        C[511:448] <= C[511:448] ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h09) begin
                        C[447:384] <= C[447:384] ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h0A) begin
                        C[383:320] <= C[383:320] ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h0B) begin
                        C[319:256] <= C[319:256] ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h0C) begin
                        C[255:192] <= C[255:192] ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h0D) begin
                        C[191:128] <= C[191:128] ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h0E) begin
                        C[127:64] <= C[127:64] ^ {col_buf_in[63:4], col_in};
                    end else if (col_ctrl_buf_in[15:8] == 'h0F) begin
                        C[63:0] <= C[63:0] ^ {col_buf_in[63:4], col_in};
                    end
                end
            end
        end
    end

    // Read from input buffers
    generate
        for (i = 0; i < 16; i++) begin
            always @(posedge clk) begin
                if (!rst_n) begin  // Zero all regs if we're in reset
                    col_buf_in[63-4*i:60-4*i] <= 0;
                    col_ctrl_buf_in[15 - i] <= 0;
                    row_buf_in[63-4*i:60-4*i] <= 0;
                    row_ctrl_buf_in[15 - i] <=  0;
                end else begin
                    if (count == i) begin
                        col_buf_in[63-4*i:60-4*i] <= (count != 15) ? col_in : 0;
                        col_ctrl_buf_in[15 - i] <= (count != 15) ? col_ctrl_in : 0;
                        row_buf_in[63-4*i:60-4*i] <= (count != 15) ? row_in : 0;
                        row_ctrl_buf_in[15 - i] <= (count != 15) ? row_ctrl_in : 0;
                    end
                end
            end
        end
    endgenerate

    // Increment handling
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            count <= 0;
            pipe_count <= 0;
            continuous <= 0;
        end else begin
            count <= count + 1;
            if (continuous) pipe_count <= pipe_count + 1;
        end
    end

    // Output storage buffers, written at posedge clk and read at negedge clk
    always @(posedge clk) begin
        if (!rst_n) begin
            col_buf_out <= 0;
            row_buf_out <= 0;
            col_ctrl_buf_out <= 0;
            row_ctrl_buf_out <= 0;
        end else begin
            if (count == 15) begin
                col_buf_out <= {col_buf_in[63:4], col_in};
                row_buf_out <= {row_buf_in[63:4], row_in};
                col_ctrl_buf_out <= {col_ctrl_buf_in[15:1], col_ctrl_in};
                row_ctrl_buf_out <= {row_ctrl_buf_in[15:1], row_ctrl_in};
            end
        end
    end

    mux4b16t1 mux_col_out_mux(.in(col_buf_out), .addr(count), .out(col_out_mux));
    mux1b16t1 mux_col_ctrl_out_mux(.in(col_ctrl_buf_out), .addr(count), .out(col_ctrl_out_mux));
    mux4b16t1 mux_row_out_mux(.in(row_buf_out), .addr(count), .out(row_out_mux));
    mux1b16t1 mux_row_ctrl_out_mux(.in(row_ctrl_buf_out), .addr(count), .out(row_ctrl_out_mux));

    // Write to output on falling edge of clock
    always @(negedge clk) begin
        if (!rst_n) begin
            col_out <= 0;
            col_ctrl_out <= 0;
            row_out <= 0;
            row_ctrl_out <= 0;
        end else begin
            col_out <= col_out_mux;
            col_ctrl_out <= col_ctrl_out_mux;
            row_out <= row_out_mux;
            row_ctrl_out <= row_ctrl_out_mux;
        end
    end

endmodule
