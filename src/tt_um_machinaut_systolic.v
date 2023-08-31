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
    // state - final dimension is block, read in 0, read out 1
    reg [15:0][3:0] ain;  // A Input (BFloat16 4-vector)
    reg [15:0][3:0] bin;  // B Input (BFloat16 4-vector)
    reg [15:0][3:0] a;  // A (BFloat16 4-vector)
    reg [15:0][3:0] b;  // B (BFloat16 4-vector)
    reg [31:0][15:0] c;  // FP32 16-vector C
    reg [5:0] state;
    // alias labels for state
    wire [1:0] cout_byte;
    wire [3:0] cout_state;
    wire [2:0] ab_sel;
    wire [1:0] ab_addr;
    wire       ab_byte;
    assign cout_byte = state[5:4];
    assign cout_state = state[3:0];
    assign ab_sel = state[3];
    assign ab_addr = state[2:1];
    assign ab_byte = state[0];
    // alias labels for input
    wire run_n;
    assign run_n = uio_in[0];
    // input/output
    reg [7:0] oe;
    reg [7:0] uo;
    reg [7:0] uout;
    assign uio_oe = oe;
    assign uio_out = uo;
    assign uo_out = uout;

    always @(posedge clk) begin
        // Set uio to inputs
        oe <= 0;
        uo <= 0;
        // Zero everything if we're in reset
        if (!rst_n) begin
            // Set all memory to zero
            ain <= '0;
            bin <= '0;
            a <= '0;
            b <= '0;
            c <= '0;
            state <= '0;
        end else begin
            if (!run_n) begin  // Run Systolic
                // Systolic pipeline
                state[3:0] <= state[3:0] + 1;
                if (!ab_sel) begin  // A vector
                    case (ab_addr)
                        0: begin case (ab_byte) 0: ain[0][15:8] <= ui_in; 0: ain[0][7:0] <= ui_in; endcase end
                        1: begin case (ab_byte) 0: ain[1][15:8] <= ui_in; 0: ain[1][7:0] <= ui_in; endcase end
                        2: begin case (ab_byte) 0: ain[2][15:8] <= ui_in; 0: ain[2][7:0] <= ui_in; endcase end
                        3: begin case (ab_byte) 0: ain[3][15:8] <= ui_in; 0: ain[3][7:0] <= ui_in; endcase end
                    endcase
                end else begin  // B vector
                    case (ab_addr)
                        0: begin case (ab_byte) 0: bin[0][15:8] <= ui_in; 0: bin[0][7:0] <= ui_in; endcase end
                        1: begin case (ab_byte) 0: bin[1][15:8] <= ui_in; 0: bin[1][7:0] <= ui_in; endcase end
                        2: begin case (ab_byte) 0: bin[2][15:8] <= ui_in; 0: bin[2][7:0] <= ui_in; endcase end
                        3: begin case (ab_byte) 0: bin[3][15:8] <= ui_in; 0: bin[3][7:0] <= ui_in; endcase end
                    endcase
                end
                if (!state[3:0]) begin // Rollover pipeline, move blocks
                    a <= ain;
                    b <= bin;
                end
            end else begin
                // Read out C vector
                state[5:0] <= state[5:0] + 1;
                case (cout_state)
                    0: begin case (cout_byte) 0: uout <= c[0][31:24]; 1: uout <= c[0][23:16]; 2: uout <= c[0][15:8]; 3: uout <= c[0][7:0]; endcase end
                    1: begin case (cout_byte) 0: uout <= c[1][31:24]; 1: uout <= c[1][23:16]; 2: uout <= c[1][15:8]; 3: uout <= c[1][7:0]; endcase end
                    2: begin case (cout_byte) 0: uout <= c[2][31:24]; 1: uout <= c[2][23:16]; 2: uout <= c[2][15:8]; 3: uout <= c[2][7:0]; endcase end
                    3: begin case (cout_byte) 0: uout <= c[3][31:24]; 1: uout <= c[3][23:16]; 2: uout <= c[3][15:8]; 3: uout <= c[3][7:0]; endcase end
                    4: begin case (cout_byte) 0: uout <= c[4][31:24]; 1: uout <= c[4][23:16]; 2: uout <= c[4][15:8]; 3: uout <= c[4][7:0]; endcase end
                    5: begin case (cout_byte) 0: uout <= c[5][31:24]; 1: uout <= c[5][23:16]; 2: uout <= c[5][15:8]; 3: uout <= c[5][7:0]; endcase end
                    6: begin case (cout_byte) 0: uout <= c[6][31:24]; 1: uout <= c[6][23:16]; 2: uout <= c[6][15:8]; 3: uout <= c[6][7:0]; endcase end
                    7: begin case (cout_byte) 0: uout <= c[7][31:24]; 1: uout <= c[7][23:16]; 2: uout <= c[7][15:8]; 3: uout <= c[7][7:0]; endcase end
                    8: begin case (cout_byte) 0: uout <= c[8][31:24]; 1: uout <= c[8][23:16]; 2: uout <= c[8][15:8]; 3: uout <= c[8][7:0]; endcase end
                    9: begin case (cout_byte) 0: uout <= c[9][31:24]; 1: uout <= c[9][23:16]; 2: uout <= c[9][15:8]; 3: uout <= c[9][7:0]; endcase end
                    10: begin case (cout_byte) 0: uout <= c[10][31:24]; 1: uout <= c[10][23:16]; 2: uout <= c[10][15:8]; 3: uout <= c[10][7:0]; endcase end
                    11: begin case (cout_byte) 0: uout <= c[11][31:24]; 1: uout <= c[11][23:16]; 2: uout <= c[11][15:8]; 3: uout <= c[11][7:0]; endcase end
                    12: begin case (cout_byte) 0: uout <= c[12][31:24]; 1: uout <= c[12][23:16]; 2: uout <= c[12][15:8]; 3: uout <= c[12][7:0]; endcase end
                    13: begin case (cout_byte) 0: uout <= c[13][31:24]; 1: uout <= c[13][23:16]; 2: uout <= c[13][15:8]; 3: uout <= c[13][7:0]; endcase end
                    14: begin case (cout_byte) 0: uout <= c[14][31:24]; 1: uout <= c[14][23:16]; 2: uout <= c[14][15:8]; 3: uout <= c[14][7:0]; endcase end
                    15: begin case (cout_byte) 0: uout <= c[15][31:24]; 1: uout <= c[15][23:16]; 2: uout <= c[15][15:8]; 3: uout <= c[15][7:0]; endcase end
                endcase
            end
        end
    end

endmodule
