// pipe.v - Floating point pipeline
`default_nettype none

module pipe0 (
    input  wire [7:0] A, input  wire [7:0] B, input  wire [15:0] C,
    input wire Ae, input wire Be, input wire save,
    output wire [34:0] out, output wire saveout
);
    // Inputs
    wire Asig; wire signed [4:0] Asexp; wire [2:0] Aman;
    wire Bsig; wire signed [4:0] Bsexp; wire [2:0] Bman;
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
    assign Asig = A[7];
    assign Aman = Ae ? A[2:0] : {A[1:0], 1'b0};
    assign Bsig = B[7];
    assign Bman = Be ? B[2:0] : {B[1:0], 1'b0};
    // Set preflags
    assign Aexp1 = Ae ? (A[6:3] == 4'b1111) : (A[6:2] == 5'b11111);
    assign Aexp0 = Ae ? (A[6:3] == 4'b0000) : (A[6:2] == 5'b00000);
    assign Bexp1 = Be ? (B[6:3] == 4'b1111) : (B[6:2] == 5'b11111);
    assign Bexp0 = Be ? (B[6:3] == 4'b0000) : (B[6:2] == 5'b00000);
    assign Aman0 = Ae ? (A[2:0] == 0) : (A[1:0] == 0);
    assign Bman0 = Be ? (B[2:0] == 0) : (B[1:0] == 0);
    // Set flags
    assign Anan = Aexp1 & !Aman0; assign Ainf = Aexp1 & Aman0; assign Azero = Aexp0 & Aman0; assign Asub = Aexp0 & !Aman0;
    assign Bnan = Bexp1 & !Bman0; assign Binf = Bexp1 & Bman0; assign Bzero = Bexp0 & Bman0; assign Bsub = Bexp0 & !Bman0;
    // Product flags - initial values
    assign Pnan = Anan || Bnan || (Ainf && Bzero) || (Azero && Binf);
    assign Pinf = !Pnan && (Ainf || Binf);
    assign Pzero = !Pnan && !Pinf && (Azero || Bzero || (Asub && Bsub));

    // Exponents
    assign Asexp = Ae ? (A[6:3] - 7) : (A[6:2] - 15);
    assign Bsexp = Be ? (B[6:3] - 7) : (B[6:2] - 15);

    // Multiplicands
    assign Mq = {1'b1, (Asub) ? Bman : Aman};
    assign Nq = (Asub) ? {Aman, 1'b0} : (Bsub) ? {Bman, 1'b0} : {1'b1, Bman};
    // Multiply
    assign Psig = Asig ^ Bsig;
    assign Psexp = Asexp + Bsexp + 15;  // TODO: add extra if subnormal?
    assign Pq = Mq * Nq;

    // TODO: I don't think we need Pzero, since it should be handled fine as a subnormal
    assign out = (!save) ? 0 : {Pnan, Pinf, Pzero, Psig, Psexp, Pq, C};
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
        (Pzero) ? {Psig, 5'b00000, 10'b0000000000} :
        (Pqr[10]) ? {Psig, Pexpf, Pqr[9:0]} :
                    {Psig, 5'b00000, Pqr[9:0]};
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
