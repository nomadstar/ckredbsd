#include <stdint.h>
#include <stdlib.h>

void *alloc_packets(uint32_t count, uint32_t size) {
    uint32_t total = count * size; // overflow risk
    return malloc(total);
}
