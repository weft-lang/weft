#include <stddef.h>
#include <stdint.h>

#if defined(__APPLE__)

#include <stdlib.h>

static void *fixture_allocate(size_t size)
{
    return calloc(1, size);
}

static void fixture_release(void *pointer)
{
    free(pointer);
}

#elif defined(__linux__) && defined(__aarch64__)

#define FIXTURE_LINUX_SYS_MUNMAP 215
#define FIXTURE_LINUX_SYS_MPROTECT 226
#define FIXTURE_LINUX_SYS_MMAP 222
#define FIXTURE_LINUX_PROT_NONE 0
#define FIXTURE_LINUX_PROT_READ_WRITE 3
#define FIXTURE_LINUX_MAP_PRIVATE_ANONYMOUS 0x22
#define FIXTURE_PAGE_SIZE 4096u
#define FIXTURE_REDZONE_BYTE 0xa5u
#define FIXTURE_HEADER_MAGIC UINT64_C(0x5745465444494147)

typedef struct fixture_allocation_header {
    uint64_t magic;
    uintptr_t mapping_base;
    size_t mapping_size;
    size_t requested_size;
    size_t aligned_size;
} fixture_allocation_header;

static long fixture_linux_syscall2(long number, long first, long second)
{
    register long x0 __asm__("x0") = first;
    register long x1 __asm__("x1") = second;
    register long x8 __asm__("x8") = number;
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x1), "r"(x8) : "memory");
    return x0;
}

static long fixture_linux_syscall3(
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

static long fixture_linux_syscall6(
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

static void fixture_trap(void)
{
    __builtin_trap();
}

static void *fixture_allocate(size_t requested_size)
{
    size_t aligned_size;
    size_t writable_size;
    size_t mapping_size;
    long raw;
    unsigned char *mapping;
    unsigned char *trailing_guard;
    unsigned char *bytes;
    fixture_allocation_header *header;
    size_t index;

    if (requested_size > (size_t) -1 - 15u) {
        return NULL;
    }
    aligned_size = (requested_size + 15u) & ~((size_t) 15u);
    if (aligned_size > (size_t) -1 - sizeof(*header) - (FIXTURE_PAGE_SIZE - 1u)) {
        return NULL;
    }
    writable_size = (sizeof(*header) + aligned_size + FIXTURE_PAGE_SIZE - 1u) &
                    ~((size_t) FIXTURE_PAGE_SIZE - 1u);
    if (writable_size > (size_t) -1 - (2u * FIXTURE_PAGE_SIZE)) {
        return NULL;
    }
    mapping_size = writable_size + (2u * FIXTURE_PAGE_SIZE);
    raw = fixture_linux_syscall6(
        FIXTURE_LINUX_SYS_MMAP,
        0,
        (long) mapping_size,
        FIXTURE_LINUX_PROT_READ_WRITE,
        FIXTURE_LINUX_MAP_PRIVATE_ANONYMOUS,
        -1,
        0);
    if (raw < 0 && raw >= -4095) {
        return NULL;
    }
    mapping = (unsigned char *) (uintptr_t) raw;
    if (fixture_linux_syscall3(
            FIXTURE_LINUX_SYS_MPROTECT,
            (long) (uintptr_t) mapping,
            FIXTURE_PAGE_SIZE,
            FIXTURE_LINUX_PROT_NONE) != 0 ||
        fixture_linux_syscall3(
            FIXTURE_LINUX_SYS_MPROTECT,
            (long) (uintptr_t) (mapping + FIXTURE_PAGE_SIZE + writable_size),
            FIXTURE_PAGE_SIZE,
            FIXTURE_LINUX_PROT_NONE) != 0) {
        (void) fixture_linux_syscall2(
            FIXTURE_LINUX_SYS_MUNMAP,
            (long) (uintptr_t) mapping,
            (long) mapping_size);
        return NULL;
    }
    trailing_guard = mapping + FIXTURE_PAGE_SIZE + writable_size;
    bytes = trailing_guard - aligned_size;
    header = (fixture_allocation_header *) (bytes - sizeof(*header));
    header->magic = FIXTURE_HEADER_MAGIC;
    header->mapping_base = (uintptr_t) mapping;
    header->mapping_size = mapping_size;
    header->requested_size = requested_size;
    header->aligned_size = aligned_size;
    for (index = requested_size; index < aligned_size; index += 1) {
        bytes[index] = FIXTURE_REDZONE_BYTE;
    }
    return bytes;
}

static void fixture_release(void *pointer)
{
    unsigned char *bytes;
    fixture_allocation_header *header;
    size_t index;

    if (pointer == NULL) {
        return;
    }
    bytes = (unsigned char *) pointer;
    header = (fixture_allocation_header *) (bytes - sizeof(*header));
    if (header->magic != FIXTURE_HEADER_MAGIC ||
        header->aligned_size < header->requested_size) {
        fixture_trap();
    }
    for (index = header->requested_size; index < header->aligned_size; index += 1) {
        if (bytes[index] != FIXTURE_REDZONE_BYTE) {
            fixture_trap();
        }
    }
    header->magic = 0;
    (void) fixture_linux_syscall2(
        FIXTURE_LINUX_SYS_MUNMAP,
        (long) header->mapping_base,
        (long) header->mapping_size);
}

#else
#error "native-binding diagnostics support only macOS/AArch64 and Linux/AArch64"
#endif

typedef struct fixture_handle {
    int64_t value;
} fixture_handle;

static int64_t fixture_drops = 0;

void *fixture_open(int64_t value)
{
    fixture_handle *resource = (fixture_handle *) fixture_allocate(sizeof(*resource));
    if (resource != NULL) {
        resource->value = value;
    }
    return resource;
}

int64_t fixture_get(void *raw)
{
    fixture_handle *resource = (fixture_handle *) raw;
    return resource == NULL ? -1 : resource->value;
}

void fixture_close(void *raw)
{
    fixture_drops += 1;
    fixture_release(raw);
}

int64_t fixture_drop_count(void)
{
    return fixture_drops;
}

int64_t fixture_sum(const uint8_t *data, uint64_t length)
{
    int64_t total = 0;
    uint64_t index;
    for (index = 0; index < length; index += 1) {
        total += data[index];
    }
    return total;
}

int64_t fixture_fill(uint8_t *data, uint64_t length, int64_t value)
{
    uint64_t index;
    for (index = 0; index < length; index += 1) {
        data[index] = (uint8_t) value;
    }
    return (int64_t) length;
}
