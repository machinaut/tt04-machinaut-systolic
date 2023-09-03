`default_nettype none

// 1-bit 4-to-1 mux
module mux1b4t1 (
    input wire [3:0] in,
    input wire [1:0] addr,
    output wire out
);
    assign out = (addr == 0) ? in[3] : (addr == 1) ? in[2] : (addr == 2) ? in[1] : in[0];
endmodule

// 4-bit 4-to-1 mux
module mux4b4t1 (
    input wire [15:0] in,
    input wire [1:0] addr,
    output wire [3:0] out
);
    assign out = (addr == 0) ? in[15:12] : (addr == 1) ? in[11:8] : (addr == 2) ? in[7:4] : in[3:0];
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
    assign uio_oe[7:4] = 4'b0000;  // Unused pins
    assign uio_out[7:2] = 6'b000000;  // Unused outputs

    // Genvars
    genvar i;
    genvar j;

    // State
    wire boundary;
    reg [1:0] count; // Counts to block size
    assign boundary = (count == 3);

    // Accumulator
    reg [15:0] C [0:3];

    // Systolic Data and Control
    // Each has wires connected to external input/outputs, a buffer, and a concatenated full value
    // Column Input
    wire [3:0] col_in;
    assign col_in = ui_in[7:4];
    reg [11:0] col_buf_in;
    wire [15:0] col_in_full;
    assign col_in_full = {col_buf_in, col_in};
    // Column Control Input
    wire col_ctrl_in;
    assign uio_oe[3] = 0;
    assign col_ctrl_in = uio_in[3];
    reg [2:0] col_ctrl_buf_in;
    wire [3:0] col_ctrl_in_full;
    assign col_ctrl_in_full = {col_ctrl_buf_in, col_ctrl_in};
    wire [1:0] col_ctrl_addr;
    assign col_ctrl_addr = col_ctrl_in_full[3:2];
    // Row Input
    wire [3:0] row_in;
    assign row_in = ui_in[3:0];
    reg [11:0] row_buf_in;
    wire [15:0] row_in_full;
    assign row_in_full = {row_buf_in, row_in};
    // Row Control Input
    wire row_ctrl_in;
    assign uio_oe[2] = 0;
    assign row_ctrl_in = uio_in[2];
    reg [2:0] row_ctrl_buf_in;
    wire [3:0] row_ctrl_in_full;
    assign row_ctrl_in_full = {row_ctrl_buf_in, row_ctrl_in};
    wire [1:0] row_ctrl_addr;
    assign row_ctrl_addr = row_ctrl_in_full[3:2];
    // Column Output
    reg [3:0] col_out;
    assign uo_out[7:4] = col_out;
    reg [15:0] col_buf_out;
    // Column Control Output
    reg col_ctrl_out;
    assign uio_oe[1] = 1;
    assign uio_out[1] = col_ctrl_out;
    reg [3:0] col_ctrl_buf_out;
    // Row Output
    reg [3:0] row_out;
    assign uo_out[3:0] = row_out;
    reg [15:0] row_buf_out;
    // Row Control Output
    reg row_ctrl_out;
    assign uio_oe[0] = 1;
    assign uio_out[0] = row_ctrl_out;
    reg [3:0] row_ctrl_buf_out;


    // Read from input buffers
    generate
        for (i = 0; i < 3; i++) begin
            always @(posedge clk) begin
                if (!rst_n) begin  // Zero all regs if we're in reset
                    col_buf_in[11-4*i:8-4*i] <= 0;
                    col_ctrl_buf_in[2-i] <= 0;
                    row_buf_in[11-4*i:8-4*i] <= 0;
                    row_ctrl_buf_in[2-i] <=  0;
                end else begin
                    if (count == i) begin
                        col_buf_in[11-4*i:8-4*i] <= col_in;
                        col_ctrl_buf_in[2-i] <= col_ctrl_in;
                        row_buf_in[11-4*i:8-4*i] <= row_in;
                        row_ctrl_buf_in[2-i] <= row_ctrl_in;
                    end
                end
            end
        end
    endgenerate

    // Increment handling
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            count <= 0;
        end else begin
            count <= count + 1;
        end
    end

    // Accumulator
    generate
        for (i = 0; i < 2; i++) begin
            for (j = 0; j < 2; j++) begin
                always @(posedge clk) begin
                    if (!rst_n) begin  // Zero all regs if we're in reset
                        C[i * 2 + j] <= 0;
                    end else begin
                        if (boundary) begin
                            C[i * 2 + j] <= C[i * 2 + j] ^ {col_in_full[15-8*j:8-8*j], row_in_full[15-8*i:8-8*i]};
                        end
                    end
                end
            end
        end
    endgenerate

    // Output storage buffers, written at posedge clk and read at negedge clk
    always @(posedge clk) begin
        if (!rst_n) begin
            col_buf_out <= 0;
            row_buf_out <= 0;
            col_ctrl_buf_out <= 0;
            row_ctrl_buf_out <= 0;
        end else begin
            if (boundary) begin
                col_buf_out <= (col_ctrl_addr == 2) ? C[0] : (col_ctrl_addr == 3) ? C[2] : col_in_full;
                row_buf_out <= (row_ctrl_addr == 2) ? C[1] : (row_ctrl_addr == 3) ? C[3] : row_in_full;
                col_ctrl_buf_out <= col_ctrl_in_full;
                row_ctrl_buf_out <= row_ctrl_in_full;
            end
        end
    end

    // Output muxes
    wire [3:0] col_out_mux;
    wire col_ctrl_out_mux;
    wire [3:0] row_out_mux;
    wire row_ctrl_out_mux;

    mux4b4t1 col_mux(.in(col_buf_out), .addr(count), .out(col_out_mux));
    mux1b4t1 col_ctrl_mux(.in(col_ctrl_buf_out), .addr(count), .out(col_ctrl_out_mux));
    mux4b4t1 row_mux(.in(row_buf_out), .addr(count), .out(row_out_mux));
    mux1b4t1 row_ctrl_mux(.in(row_ctrl_buf_out), .addr(count), .out(row_ctrl_out_mux));

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
