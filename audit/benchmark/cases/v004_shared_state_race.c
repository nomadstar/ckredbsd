#include <pthread.h>

volatile int shared_counter = 0;

void *worker(void *arg) {
    for (int i = 0; i < 100000; i++) {
        shared_counter++; // unsynchronized shared write
    }
    return arg;
}
