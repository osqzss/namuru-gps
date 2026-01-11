# namuru-gps

A SystemVerilog implementation of a single-channel GPS L1 C/A baseband tracking correlator, based on the NAMURU receiver code originally open-sourced by UNSW. The design integrates carrier/code NCOs, C/A code generation, epoch counting, and early/prompt/late I/Q accumulators. Simulation testbenches with file-driven IF input are included to validate code delay, Doppler, and correlation performance.
