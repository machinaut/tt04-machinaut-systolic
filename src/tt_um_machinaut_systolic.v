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
    reg [0:15][3:0] row_buf_in;   // Row Input Buffer
    reg [15:0] row_ctrl_buf_in;   // Row Control Input Buffer
    reg [0:15][3:0] col_buf_out;  // Column Output Buffer
    reg [15:0] col_ctrl_buf_out;  // Column Control Output Buffer
    reg [0:15][3:0] row_buf_out;  // Row Output Buffer
    reg [15:0] row_ctrl_buf_out;  // Row Control Output Buffer
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

    // Multiply-Add
    reg [0:3][15:0] A;  // 4-vector of BF16 values
    reg [0:3][15:0] B;  // 4-vector of BF16 values
    reg [0:15][31:0] C;  // 16-vector of FP32 values
    // Concat-Xor
    reg [0:3][15:0] X;  // 4-vector of uint16 values
    reg [0:3][15:0] Y;  // 4-vector of uint16 values
    reg [0:15][31:0] Z;  // 16-vector of uint32 values

    // State
    reg [3:0] count;       // Counts to block size (not part of state debug readout)
    reg [3:0] pipe_count;  // Pipeline state -- when running continuous, should match counter
    reg continuous;        // Pipeline state -- whether we're running continuously this block
    reg col_shift_done;    // Whether we've finished shifting the column (and now passing data)
    reg row_shift_done;    // Whether we've finished shifting the row (and now passing data)

    // Pipeline Stage States
    // Vars are: A, B, C, P, S, X, Y, Z
    // Value bits:
    //    1 - sign bit
    //   11 - signed exponent
    //   28 - signed Q (2.23) with guard, round, sticky
    //    4 - flag bits (nan, inf, zero, sub)
    //   20 - unused
    reg [0:7][63:0] pipe_state0;  
    reg [0:7][63:0] pipe_state1;
    reg [0:7][63:0] pipe_state2;
    reg [0:7][63:0] pipe_state3;
    reg [0:7][63:0] pipe_state4;
    reg [0:7][63:0] pipe_state5;
    reg [0:7][63:0] pipe_state6;
    reg [0:7][63:0] pipe_state7;
    reg [0:7][63:0] pipe_state8;
    reg [0:7][63:0] pipe_state9;
    reg [0:7][63:0] pipe_state10;
    reg [0:7][63:0] pipe_state11;
    reg [0:7][63:0] pipe_state12;
    reg [0:7][63:0] pipe_state13;
    reg [0:7][63:0] pipe_state14;
    reg [0:7][63:0] pipe_state15;

    // Genvars
    genvar i;

    // Read from input buffers
    generate
        for (i = 0; i < 15; i++) begin
            always @(posedge clk) begin
                if (rst_n) begin  // Zero all regs if we're in reset
                    if (count == i) begin
                        col_buf_in[63-4*i:60-4*i] <= col_in;
                        col_ctrl_buf_in[15 - i] <= col_ctrl_in;
                        row_buf_in[i] <= row_in;
                        row_ctrl_buf_in[15 - i] <= row_ctrl_in;
                    end
                end
            end
        end
    endgenerate

    // Read and handle input on rising edge of clock
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            col_buf_in <= 0;
            col_ctrl_buf_in <= 0;
            row_buf_in <= 0;
            row_ctrl_buf_in <= 0;
            col_buf_out <= 0;
            col_ctrl_buf_out <= 0;
            row_buf_out <= 0;
            row_ctrl_buf_out <= 0;
            A <= 0;
            B <= 0;
            C <= 0;
            X <= 0;
            Y <= 0;
            Z <= 0;
            count <= 0;
            pipe_count <= 0;
            continuous <= 0;
            col_shift_done <= 0;
            row_shift_done <= 0;
            pipe_state0 <= 0;
            pipe_state1 <= 0;
            pipe_state2 <= 0;
            pipe_state3 <= 0;
            pipe_state4 <= 0;
            pipe_state5 <= 0;
            pipe_state6 <= 0;
            pipe_state7 <= 0;
            pipe_state8 <= 0;
            pipe_state9 <= 0;
            pipe_state10 <= 0;
            pipe_state11 <= 0;
            pipe_state12 <= 0;
            pipe_state13 <= 0;
            pipe_state14 <= 0;
            pipe_state15 <= 0;
        end else begin  // Everything else
            count <= count + 1; // Count up to block size
            if (continuous) pipe_count <= pipe_count + 1; // Advance Pipeline Counter


        // genvar k; 
        // generate  
        //    for (k = 0; k < 64; k++) begin
        //     assign init[k] = k;
        //            always@(posedge clk) begin
        //                    if (reset) begin
        //                            ucode[k] <= init[k];
        //                    end
        //            end
        //    end
        // endgenerate
            case (count)
                // 'h0: begin col_buf_in[63-4*i:60-4*i] <= col_in; col_ctrl_buf_in['hF] <= col_ctrl_in; row_buf_in['h0] <= row_in; row_ctrl_buf_in['hF] <= row_ctrl_in; end
                // 'h1: begin col_buf_in['h1] <= col_in; col_ctrl_buf_in['hE] <= col_ctrl_in; row_buf_in['h1] <= row_in; row_ctrl_buf_in['hE] <= row_ctrl_in; end
                // 'h2: begin col_buf_in['h2] <= col_in; col_ctrl_buf_in['hD] <= col_ctrl_in; row_buf_in['h2] <= row_in; row_ctrl_buf_in['hD] <= row_ctrl_in; end
                // 'h3: begin col_buf_in['h3] <= col_in; col_ctrl_buf_in['hC] <= col_ctrl_in; row_buf_in['h3] <= row_in; row_ctrl_buf_in['hC] <= row_ctrl_in; end
                // 'h4: begin col_buf_in['h4] <= col_in; col_ctrl_buf_in['hB] <= col_ctrl_in; row_buf_in['h4] <= row_in; row_ctrl_buf_in['hB] <= row_ctrl_in; end
                // 'h5: begin col_buf_in['h5] <= col_in; col_ctrl_buf_in['hA] <= col_ctrl_in; row_buf_in['h5] <= row_in; row_ctrl_buf_in['hA] <= row_ctrl_in; end
                // 'h6: begin col_buf_in['h6] <= col_in; col_ctrl_buf_in['h9] <= col_ctrl_in; row_buf_in['h6] <= row_in; row_ctrl_buf_in['h9] <= row_ctrl_in; end
                // 'h7: begin col_buf_in['h7] <= col_in; col_ctrl_buf_in['h8] <= col_ctrl_in; row_buf_in['h7] <= row_in; row_ctrl_buf_in['h8] <= row_ctrl_in; end
                // 'h8: begin col_buf_in['h8] <= col_in; col_ctrl_buf_in['h7] <= col_ctrl_in; row_buf_in['h8] <= row_in; row_ctrl_buf_in['h7] <= row_ctrl_in; end
                // 'h9: begin col_buf_in['h9] <= col_in; col_ctrl_buf_in['h6] <= col_ctrl_in; row_buf_in['h9] <= row_in; row_ctrl_buf_in['h6] <= row_ctrl_in; end
                // 'hA: begin col_buf_in['hA] <= col_in; col_ctrl_buf_in['h5] <= col_ctrl_in; row_buf_in['hA] <= row_in; row_ctrl_buf_in['h5] <= row_ctrl_in; end
                // 'hB: begin col_buf_in['hB] <= col_in; col_ctrl_buf_in['h4] <= col_ctrl_in; row_buf_in['hB] <= row_in; row_ctrl_buf_in['h4] <= row_ctrl_in; end
                // 'hC: begin col_buf_in['hC] <= col_in; col_ctrl_buf_in['h3] <= col_ctrl_in; row_buf_in['hC] <= row_in; row_ctrl_buf_in['h3] <= row_ctrl_in; end
                // 'hD: begin col_buf_in['hD] <= col_in; col_ctrl_buf_in['h2] <= col_ctrl_in; row_buf_in['hD] <= row_in; row_ctrl_buf_in['h2] <= row_ctrl_in; end
                // 'hE: begin col_buf_in['hE] <= col_in; col_ctrl_buf_in['h1] <= col_ctrl_in; row_buf_in['hE] <= row_in; row_ctrl_buf_in['h1] <= row_ctrl_in; end
                'hF: begin
                    // Clear buffers
                    col_buf_in <= 0;
                    col_ctrl_buf_in <= 0;
                    row_buf_in <= 0;
                    row_ctrl_buf_in <= 0;
                    // Need to be careful using the control signals, since the final bit is technically not in the buffer
                    // So effectively the column control value is {col_ctrl_buf_in[0:14], col_ctrl_in}
                    // And the row control value is {row_ctrl_buf_in[0:14], row_ctrl_in}
                    if (col_ctrl_buf_in[7] & row_ctrl_buf_in[7]) begin  // Run bit set
                        if (col_ctrl_buf_in[6] & row_ctrl_buf_in[6]) begin  // Continuous bit set
                            continuous <= 1;
                        end else begin  // Single Step
                            continuous <= 0;
                        end
                    end
                    // Separately shift in row and column data

                    // Addresses (in Hex)
                    // * 01 - Internal State
                    // * 02 - A (Math Vector)
                    // * 04 - B (Math Vector)
                    // * 08-0F - C (Math Vector)
                    // * 12 - X (Math Vector)
                    // * 14 - Y (Math Vector)
                    // * 18-1F - Z (Math Vector)
                    // * 8* - Pipeline A (* is stage, 0-F)
                    // * 9* - Pipeline B
                    // * A* - Pipeline C
                    // * B* - Pipeline P
                    // * C* - Pipeline S
                    // * D* - Pipeline X
                    // * E* - Pipeline Y
                    // * F* - Pipeline Z

                    // Silently drop shift-in if somehow both row and column are shifting into the same location
                    // Remember that becuase the last part of the data is still being input,
                    //  the data is effectively {col_buf_in[63:4], col_in}
                    if (col_ctrl_buf_in[5] && ((!row_ctrl_buf_in[5]) || (col_ctrl_buf_in[15:8] != row_ctrl_buf_in[15:8]))) begin  // Shift in column data
                        // Switch on address

                        // wire [63:0] column_dest;
                        // column_dest <= {col_buf_in[63:4], col_in};

                        // mux col_dest_mux(.addr(col_ctrl_buf_in[15:8]),.out(column_dest));



                        case (col_ctrl_buf_in[15:8])
                            // 'h01: begin end  // TODO Internal State
                            // 'h02: begin A <= {col_buf_in[63:4], col_in}; end
                            // 'h04: begin B <= {col_buf_in[63:4], col_in}; end
                            // 'h08: begin C[0:1] <= {col_buf_in[63:4], col_in}; end
                            'h02: begin A <= {col_buf_in[63:4], col_in}; end
                            'h04: begin B <= {col_buf_in[63:4], col_in}; end
                            'h08: begin C[0:1] <= {col_buf_in[63:4], col_in}; end
                            'h09: begin C[2:3] <= {col_buf_in[63:4], col_in}; end
                            'h0A: begin C[4:5] <= {col_buf_in[63:4], col_in}; end
                            'h0B: begin C[6:7] <= {col_buf_in[63:4], col_in}; end
                            'h0C: begin C[8:9] <= {col_buf_in[63:4], col_in}; end
                            'h0D: begin C[10:11] <= {col_buf_in[63:4], col_in}; end
                            'h0E: begin C[12:13] <= {col_buf_in[63:4], col_in}; end
                            'h0F: begin C[14:15] <= {col_buf_in[63:4], col_in}; end
                            'h12: begin X <= {col_buf_in[63:4], col_in}; end
                            'h14: begin Y <= {col_buf_in[63:4], col_in}; end
                            'h18: begin Z[0:1] <= {col_buf_in[63:4], col_in}; end
                            'h19: begin Z[2:3] <= {col_buf_in[63:4], col_in}; end
                            'h1A: begin Z[4:5] <= {col_buf_in[63:4], col_in}; end
                            'h1B: begin Z[6:7] <= {col_buf_in[63:4], col_in}; end
                            'h1C: begin Z[8:9] <= {col_buf_in[63:4], col_in}; end
                            'h1D: begin Z[10:11] <= {col_buf_in[63:4], col_in}; end
                            'h1E: begin Z[12:13] <= {col_buf_in[63:4], col_in}; end
                            'h1F: begin Z[14:15] <= {col_buf_in[63:4], col_in}; end
                            // Pipeline states
                            'h80: begin pipe_state0[0] <= {col_buf_in[63:4], col_in}; end
                            'h81: begin pipe_state1[0] <= {col_buf_in[63:4], col_in}; end
                            'h82: begin pipe_state2[0] <= {col_buf_in[63:4], col_in}; end
                            'h83: begin pipe_state3[0] <= {col_buf_in[63:4], col_in}; end
                            'h84: begin pipe_state4[0] <= {col_buf_in[63:4], col_in}; end
                            'h85: begin pipe_state5[0] <= {col_buf_in[63:4], col_in}; end
                            'h86: begin pipe_state6[0] <= {col_buf_in[63:4], col_in}; end
                            'h87: begin pipe_state7[0] <= {col_buf_in[63:4], col_in}; end
                            'h88: begin pipe_state8[0] <= {col_buf_in[63:4], col_in}; end
                            'h89: begin pipe_state9[0] <= {col_buf_in[63:4], col_in}; end
                            'h8A: begin pipe_state10[0] <= {col_buf_in[63:4], col_in}; end
                            'h8B: begin pipe_state11[0] <= {col_buf_in[63:4], col_in}; end
                            'h8C: begin pipe_state12[0] <= {col_buf_in[63:4], col_in}; end
                            'h8D: begin pipe_state13[0] <= {col_buf_in[63:4], col_in}; end
                            'h8E: begin pipe_state14[0] <= {col_buf_in[63:4], col_in}; end
                            'h8F: begin pipe_state15[0] <= {col_buf_in[63:4], col_in}; end
                            'h90: begin pipe_state0[1] <= {col_buf_in[63:4], col_in}; end
                            'h91: begin pipe_state1[1] <= {col_buf_in[63:4], col_in}; end
                            'h92: begin pipe_state2[1] <= {col_buf_in[63:4], col_in}; end
                            'h93: begin pipe_state3[1] <= {col_buf_in[63:4], col_in}; end
                            'h94: begin pipe_state4[1] <= {col_buf_in[63:4], col_in}; end
                            'h95: begin pipe_state5[1] <= {col_buf_in[63:4], col_in}; end
                            'h96: begin pipe_state6[1] <= {col_buf_in[63:4], col_in}; end
                            'h97: begin pipe_state7[1] <= {col_buf_in[63:4], col_in}; end
                            'h98: begin pipe_state8[1] <= {col_buf_in[63:4], col_in}; end
                            'h99: begin pipe_state9[1] <= {col_buf_in[63:4], col_in}; end
                            'h9A: begin pipe_state10[1] <= {col_buf_in[63:4], col_in}; end
                            'h9B: begin pipe_state11[1] <= {col_buf_in[63:4], col_in}; end
                            'h9C: begin pipe_state12[1] <= {col_buf_in[63:4], col_in}; end
                            'h9D: begin pipe_state13[1] <= {col_buf_in[63:4], col_in}; end
                            'h9E: begin pipe_state14[1] <= {col_buf_in[63:4], col_in}; end
                            'h9F: begin pipe_state15[1] <= {col_buf_in[63:4], col_in}; end
                            'hA0: begin pipe_state0[2] <= {col_buf_in[63:4], col_in}; end
                            'hA1: begin pipe_state1[2] <= {col_buf_in[63:4], col_in}; end
                            'hA2: begin pipe_state2[2] <= {col_buf_in[63:4], col_in}; end
                            'hA3: begin pipe_state3[2] <= {col_buf_in[63:4], col_in}; end
                            'hA4: begin pipe_state4[2] <= {col_buf_in[63:4], col_in}; end
                            'hA5: begin pipe_state5[2] <= {col_buf_in[63:4], col_in}; end
                            'hA6: begin pipe_state6[2] <= {col_buf_in[63:4], col_in}; end
                            'hA7: begin pipe_state7[2] <= {col_buf_in[63:4], col_in}; end
                            'hA8: begin pipe_state8[2] <= {col_buf_in[63:4], col_in}; end
                            'hA9: begin pipe_state9[2] <= {col_buf_in[63:4], col_in}; end
                            'hAA: begin pipe_state10[2] <= {col_buf_in[63:4], col_in}; end
                            'hAB: begin pipe_state11[2] <= {col_buf_in[63:4], col_in}; end
                            'hAC: begin pipe_state12[2] <= {col_buf_in[63:4], col_in}; end
                            'hAD: begin pipe_state13[2] <= {col_buf_in[63:4], col_in}; end
                            'hAE: begin pipe_state14[2] <= {col_buf_in[63:4], col_in}; end
                            'hAF: begin pipe_state15[2] <= {col_buf_in[63:4], col_in}; end
                            'hB0: begin pipe_state0[3] <= {col_buf_in[63:4], col_in}; end
                            'hB1: begin pipe_state1[3] <= {col_buf_in[63:4], col_in}; end
                            'hB2: begin pipe_state2[3] <= {col_buf_in[63:4], col_in}; end
                            'hB3: begin pipe_state3[3] <= {col_buf_in[63:4], col_in}; end
                            'hB4: begin pipe_state4[3] <= {col_buf_in[63:4], col_in}; end
                            'hB5: begin pipe_state5[3] <= {col_buf_in[63:4], col_in}; end
                            'hB6: begin pipe_state6[3] <= {col_buf_in[63:4], col_in}; end
                            'hB7: begin pipe_state7[3] <= {col_buf_in[63:4], col_in}; end
                            'hB8: begin pipe_state8[3] <= {col_buf_in[63:4], col_in}; end
                            'hB9: begin pipe_state9[3] <= {col_buf_in[63:4], col_in}; end
                            'hBA: begin pipe_state10[3] <= {col_buf_in[63:4], col_in}; end
                            'hBB: begin pipe_state11[3] <= {col_buf_in[63:4], col_in}; end
                            'hBC: begin pipe_state12[3] <= {col_buf_in[63:4], col_in}; end
                            'hBD: begin pipe_state13[3] <= {col_buf_in[63:4], col_in}; end
                            'hBE: begin pipe_state14[3] <= {col_buf_in[63:4], col_in}; end
                            'hBF: begin pipe_state15[3] <= {col_buf_in[63:4], col_in}; end
                            'hC0: begin pipe_state0[4] <= {col_buf_in[63:4], col_in}; end
                            'hC1: begin pipe_state1[4] <= {col_buf_in[63:4], col_in}; end
                            'hC2: begin pipe_state2[4] <= {col_buf_in[63:4], col_in}; end
                            'hC3: begin pipe_state3[4] <= {col_buf_in[63:4], col_in}; end
                            'hC4: begin pipe_state4[4] <= {col_buf_in[63:4], col_in}; end
                            'hC5: begin pipe_state5[4] <= {col_buf_in[63:4], col_in}; end
                            'hC6: begin pipe_state6[4] <= {col_buf_in[63:4], col_in}; end
                            'hC7: begin pipe_state7[4] <= {col_buf_in[63:4], col_in}; end
                            'hC8: begin pipe_state8[4] <= {col_buf_in[63:4], col_in}; end
                            'hC9: begin pipe_state9[4] <= {col_buf_in[63:4], col_in}; end
                            'hCA: begin pipe_state10[4] <= {col_buf_in[63:4], col_in}; end
                            'hCB: begin pipe_state11[4] <= {col_buf_in[63:4], col_in}; end
                            'hCC: begin pipe_state12[4] <= {col_buf_in[63:4], col_in}; end
                            'hCD: begin pipe_state13[4] <= {col_buf_in[63:4], col_in}; end
                            'hCE: begin pipe_state14[4] <= {col_buf_in[63:4], col_in}; end
                            'hCF: begin pipe_state15[4] <= {col_buf_in[63:4], col_in}; end
                            'hD0: begin pipe_state0[5] <= {col_buf_in[63:4], col_in}; end
                            'hD1: begin pipe_state1[5] <= {col_buf_in[63:4], col_in}; end
                            'hD2: begin pipe_state2[5] <= {col_buf_in[63:4], col_in}; end
                            'hD3: begin pipe_state3[5] <= {col_buf_in[63:4], col_in}; end
                            'hD4: begin pipe_state4[5] <= {col_buf_in[63:4], col_in}; end
                            'hD5: begin pipe_state5[5] <= {col_buf_in[63:4], col_in}; end
                            'hD6: begin pipe_state6[5] <= {col_buf_in[63:4], col_in}; end
                            'hD7: begin pipe_state7[5] <= {col_buf_in[63:4], col_in}; end
                            'hD8: begin pipe_state8[5] <= {col_buf_in[63:4], col_in}; end
                            'hD9: begin pipe_state9[5] <= {col_buf_in[63:4], col_in}; end
                            'hDA: begin pipe_state10[5] <= {col_buf_in[63:4], col_in}; end
                            'hDB: begin pipe_state11[5] <= {col_buf_in[63:4], col_in}; end
                            'hDC: begin pipe_state12[5] <= {col_buf_in[63:4], col_in}; end
                            'hDD: begin pipe_state13[5] <= {col_buf_in[63:4], col_in}; end
                            'hDE: begin pipe_state14[5] <= {col_buf_in[63:4], col_in}; end
                            'hDF: begin pipe_state15[5] <= {col_buf_in[63:4], col_in}; end
                            'hE0: begin pipe_state0[6] <= {col_buf_in[63:4], col_in}; end
                            'hE1: begin pipe_state1[6] <= {col_buf_in[63:4], col_in}; end
                            'hE2: begin pipe_state2[6] <= {col_buf_in[63:4], col_in}; end
                            'hE3: begin pipe_state3[6] <= {col_buf_in[63:4], col_in}; end
                            'hE4: begin pipe_state4[6] <= {col_buf_in[63:4], col_in}; end
                            'hE5: begin pipe_state5[6] <= {col_buf_in[63:4], col_in}; end
                            'hE6: begin pipe_state6[6] <= {col_buf_in[63:4], col_in}; end
                            'hE7: begin pipe_state7[6] <= {col_buf_in[63:4], col_in}; end
                            'hE8: begin pipe_state8[6] <= {col_buf_in[63:4], col_in}; end
                            'hE9: begin pipe_state9[6] <= {col_buf_in[63:4], col_in}; end
                            'hEA: begin pipe_state10[6] <= {col_buf_in[63:4], col_in}; end
                            'hEB: begin pipe_state11[6] <= {col_buf_in[63:4], col_in}; end
                            'hEC: begin pipe_state12[6] <= {col_buf_in[63:4], col_in}; end
                            'hED: begin pipe_state13[6] <= {col_buf_in[63:4], col_in}; end
                            'hEE: begin pipe_state14[6] <= {col_buf_in[63:4], col_in}; end
                            'hEF: begin pipe_state15[6] <= {col_buf_in[63:4], col_in}; end
                            'hF0: begin pipe_state0[7] <= {col_buf_in[63:4], col_in}; end
                            'hF1: begin pipe_state1[7] <= {col_buf_in[63:4], col_in}; end
                            'hF2: begin pipe_state2[7] <= {col_buf_in[63:4], col_in}; end
                            'hF3: begin pipe_state3[7] <= {col_buf_in[63:4], col_in}; end
                            'hF4: begin pipe_state4[7] <= {col_buf_in[63:4], col_in}; end
                            'hF5: begin pipe_state5[7] <= {col_buf_in[63:4], col_in}; end
                            'hF6: begin pipe_state6[7] <= {col_buf_in[63:4], col_in}; end
                            'hF7: begin pipe_state7[7] <= {col_buf_in[63:4], col_in}; end
                            'hF8: begin pipe_state8[7] <= {col_buf_in[63:4], col_in}; end
                            'hF9: begin pipe_state9[7] <= {col_buf_in[63:4], col_in}; end
                            'hFA: begin pipe_state10[7] <= {col_buf_in[63:4], col_in}; end
                            'hFB: begin pipe_state11[7] <= {col_buf_in[63:4], col_in}; end
                            'hFC: begin pipe_state12[7] <= {col_buf_in[63:4], col_in}; end
                            'hFD: begin pipe_state13[7] <= {col_buf_in[63:4], col_in}; end
                            'hFE: begin pipe_state14[7] <= {col_buf_in[63:4], col_in}; end
                            'hFF: begin pipe_state15[7] <= {col_buf_in[63:4], col_in}; end
                        endcase
                    end
                    // Exact same but for row
                    if (row_ctrl_buf_in[5] && ((!col_ctrl_buf_in[5]) || (row_ctrl_buf_in[15:8] != col_ctrl_buf_in[15:8]))) begin  // Shift in column data
                        // Switch on address
                        case (row_ctrl_buf_in[15:8])
                            // 'h01: begin end  // TODO Internal State
                            'h02: begin A <= {row_buf_in[0:14], row_in}; end
                            'h04: begin B <= {row_buf_in[0:14], row_in}; end
                            'h08: begin C[0:1] <= {row_buf_in[0:14], row_in}; end
                            'h09: begin C[2:3] <= {row_buf_in[0:14], row_in}; end
                            'h0A: begin C[4:5] <= {row_buf_in[0:14], row_in}; end
                            'h0B: begin C[6:7] <= {row_buf_in[0:14], row_in}; end
                            'h0C: begin C[8:9] <= {row_buf_in[0:14], row_in}; end
                            'h0D: begin C[10:11] <= {row_buf_in[0:14], row_in}; end
                            'h0E: begin C[12:13] <= {row_buf_in[0:14], row_in}; end
                            'h0F: begin C[14:15] <= {row_buf_in[0:14], row_in}; end
                            'h12: begin X <= {row_buf_in[0:14], row_in}; end
                            'h14: begin Y <= {row_buf_in[0:14], row_in}; end
                            'h18: begin Z[0:1] <= {row_buf_in[0:14], row_in}; end
                            'h19: begin Z[2:3] <= {row_buf_in[0:14], row_in}; end
                            'h1A: begin Z[4:5] <= {row_buf_in[0:14], row_in}; end
                            'h1B: begin Z[6:7] <= {row_buf_in[0:14], row_in}; end
                            'h1C: begin Z[8:9] <= {row_buf_in[0:14], row_in}; end
                            'h1D: begin Z[10:11] <= {row_buf_in[0:14], row_in}; end
                            'h1E: begin Z[12:13] <= {row_buf_in[0:14], row_in}; end
                            'h1F: begin Z[14:15] <= {row_buf_in[0:14], row_in}; end
                            // Pipeline states
                            'h80: begin pipe_state0[0] <= {row_buf_in[0:14], row_in}; end
                            'h81: begin pipe_state1[0] <= {row_buf_in[0:14], row_in}; end
                            'h82: begin pipe_state2[0] <= {row_buf_in[0:14], row_in}; end
                            'h83: begin pipe_state3[0] <= {row_buf_in[0:14], row_in}; end
                            'h84: begin pipe_state4[0] <= {row_buf_in[0:14], row_in}; end
                            'h85: begin pipe_state5[0] <= {row_buf_in[0:14], row_in}; end
                            'h86: begin pipe_state6[0] <= {row_buf_in[0:14], row_in}; end
                            'h87: begin pipe_state7[0] <= {row_buf_in[0:14], row_in}; end
                            'h88: begin pipe_state8[0] <= {row_buf_in[0:14], row_in}; end
                            'h89: begin pipe_state9[0] <= {row_buf_in[0:14], row_in}; end
                            'h8A: begin pipe_state10[0] <= {row_buf_in[0:14], row_in}; end
                            'h8B: begin pipe_state11[0] <= {row_buf_in[0:14], row_in}; end
                            'h8C: begin pipe_state12[0] <= {row_buf_in[0:14], row_in}; end
                            'h8D: begin pipe_state13[0] <= {row_buf_in[0:14], row_in}; end
                            'h8E: begin pipe_state14[0] <= {row_buf_in[0:14], row_in}; end
                            'h8F: begin pipe_state15[0] <= {row_buf_in[0:14], row_in}; end
                            'h90: begin pipe_state0[1] <= {row_buf_in[0:14], row_in}; end
                            'h91: begin pipe_state1[1] <= {row_buf_in[0:14], row_in}; end
                            'h92: begin pipe_state2[1] <= {row_buf_in[0:14], row_in}; end
                            'h93: begin pipe_state3[1] <= {row_buf_in[0:14], row_in}; end
                            'h94: begin pipe_state4[1] <= {row_buf_in[0:14], row_in}; end
                            'h95: begin pipe_state5[1] <= {row_buf_in[0:14], row_in}; end
                            'h96: begin pipe_state6[1] <= {row_buf_in[0:14], row_in}; end
                            'h97: begin pipe_state7[1] <= {row_buf_in[0:14], row_in}; end
                            'h98: begin pipe_state8[1] <= {row_buf_in[0:14], row_in}; end
                            'h99: begin pipe_state9[1] <= {row_buf_in[0:14], row_in}; end
                            'h9A: begin pipe_state10[1] <= {row_buf_in[0:14], row_in}; end
                            'h9B: begin pipe_state11[1] <= {row_buf_in[0:14], row_in}; end
                            'h9C: begin pipe_state12[1] <= {row_buf_in[0:14], row_in}; end
                            'h9D: begin pipe_state13[1] <= {row_buf_in[0:14], row_in}; end
                            'h9E: begin pipe_state14[1] <= {row_buf_in[0:14], row_in}; end
                            'h9F: begin pipe_state15[1] <= {row_buf_in[0:14], row_in}; end
                            'hA0: begin pipe_state0[2] <= {row_buf_in[0:14], row_in}; end
                            'hA1: begin pipe_state1[2] <= {row_buf_in[0:14], row_in}; end
                            'hA2: begin pipe_state2[2] <= {row_buf_in[0:14], row_in}; end
                            'hA3: begin pipe_state3[2] <= {row_buf_in[0:14], row_in}; end
                            'hA4: begin pipe_state4[2] <= {row_buf_in[0:14], row_in}; end
                            'hA5: begin pipe_state5[2] <= {row_buf_in[0:14], row_in}; end
                            'hA6: begin pipe_state6[2] <= {row_buf_in[0:14], row_in}; end
                            'hA7: begin pipe_state7[2] <= {row_buf_in[0:14], row_in}; end
                            'hA8: begin pipe_state8[2] <= {row_buf_in[0:14], row_in}; end
                            'hA9: begin pipe_state9[2] <= {row_buf_in[0:14], row_in}; end
                            'hAA: begin pipe_state10[2] <= {row_buf_in[0:14], row_in}; end
                            'hAB: begin pipe_state11[2] <= {row_buf_in[0:14], row_in}; end
                            'hAC: begin pipe_state12[2] <= {row_buf_in[0:14], row_in}; end
                            'hAD: begin pipe_state13[2] <= {row_buf_in[0:14], row_in}; end
                            'hAE: begin pipe_state14[2] <= {row_buf_in[0:14], row_in}; end
                            'hAF: begin pipe_state15[2] <= {row_buf_in[0:14], row_in}; end
                            'hB0: begin pipe_state0[3] <= {row_buf_in[0:14], row_in}; end
                            'hB1: begin pipe_state1[3] <= {row_buf_in[0:14], row_in}; end
                            'hB2: begin pipe_state2[3] <= {row_buf_in[0:14], row_in}; end
                            'hB3: begin pipe_state3[3] <= {row_buf_in[0:14], row_in}; end
                            'hB4: begin pipe_state4[3] <= {row_buf_in[0:14], row_in}; end
                            'hB5: begin pipe_state5[3] <= {row_buf_in[0:14], row_in}; end
                            'hB6: begin pipe_state6[3] <= {row_buf_in[0:14], row_in}; end
                            'hB7: begin pipe_state7[3] <= {row_buf_in[0:14], row_in}; end
                            'hB8: begin pipe_state8[3] <= {row_buf_in[0:14], row_in}; end
                            'hB9: begin pipe_state9[3] <= {row_buf_in[0:14], row_in}; end
                            'hBA: begin pipe_state10[3] <= {row_buf_in[0:14], row_in}; end
                            'hBB: begin pipe_state11[3] <= {row_buf_in[0:14], row_in}; end
                            'hBC: begin pipe_state12[3] <= {row_buf_in[0:14], row_in}; end
                            'hBD: begin pipe_state13[3] <= {row_buf_in[0:14], row_in}; end
                            'hBE: begin pipe_state14[3] <= {row_buf_in[0:14], row_in}; end
                            'hBF: begin pipe_state15[3] <= {row_buf_in[0:14], row_in}; end
                            'hC0: begin pipe_state0[4] <= {row_buf_in[0:14], row_in}; end
                            'hC1: begin pipe_state1[4] <= {row_buf_in[0:14], row_in}; end
                            'hC2: begin pipe_state2[4] <= {row_buf_in[0:14], row_in}; end
                            'hC3: begin pipe_state3[4] <= {row_buf_in[0:14], row_in}; end
                            'hC4: begin pipe_state4[4] <= {row_buf_in[0:14], row_in}; end
                            'hC5: begin pipe_state5[4] <= {row_buf_in[0:14], row_in}; end
                            'hC6: begin pipe_state6[4] <= {row_buf_in[0:14], row_in}; end
                            'hC7: begin pipe_state7[4] <= {row_buf_in[0:14], row_in}; end
                            'hC8: begin pipe_state8[4] <= {row_buf_in[0:14], row_in}; end
                            'hC9: begin pipe_state9[4] <= {row_buf_in[0:14], row_in}; end
                            'hCA: begin pipe_state10[4] <= {row_buf_in[0:14], row_in}; end
                            'hCB: begin pipe_state11[4] <= {row_buf_in[0:14], row_in}; end
                            'hCC: begin pipe_state12[4] <= {row_buf_in[0:14], row_in}; end
                            'hCD: begin pipe_state13[4] <= {row_buf_in[0:14], row_in}; end
                            'hCE: begin pipe_state14[4] <= {row_buf_in[0:14], row_in}; end
                            'hCF: begin pipe_state15[4] <= {row_buf_in[0:14], row_in}; end
                            'hD0: begin pipe_state0[5] <= {row_buf_in[0:14], row_in}; end
                            'hD1: begin pipe_state1[5] <= {row_buf_in[0:14], row_in}; end
                            'hD2: begin pipe_state2[5] <= {row_buf_in[0:14], row_in}; end
                            'hD3: begin pipe_state3[5] <= {row_buf_in[0:14], row_in}; end
                            'hD4: begin pipe_state4[5] <= {row_buf_in[0:14], row_in}; end
                            'hD5: begin pipe_state5[5] <= {row_buf_in[0:14], row_in}; end
                            'hD6: begin pipe_state6[5] <= {row_buf_in[0:14], row_in}; end
                            'hD7: begin pipe_state7[5] <= {row_buf_in[0:14], row_in}; end
                            'hD8: begin pipe_state8[5] <= {row_buf_in[0:14], row_in}; end
                            'hD9: begin pipe_state9[5] <= {row_buf_in[0:14], row_in}; end
                            'hDA: begin pipe_state10[5] <= {row_buf_in[0:14], row_in}; end
                            'hDB: begin pipe_state11[5] <= {row_buf_in[0:14], row_in}; end
                            'hDC: begin pipe_state12[5] <= {row_buf_in[0:14], row_in}; end
                            'hDD: begin pipe_state13[5] <= {row_buf_in[0:14], row_in}; end
                            'hDE: begin pipe_state14[5] <= {row_buf_in[0:14], row_in}; end
                            'hDF: begin pipe_state15[5] <= {row_buf_in[0:14], row_in}; end
                            'hE0: begin pipe_state0[6] <= {row_buf_in[0:14], row_in}; end
                            'hE1: begin pipe_state1[6] <= {row_buf_in[0:14], row_in}; end
                            'hE2: begin pipe_state2[6] <= {row_buf_in[0:14], row_in}; end
                            'hE3: begin pipe_state3[6] <= {row_buf_in[0:14], row_in}; end
                            'hE4: begin pipe_state4[6] <= {row_buf_in[0:14], row_in}; end
                            'hE5: begin pipe_state5[6] <= {row_buf_in[0:14], row_in}; end
                            'hE6: begin pipe_state6[6] <= {row_buf_in[0:14], row_in}; end
                            'hE7: begin pipe_state7[6] <= {row_buf_in[0:14], row_in}; end
                            'hE8: begin pipe_state8[6] <= {row_buf_in[0:14], row_in}; end
                            'hE9: begin pipe_state9[6] <= {row_buf_in[0:14], row_in}; end
                            'hEA: begin pipe_state10[6] <= {row_buf_in[0:14], row_in}; end
                            'hEB: begin pipe_state11[6] <= {row_buf_in[0:14], row_in}; end
                            'hEC: begin pipe_state12[6] <= {row_buf_in[0:14], row_in}; end
                            'hED: begin pipe_state13[6] <= {row_buf_in[0:14], row_in}; end
                            'hEE: begin pipe_state14[6] <= {row_buf_in[0:14], row_in}; end
                            'hEF: begin pipe_state15[6] <= {row_buf_in[0:14], row_in}; end
                            'hF0: begin pipe_state0[7] <= {row_buf_in[0:14], row_in}; end
                            'hF1: begin pipe_state1[7] <= {row_buf_in[0:14], row_in}; end
                            'hF2: begin pipe_state2[7] <= {row_buf_in[0:14], row_in}; end
                            'hF3: begin pipe_state3[7] <= {row_buf_in[0:14], row_in}; end
                            'hF4: begin pipe_state4[7] <= {row_buf_in[0:14], row_in}; end
                            'hF5: begin pipe_state5[7] <= {row_buf_in[0:14], row_in}; end
                            'hF6: begin pipe_state6[7] <= {row_buf_in[0:14], row_in}; end
                            'hF7: begin pipe_state7[7] <= {row_buf_in[0:14], row_in}; end
                            'hF8: begin pipe_state8[7] <= {row_buf_in[0:14], row_in}; end
                            'hF9: begin pipe_state9[7] <= {row_buf_in[0:14], row_in}; end
                            'hFA: begin pipe_state10[7] <= {row_buf_in[0:14], row_in}; end
                            'hFB: begin pipe_state11[7] <= {row_buf_in[0:14], row_in}; end
                            'hFC: begin pipe_state12[7] <= {row_buf_in[0:14], row_in}; end
                            'hFD: begin pipe_state13[7] <= {row_buf_in[0:14], row_in}; end
                            'hFE: begin pipe_state14[7] <= {row_buf_in[0:14], row_in}; end
                            'hFF: begin pipe_state15[7] <= {row_buf_in[0:14], row_in}; end
                        endcase
                    end
                    // Set the output buffers
                        // Switch on address
                        case (col_ctrl_buf_in[15:8])
                            // 'h01: begin end  // TODO Internal State
                            'h02: begin col_buf_out <= A; end
                            'h04: begin col_buf_out <= B; end
                            'h08: begin col_buf_out <= C[0:1]; end
                            'h09: begin col_buf_out <= C[2:3]; end
                            'h0A: begin col_buf_out <= C[4:5]; end
                            'h0B: begin col_buf_out <= C[6:7]; end
                            'h0C: begin col_buf_out <= C[8:9]; end
                            'h0D: begin col_buf_out <= C[10:11]; end
                            'h0E: begin col_buf_out <= C[12:13]; end
                            'h0F: begin col_buf_out <= C[14:15]; end
                            'h12: begin col_buf_out <= X; end
                            'h14: begin col_buf_out <= Y; end
                            'h18: begin col_buf_out <= Z[0:1]; end
                            'h19: begin col_buf_out <= Z[2:3]; end
                            'h1A: begin col_buf_out <= Z[4:5]; end
                            'h1B: begin col_buf_out <= Z[6:7]; end
                            'h1C: begin col_buf_out <= Z[8:9]; end
                            'h1D: begin col_buf_out <= Z[10:11]; end
                            'h1E: begin col_buf_out <= Z[12:13]; end
                            'h1F: begin col_buf_out <= Z[14:15]; end
                            // Pipeline states
                            'h80: begin col_buf_out <= pipe_state0[0]; end
                            'h81: begin col_buf_out <= pipe_state1[0]; end
                            'h82: begin col_buf_out <= pipe_state2[0]; end
                            'h83: begin col_buf_out <= pipe_state3[0]; end
                            'h84: begin col_buf_out <= pipe_state4[0]; end
                            'h85: begin col_buf_out <= pipe_state5[0]; end
                            'h86: begin col_buf_out <= pipe_state6[0]; end
                            'h87: begin col_buf_out <= pipe_state7[0]; end
                            'h88: begin col_buf_out <= pipe_state8[0]; end
                            'h89: begin col_buf_out <= pipe_state9[0]; end
                            'h8A: begin col_buf_out <= pipe_state10[0]; end
                            'h8B: begin col_buf_out <= pipe_state11[0]; end
                            'h8C: begin col_buf_out <= pipe_state12[0]; end
                            'h8D: begin col_buf_out <= pipe_state13[0]; end
                            'h8E: begin col_buf_out <= pipe_state14[0]; end
                            'h8F: begin col_buf_out <= pipe_state15[0]; end
                            'h90: begin col_buf_out <= pipe_state0[1]; end
                            'h91: begin col_buf_out <= pipe_state1[1]; end
                            'h92: begin col_buf_out <= pipe_state2[1]; end
                            'h93: begin col_buf_out <= pipe_state3[1]; end
                            'h94: begin col_buf_out <= pipe_state4[1]; end
                            'h95: begin col_buf_out <= pipe_state5[1]; end
                            'h96: begin col_buf_out <= pipe_state6[1]; end
                            'h97: begin col_buf_out <= pipe_state7[1]; end
                            'h98: begin col_buf_out <= pipe_state8[1]; end
                            'h99: begin col_buf_out <= pipe_state9[1]; end
                            'h9A: begin col_buf_out <= pipe_state10[1]; end
                            'h9B: begin col_buf_out <= pipe_state11[1]; end
                            'h9C: begin col_buf_out <= pipe_state12[1]; end
                            'h9D: begin col_buf_out <= pipe_state13[1]; end
                            'h9E: begin col_buf_out <= pipe_state14[1]; end
                            'h9F: begin col_buf_out <= pipe_state15[1]; end
                            'hA0: begin col_buf_out <= pipe_state0[2]; end
                            'hA1: begin col_buf_out <= pipe_state1[2]; end
                            'hA2: begin col_buf_out <= pipe_state2[2]; end
                            'hA3: begin col_buf_out <= pipe_state3[2]; end
                            'hA4: begin col_buf_out <= pipe_state4[2]; end
                            'hA5: begin col_buf_out <= pipe_state5[2]; end
                            'hA6: begin col_buf_out <= pipe_state6[2]; end
                            'hA7: begin col_buf_out <= pipe_state7[2]; end
                            'hA8: begin col_buf_out <= pipe_state8[2]; end
                            'hA9: begin col_buf_out <= pipe_state9[2]; end
                            'hAA: begin col_buf_out <= pipe_state10[2]; end
                            'hAB: begin col_buf_out <= pipe_state11[2]; end
                            'hAC: begin col_buf_out <= pipe_state12[2]; end
                            'hAD: begin col_buf_out <= pipe_state13[2]; end
                            'hAE: begin col_buf_out <= pipe_state14[2]; end
                            'hAF: begin col_buf_out <= pipe_state15[2]; end
                            'hB0: begin col_buf_out <= pipe_state0[3]; end
                            'hB1: begin col_buf_out <= pipe_state1[3]; end
                            'hB2: begin col_buf_out <= pipe_state2[3]; end
                            'hB3: begin col_buf_out <= pipe_state3[3]; end
                            'hB4: begin col_buf_out <= pipe_state4[3]; end
                            'hB5: begin col_buf_out <= pipe_state5[3]; end
                            'hB6: begin col_buf_out <= pipe_state6[3]; end
                            'hB7: begin col_buf_out <= pipe_state7[3]; end
                            'hB8: begin col_buf_out <= pipe_state8[3]; end
                            'hB9: begin col_buf_out <= pipe_state9[3]; end
                            'hBA: begin col_buf_out <= pipe_state10[3]; end
                            'hBB: begin col_buf_out <= pipe_state11[3]; end
                            'hBC: begin col_buf_out <= pipe_state12[3]; end
                            'hBD: begin col_buf_out <= pipe_state13[3]; end
                            'hBE: begin col_buf_out <= pipe_state14[3]; end
                            'hBF: begin col_buf_out <= pipe_state15[3]; end
                            'hC0: begin col_buf_out <= pipe_state0[4]; end
                            'hC1: begin col_buf_out <= pipe_state1[4]; end
                            'hC2: begin col_buf_out <= pipe_state2[4]; end
                            'hC3: begin col_buf_out <= pipe_state3[4]; end
                            'hC4: begin col_buf_out <= pipe_state4[4]; end
                            'hC5: begin col_buf_out <= pipe_state5[4]; end
                            'hC6: begin col_buf_out <= pipe_state6[4]; end
                            'hC7: begin col_buf_out <= pipe_state7[4]; end
                            'hC8: begin col_buf_out <= pipe_state8[4]; end
                            'hC9: begin col_buf_out <= pipe_state9[4]; end
                            'hCA: begin col_buf_out <= pipe_state10[4]; end
                            'hCB: begin col_buf_out <= pipe_state11[4]; end
                            'hCC: begin col_buf_out <= pipe_state12[4]; end
                            'hCD: begin col_buf_out <= pipe_state13[4]; end
                            'hCE: begin col_buf_out <= pipe_state14[4]; end
                            'hCF: begin col_buf_out <= pipe_state15[4]; end
                            'hD0: begin col_buf_out <= pipe_state0[5]; end
                            'hD1: begin col_buf_out <= pipe_state1[5]; end
                            'hD2: begin col_buf_out <= pipe_state2[5]; end
                            'hD3: begin col_buf_out <= pipe_state3[5]; end
                            'hD4: begin col_buf_out <= pipe_state4[5]; end
                            'hD5: begin col_buf_out <= pipe_state5[5]; end
                            'hD6: begin col_buf_out <= pipe_state6[5]; end
                            'hD7: begin col_buf_out <= pipe_state7[5]; end
                            'hD8: begin col_buf_out <= pipe_state8[5]; end
                            'hD9: begin col_buf_out <= pipe_state9[5]; end
                            'hDA: begin col_buf_out <= pipe_state10[5]; end
                            'hDB: begin col_buf_out <= pipe_state11[5]; end
                            'hDC: begin col_buf_out <= pipe_state12[5]; end
                            'hDD: begin col_buf_out <= pipe_state13[5]; end
                            'hDE: begin col_buf_out <= pipe_state14[5]; end
                            'hDF: begin col_buf_out <= pipe_state15[5]; end
                            'hE0: begin col_buf_out <= pipe_state0[6]; end
                            'hE1: begin col_buf_out <= pipe_state1[6]; end
                            'hE2: begin col_buf_out <= pipe_state2[6]; end
                            'hE3: begin col_buf_out <= pipe_state3[6]; end
                            'hE4: begin col_buf_out <= pipe_state4[6]; end
                            'hE5: begin col_buf_out <= pipe_state5[6]; end
                            'hE6: begin col_buf_out <= pipe_state6[6]; end
                            'hE7: begin col_buf_out <= pipe_state7[6]; end
                            'hE8: begin col_buf_out <= pipe_state8[6]; end
                            'hE9: begin col_buf_out <= pipe_state9[6]; end
                            'hEA: begin col_buf_out <= pipe_state10[6]; end
                            'hEB: begin col_buf_out <= pipe_state11[6]; end
                            'hEC: begin col_buf_out <= pipe_state12[6]; end
                            'hED: begin col_buf_out <= pipe_state13[6]; end
                            'hEE: begin col_buf_out <= pipe_state14[6]; end
                            'hEF: begin col_buf_out <= pipe_state15[6]; end
                            'hF0: begin col_buf_out <= pipe_state0[7]; end
                            'hF1: begin col_buf_out <= pipe_state1[7]; end
                            'hF2: begin col_buf_out <= pipe_state2[7]; end
                            'hF3: begin col_buf_out <= pipe_state3[7]; end
                            'hF4: begin col_buf_out <= pipe_state4[7]; end
                            'hF5: begin col_buf_out <= pipe_state5[7]; end
                            'hF6: begin col_buf_out <= pipe_state6[7]; end
                            'hF7: begin col_buf_out <= pipe_state7[7]; end
                            'hF8: begin col_buf_out <= pipe_state8[7]; end
                            'hF9: begin col_buf_out <= pipe_state9[7]; end
                            'hFA: begin col_buf_out <= pipe_state10[7]; end
                            'hFB: begin col_buf_out <= pipe_state11[7]; end
                            'hFC: begin col_buf_out <= pipe_state12[7]; end
                            'hFD: begin col_buf_out <= pipe_state13[7]; end
                            'hFE: begin col_buf_out <= pipe_state14[7]; end
                            'hFF: begin col_buf_out <= pipe_state15[7]; end
                            default: begin col_buf_out <= {col_buf_in[63:4], col_in}; end
                        endcase
                        // Switch on address
                        case (row_ctrl_buf_in[15:8])
                            // 'h01: begin end  // TODO Internal State
                            'h02: begin row_buf_out <= A; end
                            'h04: begin row_buf_out <= B; end
                            'h08: begin row_buf_out <= C[0:1]; end
                            'h09: begin row_buf_out <= C[2:3]; end
                            'h0A: begin row_buf_out <= C[4:5]; end
                            'h0B: begin row_buf_out <= C[6:7]; end
                            'h0C: begin row_buf_out <= C[8:9]; end
                            'h0D: begin row_buf_out <= C[10:11]; end
                            'h0E: begin row_buf_out <= C[12:13]; end
                            'h0F: begin row_buf_out <= C[14:15]; end
                            'h12: begin row_buf_out <= X; end
                            'h14: begin row_buf_out <= Y; end
                            'h18: begin row_buf_out <= Z[0:1]; end
                            'h19: begin row_buf_out <= Z[2:3]; end
                            'h1A: begin row_buf_out <= Z[4:5]; end
                            'h1B: begin row_buf_out <= Z[6:7]; end
                            'h1C: begin row_buf_out <= Z[8:9]; end
                            'h1D: begin row_buf_out <= Z[10:11]; end
                            'h1E: begin row_buf_out <= Z[12:13]; end
                            'h1F: begin row_buf_out <= Z[14:15]; end
                            // Pipeline states
                            'h80: begin row_buf_out <= pipe_state0[0]; end
                            'h81: begin row_buf_out <= pipe_state1[0]; end
                            'h82: begin row_buf_out <= pipe_state2[0]; end
                            'h83: begin row_buf_out <= pipe_state3[0]; end
                            'h84: begin row_buf_out <= pipe_state4[0]; end
                            'h85: begin row_buf_out <= pipe_state5[0]; end
                            'h86: begin row_buf_out <= pipe_state6[0]; end
                            'h87: begin row_buf_out <= pipe_state7[0]; end
                            'h88: begin row_buf_out <= pipe_state8[0]; end
                            'h89: begin row_buf_out <= pipe_state9[0]; end
                            'h8A: begin row_buf_out <= pipe_state10[0]; end
                            'h8B: begin row_buf_out <= pipe_state11[0]; end
                            'h8C: begin row_buf_out <= pipe_state12[0]; end
                            'h8D: begin row_buf_out <= pipe_state13[0]; end
                            'h8E: begin row_buf_out <= pipe_state14[0]; end
                            'h8F: begin row_buf_out <= pipe_state15[0]; end
                            'h90: begin row_buf_out <= pipe_state0[1]; end
                            'h91: begin row_buf_out <= pipe_state1[1]; end
                            'h92: begin row_buf_out <= pipe_state2[1]; end
                            'h93: begin row_buf_out <= pipe_state3[1]; end
                            'h94: begin row_buf_out <= pipe_state4[1]; end
                            'h95: begin row_buf_out <= pipe_state5[1]; end
                            'h96: begin row_buf_out <= pipe_state6[1]; end
                            'h97: begin row_buf_out <= pipe_state7[1]; end
                            'h98: begin row_buf_out <= pipe_state8[1]; end
                            'h99: begin row_buf_out <= pipe_state9[1]; end
                            'h9A: begin row_buf_out <= pipe_state10[1]; end
                            'h9B: begin row_buf_out <= pipe_state11[1]; end
                            'h9C: begin row_buf_out <= pipe_state12[1]; end
                            'h9D: begin row_buf_out <= pipe_state13[1]; end
                            'h9E: begin row_buf_out <= pipe_state14[1]; end
                            'h9F: begin row_buf_out <= pipe_state15[1]; end
                            'hA0: begin row_buf_out <= pipe_state0[2]; end
                            'hA1: begin row_buf_out <= pipe_state1[2]; end
                            'hA2: begin row_buf_out <= pipe_state2[2]; end
                            'hA3: begin row_buf_out <= pipe_state3[2]; end
                            'hA4: begin row_buf_out <= pipe_state4[2]; end
                            'hA5: begin row_buf_out <= pipe_state5[2]; end
                            'hA6: begin row_buf_out <= pipe_state6[2]; end
                            'hA7: begin row_buf_out <= pipe_state7[2]; end
                            'hA8: begin row_buf_out <= pipe_state8[2]; end
                            'hA9: begin row_buf_out <= pipe_state9[2]; end
                            'hAA: begin row_buf_out <= pipe_state10[2]; end
                            'hAB: begin row_buf_out <= pipe_state11[2]; end
                            'hAC: begin row_buf_out <= pipe_state12[2]; end
                            'hAD: begin row_buf_out <= pipe_state13[2]; end
                            'hAE: begin row_buf_out <= pipe_state14[2]; end
                            'hAF: begin row_buf_out <= pipe_state15[2]; end
                            'hB0: begin row_buf_out <= pipe_state0[3]; end
                            'hB1: begin row_buf_out <= pipe_state1[3]; end
                            'hB2: begin row_buf_out <= pipe_state2[3]; end
                            'hB3: begin row_buf_out <= pipe_state3[3]; end
                            'hB4: begin row_buf_out <= pipe_state4[3]; end
                            'hB5: begin row_buf_out <= pipe_state5[3]; end
                            'hB6: begin row_buf_out <= pipe_state6[3]; end
                            'hB7: begin row_buf_out <= pipe_state7[3]; end
                            'hB8: begin row_buf_out <= pipe_state8[3]; end
                            'hB9: begin row_buf_out <= pipe_state9[3]; end
                            'hBA: begin row_buf_out <= pipe_state10[3]; end
                            'hBB: begin row_buf_out <= pipe_state11[3]; end
                            'hBC: begin row_buf_out <= pipe_state12[3]; end
                            'hBD: begin row_buf_out <= pipe_state13[3]; end
                            'hBE: begin row_buf_out <= pipe_state14[3]; end
                            'hBF: begin row_buf_out <= pipe_state15[3]; end
                            'hC0: begin row_buf_out <= pipe_state0[4]; end
                            'hC1: begin row_buf_out <= pipe_state1[4]; end
                            'hC2: begin row_buf_out <= pipe_state2[4]; end
                            'hC3: begin row_buf_out <= pipe_state3[4]; end
                            'hC4: begin row_buf_out <= pipe_state4[4]; end
                            'hC5: begin row_buf_out <= pipe_state5[4]; end
                            'hC6: begin row_buf_out <= pipe_state6[4]; end
                            'hC7: begin row_buf_out <= pipe_state7[4]; end
                            'hC8: begin row_buf_out <= pipe_state8[4]; end
                            'hC9: begin row_buf_out <= pipe_state9[4]; end
                            'hCA: begin row_buf_out <= pipe_state10[4]; end
                            'hCB: begin row_buf_out <= pipe_state11[4]; end
                            'hCC: begin row_buf_out <= pipe_state12[4]; end
                            'hCD: begin row_buf_out <= pipe_state13[4]; end
                            'hCE: begin row_buf_out <= pipe_state14[4]; end
                            'hCF: begin row_buf_out <= pipe_state15[4]; end
                            'hD0: begin row_buf_out <= pipe_state0[5]; end
                            'hD1: begin row_buf_out <= pipe_state1[5]; end
                            'hD2: begin row_buf_out <= pipe_state2[5]; end
                            'hD3: begin row_buf_out <= pipe_state3[5]; end
                            'hD4: begin row_buf_out <= pipe_state4[5]; end
                            'hD5: begin row_buf_out <= pipe_state5[5]; end
                            'hD6: begin row_buf_out <= pipe_state6[5]; end
                            'hD7: begin row_buf_out <= pipe_state7[5]; end
                            'hD8: begin row_buf_out <= pipe_state8[5]; end
                            'hD9: begin row_buf_out <= pipe_state9[5]; end
                            'hDA: begin row_buf_out <= pipe_state10[5]; end
                            'hDB: begin row_buf_out <= pipe_state11[5]; end
                            'hDC: begin row_buf_out <= pipe_state12[5]; end
                            'hDD: begin row_buf_out <= pipe_state13[5]; end
                            'hDE: begin row_buf_out <= pipe_state14[5]; end
                            'hDF: begin row_buf_out <= pipe_state15[5]; end
                            'hE0: begin row_buf_out <= pipe_state0[6]; end
                            'hE1: begin row_buf_out <= pipe_state1[6]; end
                            'hE2: begin row_buf_out <= pipe_state2[6]; end
                            'hE3: begin row_buf_out <= pipe_state3[6]; end
                            'hE4: begin row_buf_out <= pipe_state4[6]; end
                            'hE5: begin row_buf_out <= pipe_state5[6]; end
                            'hE6: begin row_buf_out <= pipe_state6[6]; end
                            'hE7: begin row_buf_out <= pipe_state7[6]; end
                            'hE8: begin row_buf_out <= pipe_state8[6]; end
                            'hE9: begin row_buf_out <= pipe_state9[6]; end
                            'hEA: begin row_buf_out <= pipe_state10[6]; end
                            'hEB: begin row_buf_out <= pipe_state11[6]; end
                            'hEC: begin row_buf_out <= pipe_state12[6]; end
                            'hED: begin row_buf_out <= pipe_state13[6]; end
                            'hEE: begin row_buf_out <= pipe_state14[6]; end
                            'hEF: begin row_buf_out <= pipe_state15[6]; end
                            'hF0: begin row_buf_out <= pipe_state0[7]; end
                            'hF1: begin row_buf_out <= pipe_state1[7]; end
                            'hF2: begin row_buf_out <= pipe_state2[7]; end
                            'hF3: begin row_buf_out <= pipe_state3[7]; end
                            'hF4: begin row_buf_out <= pipe_state4[7]; end
                            'hF5: begin row_buf_out <= pipe_state5[7]; end
                            'hF6: begin row_buf_out <= pipe_state6[7]; end
                            'hF7: begin row_buf_out <= pipe_state7[7]; end
                            'hF8: begin row_buf_out <= pipe_state8[7]; end
                            'hF9: begin row_buf_out <= pipe_state9[7]; end
                            'hFA: begin row_buf_out <= pipe_state10[7]; end
                            'hFB: begin row_buf_out <= pipe_state11[7]; end
                            'hFC: begin row_buf_out <= pipe_state12[7]; end
                            'hFD: begin row_buf_out <= pipe_state13[7]; end
                            'hFE: begin row_buf_out <= pipe_state14[7]; end
                            'hFF: begin row_buf_out <= pipe_state15[7]; end
                            default: begin row_buf_out <= {row_buf_in[0:14], row_in}; end
                        endcase
                    // This will be removed, for now passthrough
                    col_ctrl_buf_out <= {col_ctrl_buf_in[15:1], col_ctrl_in};
                    row_ctrl_buf_out <= {row_ctrl_buf_in[15:1], row_ctrl_in};
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
        end else begin // Write from output buffers to output lines
            case (count)
                'h0: begin col_out <= col_buf_out['h0]; col_ctrl_out <= col_ctrl_buf_out['hF]; row_out <= row_buf_out['h0]; row_ctrl_out <= row_ctrl_buf_out['hF]; end
                'h1: begin col_out <= col_buf_out['h1]; col_ctrl_out <= col_ctrl_buf_out['hE]; row_out <= row_buf_out['h1]; row_ctrl_out <= row_ctrl_buf_out['hE]; end
                'h2: begin col_out <= col_buf_out['h2]; col_ctrl_out <= col_ctrl_buf_out['hD]; row_out <= row_buf_out['h2]; row_ctrl_out <= row_ctrl_buf_out['hD]; end
                'h3: begin col_out <= col_buf_out['h3]; col_ctrl_out <= col_ctrl_buf_out['hC]; row_out <= row_buf_out['h3]; row_ctrl_out <= row_ctrl_buf_out['hC]; end
                'h4: begin col_out <= col_buf_out['h4]; col_ctrl_out <= col_ctrl_buf_out['hB]; row_out <= row_buf_out['h4]; row_ctrl_out <= row_ctrl_buf_out['hB]; end
                'h5: begin col_out <= col_buf_out['h5]; col_ctrl_out <= col_ctrl_buf_out['hA]; row_out <= row_buf_out['h5]; row_ctrl_out <= row_ctrl_buf_out['hA]; end
                'h6: begin col_out <= col_buf_out['h6]; col_ctrl_out <= col_ctrl_buf_out['h9]; row_out <= row_buf_out['h6]; row_ctrl_out <= row_ctrl_buf_out['h9]; end
                'h7: begin col_out <= col_buf_out['h7]; col_ctrl_out <= col_ctrl_buf_out['h8]; row_out <= row_buf_out['h7]; row_ctrl_out <= row_ctrl_buf_out['h8]; end
                'h8: begin col_out <= col_buf_out['h8]; col_ctrl_out <= col_ctrl_buf_out['h7]; row_out <= row_buf_out['h8]; row_ctrl_out <= row_ctrl_buf_out['h7]; end
                'h9: begin col_out <= col_buf_out['h9]; col_ctrl_out <= col_ctrl_buf_out['h6]; row_out <= row_buf_out['h9]; row_ctrl_out <= row_ctrl_buf_out['h6]; end
                'hA: begin col_out <= col_buf_out['hA]; col_ctrl_out <= col_ctrl_buf_out['h5]; row_out <= row_buf_out['hA]; row_ctrl_out <= row_ctrl_buf_out['h5]; end
                'hB: begin col_out <= col_buf_out['hB]; col_ctrl_out <= col_ctrl_buf_out['h4]; row_out <= row_buf_out['hB]; row_ctrl_out <= row_ctrl_buf_out['h4]; end
                'hC: begin col_out <= col_buf_out['hC]; col_ctrl_out <= col_ctrl_buf_out['h3]; row_out <= row_buf_out['hC]; row_ctrl_out <= row_ctrl_buf_out['h3]; end
                'hD: begin col_out <= col_buf_out['hD]; col_ctrl_out <= col_ctrl_buf_out['h2]; row_out <= row_buf_out['hD]; row_ctrl_out <= row_ctrl_buf_out['h2]; end
                'hE: begin col_out <= col_buf_out['hE]; col_ctrl_out <= col_ctrl_buf_out['h1]; row_out <= row_buf_out['hE]; row_ctrl_out <= row_ctrl_buf_out['h1]; end
                'hF: begin col_out <= col_buf_out['hF]; col_ctrl_out <= col_ctrl_buf_out['h0]; row_out <= row_buf_out['hF]; row_ctrl_out <= row_ctrl_buf_out['h0]; end
            endcase
        end
    end

endmodule
