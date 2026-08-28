/*
 * Weft's Mbed TLS 3.6.7 profile.
 *
 * The official release configuration is the compatibility baseline. We remove
 * every ambient platform authority used by the TLS slice: sockets, files,
 * clocks, entropy and timers. The adapter supplies bounded memory BIOs,
 * per-session random material and an explicit certificate-verification time.
 */
#ifndef WEFT_MBEDTLS_CONFIG_H
#define WEFT_MBEDTLS_CONFIG_H

#include <stddef.h>

void *weft_tls_calloc(size_t count, size_t size);
void weft_tls_free(void *pointer);
int weft_tls_snprintf(char *buffer, size_t length, const char *format, ...);
int weft_tls_printf(const char *format, ...);

#include "mbedtls/mbedtls_config.h"

#undef MBEDTLS_HAVE_TIME
#undef MBEDTLS_HAVE_TIME_DATE
#undef MBEDTLS_FS_IO
#undef MBEDTLS_NET_C
#undef MBEDTLS_AESCE_C
#undef MBEDTLS_DEBUG_C
#undef MBEDTLS_ENTROPY_C
#undef MBEDTLS_LMS_C
#undef MBEDTLS_PSA_CRYPTO_C
#undef MBEDTLS_PSA_CRYPTO_STORAGE_C
#undef MBEDTLS_PSA_ITS_FILE_C
#undef MBEDTLS_TIMING_C
#undef MBEDTLS_SELF_TEST

#undef MBEDTLS_SSL_PROTO_DTLS
#undef MBEDTLS_SSL_DTLS_ANTI_REPLAY
#undef MBEDTLS_SSL_DTLS_HELLO_VERIFY
#undef MBEDTLS_SSL_DTLS_CLIENT_PORT_REUSE
#undef MBEDTLS_SSL_DTLS_CONNECTION_ID

#undef MBEDTLS_SSL_PROTO_TLS1_3
#undef MBEDTLS_SSL_TLS1_3_COMPATIBILITY_MODE
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_ENABLED
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_ENABLED
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_EPHEMERAL_ENABLED

#undef MBEDTLS_SSL_RENEGOTIATION
#undef MBEDTLS_SSL_SESSION_TICKETS

#define MBEDTLS_NO_UDBL_DIVISION
#define MBEDTLS_TEST_SW_INET_PTON
#define MBEDTLS_PLATFORM_MEMORY
#define MBEDTLS_PLATFORM_NO_STD_FUNCTIONS
#define MBEDTLS_PLATFORM_CALLOC_MACRO weft_tls_calloc
#define MBEDTLS_PLATFORM_FREE_MACRO weft_tls_free
#define MBEDTLS_PLATFORM_PRINTF_MACRO weft_tls_printf
#define MBEDTLS_PLATFORM_SNPRINTF_MACRO weft_tls_snprintf

#endif
