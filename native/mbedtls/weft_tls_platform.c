/* Platform leaves used by the static Mbed TLS archive. */

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__APPLE__)
#include <stdlib.h>

void *weft_tls_calloc(size_t count, size_t size)
{
    return calloc(count, size);
}

void weft_tls_free(void *pointer)
{
    free(pointer);
}

#elif defined(__linux__) && defined(__aarch64__)

#define WEFT_LINUX_SYS_MUNMAP 215
#define WEFT_LINUX_SYS_MMAP 222
#define WEFT_LINUX_SYS_MPROTECT 226
#define WEFT_LINUX_PROT_NONE 0
#define WEFT_LINUX_PROT_READ_WRITE 3
#define WEFT_LINUX_MAP_PRIVATE_ANONYMOUS 0x22
#define WEFT_LINUX_PAGE_SIZE 4096u

#if defined(WEFT_TLS_PLATFORM_DIAGNOSTICS)
typedef struct weft_tls_allocation_header {
    uint64_t magic;
    uintptr_t mapping_base;
    size_t mapping_size;
    size_t requested_size;
    size_t aligned_size;
} weft_tls_allocation_header;

#define WEFT_TLS_ALLOCATION_MAGIC UINT64_C(0x57454654544c5344)
#define WEFT_TLS_REDZONE_BYTE 0xa5u
#else
typedef struct weft_tls_allocation_header {
    size_t mapping_size;
    size_t requested_size;
} weft_tls_allocation_header;
#endif

static long weft_linux_syscall2(long number, long first, long second)
{
    register long x0 __asm__("x0") = first;
    register long x1 __asm__("x1") = second;
    register long x8 __asm__("x8") = number;
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x1), "r"(x8) : "memory");
    return x0;
}

#if defined(WEFT_TLS_PLATFORM_DIAGNOSTICS)
static long weft_linux_syscall3(
    long number,
    long first,
    long second,
    long third)
{
    register long x0 __asm__("x0") = first;
    register long x1 __asm__("x1") = second;
    register long x2 __asm__("x2") = third;
    register long x8 __asm__("x8") = number;
    __asm__ volatile(
        "svc 0"
        : "+r"(x0)
        : "r"(x1), "r"(x2), "r"(x8)
        : "memory");
    return x0;
}
#endif

static long weft_linux_syscall6(
    long number,
    long first,
    long second,
    long third,
    long fourth,
    long fifth,
    long sixth)
{
    register long x0 __asm__("x0") = first;
    register long x1 __asm__("x1") = second;
    register long x2 __asm__("x2") = third;
    register long x3 __asm__("x3") = fourth;
    register long x4 __asm__("x4") = fifth;
    register long x5 __asm__("x5") = sixth;
    register long x8 __asm__("x8") = number;
    __asm__ volatile(
        "svc 0"
        : "+r"(x0)
        : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5), "r"(x8)
        : "memory");
    return x0;
}

void *weft_tls_calloc(size_t count, size_t size)
{
#if defined(WEFT_TLS_PLATFORM_DIAGNOSTICS)
    size_t requested;
    size_t aligned_size;
    size_t writable_size;
    size_t mapping_size;
    long raw;
    unsigned char *mapping;
    unsigned char *trailing_guard;
    unsigned char *bytes;
    weft_tls_allocation_header *header;
    size_t index;

    if (size != 0 && count > ((size_t) -1) / size) {
        return NULL;
    }
    requested = count * size;
    if (requested > ((size_t) -1) - 15u) {
        return NULL;
    }
    aligned_size = (requested + 15u) & ~((size_t) 15u);
    if (aligned_size > ((size_t) -1) - sizeof(*header) -
                           (WEFT_LINUX_PAGE_SIZE - 1u)) {
        return NULL;
    }
    writable_size = (sizeof(*header) + aligned_size +
                     WEFT_LINUX_PAGE_SIZE - 1u) &
                    ~((size_t) WEFT_LINUX_PAGE_SIZE - 1u);
    if (writable_size > ((size_t) -1) - (2u * WEFT_LINUX_PAGE_SIZE)) {
        return NULL;
    }
    mapping_size = writable_size + (2u * WEFT_LINUX_PAGE_SIZE);
    raw = weft_linux_syscall6(
        WEFT_LINUX_SYS_MMAP,
        0,
        (long) mapping_size,
        WEFT_LINUX_PROT_READ_WRITE,
        WEFT_LINUX_MAP_PRIVATE_ANONYMOUS,
        -1,
        0);
    if (raw < 0 && raw >= -4095) {
        return NULL;
    }
    mapping = (unsigned char *) (uintptr_t) raw;
    if (weft_linux_syscall3(
            WEFT_LINUX_SYS_MPROTECT,
            (long) (uintptr_t) mapping,
            WEFT_LINUX_PAGE_SIZE,
            WEFT_LINUX_PROT_NONE) != 0 ||
        weft_linux_syscall3(
            WEFT_LINUX_SYS_MPROTECT,
            (long) (uintptr_t) (mapping + WEFT_LINUX_PAGE_SIZE + writable_size),
            WEFT_LINUX_PAGE_SIZE,
            WEFT_LINUX_PROT_NONE) != 0) {
        (void) weft_linux_syscall2(
            WEFT_LINUX_SYS_MUNMAP,
            (long) (uintptr_t) mapping,
            (long) mapping_size);
        return NULL;
    }
    trailing_guard = mapping + WEFT_LINUX_PAGE_SIZE + writable_size;
    bytes = trailing_guard - aligned_size;
    header = (weft_tls_allocation_header *) (bytes - sizeof(*header));
    header->magic = WEFT_TLS_ALLOCATION_MAGIC;
    header->mapping_base = (uintptr_t) mapping;
    header->mapping_size = mapping_size;
    header->requested_size = requested;
    header->aligned_size = aligned_size;
    for (index = requested; index < aligned_size; index += 1) {
        bytes[index] = WEFT_TLS_REDZONE_BYTE;
    }
    return bytes;
#else
    size_t requested;
    size_t total;
    size_t mapping_size;
    long raw;
    weft_tls_allocation_header *header;
    unsigned char *bytes;
    size_t index;

    if (size != 0 && count > ((size_t) -1) / size) {
        return NULL;
    }
    requested = count * size;
    if (requested > ((size_t) -1) - sizeof(*header)) {
        return NULL;
    }
    total = requested + sizeof(*header);
    if (total > ((size_t) -1) - 4095) {
        return NULL;
    }
    mapping_size = (total + 4095) & ~((size_t) 4095);
    raw = weft_linux_syscall6(
        WEFT_LINUX_SYS_MMAP,
        0,
        (long) mapping_size,
        WEFT_LINUX_PROT_READ_WRITE,
        WEFT_LINUX_MAP_PRIVATE_ANONYMOUS,
        -1,
        0);
    if (raw < 0 && raw >= -4095) {
        return NULL;
    }
    header = (weft_tls_allocation_header *) (uintptr_t) raw;
    header->mapping_size = mapping_size;
    header->requested_size = requested;
    bytes = (unsigned char *) (header + 1);
    for (index = 0; index < requested; index += 1) {
        bytes[index] = 0;
    }
    return bytes;
#endif
}

void weft_tls_free(void *pointer)
{
#if defined(WEFT_TLS_PLATFORM_DIAGNOSTICS)
    unsigned char *bytes;
    weft_tls_allocation_header *header;
    uintptr_t mapping_base;
    size_t mapping_size;
    size_t index;

    if (pointer == NULL) {
        return;
    }
    bytes = (unsigned char *) pointer;
    header = (weft_tls_allocation_header *) (bytes - sizeof(*header));
    if (header->magic != WEFT_TLS_ALLOCATION_MAGIC ||
        header->aligned_size < header->requested_size) {
        __builtin_trap();
    }
    for (index = header->requested_size; index < header->aligned_size; index += 1) {
        if (bytes[index] != WEFT_TLS_REDZONE_BYTE) {
            __builtin_trap();
        }
    }
    mapping_base = header->mapping_base;
    mapping_size = header->mapping_size;
    header->magic = 0;
    (void) weft_linux_syscall2(
        WEFT_LINUX_SYS_MUNMAP,
        (long) mapping_base,
        (long) mapping_size);
#else
    weft_tls_allocation_header *header;
    if (pointer == NULL) {
        return;
    }
    header = ((weft_tls_allocation_header *) pointer) - 1;
    (void) weft_linux_syscall2(
        WEFT_LINUX_SYS_MUNMAP,
        (long) (uintptr_t) header,
        (long) header->mapping_size);
#endif
}

#if defined(__linux__) && defined(__aarch64__) && \
    defined(WEFT_TLS_PLATFORM_DIAGNOSTICS)
int weft_tls_platform_diagnostics_enabled(void)
{
    return 1;
}
#endif

#else
#error "Weft's Mbed TLS platform supports only macOS/AArch64 and Linux/AArch64"
#endif

void *memcpy(void *destination, const void *source, size_t length)
{
    unsigned char *out = (unsigned char *) destination;
    const unsigned char *in = (const unsigned char *) source;
    size_t index;
    for (index = 0; index < length; index += 1) {
        out[index] = in[index];
    }
    return destination;
}

void *memmove(void *destination, const void *source, size_t length)
{
    unsigned char *out = (unsigned char *) destination;
    const unsigned char *in = (const unsigned char *) source;
    size_t index;
    if (out < in) {
        for (index = 0; index < length; index += 1) {
            out[index] = in[index];
        }
    } else if (out > in) {
        index = length;
        while (index > 0) {
            index -= 1;
            out[index] = in[index];
        }
    }
    return destination;
}

void *memset(void *destination, int value, size_t length)
{
    unsigned char *out = (unsigned char *) destination;
    size_t index;
    for (index = 0; index < length; index += 1) {
        out[index] = (unsigned char) value;
    }
    return destination;
}

int memcmp(const void *left, const void *right, size_t length)
{
    const unsigned char *a = (const unsigned char *) left;
    const unsigned char *b = (const unsigned char *) right;
    size_t index;
    for (index = 0; index < length; index += 1) {
        if (a[index] != b[index]) {
            return a[index] < b[index] ? -1 : 1;
        }
    }
    return 0;
}

size_t strlen(const char *text)
{
    size_t length = 0;
    while (text[length] != '\0') {
        length += 1;
    }
    return length;
}

size_t strnlen(const char *text, size_t limit)
{
    size_t length = 0;
    while (length < limit && text[length] != '\0') {
        length += 1;
    }
    return length;
}

int strcmp(const char *left, const char *right)
{
    size_t index = 0;
    while (left[index] != '\0' && left[index] == right[index]) {
        index += 1;
    }
    return (unsigned char) left[index] - (unsigned char) right[index];
}

int strncmp(const char *left, const char *right, size_t limit)
{
    size_t index = 0;
    while (index < limit && left[index] != '\0' && left[index] == right[index]) {
        index += 1;
    }
    if (index == limit) {
        return 0;
    }
    return (unsigned char) left[index] - (unsigned char) right[index];
}

char *strncpy(char *destination, const char *source, size_t limit)
{
    size_t index = 0;
    while (index < limit && source[index] != '\0') {
        destination[index] = source[index];
        index += 1;
    }
    while (index < limit) {
        destination[index] = '\0';
        index += 1;
    }
    return destination;
}

char *strchr(const char *text, int needle)
{
    char wanted = (char) needle;
    while (*text != '\0') {
        if (*text == wanted) {
            return (char *) text;
        }
        text += 1;
    }
    return wanted == '\0' ? (char *) text : NULL;
}

char *strstr(const char *text, const char *needle)
{
    size_t needle_length = strlen(needle);
    if (needle_length == 0) {
        return (char *) text;
    }
    while (*text != '\0') {
        if (strncmp(text, needle, needle_length) == 0) {
            return (char *) text;
        }
        text += 1;
    }
    return NULL;
}

void explicit_bzero(void *destination, size_t length)
{
    volatile unsigned char *out = (volatile unsigned char *) destination;
    while (length > 0) {
        *out = 0;
        out += 1;
        length -= 1;
    }
}

int weft_tls_snprintf(char *buffer, size_t length, const char *format, ...)
{
    (void) format;
    if (length > 0) {
        buffer[0] = '\0';
    }
    return -1;
}

int weft_tls_printf(const char *format, ...)
{
    (void) format;
    return -1;
}
