#pragma once
#include <stdint.h>

#define TICKS_PER_MS (10140625 / 1000)

static inline uint64_t get_time(void)
{
    unsigned long lo, hi, hi2;

    do {
        asm volatile("csrr %0, timeh" : "=r"(hi));
        asm volatile("csrr %0, time" : "=r"(lo));
        asm volatile("csrr %0, timeh" : "=r"(hi2));
    } while (hi != hi2);

    return ((uint64_t)hi << 32) | lo;
}
