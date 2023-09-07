# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# this is the only part you should need to modify:
VERILOG_SOURCES += $(PWD)/pipetb.v $(PWD)/pipe.v

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = pipetb

# MODULE is the basename of the Python test file
MODULE = pipe

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
