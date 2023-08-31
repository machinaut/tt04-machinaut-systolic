# Note

Change the name to AI Decelerator

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
* Input: A, B, C, A_Q, A_sexp, B_Q, B_sexp, P_Q, P_sexp, S_Q, S_sexp, A_nan, A_inf, A_zero, A_sub, ...
* Output: Same

## Wish
* JTAG - old/boring not new hotness (4-pin)
* OpenOCD

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
