`default_nettype none
`timescale 1ns/1ps

/*
this testbench just instantiates the module and makes some convenient wires
that can be driven / tested by the cocotb test.py
*/

// testbench is controlled by tile.py
module tile ();

    // this part dumps the trace to a vcd file that can be viewed with GTKWave
    initial begin
        $dumpfile ("tile.vcd");
        $dumpvars (0, tile);
        #1;
    end

    // wire up the inputs and outputs
    reg  clk;
    reg  rst_n;
    reg  ena;

    wire [0:1][0:1][7:0] uio_in;
    wire [0:1][0:1][7:0] uio_out;
    wire [0:1][0:1][7:0] uio_oe;

    // Tile externals
    reg  [0:1][3:0] col_in;  // Column Inputs
    reg  [0:1] col_ctrl_in;  // Column Control Inputs
    reg  [0:1][3:0] row_in;  // Row Inputs
    reg  [0:1] row_ctrl_in;  // Row Control Inputs
    wire [0:1][3:0] col_out; // Column Outputs
    wire [0:1] col_ctrl_out; // Column Control Outputs
    wire [0:1][3:0] row_out; // Row Outputs
    wire [0:1] row_ctrl_out; // Row Control Outputs
    // Tile internals
    wire [0:1][3:0] col_con; // Column Connections
    wire [0:1] col_ctrl_con; // Column Control Connections
    wire [0:1][3:0] row_con; // Row Connections
    wire [0:1] row_ctrl_con; // Row Control Connections

    // Tile 00
    tt_um_machinaut_systolic tile00 (
        .ui_in   ({col_in[0], row_in[0]}),
        .uo_out  ({col_con[0], row_con[0]}),
        .uio_in  ({uio_in[0][0][7:4], col_ctrl_in[0], row_ctrl_in[0], uio_in[0][0][1:0]}),
        .uio_out ({uio_out[0][0][7:2], col_ctrl_con[0], row_ctrl_con[0]}),
        .uio_oe  ({uio_oe[0][0]}),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );
    // Tile 01
    tt_um_machinaut_systolic tile01 (
        .ui_in   ({col_in[1], row_con[0]}),
        .uo_out  ({col_con[1], row_out[0]}),
        .uio_in  ({uio_in[0][1][7:4], col_ctrl_in[1], row_ctrl_con[0], uio_in[0][1][1:0]}),
        .uio_out ({uio_out[0][1][7:2], col_ctrl_con[1], row_ctrl_out[0]}),
        .uio_oe  ({uio_oe[0][1]}),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );
    // Tile 10
    tt_um_machinaut_systolic tile10 (
        .ui_in   ({col_con[0], row_in[1]}),
        .uo_out  ({col_out[0], row_con[1]}),
        .uio_in  ({uio_in[1][0][7:4], col_ctrl_con[0], row_ctrl_in[1], uio_in[1][0][1:0]}),
        .uio_out ({uio_out[1][0][7:2], col_ctrl_out[0], row_ctrl_con[1]}),
        .uio_oe  ({uio_oe[1][0]}),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );
    // Tile 11
    tt_um_machinaut_systolic tile11 (
        .ui_in   ({col_con[1], row_con[1]}),
        .uo_out  ({col_out[1], row_out[1]}),
        .uio_in  ({uio_in[1][1][7:4], col_ctrl_con[1], row_ctrl_con[1], uio_in[1][1][1:0]}),
        .uio_out ({uio_out[1][1][7:2], col_ctrl_out[1], row_ctrl_out[1]}),
        .uio_oe  ({uio_oe[1][1]}),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

endmodule
