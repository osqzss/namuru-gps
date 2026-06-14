# namuru-gps

This repository provides a Verilog implementation of a single-channel GPS L1 C/A baseband tracking correlator, based on the NAMURU receiver code originally open-sourced by UNSW (The University of New South Wales). The design integrates a carrier NCO, code NCO, C/A code generation, epoch counting, and early/prompt/late I/Q accumulators. Simulation testbenches with file-driven IF input are included to validate code delay (slew), Doppler, and correlation performance.

## Repository Structure

- `rtl/`: Verilog source code for the GPS L1 C/A tracking channel and its submodules.
- `test/`: Testbenches for verifying the SystemVerilog modules.
- `sh/`: Helper scripts to run simulations with Icarus Verilog.
- `sim/`: IF signal generator used by the testbenches.

## Quick Check

### 1\. Generate IF data

Generate a single-PRN IF data stream (text format) with the IF generator:
```bash
cd sim
./gps_if_sim --prn 1 --delay 200 --dopp -2500 --ms 100 --cn0 55 > gps_if.txt
```

### 2\. Run the tracking channel testbench

Run `test/tb_tracking_channel.sv` using Icarus Verilog via the provided script:
```bash
cd sh
./tb_tracking_channel.sh
```
The testbench reads the IF file from Step 1 and outputs correlation results (early/prompt/late I/Q and power) to `corr_dump.txt`.

Make sure the following parameters in `test/tb_tracking_channel.sv` match the IF generator settings:

- `PRN_KEY_INIT`: PRN selection / G2 initial state (See [prn_keys.txt](https://github.com/osqzss/namuru-gps/blob/main/prn_keys.txt))
- `CODE_DELAY`: Code delay in chip
- `IF_DOPPLER_HZ`: Carrier Doppler in Hz

### 3\. Plot the outputs

Plot `corr_dump.txt` using the provided Python script:
```bash
cd sh
python corr_dump_plot.py
```

### 4\. Run the multi-channel baseband testbench

`gps_baseband.v` integrates multiple tracking channels and exposes a simple register interface (Avalon-style) for configuration and data readout. The testbench polls `new_data` every 900 us and reads correlator dumps once `new_data` is asserted.

```bash
cd sh
./tb_gps_baseband.sh
```

### 5\. Run the AXI4-Lite wrapper testbench (CDC)

`gps_baseband_axi4lite_wrapper.v` provides an AXI4-Lite slave interface on top of `gps_baseband.v`. The wrapper now spans **two asynchronous clock domains**:

- `aclk` — the PS AXI clock (e.g. `FCLK_CLK0`, 50 MHz).
- `baseband_clk` — the RF sampling clock derived from the MAX2769C `CLKOUT` (16.368 MHz), routed through a BUFG.

All signals crossing between these domains pass through dedicated clock-domain-crossing (CDC) logic so that register accesses remain coherent regardless of the clock-frequency ratio. The CDC is built from two portable primitives written in plain Verilog (no Xilinx XPM macros), so the whole design remains simulatable with Icarus Verilog:

- `rtl/cdc_sync_2ff.v` — a two-flip-flop synchronizer for single-/multi-bit level signals. Both flip-flops carry the `ASYNC_REG` attribute so Vivado keeps the synchronizer pair adjacent and runs automatic CDC analysis.
- `rtl/cdc_handshake.v` — a four-phase request/acknowledge handshake that safely transfers a multi-bit word between domains. Its port list matches `xpm_cdc_handshake` (`DEST_EXT_HSK=0`) so the two can be swapped without touching the surrounding logic.

The wrapper instantiates four CDC crossings:

| # | Signal | Direction | Primitive | Width |
|---|--------|-----------|-----------|-------|
| 1 | Write bus (address + data) | `aclk` → `baseband_clk` | `cdc_handshake` | 40-bit |
| 2 | Read request (address) | `aclk` → `baseband_clk` | `cdc_handshake` | 8-bit |
| 3 | Read data | `baseband_clk` → `aclk` | `cdc_handshake` | 32-bit |
| 4 | `accum_int` interrupt level | `baseband_clk` → `aclk` | `cdc_sync_2ff` | 1-bit |

On the AXI side, separate write and read FSMs drive the handshakes and hold each AXI response until the corresponding transfer has been acknowledged by the baseband domain. On the baseband side, a small state machine consumes the synchronized write/read pulses and drives the existing `gps_baseband` register bus, adding the extra cycle needed because `gps_baseband` updates `read_data` synchronously. The reset is also synchronized into `baseband_clk` (asynchronous assert, synchronous deassert). Note that simultaneous AXI read and write is not supported; the PS driver must serialise register accesses, which is normal for polled use.

The testbench (`test/tb_gps_baseband_axi4lite.sv`) generates both clocks independently (50 MHz `aclk` and 16.368 MHz `baseband_clk`), drives the file-based IF samples at the baseband rate, and exercises the full AXI → CDC → baseband → CDC → AXI path for every register access. The run script compiles the two CDC primitives along with the rest of the RTL:

```bash
cd sh
./tb_gps_baseband_axi4lite.sh
```

The required Vivado timing constraints (`create_clock` for `baseband_clk`, an asynchronous `set_clock_groups`, and `set_max_delay -datapath_only` on each handshake data path) are documented in the header of `gps_baseband_axi4lite_wrapper.v`.

## Status

(**2026/01/13**) As of now, the publicly available HDL is verified up to `tracking_channel.sv`.
An AXI4-Lite control interface wrapper will be added after its operation is fully validated.

(**2026/02/15**) Verified in simulation (Icarus Verilog): `tracking_channel.v`, multi-channel `gps_baseband.v`, and AXI4-Lite access via `gps_baseband_axi4lite_wrapper.v` using file-driven IF input.

(**2026/06/13**) Added CDC support for mixed clock domains (PS/AXI `aclk` vs RF sampling `baseband_clk`) using the portable `cdc_sync_2ff.v` and `cdc_handshake.v` primitives. Verified in simulation (Icarus Verilog) via `tb_gps_baseband_axi4lite.sv` with the two clocks running asynchronously.

**Upcoming work**: Vivado project generation and on-target bring-up on the FPGA.
