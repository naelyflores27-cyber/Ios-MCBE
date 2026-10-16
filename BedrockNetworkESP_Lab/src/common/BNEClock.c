#include "BNEClock.h"

#include <time.h>

uint64_t bne_monotonic_time_ms(void) {
    struct timespec time_value;
    if (clock_gettime(CLOCK_MONOTONIC, &time_value) != 0) return 0;
    return (uint64_t)time_value.tv_sec * 1000 +
        (uint64_t)time_value.tv_nsec / 1000000;
}