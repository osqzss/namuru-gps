#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_tracking_channel \
  ../test/tb_tracking_channel.sv \
  ../rtl/time_base.sv \
  ../rtl/code_nco.sv \
  ../rtl/code_gen.sv \
  ../rtl/carrier_nco.sv \
  ../rtl/carrier_mixer.sv \
  ../rtl/accumulator.sv \
  ../rtl/epoch_counter.sv \
  ../rtl/tracking_channel.sv
vvp sim_tracking_channel

# View *.vcd file:
# gtkwave tracking_channel.vcd
