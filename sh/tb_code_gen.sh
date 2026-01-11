#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_code_gen ../test/tb_code_gen.sv ../rtl/code_gen.sv ../rtl/code_nco.sv
vvp sim_code_gen

# View *.vcd file:
gtkwave code_gen.vcd
