`default_nettype none

// TODO: check all the regs in gtkwave, and look for any fast-switching ones
// TODO: just read the VCD file for these instead, somehow?


// Unpack an input value to its components
module multiplicand (
    // input value
    input wire [7:0] X,
    input wire fmt,
    // output flags
    output wire nan,
    output wire inf,
    output wire zero,
    // output values
    output wire [5:0] sexp,  // Stores exp + 16
    output wire [2:0] frac  // omit the implied high bit
);
    // preflags
    wire exp0;
    wire exp1;
    wire man0;
    assign exp0 = fmt ? (X[6:3] == 4'b0000) : (X[6:2] == 5'b00000);
    assign exp1 = fmt ? (X[6:3] == 4'b1111) : (X[6:2] == 5'b11111);
    assign man0 = fmt ? (X[2:0] == 3'b000) : (X[1:0] == 2'b00);
    // flags
    wire sub;
    assign nan = exp1 && (fmt ? (X[2:0] == 3'b111) : !man0);
    assign inf = exp1 && man0 && !fmt;
    assign zero = exp0 && man0;
    assign sub = exp0 && !man0;
    // calculate exponent
    assign sexp = (sub) ?
        ((fmt) ? // subnormals
            (X[2] ? (X[6:3] + 9) : X[1] ? (X[6:3] + 8) : (X[6:3] + 7)) : // E4M3 subnormals
            (X[1] ? (X[6:2] + 1) : (X[6:2] + 0))  // E5M2 subnormals
        ) : // normals
        (fmt ? (X[6:3] + 9) : (X[6:2] + 1));
    assign frac = (sub) ? 
        ((fmt) ? // subnormals
            (X[2] ? {X[1:0], 1'b0} : X[1] ? {X[0], 2'b00} : {3'b000}) : // E4M3 subnormals
            (X[1] ? {X[0], 2'b00} : {3'b000})  // E5M2 subnormals
        ) : // normals
        (fmt ? {X[2:0]} : {X[1:0], 1'b0});
endmodule

// Multiply A and B to get product
module pipe0 (
    input wire [7:0] A,
    input wire [7:0] B,
    input wire [15:0] C,
    input wire Afmt,
    input wire Bfmt,
    input wire save,
    output wire [33:0] out,
    output wire saveout
);
    // Inputs
    wire [5:0] Asexp; wire [2:0] Afrac;
    wire [5:0] Bsexp; wire [2:0] Bfrac;
    wire Anan; wire Ainf; wire Azero;
    wire Bnan; wire Binf; wire Bzero;
    // Outputs
    wire Pnan;
    wire Pinf;
    wire Pzero;
    wire Psig;
    wire [6:0] Psexp;  // TODO: try reducing this to fewer bits
    wire [6:0] Pfrac;
    wire [15:0] Cout;

    // Multiplicands
    multiplicand Am(.X(A), .fmt(Afmt), .nan(Anan), .inf(Ainf), .zero(Azero), .sexp(Asexp), .frac(Afrac));
    multiplicand Bm(.X(B), .fmt(Bfmt), .nan(Bnan), .inf(Binf), .zero(Bzero), .sexp(Bsexp), .frac(Bfrac));

    // Product flags
    assign Pnan = Anan || Bnan || (Ainf && Bzero) || (Azero && Binf);
    assign Pinf = (!Pnan) && (Ainf || Binf);
    assign Pzero = (!Pnan) && (!Pinf) && (Azero || Bzero);

    // Multiply
    wire [7:0] Pq;
    assign Psig = A[7] ^ B[7];
    assign Pq = {1'b1, Afrac} * {1'b1, Bfrac};
    assign Psexp = Asexp + Bsexp + Pq[7];  // Stores exp + 32
    assign Pfrac = Pq[7] ? Pq[6:0] : {Pq[5:0], 1'b0};

    // Outputs
    assign out = {Pnan, Pinf, Pzero, Psig, Psexp, Pfrac, C};
    assign saveout = save;
endmodule

module roundproduct (
    input wire [6:0] sexp,
    input wire [6:0] frac,
    output wire [9:0] man
);
    wire rem;
    wire half;
    wire round;
    wire odd;
    wire [10:0] shifted;

    assign rem =
        (sexp == 13) ? (|frac[0]) :
        (sexp == 12) ? (|frac[1:0]) :
        (sexp == 11) ? (|frac[2:0]) :
        (sexp == 10) ? (|frac[3:0]) :
        (sexp ==  9) ? (|frac[4:0]) :
        (sexp ==  8) ? (|frac[5:0]) :
        (sexp ==  7) ? (|frac[6:0]) : 
        0;

    assign shifted =
        (sexp >= 18) ? {frac, 4'b0000} :
        (sexp == 17) ? {1'b1, frac, 3'b000} :
        (sexp == 16) ? {2'b01, frac, 2'b00} :
        (sexp == 15) ? {3'b001, frac, 1'b0} :
        (sexp == 14) ? {4'b0001, frac[6:0]} :
        (sexp == 13) ? {5'b00001, frac[6:1]} :
        (sexp == 12) ? {6'b000001, frac[6:2]} :
        (sexp == 11) ? {7'b0000001, frac[6:3]} :
        (sexp == 10) ? {8'b00000001, frac[6:4]} :
        (sexp ==  9) ? {9'b000000001, frac[6:5]} :
        (sexp ==  8) ? {10'b0000000001, frac[6]} :
        (sexp ==  7) ? {11'b00000000001} :
        0;

    assign half = shifted[0];
    assign odd = shifted[1];
    assign round = (half) && (odd || rem);
    assign man = (round) ? (shifted[10:1] + 1) : shifted[10:1];
endmodule

// Round the product and normalize to FP16
module pipe1 (
    input wire [33:0] in,
    input wire save,
    output wire [31:0] out,
    output wire saveout
);
    // Input
    wire Pnan;
    wire Pinf;
    wire Pzero;
    wire Psig;
    wire [6:0] Psexp;
    wire [6:0] Pfrac;
    wire [15:0] C;
    assign Pnan = in[33];
    assign Pinf = in[32];
    assign Pzero = in[31];
    assign Psig = in[30];
    assign Psexp = in[29:23];
    assign Pfrac = in[22:16];
    assign C = in[15:0];

    // Product
    wire [4:0] Pexp;
    wire [9:0] Pman;
    wire [15:0] P;
    roundproduct rp(.sexp(Psexp), .frac(Pfrac), .man(Pman));
    assign Pexp = (Psexp >= 48) ? 31 : (Psexp <= 16) ? 0 : Psexp - 17;

    // Final product value
    assign P =
        (Pnan) ? {1'b0, 5'b11111, 10'b1111111111} :
        (Pinf  || (Pexp == 31)) ? {Psig, 5'b11111, 10'b0000000000} :
        (Pzero || (Psexp < 7)) ? {Psig, 5'b00000, 10'b0000000000} :
        (Psexp > 16) ? {Psig, Pexp, Pman} :
                        {Psig, 5'b00000, Pman};
    // Output
    assign out = (!save) ? 0 : {P, C};
    assign saveout = save;
endmodule

module pipe2 (
    input wire [31:0] in, input wire save,
    output wire [39:0] out, output wire saveout
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
    wire [14:0] Sq; 
    wire [4:0] Sexp; 
    // wire Sqro; wire Sqrg; wire Sqrr; wire Sqrs;
    // wire [11:0] Sqr; wire [4:0] Sexpr;
    // wire [10:0] Sqf; wire [4:0] Sexpf;
    // wire [15:0] S;

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
    assign Sinf = (!Snan) && (Pinf || Cinf);
    assign Szero = (!Snan) && (!Sinf) && (Pzero && Czero);

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

    // Bits: Snan=1 Sinf=1 Szero=1 Ssig=1 Sexp=5 Sq=15 C=16 = 40
    assign out = (!save) ? 0 : {Snan, Sinf, Szero, Ssig, Sexp, Sq, C};
    assign saveout = save;
endmodule

module pipe3 (
    input wire [39:0] in, input wire save,
    output wire [15:0] out, output wire saveout
);
    wire [15:0] C;
    wire Sinfin; wire Szeroin;
    wire Snan; wire Sinf; wire Szero;
    wire Ssig;
    wire [14:0] Sq; wire [13:0] Sqs; wire [4:0] Sexp; wire [4:0] Sexps;
    wire Sqro; wire Sqrg; wire Sqrr; wire Sqrs;
    wire [11:0] Sqr; wire [4:0] Sexpr;
    wire [10:0] Sqf; wire [4:0] Sexpf;
    wire [15:0] S;

    assign C = in[15:0];
    assign Sq = in[30:16];
    assign Sexp = in[35:31];
    assign Ssig = in[36];
    assign Szeroin = in[37];
    assign Sinfin = in[38];
    assign Snan = in[39];

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
    assign Szero = (Szeroin) || (Sexps == 0);
    // Rounding
    assign Sqro = Sqs[3];  // Odd bit
    assign Sqrg = Sqs[2];  // Guard bit
    assign Sqrr = Sqs[1];  // Round bit
    assign Sqrs = Sqs[0];  // Sticky bit
    assign Sqr = ((Sqrg) && (Sqrr || Sqrs || Sqro)) ? (Sqs[13:3] + 1) : {1'b0, Sqs[13:3]};
    assign Sexpr = (Sqr[11] == 1) ? Sexps + 1 : Sexps;
    assign Sqf = (Sqr[11] == 1) ? Sqr[11:1] : Sqr[10:0];
    // Maybe overflow
    assign Sinf = (Sinfin) || (Sexpr == 31);

    // Final sum value
    assign S =
        (Snan) ? {1'b0, 5'b11111, 10'b1111111111} :
        (Sinf) ? {Ssig, 5'b11111, 10'b0000000000} :
        (Szero) ? {Ssig, 5'b00000, 10'b0000000000} :
        (Sqf[10]) ? {Ssig, Sexpr, Sqf[9:0]} :
                    {Ssig, 5'b00000, Sqf[9:0]};
    assign out = (!save) ? 0 : S;
    assign saveout = save;
endmodule


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
    wire [7:0] A0i; wire [7:0] A1i; wire [7:0] A0o; wire [7:0] A1o;
    wire [7:0] B0i; wire [7:0] B1i; wire [7:0] B0o; wire [7:0] B1o;
    assign A0i = ci[15:8]; assign A1i = ci[7:0]; assign A0o = co[15:8]; assign A1o = co[7:0];
    assign B0i = ri[15:8]; assign B1i = ri[7:0]; assign B0o = ro[15:8]; assign B1o = ro[7:0];
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