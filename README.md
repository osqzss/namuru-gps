# namuru-gps

This repository provides a SystemVerilog implementation of a single-channel GPS L1 C/A baseband tracking correlator, based on the NAMURU receiver code originally open-sourced by UNSW. The design integrates carrier/code NCOs, C/A code generation, epoch counting, and early/prompt/late I/Q accumulators. Simulation testbenches with file-driven IF input are included to validate code delay, Doppler, and correlation performance.

## Contents

The repository structure is organized as follows:

- **`rtl/`**: Contains the SystemVerilog source code for the GPS C/A code tracking channel.
- **`test/`**: Includes the testbenches for verifying the SystemVerilog modules.
- **`sh/`**: Contains shell scripts to execute the testbenches using Icarus Verilog.
- **`sim/`**: Provides the source code for a command-line interface (CLI) application that generates the intermediate frequency (IF) signals used in the testbenches.