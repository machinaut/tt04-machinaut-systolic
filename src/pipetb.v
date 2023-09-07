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
    wire        PipeAe;  // A exponent size
    wire        PipeBe;  // B exponent size
    wire        PipeSave;  // Save flag
    // Pipeline outputs
    wire [34:0] Pipe0w;  // Pipeline 0 output
    wire        Pipe0Sw;  // Pipeline 0 output Save
    wire [31:0] Pipe1w;  // Pipeline 1 output
    wire        Pipe1Sw;  // Pipeline 1 output Save
    wire [39:0] Pipe2w;  // Pipeline 2 output
    wire        Pipe2Sw;  // Pipeline 2 output Save
    wire [15:0] Pipe3w;  // Pipeline 3 output (to C)
    wire        Pipe3Sw;  // Pipeline 3 output Save

    // Pipeline stages
    pipe0 p0(
        .A(PipeA), .B(PipeB), .C(PipeC),
        .Ae(PipeAe), .Be(PipeBe), .save(PipeSave),
        .out(Pipe0w), .saveout(Pipe0Sw));
    pipe1 p1(.in(Pipe0w), .save(Pipe0Sw), .out(Pipe1w), .saveout(Pipe1Sw));  
    pipe2 p2(.in(Pipe1w), .save(Pipe1Sw), .out(Pipe2w), .saveout(Pipe2Sw));
    pipe3 p3(.in(Pipe2w), .save(Pipe2Sw), .out(Pipe3w), .saveout(Pipe3Sw));

endmodule
