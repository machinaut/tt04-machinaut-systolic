`default_nettype none
`timescale 1ns/1ps

// testbench is controlled by test.py
module pipetb ();

    // this part dumps the trace to a vcd file that can be viewed with GTKWave
    initial begin
        $dumpfile ("pipetb.vcd");
        $dumpvars (0, pipetb);
        #1;
    end

    // Pipeline inputs
    wire [7:0]  PipeA;  // A input to pipeline
    wire [7:0]  PipeB;  // B input to pipeline
    wire [15:0] PipeC;  // C input to pipeline
    wire        PipeAfmt;  // A FP8 format
    wire        PipeBfmt;  // B FP8 format
    wire        PipeSave;  // Save flag
    // Pipeline outputs
    // Stage 0
    wire [33:0] Pipe0w;
    wire        Pipe0Save;
    // Stage 1
    wire [31:0] Pipe1w;  // Pipeline 1 output
    wire        Pipe1Save;  // Pipeline 1 output Save
    // Stage 2
    wire [39:0] Pipe2w;  // Pipeline 2 output
    wire        Pipe2Save;  // Pipeline 2 output Save
    // Stage 3
    wire [15:0] Pipe3w;  // Pipeline 3 output (to C)
    wire        Pipe3Save;  // Pipeline 3 output Save

    // Pipeline stages
    pipe0 p0(
        .A(PipeA), .B(PipeB), .C(PipeC), .Afmt(PipeAfmt), .Bfmt(PipeBfmt), .save(PipeSave),
        .out(Pipe0w), .saveout(Pipe0Save)
        );
    pipe1 p1(
        .in(Pipe0w), .save(Pipe0Save),
        .out(Pipe1w), .saveout(Pipe1Save));
    pipe2 p2(.in(Pipe1w), .save(Pipe1Save), .out(Pipe2w), .saveout(Pipe2Save));
    pipe3 p3(.in(Pipe2w), .save(Pipe2Save), .out(Pipe3w), .saveout(Pipe3Save));

endmodule
