#include <stddef.h>
#include <stdint.h>
#include <time.h>
#include <sys/random.h>

int mbedtls_hardware_poll(void *data, unsigned char *output, size_t len, size_t *olen) {
    (void)data;
    ssize_t got = getrandom(output, len, 0);
    if (got < 0) {
        *olen = 0;
        return -1;
    }
    *olen = (size_t)got;
    return 0;
}

/* milliseconds off a clock that only goes forward, for tls 1.3 ticket ages */
int64_t mbedtls_ms_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
