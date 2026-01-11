#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_carrier_nco ../test/tb_carrier_nco.sv ../rtl/carrier_nco.sv
vvp sim_carrier_nco

# View *.vcd file:
# gtkwave carrier_nco.vcd
