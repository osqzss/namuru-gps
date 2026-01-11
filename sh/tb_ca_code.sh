#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_ca_code ../test/tb_ca_code.sv ../rtl/code_gen.sv ../rtl/code_nco.sv
vvp sim_ca_code

# View *.vcd file:
# gtkwave ca_code.vcd
