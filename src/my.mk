all: my

my: my.v my_tb.v
	iverilog -o my.vvp my.v my_tb.v && vvp my.vvp