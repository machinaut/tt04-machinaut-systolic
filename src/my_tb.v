// add testbench
`include "my.v"

module add_tb;
    reg  A  = 0; // first input
    reg  B  = 0; // second input
    reg  C  = 0; // carry input
    reg  EN = 0; // enable gate
    // half_adder test outputs
    wire ha_out;    // output
    wire ha_cout;   // carry output
    // full_adder test outputs
    wire fa_out;    // output
    wire fa_cout;   // carry output

    half_adder ha(A, B, EN, ha_out, ha_cout);
    full_adder fa(A, B, C, EN, fa_out, fa_cout);

    // Half adder test assertion.
    `define HA_TEST(ans, cans) begin \
        if (ha_out !== (ans) || ha_cout !== (cans)) \
            $error("FAIL: Half: %d != %d, or carry %d != %d", ha_out, ans, ha_cout, cans); \
    end

    // Full adder test assertion.
    `define FA_TEST(ans, cans) begin \
        if (fa_out !== (ans) || fa_cout !== (cans)) \
            $error("FAIL: Full: %d != %d, or carry %d != %d", fa_out, ans, fa_cout, cans); \
    end

    // Both adders test assertion.
    `define TEST(ans, cans) begin \
        `HA_TEST(ans, cans); \
        `FA_TEST(ans, cans); \
    end

    initial begin
        $dumpfile("my_tb.vcd");
        $dumpvars(0, ha); $dumpvars(0, fa);
        #5 EN = 1;
        #5 A = 1'b0; B = 1'b0; C = 1'b0; #5 `TEST(0, 0);
        #5 A = 1'b0; B = 1'b0; C = 1'b1; #5 `HA_TEST(0, 0); `FA_TEST(1, 0);
        #5 A = 1'b0; B = 1'b1; C = 1'b0; #5 `TEST(1, 0);
        #5 A = 1'b1; B = 1'b0; C = 1'b0; #5 `TEST(1, 0);
        #5 A = 1'b1; B = 1'b1; C = 1'b0; #5 `TEST(0, 1);

        #5 EN = 0;
        #5 A = 0; B = 0; #5 `TEST(1'bZ, 1'bz);

        #5 $display("done"); $finish;
    end
endmodule
