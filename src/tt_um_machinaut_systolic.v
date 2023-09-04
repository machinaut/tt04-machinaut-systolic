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

// Addresses for Columns and Rows
// Address is encoded as the top two bits of the _ctrl_ signal
// Address  Column  Row
// 0        pass    pass
// 1        A       B
// 2        C0      C1
// 3        C2      C3

// Pipeline modules
// Input multiplexer to pick what's going into the first pipeline stage this clock
module pipeIn (
    input wire [1:0] cnt,  // state counter
    input wire [15:0] ci, input wire [15:0] co,  // column in/out
    input wire [15:0] ri, input wire [15:0] ro,  // row in/out
    // accumulator state
    input wire [15:0] C0, input wire [15:0] C1, input wire [15:0] C2, input wire [15:0] C3,
    // these will go into pipeline 0 this clock
    output wire [7:0] A,  output wire [7:0] B, output wire [15:0] C
);
    // ci/co are A0 (15:8) and A1 (7:0)
    // ri/ro are B0 (15:8) and B1 (7:0)
    // Aliases for clarity
    wire [7:0] A0i; wire [7:0] A1i; wire [7:0] A0o; wire [7:0] A1o;
    wire [7:0] B0i; wire [7:0] B1i; wire [7:0] B0o; wire [7:0] B1o;
    assign A0i = ci[15:8]; assign A1i = ci[7:0]; assign A0o = co[15:8]; assign A1o = co[7:0];
    assign B0i = ri[15:8]; assign B1i = ri[7:0]; assign B0o = ro[15:8]; assign B1o = ro[7:0];
    // If state is 2, read A0/B0 from inputs and C0 from accumulator
    // If state is 3, read A1/B0 from inputs and C1 from accumulator
    // If state is 0, read A0/B1 from outputs and C2 from accumulator
    // If state is 1, read A1/B1 from outputs and C3 from accumulator
    assign A = (cnt == 2) ? A0i : (cnt == 3) ? A1i : (cnt == 0) ? A0o : A1o;
    assign B = (cnt == 2) ? B0i : (cnt == 3) ? B0i : (cnt == 0) ? B1o : B1o;
    assign C = (cnt == 2) ? C0 : (cnt == 3) ? C1 : (cnt == 0) ? C2 : C3;
endmodule
module pipe0 (
    input  wire [7:0] A, input  wire [7:0] B, input  wire [15:0] C,
    output wire [27:0] out
);
    wire [15:0] Cout;
    // XOR the top two bits of A and B to the top 2 bits of each byte of C
    assign Cout = {C[15:14] ^ A[7:6], C[13:8], C[7:6] ^ B[7:6], C[5:0]};
    assign out = {A[5:0], B[5:0], Cout};
endmodule
module pipe1 (
    input wire [27:0] in,
    output wire [23:0] out
);
    // Unpack inputs
    wire [5:0] A;
    wire [5:0] B;
    wire [15:0] C;
    wire [15:0] Cout;
    assign A = in[27:22];
    assign B = in[21:16];
    assign C = in[15:0];
    // XOR the next two bits of A and B to the next 2 bits of each byte of C
    assign Cout = {C[15:14], C[13:12] ^ A[5:4], C[11:6], C[5:4] ^ B[5:4], C[3:0]};
    assign out = {A[3:0], B[3:0], Cout};
endmodule
module pipe2 (
    input wire [23:0] in,
    output wire [19:0] out
);
    // Unpack inputs
    wire [3:0] A;
    wire [3:0] B;
    wire [15:0] C;
    wire [15:0] Cout;
    assign A = in[23:20];
    assign B = in[19:16];
    assign C = in[15:0];
    // XOR the next two bits of A and B to the next 2 bits of each byte of C
    assign Cout = {C[15:12], C[11:10] ^ A[3:2], C[9:4], C[3:2] ^ B[3:2], C[1:0]};
    assign out = {A[1:0], B[1:0], Cout};
endmodule
module pipe3 (
    input wire [19:0] in,
    output wire [15:0] out
);
    // Unpack inputs
    wire [1:0] A;
    wire [1:0] B;
    wire [15:0] C;
    wire [15:0] Cout;
    assign A = in[19:18];
    assign B = in[17:16];
    assign C = in[15:0];
    // XOR the next two bits of A and B to the next 2 bits of each byte of C
    assign Cout = {C[15:10], C[9:8] ^ A[1:0], C[7:2], C[1:0] ^ B[1:0]};
    assign out = Cout;
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

    // Accumulator
    reg [15:0] C [0:3];
    // Pipeline
    wire [7:0] PipeA;  // A input to pipeline
    wire [7:0] PipeB;  // B input to pipeline
    wire [15:0] PipeC;  // C input to pipeline
    wire [27:0] Pipe0w;  // Pipeline 0 output
    reg  [27:0] Pipe0s;  // Pipeline 0 state
    reg         Save0s;  // Pipeline 0 state Save
    wire [23:0] Pipe1w;  // Pipeline 1 output
    wire        Save1w;  // Pipeline 1 output Save
    reg  [23:0] Pipe1s;  // Pipeline 1 state
    reg         Save1s;  // Pipeline 1 state Save
    wire [19:0] Pipe2w;  // Pipeline 2 output
    wire        Save2w;  // Pipeline 2 output Save
    reg  [19:0] Pipe2s;  // Pipeline 2 state
    reg         Save2s;  // Pipeline 2 state Save
    wire [15:0] Pipe3w;  // Pipeline 3 output (to C)
    wire        Save3w;  // Pipeline 3 output Save

    // Increment handling
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            count <= 0;
        end else begin
            count <= count + 1;
        end
    end

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

    // Output storage buffers, written at posedge clk and read at negedge clk
    always @(posedge clk) begin
        if (!rst_n) begin
            col_buf_out <= 0;
            row_buf_out <= 0;
            col_ctrl_buf_out <= 0;
            row_ctrl_buf_out <= 0;
        end else begin
            if (boundary) begin
                if (col_ctrl_in_full[3:2] == 2) begin
                    col_buf_out <= C[0];
                end else if (col_ctrl_in_full[3:2] == 3) begin
                    col_buf_out <= C[2];
                end else begin
                    col_buf_out <= col_in_full;
                end
                if (row_ctrl_in_full[3:2] == 2) begin
                    row_buf_out <= C[1];
                end else if (row_ctrl_in_full[3:2] == 3) begin
                    row_buf_out <= C[3];
                end else begin
                    row_buf_out <= row_in_full;
                end
                col_ctrl_buf_out <= col_ctrl_in_full;
                row_ctrl_buf_out <= row_ctrl_in_full;
            end
        end
    end

    // Pipeline
    // Multiplex inputs to pipeline
    pipeIn pIn(.cnt(count),
        .ci(col_in_full), .co(col_buf_out), .ri(row_in_full), .ro(row_buf_out),
        .C0(C[0]), .C1(C[1]), .C2(C[2]), .C3(C[3]),
        .A(PipeA), .B(PipeB), .C(PipeC));
    // Pipeline stages
    pipe0 p0(.A(PipeA), .B(PipeB), .C(PipeC), .out(Pipe0w));
    pipe1 p1(.in(Pipe0s), .out(Pipe1w));
    pipe2 p2(.in(Pipe1s), .out(Pipe2w));
    pipe3 p3(.in(Pipe2s), .out(Pipe3w));
    // Save bits
    assign Save1w = Save0s;
    assign Save2w = Save1s;
    assign Save3w = Save2s;
    // Latch pipeline outputs
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            Pipe0s <= 0; Pipe1s <= 0; Pipe2s <= 0;
            Save0s <= 0; Save1s <= 0; Save2s <= 0;
        end else begin
            Pipe0s <= Pipe0w; Pipe1s <= Pipe1w; Pipe2s <= Pipe2w;
            Save1s <= Save1w; Save2s <= Save2w;
            // Set Save0s based on address
            if (count == 2) begin
                Save0s <= (col_ctrl_in_full[3:2] == 1) && (row_ctrl_in_full[3:2] == 1);
            end else if (count == 3) begin
                Save0s <= (col_ctrl_in_full[3:2] == 1) && (row_ctrl_in_full[3:2] == 1);
            end else if (count == 0) begin
                Save0s <= (col_ctrl_buf_out[3:2] == 1) && (row_ctrl_buf_out[3:2] == 1);
            end else begin
                Save0s <= (col_ctrl_buf_out[3:2] == 1) && (row_ctrl_buf_out[3:2] == 1);
            end
        end
    end

    // Accumulator
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            C[0] <= 0; C[1] <= 0; C[2] <= 0; C[3] <= 0;
        end else begin
            if (count == 3) begin
                if (col_ctrl_in_full[3:2] == 2) begin
                    C[0] <= col_in_full;
                end
                if (col_ctrl_in_full[3:2] == 3) begin
                    C[2] <= col_in_full;
                end else if (Save2s) begin
                    C[2] <= Pipe3w;
                end
                if (row_ctrl_in_full[3:2] == 2) begin
                    C[1] <= row_in_full;
                end
                if (row_ctrl_in_full[3:2] == 3) begin
                    C[3] <= row_in_full;
                end
            end else if (count == 0) begin
                if (Save2s) begin
                    C[3] <= Pipe3w;
                end
            end else if (count == 1) begin
                if (Save2s) begin
                    C[0] <= Pipe3w;
                end
            end else begin
                if (Save2s) begin
                    C[1] <= Pipe3w;
                end
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
