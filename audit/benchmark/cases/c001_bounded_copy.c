#include <stddef.h>
#include <string.h>

void copy_user_safe(const char *user_input, char *out, size_t out_size) {
    if (!out || out_size == 0) return;
    strncpy(out, user_input, out_size - 1);
    out[out_size - 1] = '\0';
}
