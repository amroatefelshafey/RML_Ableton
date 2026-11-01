/*
 * HPS-side test for the ids_cnn1d_avmm accelerator on the DE1-SoC.
 * Maps the lightweight HPS-to-FPGA bridge through /dev/mem, pushes the 100
 * labeled samples through the FPGA, and checks every logit against the
 * bit-exact reference computed in Python.
 *
 * Build: arm-none-linux-gnueabihf-gcc -O2 -static ids_fpga_test.c -o ids_fpga_test
 * Run:   ./ids_fpga_test [component offset in hex, default 0x0]   (as root)
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "ids_samples.h"

#define LW_BRIDGE_BASE 0xFF200000u
#define LW_BRIDGE_SPAN 0x00200000u

/* Word offsets, see rtl/src/ids_cnn1d_avmm.sv */
#define REG_IN      0
#define REG_CTRL    16
#define REG_STATUS  16
#define REG_RESULT  17
#define REG_LOGIT   18
#define REG_COUNT   26
#define REG_ID      27
#define IDS_ID      0x1D5C0001u

static volatile uint32_t *regs;

static int classify(const signed char x[64], int32_t logits[8])
{
    const uint8_t *b = (const uint8_t *)x;
    while (!(regs[REG_STATUS] & 1u))
        ;
    for (int w = 0; w < 16; w++)
        regs[REG_IN + w] = (uint32_t)b[4*w] | (uint32_t)b[4*w+1] << 8 |
                           (uint32_t)b[4*w+2] << 16 | (uint32_t)b[4*w+3] << 24;
    regs[REG_CTRL] = 1;
    while (!(regs[REG_STATUS] & 2u))
        ;
    for (int k = 0; k < 8; k++)
        logits[k] = (int32_t)regs[REG_LOGIT + k];
    return (int)(regs[REG_RESULT] & 7u);     /* this read pops the result */
}

int main(int argc, char **argv)
{
    uint32_t offset = argc > 1 ? (uint32_t)strtoul(argv[1], NULL, 16) : 0;
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem (run as root)"); return 1; }
    void *base = mmap(NULL, LW_BRIDGE_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, LW_BRIDGE_BASE);
    if (base == MAP_FAILED) { perror("mmap"); return 1; }
    regs = (volatile uint32_t *)((uint8_t *)base + offset);

    if (regs[REG_ID] != IDS_ID) {
        fprintf(stderr, "ID register reads 0x%08x, expected 0x%08x: wrong offset or "
                        "FPGA not configured\n", regs[REG_ID], IDS_ID);
        return 1;
    }

    int correct = 0, golden_mismatch = 0;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int s = 0; s < IDS_N_SAMPLES; s++) {
        int32_t lg[8];
        int cls = classify(IDS_X[s], lg);
        int bad = cls != IDS_GOLDEN[s];
        for (int k = 0; k < 8; k++)
            bad |= lg[k] != IDS_GOLDEN_LOGIT[s][k];
        golden_mismatch += bad;
        correct += cls == IDS_LABEL[s];
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double us = ((t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec)) / 1e3;

    printf("Samples:            %d\n", IDS_N_SAMPLES);
    printf("Accuracy:           %.2f%%\n", 100.0 * correct / IDS_N_SAMPLES);
    printf("Golden mismatches:  %d (expect 0)\n", golden_mismatch);
    printf("Avg time / sample:  %.2f us (dominated by MMIO over the LW bridge)\n",
           us / IDS_N_SAMPLES);
    printf("FPGA result count:  %u\n", regs[REG_COUNT]);
    return golden_mismatch != 0;
}
