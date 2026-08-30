#include <stdint.h>
#include <signal.h>
#include <stdlib.h>

void *fixture_open(int64_t value);
void fixture_close(void *raw);

static void fixture_canary_rejected(int signal_number)
{
    (void) signal_number;
    _Exit(99);
}

int main(void)
{
    (void) signal(SIGBUS, fixture_canary_rejected);
    (void) signal(SIGSEGV, fixture_canary_rejected);
    volatile uint8_t *bytes = (volatile uint8_t *) fixture_open(42);
    if (bytes == (void *) 0) {
        return 2;
    }
    bytes[16] = 0x42;
    fixture_close((void *) bytes);
    return 0;
}
