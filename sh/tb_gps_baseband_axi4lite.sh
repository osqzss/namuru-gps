#!/bin/sh
# Run the AXI4-Lite CDC testbench with Icarus Verilog.
# Execute from the sim/ directory:
#   cd sim && sh ../sh/tb_gps_baseband_axi4lite.sh

set -e

iverilog -g2012 -Wall \
  -o sim_gps_baseband_axi4lite \
  ../test/tb_gps_baseband_axi4lite.sv \
  ../rtl/cdc_sync_2ff.v \
  ../rtl/cdc_handshake.v \
  ../rtl/time_base.v \
  ../rtl/code_nco.v \
  ../rtl/code_gen.v \
  ../rtl/carrier_nco.v \
  ../rtl/carrier_mixer.v \
  ../rtl/accumulator.v \
  ../rtl/epoch_counter.v \
  ../rtl/tracking_channel.v \
  ../rtl/gps_baseband.v \
  ../rtl/gps_baseband_axi4lite_wrapper.v

vvp sim_gps_baseband_axi4lite
