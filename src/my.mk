all: my

# my: my.v my_tb.v
# 	iverilog -o my.vvp my.v my_tb.v && vvp my.vvp

my: my_fadd.v my_fmul.v my_sys.v my_tb.v
	iverilog -o my.vvp $? && vvp my.vvp
