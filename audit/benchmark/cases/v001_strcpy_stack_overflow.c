#include <string.h>

void copy_user(const char *user_input) {
    char buf[16];
    strcpy(buf, user_input); // unsafe: no bounds check
}
