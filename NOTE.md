# Note

## Design Considerations
* A simple as possible while keeping to the spirit of the thing
* Standard floating point formats, despite better (smaller) alternative available
* No features outside of super simple FMA array
* Maximize use of the ui_in (read 8 bits every clock) and uo_out (write 8 bits every clock)
* Use uio for control and debug
* In theory could be tiled into larger units, but in practice I won't get that many units
* Matches what python does in rounding, not worried about other rounding modes
* Rounds inbetween multiply and add, instead of keeping precision

## MVP:
* Get C read-out working
* Get C read-in working
* Test C read-in and read-out
* Make placeholder pipeline stages
* Make A.B + C pipeline_15 stage
* Test single-block A.B, and read out C
* Figure out how to divide pipeline
* Implement pipeline parts, debugging in gtkwave
* Test pipeline w/ random numbers for hours

## TODO:
* Change the name to AI **Decelerator**
* Check timing for sanity
* JTAG-like shift register for all state bits
* Other float rounding modes
* Schematic for hooking it up to laptop to test (somehow)
* Schematic for tiling these into systolic 4x4, including handling muxing and readout

## UIO Assignment
* 1 - Mode Input (0: AB Systolic, 1: C read in/out) - Only happens at block boundary
* 1 - Mode Output (will lag because C is larger than A + B)
* 1 - Size (0: BFloat16, 1: FP32)
* 1 - unused
* 4 - Debug (JTAG or similar)

## Running and Modes
* Holding rst_n low for a cycle will zero out the internal state
* From there, if run is high, we will step the pipeline, otherwise we will idle through clocks
  * When we run, we advance the state, and we'll start at state 0
* If mode is 0, we'll be doing the normal systolic process every clock
  * inputs will be read into A_in and B_in (next block)
  * outputs will be read out from A and B (current block)
  * pipeline stages will advance (processing previous block and current block)
  * state will increment every clock and wrap around after 15
* If mode is 1, we'll be reading in C and writing out C, based on size
  * this will start at the next time state rolls over
  * state will increment every clock and wrap around after 15 if size:0 or 31 if size:1
  * inputs will be read into C directly, and C will be read out to output directly
* Size sets the size of C read out/read in (only during mode:1)
  * If size is 0, we'll only read out the BF16 part of C, and read in a BF16 for C
  * If size is 1, we'll read out the full FP32 C, and there will be twice as many cycles
  * Size=0 can tile comfortably since C is same size as A+B
  * Size=1 can be used to get more accurate answers, but cannot tile since the size is mismatched

## Tiling Alternative
* Inputs and outputs are two half-bytes -- top half is column, bottom half is row (or vice versa)
* Inputs and outputs are processed 4 bits at a time
* No need for input or output mux when tiling
* Hook up 4 inputs to column above, 4 outputs to column below, and 4 inputs to the row before, and 4 outputs to the row after
* Hook up all UIO signals to all tiles
* Tiling scan-chain should do the right thing with these

## 4 x 4 Systolic Array doing Fused multiply add
* A, B are BFloat16 (1, 8, 7)
* C is FP32 (1, 8, 23)
* A is a 4 x N matrix - read one row at a time
* B is a N x 4 matrix - read one column at a time
* C accumulates the product

* You can tile these into a rectangle, and they should efficiently move data

|     | A_0 | A_1 | A_2 | A_3 |
| --- | --- | --- | --- | --- | --- |
| B_0 | C00 | C01 | C02 | C03 | B_0 |
| B_1 | C10 | C11 | C12 | C13 | B_1 |
| B_2 | C20 | C21 | C22 | C23 | B_2 |
| B_3 | C30 | C31 | C32 | C33 | B_3 |
| --- | --- | --- | --- | --- | --- |
|     | A_0 | A_1 | A_2 | A_3 |

## Pipeline interface
* Input: i, j, A_i, B_j, C_ji, A*, B*, C*, P*, S*
* Input Stars have: V_sig, V_sexp, V_qgrs, V_nan, V_inf, V_zero, V_sub
* Output: Same as input
* Output of final stage (pipe_15): also has new C value
* Debug: Scan-chain of all the pipeline stages in order after all the central states and buffers

## Pipeline State
| state   | 0    | 1    | 2    | 3    | 4    | 5    | 6    | 7    | 8    | 9    | 10   | 11   | 12   | 13   | 14   | 15   |
| ------- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| ui_in   | A0H2 | A0L2 | A1H2 | A1L2 | A2H2 | A2L2 | A3H2 | A3L2 | B0H2 | B0L2 | B1H2 | B1L2 | B2H2 | B2L2 | B3H2 | B3L2 |
| uo_out  | A0H1 | A0L1 | A1H1 | A1L1 | A2H1 | A2L1 | A3H1 | A3L1 | B0H1 | B0L1 | B1H1 | B1L1 | B2H1 | B2L1 | B3H1 | B3L1 |
| pipe_0  | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 | C211 | C221 | C231 | C301 | C311 | C321 | C331 |
| pipe_1  | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 | C211 | C221 | C231 | C301 | C311 | C321 |
| pipe_2  | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 | C211 | C221 | C231 | C301 | C311 |
| pipe_3  | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 | C211 | C221 | C231 | C301 |
| pipe_4  | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 | C211 | C221 | C231 |
| pipe_5  | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 | C211 | C221 |
| pipe_6  | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 | C211 |
| pipe_7  | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 | C201 |
| pipe_8  | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 | C131 |
| pipe_9  | C130 | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 | C121 |
| pipe_10 | C120 | C130 | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 | C111 |
| pipe_11 | C110 | C120 | C130 | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 | C101 |
| pipe_12 | C100 | C110 | C120 | C130 | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 | C031 |
| pipe_13 | C030 | C100 | C110 | C120 | C130 | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 | C021 |
| pipe_14 | C020 | C030 | C100 | C110 | C120 | C130 | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 | C011 |
| pipe_15 | C010 | C020 | C030 | C100 | C110 | C120 | C130 | C200 | C210 | C220 | C230 | C300 | C310 | C320 | C330 | C001 |

## Control Signals

* 8-bit Address, 8-bit Command

Addresses (in Hex)
* 01 - Internal State
* 02 - A (Math Vector)
* 04 - B (Math Vector)
* 08-0F - C (Math Vector)
* 12 - X (Math Vector)
* 14 - Y (Math Vector)
* 18-1F - Z (Math Vector)
* 8* - Pipeline A (* is stage, 0-F)
* 9* - Pipeline B
* A* - Pipeline C
* B* - Pipeline P
* C* - Pipeline S
* D* - Pipeline X
* E* - Pipeline Y
* F* - Pipeline Z

Control Bits
* 7 - 0: Idle, 1: Run (Advance the pipeline this block or not)
* 6 - 0: Step, 1: Continuous (If running, how much to advance pipeline this block)
* 5 - 0: Pass, 1: Shift In (Shift In data and then set _shift reg and pass the rest)