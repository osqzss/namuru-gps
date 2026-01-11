#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_code_slew ../test/tb_code_slew.sv ../rtl/code_gen.sv ../rtl/code_nco.sv
vvp sim_code_slew

# View *.vcd file:
# gtkwave code_slew.vcd
