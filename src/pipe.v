// pipe.v - Floating point pipeline
`default_nettype none

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
    wire Pnan; wire Pinf; wire Pzero;
    wire Cnan; wire Cinf; wire Czero;

    // Summands
    wire [15:0] F; wire [15:0] G;
    wire Fsig; wire [4:0] Fexp; wire [9:0] Fman;
    wire Gsig; wire [4:0] Gexp; wire [9:0] Gman;
    wire [4:0] Fexps; wire [4:0] Gexps;
    wire [13:0] Fq; wire [13:0] Gq; wire [13:0] Gqs;
    wire [4:0] shift; 

    // Sum
    wire Snan; wire Sinf; wire Szero;
    wire Ssig;
    wire [14:0] Sq; 
    wire [4:0] Sexp; 

    // Unpack inputs
    assign P = in[31:16]; assign C = in[15:0];
    assign Psig = P[15]; assign Pexp = P[14:10]; assign Pman = P[9:0];
    assign Csig = C[15]; assign Cexp = C[14:10]; assign Cman = C[9:0];
    // Set preflags
    assign Pexp0 = (Pexp == 0); assign Pexp1 = (Pexp == 31); assign Pman0 = (Pman == 0);
    assign Cexp0 = (Cexp == 0); assign Cexp1 = (Cexp == 31); assign Cman0 = (Cman == 0);
    // Set flags
    assign Pnan = Pexp1 & !Pman0; assign Pinf = Pexp1 & Pman0; assign Pzero = Pexp0 & Pman0;
    assign Cnan = Cexp1 & !Cman0; assign Cinf = Cexp1 & Cman0; assign Czero = Cexp0 & Cman0;
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
    wire Sinfin; wire Szeroin;
    wire Snan; wire Sinf; wire Szero;
    wire Ssig;
    wire [14:0] Sq; wire [13:0] Sqs; wire [4:0] Sexp; wire [4:0] Sexps;
    wire Sqro; wire Sqrg; wire Sqrr; wire Sqrs;
    wire [11:0] Sqr; wire [4:0] Sexpr;
    wire [10:0] Sqf;
    wire [15:0] S;

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
