#include <stdio.h>
#include <stdint.h>
#include <time.h>

__attribute__((noinline))
float s31_fpu_test(float a, float b, float c) {
	return a * b + c;
}

__attribute__((noinline))
uint32_t s31_bitmanip_test(uint32_t x, uint32_t idx) {
	/* Triggers zbb (__builtin_bswap32 -> rev8, __builtin_clz -> clz)
	 * and zbs (1u << idx) + zba (array/shift add) */
	return __builtin_bswap32(x) + (uint32_t)__builtin_clz(x | 1u) + (1u << (idx & 31));
}

int main(void) {
	float r = s31_fpu_test(1.5f, 2.25f, 0.625f); /* 3.375 + 0.625 = 4.0f */
	union { float f; uint32_t u; } u = { .f = r };
	uint32_t bm = s31_bitmanip_test(0x12345678u, 5);
	printf("HELLO_RISCV32_ILP32F_OK sizeof(long)=%zu sizeof(time_t)=%zu fpu_bits=0x%08x bm=0x%08x\n",
	       sizeof(long), sizeof(time_t), u.u, bm);
	return (u.u == 0x40800000u) ? 0 : 1;
}
