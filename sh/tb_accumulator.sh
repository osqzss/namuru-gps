#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_accumulator ../test/tb_accumulator.sv ../rtl/accumulator.sv
vvp sim_accumulator

# View *.vcd file:
# gtkwave accumulator.vcd
