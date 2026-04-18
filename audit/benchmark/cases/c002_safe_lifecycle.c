#include <stdlib.h>

int read_once(void) {
    int *p = malloc(sizeof(int));
    if (!p) return -1;
    *p = 42;
    int value = *p;
    free(p);
    return value;
}
