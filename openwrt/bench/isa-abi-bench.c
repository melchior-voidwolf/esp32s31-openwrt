/*
 * ESP32-S31 ABI/ISA microbenchmark.
 *
 * Build variants with the same C source and -O2 -fno-fast-math
 * -ffp-contract=off.  The checksums make cross-variant correctness drift
 * visible; disassembly is still required to prove the intended instructions.
 */
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern float abi_float_step(float acc, float factor, float increment);

static uint64_t monotonic_ns(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("clock_gettime");
        exit(2);
    }
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

__attribute__((noinline))
static uint32_t bench_float(uint32_t iterations, uint32_t seed)
{
    float acc = 1.0f + (float)(seed & 0xffffu) * 0x1p-20f;
    const float factor = 0.99999994f;
    const float increment = 0x1p-23f;
    uint32_t bits;

    for (uint32_t i = 0; i < iterations; ++i)
        acc = acc * factor + increment;
    memcpy(&bits, &acc, sizeof(bits));
    return bits;
}

__attribute__((noinline))
static uint32_t bench_abi_call(uint32_t iterations, uint32_t seed)
{
    float acc = 1.0f + (float)(seed & 0xffffu) * 0x1p-20f;
    const float factor = 0.99999994f;
    const float increment = 0x1p-23f;
    uint32_t bits;

    for (uint32_t i = 0; i < iterations; ++i)
        acc = abi_float_step(acc, factor, increment);
    memcpy(&bits, &acc, sizeof(bits));
    return bits;
}

__attribute__((noinline))
static uint32_t bench_sqrt(uint32_t iterations, uint32_t seed)
{
    float acc = (float)(seed & 7u);

    for (uint32_t i = 0; i < iterations; ++i)
        acc += sqrtf((float)(i & 1023u) + 1.0f);
    uint32_t bits;
    memcpy(&bits, &acc, sizeof(bits));
    return bits;
}

__attribute__((noinline))
static uint64_t bench_double(uint32_t iterations, uint32_t seed)
{
    double acc = 1.0 + (double)(seed & 0xffffu) * 0x1p-20;
    const double factor = 0.9999999999999999;
    const double increment = 0x1p-53;
    uint64_t bits;

    for (uint32_t i = 0; i < iterations; ++i)
        acc = acc * factor + increment;
    memcpy(&bits, &acc, sizeof(bits));
    return bits;
}

__attribute__((noinline))
static uint32_t bench_bits(uint32_t iterations, uint32_t seed)
{
    uint32_t x = seed ? seed : 1u;
    uint32_t acc = 0x9e3779b9u;

    for (uint32_t i = 0; i < iterations; ++i) {
        uint32_t y;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        y = x | 1u;
        acc += (uint32_t)__builtin_clz(y);
        acc ^= (uint32_t)__builtin_ctz(y);
        acc += __builtin_bswap32(x);
        acc = (acc << 7) | (acc >> 25);
        acc &= ~(1u << ((x >> 8) & 31));
        acc |= 1u << (x & 31);
    }
    return acc ^ x;
}

static void print_result(const char *mode, uint32_t iterations,
                         uint64_t elapsed, uint64_t checksum, int width)
{
    printf("RESULT mode=%s iterations=%" PRIu32
           " seconds=%llu.%06llu checksum=%0*llx\n",
           mode, iterations,
           (unsigned long long)(elapsed / 1000000000ull),
           (unsigned long long)((elapsed % 1000000000ull) / 1000ull),
           width, (unsigned long long)checksum);
}

static void run_one(const char *mode, uint32_t iterations, uint32_t seed)
{
    uint64_t start = monotonic_ns();
    uint64_t checksum;
    int width = 8;

    if (strcmp(mode, "float") == 0) {
        checksum = bench_float(iterations, seed);
    } else if (strcmp(mode, "abi-call") == 0) {
        checksum = bench_abi_call(iterations, seed);
    } else if (strcmp(mode, "sqrt") == 0) {
        checksum = bench_sqrt(iterations, seed);
    } else if (strcmp(mode, "double") == 0) {
        checksum = bench_double(iterations, seed);
        width = 16;
    } else if (strcmp(mode, "bits") == 0) {
        checksum = bench_bits(iterations, seed);
    } else {
        fprintf(stderr, "unknown mode: %s\n", mode);
        exit(2);
    }
    print_result(mode, iterations, monotonic_ns() - start, checksum, width);
}

int main(int argc, char **argv)
{
    static const char *const modes[] = { "float", "abi-call", "sqrt", "double", "bits" };
    uint32_t iterations = 2000000;
    uint32_t seed = 0x12345678u;

    if (argc < 2) {
        fprintf(stderr, "usage: %s float|abi-call|sqrt|double|bits|all [iterations] [seed]\n", argv[0]);
        return 2;
    }
    if (argc > 2)
        iterations = (uint32_t)strtoul(argv[2], NULL, 0);
    if (argc > 3)
        seed = (uint32_t)strtoul(argv[3], NULL, 0);
    if (!iterations) {
        fprintf(stderr, "iterations must be nonzero\n");
        return 2;
    }

    if (strcmp(argv[1], "all") != 0) {
        run_one(argv[1], iterations, seed);
        return 0;
    }
    for (size_t i = 0; i < sizeof(modes) / sizeof(modes[0]); ++i)
        run_one(modes[i], iterations, seed);
    return 0;
}
