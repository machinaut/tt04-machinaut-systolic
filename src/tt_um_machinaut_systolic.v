`default_nettype none

// TODO: check all the regs in gtkwave, and look for any fast-switching ones
// TODO: just read the VCD file for these instead, somehow?

// 1-bit 4-to-1 mux
// TODO: use these in any case we switch on count
// TODO: use case statement instead of ternary
module mux1b4t1 (
    input wire [3:0] in,
    input wire [1:0] addr,
    output wire out
);
    assign out = (addr == 0) ? in[3] : (addr == 1) ? in[2] : (addr == 2) ? in[1] : in[0];
endmodule

// 4-bit 4-to-1 mux
// TODO: use these in any case we switch on count
// TODO: use case statement instead of ternary
module mux4b4t1 (
    input wire [15:0] in,
    input wire [1:0] addr,
    output wire [3:0] out
);
    assign out = (addr == 0) ? in[15:12] : (addr == 1) ? in[11:8] : (addr == 2) ? in[7:4] : in[3:0];
endmodule

// Pipeline modules
// Input multiplexer to pick what's going into the first pipeline stage this clock
module pipeIn (
    // TODO call it 'count' everywhere
    input wire [1:0] cnt,  // state counter
    input wire [15:0] ci, input wire [15:0] co,  // column in/out
    input wire [3:0] cci, input wire [3:0] cco,  // column control in/out
    input wire [15:0] ri, input wire [15:0] ro,  // row in/out
    input wire [3:0] rci, input wire [3:0] rco,  // row control in/out
    // accumulator state
    input wire [15:0] C0, input wire [15:0] C1, input wire [15:0] C2, input wire [15:0] C3,
    // these will go into pipeline 0 this clock
    output wire [7:0] A,  output wire [7:0] B, output wire [15:0] C,
    output wire Afmt, output wire Bfmt, output wire save
);
    // ci/co are A0 (15:8) and A1 (7:0)
    // ri/ro are B0 (15:8) and B1 (7:0)
    // Aliases for clarity
    wire [7:0] A0i; wire [7:0] A0o; wire [7:0] A1o;
    wire [7:0] B0i; wire [7:0] B0o; wire [7:0] B1o;
    assign A0i = ci[15:8]; assign A0o = co[15:8]; assign A1o = co[7:0];
    assign B0i = ri[15:8]; assign B0o = ro[15:8]; assign B1o = ro[7:0];
    // If state is 3, read A0/B0 from inputs and C0 from accumulator
    // If state is 0, read A1/B0 from outputs and C1 from accumulator
    // If state is 1, read A0/B1 from outputs and C2 from accumulator
    // If state is 2, read A1/B1 from outputs and C3 from accumulator
    assign Afmt = (cnt == 3) ? cci[2] : (cnt == 0) ? cco[1] : (cnt == 1) ? cco[2] : cco[1];
    assign Bfmt = (cnt == 3) ? rci[2] : (cnt == 0) ? rco[2] : (cnt == 1) ? rco[1] : rco[1];
    // TODO ADDRESS DECODE
    assign save = (cnt == 3) ? ((cci[3] == 0) && (rci[3] == 1)) : ((cco[3] == 0) && (rco[3] == 1));
    // TODO COUNT MUX
    assign A = (!save) ? 0 : (cnt == 3) ? A0i : (cnt == 0) ? A1o : (cnt == 1) ? A0o : A1o;
    assign B = (!save) ? 0 : (cnt == 3) ? B0i : (cnt == 0) ? B0o : (cnt == 1) ? B1o : B1o;
    assign C = (!save) ? 0 : (cnt == 3) ? C0  : (cnt == 0) ? C1  : (cnt == 1) ? C2 : C3;
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
    // TODO: unify these at the end of the module
    assign uio_oe[7:4] = 4'b0000;  // Unused pins
    assign uio_out[7:2] = 6'b000000;  // Unused outputs

    // Genvars
    genvar i;

    // State
    reg [1:0] count; // Counts to block size

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

    // Accumulator
    reg [15:0] C0;
    reg [15:0] C1;
    reg [15:0] C2;
    reg [15:0] C3;
    // Pipeline
    wire [7:0] PipeA;  // A input to pipeline
    wire [7:0] PipeB;  // B input to pipeline
    wire [15:0] PipeC;  // C input to pipeline
    wire        PipeAfmt;  // A exponent size
    wire        PipeBfmt;  // B exponent size
    wire        PipeSave;  // Save flag
    wire [33:0] Pipe0w;  // Pipeline 0 output
    wire        Pipe0Sw;  // Pipeline 0 output Save
    reg  [33:0] Pipe0s;  // Pipeline 0 state
    reg         Pipe0Ss;  // Pipeline 0 state Save
    wire [31:0] Pipe1w;  // Pipeline 1 output
    wire        Pipe1Sw;  // Pipeline 1 output Save
    reg  [31:0] Pipe1s;  // Pipeline 1 state
    reg         Pipe1Ss;  // Pipeline 1 state Save
    wire [39:0] Pipe2w;  // Pipeline 2 output
    wire        Pipe2Sw;  // Pipeline 2 output Save
    reg  [39:0] Pipe2s;  // Pipeline 2 state
    reg         Pipe2Ss;  // Pipeline 2 state Save
    wire [15:0] Pipe3w;  // Pipeline 3 output (to C)
    wire        Pipe3Sw;  // Pipeline 3 output Save

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
            if (count == 3) begin
                // TODO ADDRESS DECODE
                if ((col_ctrl_in_full[3:2] == 2'b10) && (row_ctrl_in_full[3:2] == 2'b01)) begin
                    col_buf_out <= C0;
                    row_buf_out <= Pipe3Sw ? Pipe3w : C1;
                end else if ((col_ctrl_in_full[3:2] == 2'b11) && (row_ctrl_in_full[3:2] == 2'b00)) begin
                    col_buf_out <= C2;
                    row_buf_out <= C3;
                end else begin
                    col_buf_out <= col_in_full;
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
        .ci(col_in_full), .co(col_buf_out),
        .cci(col_ctrl_in_full), .cco(col_ctrl_buf_out),
        .ri(row_in_full), .ro(row_buf_out),
        .rci(row_ctrl_in_full), .rco(row_ctrl_buf_out),
        .C0(C0), .C1(C1), .C2(C2), .C3(C3),
        .A(PipeA), .B(PipeB), .C(PipeC),
        .Afmt(PipeAfmt), .Bfmt(PipeBfmt), .save(PipeSave)
    );
    // Pipeline stages
    pipe0 p0(
        .A(PipeA), .B(PipeB), .C(PipeC),
        .Afmt(PipeAfmt), .Bfmt(PipeBfmt), .save(PipeSave),
        .out(Pipe0w), .saveout(Pipe0Sw));
    pipe1 p1(.in(Pipe0s), .save(Pipe0Ss), .out(Pipe1w), .saveout(Pipe1Sw));  
    pipe2 p2(.in(Pipe1s), .save(Pipe1Ss), .out(Pipe2w), .saveout(Pipe2Sw));
    pipe3 p3(.in(Pipe2s), .save(Pipe2Ss), .out(Pipe3w), .saveout(Pipe3Sw));
    // Latch pipeline outputs
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            Pipe0s <= 0; Pipe1s <= 0; Pipe2s <= 0;
            Pipe0Ss <= 0; Pipe1Ss <= 0; Pipe2Ss <= 0;
        end else begin
            Pipe0s <= Pipe0w; Pipe1s <= Pipe1w; Pipe2s <= Pipe2w;
            Pipe0Ss <= Pipe0Sw; Pipe1Ss <= Pipe1Sw; Pipe2Ss <= Pipe2Sw;
        end
    end

    // Accumulator
    always @(posedge clk) begin
        if (!rst_n) begin  // Zero all regs if we're in reset
            C0 <= 0; C1 <= 0; C2 <= 0; C3 <= 0;
        end else begin
            if (count == 3) begin
                // TODO ADDRESS DECODE
                if ((col_ctrl_in_full[3:2] == 2'b10) && (row_ctrl_in_full[3:2] == 2'b01)) begin
                    C0 <= col_in_full;
                    C1 <= row_in_full;
                end else begin
                    if ((col_ctrl_in_full[3:2] == 2'b11) && (row_ctrl_in_full[3:2] == 2'b00)) begin
                        C2 <= col_in_full;
                        C3 <= row_in_full;
                    end
                    if (Pipe3Sw) begin
                        C1 <= Pipe3w;
                    end
                end
            end else if (count == 0) begin
                if (Pipe3Sw) begin
                    C2 <= Pipe3w;
                end
            end else if (count == 1) begin
                if (Pipe3Sw) begin
                    C3 <= Pipe3w;
                end
            end else begin
                if (Pipe3Sw) begin
                    C0 <= Pipe3w;
                end
            end
        end
    end

    // Column Output
    reg [15:0] col_buf_out;
    // Column Control Output
    reg [3:0] col_ctrl_buf_out;
    // Row Output
    reg [15:0] row_buf_out;
    // Row Control Output
    reg [3:0] row_ctrl_buf_out;

    // Output muxes
    wire [3:0] col_out_mux;
    wire col_ctrl_out_mux;
    wire [3:0] row_out_mux;
    wire row_ctrl_out_mux;
    mux4b4t1 col_mux(.in(col_buf_out), .addr(count), .out(col_out_mux));
    mux1b4t1 col_ctrl_mux(.in(col_ctrl_buf_out), .addr(count), .out(col_ctrl_out_mux));
    mux4b4t1 row_mux(.in(row_buf_out), .addr(count), .out(row_out_mux));
    mux1b4t1 row_ctrl_mux(.in(row_ctrl_buf_out), .addr(count), .out(row_ctrl_out_mux));

    // Assign outputs
    assign uo_out = (!rst_n) ? 0 : {col_out_mux, row_out_mux};
    assign uio_oe[1:0] = (!rst_n) ? 0 : 2'b11;
    assign uio_out[1:0] = (!rst_n) ? 0 : {col_ctrl_out_mux, row_ctrl_out_mux};
endmodule
