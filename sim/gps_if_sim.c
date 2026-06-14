// gps_if_sim.c
// Build: gcc -O2 -Wall -Wextra -lm gps_if_sim.c -o gps_if_sim
//
// Output: i_sign i_mag  (each 0/1)

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// GPS L1 C/A
#define CHIP_RATE 1.023e6
#define CA_LEN 1023

// Data bit
#define BIT_MS 5

// Standard GPS PRN 1..37 G2 tap pairs (phase selectors).
// Each entry is two tap positions (1..10) XORed from G2.
typedef struct { int t1, t2; } g2tap_t;
static const g2tap_t G2_TAPS_PRN_1_37[37] = {
    {2,6},   {3,7},   {4,8},   {5,9},   {1,9},   {2,10},  {1,8},   {2,9},   {3,10},  {2,3},
    {3,4},   {5,6},   {6,7},   {7,8},   {8,9},   {9,10},  {1,4},   {2,5},   {3,6},   {4,7},
    {5,8},   {6,9},   {1,3},   {4,6},   {5,7},   {6,8},   {7,9},   {8,10},  {1,6},   {2,7},
    {3,8},   {4,9},   {5,10},  {4,10},  {1,7},   {2,8},   {4,10}
};

// Simple uniform RNG [0,1)
static inline double urand(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    *state = x;
    return (double)x / 4294967296.0;
}

// Standard normal RNG using Box-Muller
static inline double grand(uint32_t *state) {
    double u1 = urand(state);
    double u2 = urand(state);
    if (u1 < 1e-12) u1 = 1e-12;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

// Generate C/A chips (+1/-1) for given PRN (1..37)
static int gen_ca_code(int prn, int8_t ca[CA_LEN]) {
    if (prn < 1 || prn > 37) return -1;

    // G1 and G2 are 10-bit shift registers, initial all ones
    int g1[10], g2[10];
    for (int i = 0; i < 10; i++) { g1[i] = 1; g2[i] = 1; }

    int t1 = G2_TAPS_PRN_1_37[prn - 1].t1;
    int t2 = G2_TAPS_PRN_1_37[prn - 1].t2;

    for (int i = 0; i < CA_LEN; i++) {
        int g1_out = g1[9];
        int g2_out = g2[t1 - 1] ^ g2[t2 - 1];
        int ca_bit = g1_out ^ g2_out;
        ca[i] = (ca_bit == 0) ? +1 : -1;

        int g1_fb = g1[2] ^ g1[9];
        int g2_fb = g2[1] ^ g2[2] ^ g2[5] ^ g2[7] ^ g2[8] ^ g2[9];

        for (int k = 9; k >= 1; k--) g1[k] = g1[k - 1];
        g1[0] = g1_fb;
        for (int k = 9; k >= 1; k--) g2[k] = g2[k - 1];
        g2[0] = g2_fb;
    }
    return 0;
}

// Quantize a real value x -> sign/mag bits.
// sign: 0 = negative, 1 = positive
// mag : 0 = 1, 1 = 3
static inline void quantize_2bit(double x, int *sign, int *mag) {
    // Threshold chosen so that for pure N(0,1):
    // P(|x| < T) = 0.68  => T ~ 0.994 (since Phi(T)=0.84)
    const double T = 0.9944578832;

    *sign = (x >= 0.0) ? 1 : 0;
    *mag  = (fabs(x) >= T) ? 1 : 0;
}

static void usage(const char *p) {
    fprintf(stderr,
        "Usage: %s --prn N --delay chips --dopp Hz [options]\n"
        "Options:\n"
        "  --fs Hz        sampling frequency (default 16368000)\n"
        "  --fif Hz       IF center frequency (default 4092000)\n"
        "  --ms MS        duration in ms (default 10)\n"
        "  --cn0 dBHz     C/N0 (default 45)\n"
        "  -o path        output (default stdout)\n"
        "  --seed u32     RNG seed (default 1)\n",
        p
    );
}

int main(int argc, char **argv) {
    int prn = 0;
    double codephase = 0.0, fbb = 0.0, fif = 4.092e6;
    double fs = 16.368e6, ms = 10.0, cn0_dbhz = 45.0;
    const char *outpath = NULL;
    uint32_t seed = 1;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--prn") && i + 1 < argc) prn = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--delay") && i + 1 < argc) codephase = atof(argv[++i]);
        else if (!strcmp(argv[i], "--dopp") && i + 1 < argc) fbb = atof(argv[++i]);
        else if (!strcmp(argv[i], "--fif") && i + 1 < argc) fif = atof(argv[++i]);
        else if (!strcmp(argv[i], "--fs") && i + 1 < argc) fs = atof(argv[++i]);
        else if (!strcmp(argv[i], "--ms") && i + 1 < argc) ms = atof(argv[++i]);
        else if (!strcmp(argv[i], "--cn0") && i + 1 < argc) cn0_dbhz = atof(argv[++i]);
        else if (!strcmp(argv[i], "--seed") && i + 1 < argc) seed = (uint32_t)strtoul(argv[++i], NULL, 10);
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) outpath = argv[++i];
        else { usage(argv[0]); return 2; }
    }

    if (prn < 1 || prn > 37) { usage(argv[0]); return 2; }
    
    // Set delayed code phase
    codephase = fmod(1023.0 - codephase, 1023.0);

    if (!(codephase >= 0.0 && codephase <= 1023.0)) {
        fprintf(stderr, "Error: --codephase must be in [0,1023].\n");
        return 2;
    }

    int8_t ca[CA_LEN];
    if (gen_ca_code(prn, ca) != 0) {
        fprintf(stderr, "Error: PRN %d not supported (1..37).\n", prn);
        return 2;
    }

    FILE *fp = stdout;
    if (outpath) {
        fp = fopen(outpath, "w");
        if (!fp) { perror("fopen"); return 1; }
    }

    const double cn0_lin = pow(10.0, cn0_dbhz / 10.0);
    const double A = sqrt(4.0 * cn0_lin / fs); // IF(real): carrier power = A^2/2

    const uint64_t N = (uint64_t)llround((ms * 1e-3) * fs);
    const double fcar = fif + fbb;
    double phase = 0.0;
    const double dphi = 2.0 * M_PI * fcar / fs;

    uint32_t rng = seed ? seed : 1;

    // Update the data bit every BIT_MS milliseconds.
    int data_bit = +1;          // +1 or -1
    uint64_t epoch_count = 0;   // counts C/A code epochs (each time chip_f wraps)
    double prev_chip_f = 0.0;
    int prev_valid = 0;

    for (uint64_t n = 0; n < N; n++) {
        double t_chip = ((double)n) * (CHIP_RATE / fs);
        double chip_f = fmod(codephase + t_chip, (double)CA_LEN);
        if (chip_f < 0) chip_f += CA_LEN;

        // Detect C/A code epoch boundary by wrap-around of chip_f.
        if (prev_valid) {
            if (chip_f < prev_chip_f) {
                epoch_count++;
                if ((epoch_count % BIT_MS) == 0) {
                    // new nav data bit (+1/-1)
                    //data_bit = (urand(&rng) < 0.5) ? +1 : -1;
                    data_bit *= -1;
                }
            }
        } else {
            prev_valid = 1;
        }
        prev_chip_f = chip_f;

        int chip_idx = (int)floor(chip_f);
        double c = (double)ca[chip_idx];

        double s = A * c * cos(phase) + grand(&rng);

        // Apply navigation data bit
        s *= (double)data_bit;

        int is, im;
        quantize_2bit(s, &is, &im);
        fprintf(fp, "%d %d\n", is, im);

        phase += dphi;
        if (phase > 1e6) phase = fmod(phase, 2.0 * M_PI);
    }

    if (fp != stdout) fclose(fp);
    return 0;
}
