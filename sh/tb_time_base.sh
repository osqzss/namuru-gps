#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_time_base ../test/tb_time_base.sv ../rtl/time_base.sv
vvp sim_time_base

# View *.vcd file:
gtkwave time_base.vcd
