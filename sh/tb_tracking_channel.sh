#!/bin/sh

# Run Icarus verilog:
iverilog -g2012 -Wall -o sim_tracking_channel \
  ../test/tb_tracking_channel.sv \
  ../rtl/time_base.v\
  ../rtl/code_nco.v \
  ../rtl/code_gen.v \
  ../rtl/carrier_nco.v \
  ../rtl/carrier_mixer.v \
  ../rtl/accumulator.v \
  ../rtl/epoch_counter.v \
  ../rtl/tracking_channel.v
vvp sim_tracking_channel

# View *.vcd file:
# gtkwave tracking_channel.vcd
