#include <stdlib.h>

int read_after_release(void) {
    int *p = malloc(sizeof(int));
    if (!p) return -1;
    *p = 42;
    free(p);
    return *p; // use-after-free
}
