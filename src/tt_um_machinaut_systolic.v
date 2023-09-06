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
// CC - Column Control Bits
// RC - Row Control Bits
// CC0 CC1 RC0 RC1 | Address
// ----------------|--------
// 0   0   0   0   | passthrough (default)
// 0   X   1   Y   | AB (X sets A datatype, Y sets B datatype)
// 1   0   0   0   | C Short (read in/out E5 format)
// 1   0   0   1   | C Low (C0, C1 in full FP16)
// 1   1   0   0   | C High (C2, C3 in full FP16)

// Pipeline modules
// Input multiplexer to pick what's going into the first pipeline stage this clock
module pipeIn (
    input wire [1:0] cnt,  // state counter
    input wire [15:0] ci, input wire [15:0] co,  // column in/out
    input wire [3:0] cci, input wire [3:0] cco,  // column control in/out
    input wire [15:0] ri, input wire [15:0] ro,  // row in/out
    input wire [3:0] rci, input wire [3:0] rco,  // row control in/out
    // accumulator state
    input wire [15:0] C0, input wire [15:0] C1, input wire [15:0] C2, input wire [15:0] C3,
    // these will go into pipeline 0 this clock
    output wire [7:0] A,  output wire [7:0] B, output wire [15:0] C,
    output wire Ae, output wire Be, output wire save
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
    assign Ae   = (cnt == 3) ? cci[2] : cco[2];
    assign Be   = (cnt == 3) ? rci[2] : rco[2];
    assign save = (cnt == 3) ? ((cci[3] == 0) && (rci[3] == 1)) : ((cco[3] == 0) && (rco[3] == 1));
    assign A = (!save) ? 0 : (cnt == 3) ? A0i : (cnt == 0) ? A1o : (cnt == 1) ? A0o : A1o;
    assign B = (!save) ? 0 : (cnt == 3) ? B0i : (cnt == 0) ? B0o : (cnt == 1) ? B1o : B1o;
    assign C = (!save) ? 0 : (cnt == 3) ? C0  : (cnt == 0) ? C1  : (cnt == 1) ? C2 : C3;
endmodule
module pipe0 (
    input  wire [7:0] A, input  wire [7:0] B, input  wire [15:0] C,
    input wire Ae, input wire Be, input wire save,
    output wire [34:0] out, output wire saveout
);
    // Inputs
    wire Asig; wire [4:0] Aexp; wire [1:0] Aman;
    wire Bsig; wire [4:0] Bexp; wire [1:0] Bman;
    // Preflags
    wire Aexp0; wire Aexp1; wire Aman0;
    wire Bexp0; wire Bexp1; wire Bman0;
    // Flags
    wire Anan; wire Ainf; wire Azero; wire Asub;
    wire Bnan; wire Binf; wire Bzero; wire Bsub;

    // Multiplicands
    wire [3:0] Mq; wire [3:0] Nq;
    // Product intermediates
    wire Psig;
    wire [7:0] Pq; wire [7:0] Pqs; wire [7:0] Pqs1; wire [13:0] Pqf; wire [10:0] Pqr;
    wire Pqrg; wire Pqrr; wire Pqrs; wire Pqro;
    wire signed [6:0] Psexp; wire signed [6:0] Psexps; wire [4:0] Pexpf;
    // Product flags
    wire Pnan; wire Pinf; wire Pzero;

    // Unpack inputs
    assign Asig = A[7]; assign Aexp = A[6:2]; assign Aman = A[1:0];
    assign Bsig = B[7]; assign Bexp = B[6:2]; assign Bman = B[1:0];
    // Set preflags
    assign Aexp0 = (Aexp == 0); assign Aexp1 = (Aexp == 31); assign Aman0 = (Aman == 0);
    assign Bexp0 = (Bexp == 0); assign Bexp1 = (Bexp == 31); assign Bman0 = (Bman == 0);
    // Set flags
    assign Anan = Aexp1 & !Aman0; assign Ainf = Aexp1 & Aman0; assign Azero = Aexp0 & Aman0; assign Asub = Aexp0 & !Aman0;
    assign Bnan = Bexp1 & !Bman0; assign Binf = Bexp1 & Bman0; assign Bzero = Bexp0 & Bman0; assign Bsub = Bexp0 & !Bman0;
    // Product flags - initial values
    assign Pnan = Anan || Bnan || (Ainf && Bzero) || (Azero && Binf);
    assign Pinf = !Pnan && (Ainf || Binf);
    assign Pzero = !Pnan && !Pinf && (Azero || Bzero || (Asub && Bsub));

    // Multiplicands
    assign Mq = {1'b1, (Asub) ? Bman : Aman, 1'b0};
    assign Nq = {(Asub || Bsub) ? 1'b0 : 1'b1, (Asub) ? Aman : Bman, 1'b0};
    // Multiply
    assign Psig = Asig ^ Bsig;
    assign Psexp = Aexp + Bexp + ((Asub || Bsub) ? -14 : -15);
    assign Pq = Mq * Nq;

    assign out = save ? {Pnan, Pinf, Pzero, Psig, Psexp, Pq, C} : 0;
    assign saveout = save;
endmodule
module pipe1 (
    input wire [34:0] in, input wire save,
    output wire [31:0] out, output wire saveout
);

    // Inputs
    wire Pnan;
    wire Pinfin;
    wire Pzeroin;
    wire Psig;
    wire signed [6:0] Psexp;
    wire [7:0] Pq;
    wire [15:0] C;

    // Product intermediates
    wire [7:0] Pqs; wire [7:0] Pqs1; wire [13:0] Pqf; wire [10:0] Pqr;
    wire Pqrg; wire Pqrr; wire Pqrs; wire Pqro;
    wire signed [6:0] Psexps; wire [4:0] Pexpf;
    // Product flags
    wire Pinf; wire Pzero;
    // Product final value
    wire [15:0] P;

    // Unpack inputs
    assign C = in[15:0];
    assign Pq = in[23:16];
    assign Psexp = in[30:24];
    assign Psig = in[31];
    assign Pzeroin = in[32];
    assign Pinfin = in[33];
    assign Pnan = in[34];

    // Left shift to normalize, in normal flows this results in Pqs[7] == 1
    // TODO: have these only deal with the lower bits, and chop off the upper bit as always 1
    assign Pqs    = (Pq[7] == 1) ? Pq        : (Pq[6] == 1) ? {Pq[6:0], 1'b0} : (Pq[5] == 1) ? {Pq[5:0], 2'b00} : (Pq[4] == 1) ? {Pq[4:0], 3'b000} : {Pq[3:0], 4'b0000};
    assign Pqs1 = {1'b1, Pqs[6:0]};
    assign Psexps = (Pq[7] == 1) ? Psexp + 1 : (Pq[6] == 1) ? Psexp           : (Pq[5] == 1) ? Psexp - 1        : (Pq[4] == 1) ? Psexp - 2         : Psexp - 3;
    // Set Pinf, which might overflow post-normalization
    assign Pinf = Pinfin || (Psexps >= 31);
    assign Pzero = Pzeroin || (Psexps < -10);

    // Shift right to get to a normal exponent
    assign Pexpf = (Psexps > 0) ? Psexps : 1;
    assign Pqf =
        (Psexps >   0) ? {Pqs1, 6'b000000} :
        (Psexps ==  0) ? {1'b0, Pqs1, 5'b00000} :
        (Psexps == -1) ? {2'b00, Pqs1, 4'b0000} :
        (Psexps == -2) ? {3'b000, Pqs1, 3'b000} :
        (Psexps == -3) ? {4'b0000, Pqs1, 2'b00} :
        (Psexps == -4) ? {5'b00000, Pqs1, 1'b0} :
        (Psexps == -5) ? {6'b000000, Pqs1} :
        (Psexps == -6) ? {7'b0000000, Pqs1[7:2], (|Pqs1[1:0])} :
        (Psexps == -7) ? {8'b00000000, Pqs1[7:3], (|Pqs1[2:0])} :
        (Psexps == -8) ? {9'b000000000, Pqs1[7:4], (|Pqs1[3:0])} :
        (Psexps == -9) ? {10'b0000000000, Pqs1[7:5], (|Pqs1[4:0])} :
                         {11'b00000000000, Pqs1[7:6], (|Pqs1[5:0])};
    // Handle rounding
    assign Pqro = Pqf[3];  // Odd bit
    assign Pqrg = Pqf[2];  // Guard bit
    assign Pqrr = Pqf[1];  // Round bit
    assign Pqrs = Pqf[0];  // Sticky bit
    assign Pqr = ((Pqrg) && (Pqrr || Pqrs || Pqro)) ? (Pqf[13:3] + 1) : Pqf[13:3];

    // Final product value
    assign P =
        (Pnan) ? {1'b0, 5'b11111, 10'b1111111111} :
        (Pinf) ? {Psig, 5'b11111, 10'b0000000000} :
        (Pzero) ? {1'b0, 5'b00000, 10'b0000000000} :
        (Pqr[10]) ? {Psig, Pexpf, Pqr[9:0]} :
                    {Psig, 5'b00000, Pqr[9:0]};
    // Output
    assign out = save ? {P, C} : 0;
    assign saveout = save;
endmodule
module pipe2 (
    input wire [31:0] in, input wire save,
    output wire [31:0] out, output wire saveout
);
    // Inputs
    wire [15:0] P; wire [15:0] C;
    wire Psig; wire [4:0] Pexp; wire [9:0] Pman;
    wire Csig; wire [4:0] Cexp; wire [9:0] Cman;
    // Preflags
    wire Pexp0; wire Pexp1; wire Pman0;
    wire Cexp0; wire Cexp1; wire Cman0;
    // Flags
    wire Pnan; wire Pinf; wire Pzero; wire Psub;
    wire Cnan; wire Cinf; wire Czero; wire Csub;

    // Summands
    wire [15:0] F; wire [15:0] G;
    wire Fsig; wire [4:0] Fexp; wire [9:0] Fman;
    wire Gsig; wire [4:0] Gexp; wire [9:0] Gman;
    wire [4:0] Fexps; wire [4:0] Gexps;
    wire [13:0] Fq; wire [13:0] Gq; wire [13:0] Gqs;
    wire [4:0] shift; 

    // Sum
    wire Snan; wire Sinf; wire Szero; wire Ssub;
    wire Ssig;
    wire [14:0] Sq; wire [13:0] Sqs; wire [4:0] Sexp; wire [4:0] Sexps;
    wire Sqro; wire Sqrg; wire Sqrr; wire Sqrs;
    wire [11:0] Sqr; wire [4:0] Sexpr;
    wire [10:0] Sqf; wire [4:0] Sexpf;
    wire [15:0] S;

    // Unpack inputs
    assign P = in[31:16]; assign C = in[15:0];
    assign Psig = P[15]; assign Pexp = P[14:10]; assign Pman = P[9:0];
    assign Csig = C[15]; assign Cexp = C[14:10]; assign Cman = C[9:0];
    // Set preflags
    assign Pexp0 = (Pexp == 0); assign Pexp1 = (Pexp == 31); assign Pman0 = (Pman == 0);
    assign Cexp0 = (Cexp == 0); assign Cexp1 = (Cexp == 31); assign Cman0 = (Cman == 0);
    // Set flags
    assign Pnan = Pexp1 & !Pman0; assign Pinf = Pexp1 & Pman0; assign Pzero = Pexp0 & Pman0; assign Psub = Pexp0 & !Pman0;
    assign Cnan = Cexp1 & !Cman0; assign Cinf = Cexp1 & Cman0; assign Czero = Cexp0 & Cman0; assign Csub = Cexp0 & !Cman0;
    // Sum flags - initial values
    assign Snan = Pnan || Cnan || (Pinf && Cinf && (Psig != Csig));
    // assign Sinf = (!Snan) && (Pinf || Cinf);
    // assign Szero = (!Snan) && (!Sinf) && (Pzero && Czero);

    // Summands
    assign F = (P[14:0] > C[14:0]) ? P : C;
    assign G = (P[14:0] > C[14:0]) ? C : P;
    assign Fsig = F[15]; assign Fexp = F[14:10]; assign Fman = F[9:0];
    assign Gsig = G[15]; assign Gexp = G[14:10]; assign Gman = G[9:0];
    assign Fexps = (Fexp > 0) ? Fexp : 1;
    assign Gexps = (Gexp > 0) ? Gexp : 1;
    assign Fq = {(Fexp > 0) ? 1'b1 : 1'b0, Fman, 3'b000};
    assign Gq = {(Gexp > 0) ? 1'b1 : 1'b0, Gman, 3'b000};
    assign shift = Fexps - Gexps;
    assign Gqs = (shift == 0) ? Gq :
        (shift == 1) ? {1'b0, Gq[13:2], (|Gq[1:0])} :
        (shift == 2) ? {2'b00, Gq[13:3], (|Gq[2:0])} :
        (shift == 3) ? {3'b000, Gq[13:4], (|Gq[3:0])} :
        (shift == 4) ? {4'b0000, Gq[13:5], (|Gq[4:0])} :
        (shift == 5) ? {5'b00000, Gq[13:6], (|Gq[5:0])} :
        (shift == 6) ? {6'b000000, Gq[13:7], (|Gq[6:0])} :
        (shift == 7) ? {7'b0000000, Gq[13:8], (|Gq[7:0])} :
        (shift == 8) ? {8'b00000000, Gq[13:9], (|Gq[8:0])} :
        (shift == 9) ? {9'b000000000, Gq[13:10], (|Gq[9:0])} :
        (shift == 10) ? {10'b0000000000, Gq[13:11], (|Gq[10:0])} :
        (shift == 11) ? {11'b00000000000, Gq[13:12], (|Gq[11:0])} :
        (shift == 12) ? {12'b000000000000, Gq[13], (|Gq[12:0])} :
                        {13'b0000000000000, (|Gq[13:0])};
    // Sum
    assign Sq = (Fsig == Gsig) ? Fq + Gqs : Fq - Gqs;
    assign Sexp = Fexps;
    assign Ssig = Fsig;

    // Normalize, shifting left
    assign Sqs = (Sq[14] == 1) ? {Sq[14:2], (|Sq[1:0])} :
        (Sq[13] == 1 || Sexp == 1) ? Sq[13:0] :
        (Sq[12] == 1 || Sexp == 2) ? {Sq[12:0], 1'b0} :
        (Sq[11] == 1 || Sexp == 3) ? {Sq[11:0], 2'b00} :
        (Sq[10] == 1 || Sexp == 4) ? {Sq[10:0], 3'b000} :
        (Sq[9] == 1 || Sexp == 5) ? {Sq[9:0], 4'b0000} :
        (Sq[8] == 1 || Sexp == 6) ? {Sq[8:0], 5'b00000} :
        (Sq[7] == 1 || Sexp == 7) ? {Sq[7:0], 6'b000000} :
        (Sq[6] == 1 || Sexp == 8) ? {Sq[6:0], 7'b0000000} :
        (Sq[5] == 1 || Sexp == 9) ? {Sq[5:0], 8'b00000000} :
        (Sq[4] == 1 || Sexp == 10) ? {Sq[4:0], 9'b000000000} :
        (Sq[3] == 1 || Sexp == 11) ? {Sq[3:0], 10'b0000000000} :
        (Sq[2] == 1 || Sexp == 12) ? {Sq[2:0], 11'b00000000000} :
        (Sq[1] == 1 || Sexp == 13) ? {Sq[1:0], 12'b000000000000} :
        (Sq[0] == 1 || Sexp == 14) ? {Sq[0], 13'b0000000000000} :
        14'b0;
    assign Sexps = (Sq[14] == 1) ? Sexp + 1 :
        (Sq[13] == 1 || Sexp == 1) ? Sexp :
        (Sq[12] == 1 || Sexp == 2) ? Sexp - 1 :
        (Sq[11] == 1 || Sexp == 3) ? Sexp - 2 :
        (Sq[10] == 1 || Sexp == 4) ? Sexp - 3 :
        (Sq[9] == 1 || Sexp == 5) ? Sexp - 4 :
        (Sq[8] == 1 || Sexp == 6) ? Sexp - 5 :
        (Sq[7] == 1 || Sexp == 7) ? Sexp - 6 :
        (Sq[6] == 1 || Sexp == 8) ? Sexp - 7 :
        (Sq[5] == 1 || Sexp == 9) ? Sexp - 8 :
        (Sq[4] == 1 || Sexp == 10) ? Sexp - 9 :
        (Sq[3] == 1 || Sexp == 11) ? Sexp - 10 :
        (Sq[2] == 1 || Sexp == 12) ? Sexp - 11 :
        (Sq[1] == 1 || Sexp == 13) ? Sexp - 12 :
        (Sq[0] == 1 || Sexp == 14) ? Sexp - 13 :
        0;
    
    // assign Sinf = ((!Snan) && (Pinf || Cinf)) || (Sexps == 31);
    assign Szero = ((!Snan) && (!Sinf) && (Pzero && Czero)) || (Sexps == 0);
    // Rounding
    assign Sqro = Sqs[3];  // Odd bit
    assign Sqrg = Sqs[2];  // Guard bit
    assign Sqrr = Sqs[1];  // Round bit
    assign Sqrs = Sqs[0];  // Sticky bit
    assign Sqr = ((Sqrg) && (Sqrr || Sqrs || Sqro)) ? (Sqs[13:3] + 1) : {1'b0, Sqs[13:3]};
    assign Sexpr = (Sqr[11] == 1) ? Sexps + 1 : Sexps;
    assign Sqf = (Sqr[11] == 1) ? Sqr[11:1] : Sqr[10:0];
    // Maybe overflow
    assign Sinf = (((!Snan) && (Pinf || Cinf)) || (Sexps == 31)) || (Sexpr == 31);

    // Final sum value
    assign S =
        (Snan) ? {1'b0, 5'b11111, 10'b1111111111} :
        (Sinf) ? {Ssig, 5'b11111, 10'b0000000000} :
        (Szero) ? {Ssig, 5'b00000, 10'b0000000000} :
        (Sqf[10]) ? {Ssig, Sexpr, Sqf[9:0]} :
                    {Ssig, 5'b00000, Sqf[9:0]};

    assign out = save ? {16'h0000, S} : 0;
    assign saveout = save;
endmodule
module pipe3 (
    input wire [31:0] in, input wire save,
    output wire [15:0] out, output wire saveout
);
    assign out = save ? in[15:0] : 0;
    assign saveout = save;
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

    // Accumulator
    reg [15:0] C0;
    reg [15:0] C1;
    reg [15:0] C2;
    reg [15:0] C3;
    // Pipeline
    wire [7:0] PipeA;  // A input to pipeline
    wire [7:0] PipeB;  // B input to pipeline
    wire [15:0] PipeC;  // C input to pipeline
    wire        PipeAe;  // A exponent size
    wire        PipeBe;  // B exponent size
    wire        PipeSave;  // Save flag
    wire [34:0] Pipe0w;  // Pipeline 0 output
    wire        Pipe0Sw;  // Pipeline 0 output Save
    reg  [34:0] Pipe0s;  // Pipeline 0 state
    reg         Pipe0Ss;  // Pipeline 0 state Save
    wire [31:0] Pipe1w;  // Pipeline 1 output
    wire        Pipe1Sw;  // Pipeline 1 output Save
    reg  [31:0] Pipe1s;  // Pipeline 1 state
    reg         Pipe1Ss;  // Pipeline 1 state Save
    wire [31:0] Pipe2w;  // Pipeline 2 output
    wire        Pipe2Sw;  // Pipeline 2 output Save
    reg  [31:0] Pipe2s;  // Pipeline 2 state
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
            if (boundary) begin
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
        .Ae(PipeAe), .Be(PipeBe), .save(PipeSave)
    );
    // Pipeline stages
    pipe0 p0(
        .A(PipeA), .B(PipeB), .C(PipeC),
        .Ae(PipeAe), .Be(PipeBe), .save(PipeSave),
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
                if ((col_ctrl_in_full[3:2] == 2'b10) && (row_ctrl_in_full[3:2] == 2'b01)) begin
                    C0 <= col_in_full;
                    C1 <= row_in_full;
                end else if (Pipe3Sw) begin
                    C1 <= Pipe3w;
                end
                if ((col_ctrl_in_full[3:2] == 2'b11) && (row_ctrl_in_full[3:2] == 2'b00)) begin
                    C2 <= col_in_full;
                    C3 <= row_in_full;
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
    assign uio_oe[1:0] = 2'b11;
    assign uio_out[1:0] = (!rst_n) ? 0 : {col_ctrl_out_mux, row_ctrl_out_mux};

endmodule
