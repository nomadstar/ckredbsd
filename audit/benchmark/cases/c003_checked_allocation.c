#include <limits.h>
#include <stddef.h>
#include <stdlib.h>

void *alloc_packets_safe(size_t count, size_t size) {
    if (size != 0 && count > SIZE_MAX / size) {
        return NULL;
    }
    return calloc(count, size);
}
