# gps_if_sim

`gps_if_sim` is a small command-line utility that generates **GPS L1 C/A-like real IF samples** for RTL/FPGA correlator and acquisition testing. It synthesizes a selected PRN C/A code (PRN 1–37) mixed to an IF carrier (center frequency + Doppler), adds AWGN, and then outputs **2-bit sign/magnitude** samples that mimic a typical GNSS RF IC quantizer.

Each output sample is written as two bits:

- `i_sign` (0 = negative, 1 = positive)  
- `i_mag`  (0 = amplitude 1, 1 = amplitude 3)

So the reconstructed sample value is one of **{-3, -1, +1, +3}**.

## Build

```bash
gcc -O2 -Wall -Wextra gps_if_sim.c -lm -o gps_if_sim
```

## Usage

```bash
./gps_if_sim --prn N --delay CHIPS --dopp HZ [options]
```

**Required**

- --prn : PRN number (1..37)
- --delay : code delay in chips (real, 0..1023)
- --dopp : Doppler / baseband frequency offset in Hz (added to IF)

**Options**

- --fs : sampling frequency in Hz (default: 16368000)
- --fif : IF center frequency in Hz (default: 4092000)
- --ms : output duration in milliseconds (default: 10)
- --cn0 : C/N0 in dB-Hz (default: 45)
- --seed : RNG seed (default: 1)
- -o : output file path (default: stdout)

**Example**

Generate a longer capture with a stronger signal.

```bash
./gps_if_sim --prn 1 --delay 200 --dopp -2500 --ms 100 --cn0 55 > gps_if.txt
```

# gps_if_acq.py

This repository also includes `gps_if_acq.py`, a lightweight **FFT-based GPS L1 C/A acquisition** script for verifying the generated IF data.

It:
- reads `gps_if_sim` output (`i_sign i_mag` per line) and reconstructs real-valued samples in **{-3, -1, +1, +3}**
- performs **FFT-based circular correlation** against a local PRN replica
- searches **residual Doppler** over a configurable range
- uses **non-coherent integration**
- reports the estimated **code delay** and **frequency offset**
- plots:
  - IF histogram
  - IF power spectrum
  - correlation vs. code delay at the best Doppler bin
  - Doppler search metric curve

## Usage

Generate IF data with `gps_if_sim`, then run acquisition using only file name and PRN (other parameters use defaults).

**Example**

```bash
python3 gps_if_acq.py --prn 1 --file gps_if.txt
```
