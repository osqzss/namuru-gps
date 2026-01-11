#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_carrier_mixer ../test/tb_carrier_mixer.sv ../rtl/carrier_mixer.sv
vvp sim_carrier_mixer

# View *.vcd file:
# gtkwave carrier_mixer.vcd
