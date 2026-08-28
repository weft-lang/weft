/*
 * Callback-free Weft ABI over Mbed TLS 3.6.7.
 *
 * Mbed TLS sees fixed C callbacks over bounded adapter-owned buffers. Weft
 * supplies and drains bytes explicitly, so no socket, clock, entropy or
 * scheduler authority crosses the native ABI.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "mbedtls/hmac_drbg.h"
#include "mbedtls/md.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509.h"
#include "mbedtls/x509_crt.h"

#define WEFT_TLS_INPUT_CAPACITY (256u * 1024u)
#define WEFT_TLS_OUTPUT_CAPACITY (256u * 1024u)
#define WEFT_TLS_WRITE_CAPACITY (16u * 1024u)
#define WEFT_TLS_MAX_CERTIFICATE_BYTES (8u * 1024u * 1024u)
#define WEFT_TLS_MAX_KEY_BYTES (1024u * 1024u)
#define WEFT_TLS_MAX_IDENTITY_BYTES 253u
#define WEFT_TLS_MIN_SEED_BYTES 32u
#define WEFT_TLS_MAX_SEED_BYTES 256u

#define WEFT_TLS_STEP_DONE 0
#define WEFT_TLS_STEP_NEED_INPUT 1
#define WEFT_TLS_STEP_NEED_OUTPUT 2
#define WEFT_TLS_STEP_PEER_CLOSED 3
#define WEFT_TLS_STEP_WROTE 4
#define WEFT_TLS_STEP_READ 5

#define WEFT_TLS_ERROR_ALLOCATION -1001
#define WEFT_TLS_ERROR_TRUST -1002
#define WEFT_TLS_ERROR_IDENTITY -1003
#define WEFT_TLS_ERROR_CERTIFICATE -1004
#define WEFT_TLS_ERROR_PRIVATE_KEY -1005
#define WEFT_TLS_ERROR_CONFIGURATION -1006
#define WEFT_TLS_ERROR_VERIFICATION -1007
#define WEFT_TLS_ERROR_PROTOCOL -1008
#define WEFT_TLS_ERROR_STATE -1009
#define WEFT_TLS_ERROR_LIMIT -1010
#define WEFT_TLS_ERROR_EXPIRED -1011
#define WEFT_TLS_ERROR_NOT_YET_VALID -1012
#define WEFT_TLS_ERROR_TRUNCATED -1013
#define WEFT_TLS_ERROR_RANDOM -1014

typedef struct weft_tls_utc_time {
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
} weft_tls_utc_time;

typedef struct weft_tls_session {
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config config;
    mbedtls_x509_crt trust_roots;
    mbedtls_x509_crt own_certificate;
    mbedtls_pk_context own_key;
    mbedtls_hmac_drbg_context random;
    int64_t verification_time;
    int64_t last_error;
    int64_t last_detail;
    int64_t last_count;
    size_t input_start;
    size_t input_length;
    size_t output_start;
    size_t output_length;
    size_t write_length;
    int input_eof;
    int handshake_done;
    int write_active;
    int close_done;
    unsigned char input[WEFT_TLS_INPUT_CAPACITY];
    unsigned char output[WEFT_TLS_OUTPUT_CAPACITY];
    unsigned char write_buffer[WEFT_TLS_WRITE_CAPACITY];
} weft_tls_session;

static const int weft_tls_ciphersuites[] = {
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,
    MBEDTLS_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    0
};

static int weft_tls_bytes_have_zero(const unsigned char *bytes, size_t length)
{
    size_t index;
    for (index = 0; index < length; index += 1) {
        if (bytes[index] == 0) {
            return 1;
        }
    }
    return 0;
}

static unsigned char *weft_tls_copy_terminated(
    const unsigned char *bytes,
    size_t length)
{
    unsigned char *copy;
    if (length == (size_t) -1) {
        return NULL;
    }
    copy = (unsigned char *) weft_tls_calloc(length + 1, 1);
    if (copy == NULL) {
        return NULL;
    }
    if (length > 0) {
        memcpy(copy, bytes, length);
    }
    copy[length] = 0;
    return copy;
}

static void weft_tls_compact(
    unsigned char *bytes,
    size_t *start,
    size_t *length)
{
    if (*length == 0) {
        *start = 0;
    } else if (*start > 0) {
        memmove(bytes, bytes + *start, *length);
        *start = 0;
    }
}

int weft_tls_send(void *context, const unsigned char *bytes, size_t length)
{
    weft_tls_session *session = (weft_tls_session *) context;
    size_t available;
    size_t copied;
    weft_tls_compact(
        session->output,
        &session->output_start,
        &session->output_length);
    available = WEFT_TLS_OUTPUT_CAPACITY - session->output_length;
    if (available == 0) {
        return MBEDTLS_ERR_SSL_WANT_WRITE;
    }
    copied = length < available ? length : available;
    memcpy(session->output + session->output_length, bytes, copied);
    session->output_length += copied;
    return (int) copied;
}

int weft_tls_receive(void *context, unsigned char *bytes, size_t length)
{
    weft_tls_session *session = (weft_tls_session *) context;
    size_t copied;
    if (session->input_length == 0) {
        return session->input_eof ? 0 : MBEDTLS_ERR_SSL_WANT_READ;
    }
    copied = length < session->input_length ? length : session->input_length;
    memcpy(bytes, session->input + session->input_start, copied);
    session->input_start += copied;
    session->input_length -= copied;
    if (session->input_length == 0) {
        session->input_start = 0;
    }
    return (int) copied;
}

int weft_tls_random(
    void *context,
    unsigned char *output,
    size_t length)
{
    return mbedtls_hmac_drbg_random(context, output, length);
}

static weft_tls_utc_time weft_tls_time_from_unix(int64_t seconds)
{
    int64_t days = seconds / 86400;
    int64_t day_seconds = seconds % 86400;
    int64_t shifted;
    int64_t era;
    unsigned day_of_era;
    unsigned year_of_era;
    int year;
    unsigned day_of_year;
    unsigned month_position;
    unsigned day;
    int month;
    weft_tls_utc_time result;

    if (day_seconds < 0) {
        day_seconds += 86400;
        days -= 1;
    }
    shifted = days + 719468;
    era = (shifted >= 0 ? shifted : shifted - 146096) / 146097;
    day_of_era = (unsigned) (shifted - era * 146097);
    year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 -
                   day_of_era / 146096) / 365;
    year = (int) year_of_era + (int) era * 400;
    day_of_year = day_of_era -
                  (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    month_position = (5 * day_of_year + 2) / 153;
    day = day_of_year - (153 * month_position + 2) / 5 + 1;
    month = (int) month_position + (month_position < 10 ? 3 : -9);
    year += month <= 2;

    result.year = year;
    result.month = month;
    result.day = (int) day;
    result.hour = (int) (day_seconds / 3600);
    result.minute = (int) ((day_seconds % 3600) / 60);
    result.second = (int) (day_seconds % 60);
    return result;
}

static int weft_tls_compare_x509_time(
    const mbedtls_x509_time *certificate,
    const weft_tls_utc_time *current)
{
    if (certificate->year != current->year) {
        return certificate->year < current->year ? -1 : 1;
    }
    if (certificate->mon != current->month) {
        return certificate->mon < current->month ? -1 : 1;
    }
    if (certificate->day != current->day) {
        return certificate->day < current->day ? -1 : 1;
    }
    if (certificate->hour != current->hour) {
        return certificate->hour < current->hour ? -1 : 1;
    }
    if (certificate->min != current->minute) {
        return certificate->min < current->minute ? -1 : 1;
    }
    if (certificate->sec != current->second) {
        return certificate->sec < current->second ? -1 : 1;
    }
    return 0;
}

int weft_tls_verify_time(
    void *context,
    mbedtls_x509_crt *certificate,
    int depth,
    uint32_t *flags)
{
    weft_tls_session *session = (weft_tls_session *) context;
    weft_tls_utc_time current =
        weft_tls_time_from_unix(session->verification_time);
    (void) depth;
    if (weft_tls_compare_x509_time(&certificate->valid_to, &current) < 0) {
        *flags |= MBEDTLS_X509_BADCERT_EXPIRED;
    }
    if (weft_tls_compare_x509_time(&certificate->valid_from, &current) > 0) {
        *flags |= MBEDTLS_X509_BADCERT_FUTURE;
    }
    return 0;
}

static void weft_tls_session_init(weft_tls_session *session)
{
    mbedtls_ssl_init(&session->ssl);
    mbedtls_ssl_config_init(&session->config);
    mbedtls_x509_crt_init(&session->trust_roots);
    mbedtls_x509_crt_init(&session->own_certificate);
    mbedtls_pk_init(&session->own_key);
    mbedtls_hmac_drbg_init(&session->random);
}

static void weft_tls_session_release(weft_tls_session *session)
{
    mbedtls_ssl_free(&session->ssl);
    mbedtls_ssl_config_free(&session->config);
    mbedtls_x509_crt_free(&session->trust_roots);
    mbedtls_x509_crt_free(&session->own_certificate);
    mbedtls_pk_free(&session->own_key);
    mbedtls_hmac_drbg_free(&session->random);
}

static int weft_tls_seed(
    weft_tls_session *session,
    const unsigned char *seed,
    size_t seed_length)
{
    const mbedtls_md_info_t *sha256;
    if (seed_length < WEFT_TLS_MIN_SEED_BYTES ||
        seed_length > WEFT_TLS_MAX_SEED_BYTES) {
        return WEFT_TLS_ERROR_RANDOM;
    }
    sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (sha256 == NULL ||
        mbedtls_hmac_drbg_seed_buf(
            &session->random, sha256, seed, seed_length) != 0) {
        return WEFT_TLS_ERROR_RANDOM;
    }
    return 0;
}

static int weft_tls_configure(
    weft_tls_session *session,
    int endpoint,
    const unsigned char *seed,
    size_t seed_length)
{
    int result = weft_tls_seed(session, seed, seed_length);
    if (result != 0) {
        return result;
    }
    result = mbedtls_ssl_config_defaults(
        &session->config,
        endpoint,
        MBEDTLS_SSL_TRANSPORT_STREAM,
        MBEDTLS_SSL_PRESET_DEFAULT);
    if (result != 0) {
        session->last_detail = result;
        return WEFT_TLS_ERROR_CONFIGURATION;
    }
    mbedtls_ssl_conf_rng(
        &session->config,
        weft_tls_random,
        &session->random);
    mbedtls_ssl_conf_ciphersuites(&session->config, weft_tls_ciphersuites);
    mbedtls_ssl_conf_min_tls_version(
        &session->config,
        MBEDTLS_SSL_VERSION_TLS1_2);
    mbedtls_ssl_conf_max_tls_version(
        &session->config,
        MBEDTLS_SSL_VERSION_TLS1_2);
    return 0;
}

static int weft_tls_setup(weft_tls_session *session)
{
    int result = mbedtls_ssl_setup(&session->ssl, &session->config);
    if (result != 0) {
        session->last_detail = result;
        return result == MBEDTLS_ERR_SSL_ALLOC_FAILED ?
            WEFT_TLS_ERROR_ALLOCATION : WEFT_TLS_ERROR_CONFIGURATION;
    }
    mbedtls_ssl_set_bio(
        &session->ssl,
        session,
        weft_tls_send,
        weft_tls_receive,
        NULL);
    return 0;
}

static int weft_tls_parse_certificate_chain(
    mbedtls_x509_crt *chain,
    const unsigned char *bytes,
    size_t length)
{
    unsigned char *terminated;
    int result;
    if (length == 0 || length > WEFT_TLS_MAX_CERTIFICATE_BYTES) {
        return WEFT_TLS_ERROR_LIMIT;
    }
    terminated = weft_tls_copy_terminated(bytes, length);
    if (terminated == NULL) {
        return WEFT_TLS_ERROR_ALLOCATION;
    }
    result = mbedtls_x509_crt_parse(chain, terminated, length + 1);
    weft_tls_free(terminated);
    return result == 0 ? 0 : WEFT_TLS_ERROR_CERTIFICATE;
}

static int weft_tls_parse_private_key(
    weft_tls_session *session,
    const unsigned char *bytes,
    size_t length)
{
    unsigned char *terminated;
    int result;
    if (length == 0 || length > WEFT_TLS_MAX_KEY_BYTES) {
        return WEFT_TLS_ERROR_LIMIT;
    }
    terminated = weft_tls_copy_terminated(bytes, length);
    if (terminated == NULL) {
        return WEFT_TLS_ERROR_ALLOCATION;
    }
    result = mbedtls_pk_parse_key(
        &session->own_key,
        terminated,
        length + 1,
        NULL,
        0,
        weft_tls_random,
        &session->random);
    weft_tls_free(terminated);
    return result == 0 ? 0 : WEFT_TLS_ERROR_PRIVATE_KEY;
}

static void *weft_tls_fail_new(weft_tls_session *session, int error)
{
    session->last_error = error;
    return session;
}

void *weft_tls_client_new(
    const unsigned char *trust_roots,
    size_t trust_roots_length,
    const unsigned char *identity,
    size_t identity_length,
    const unsigned char *seed,
    size_t seed_length,
    int64_t verification_time)
{
    weft_tls_session *session;
    unsigned char *terminated_identity;
    int result;
    session = (weft_tls_session *) weft_tls_calloc(1, sizeof(*session));
    if (session == NULL) {
        return NULL;
    }
    weft_tls_session_init(session);
    session->verification_time = verification_time;
    result = weft_tls_configure(
        session, MBEDTLS_SSL_IS_CLIENT, seed, seed_length);
    if (result != 0) {
        return weft_tls_fail_new(session, result);
    }
    result = weft_tls_parse_certificate_chain(
        &session->trust_roots, trust_roots, trust_roots_length);
    if (result != 0) {
        return weft_tls_fail_new(
            session,
            result == WEFT_TLS_ERROR_CERTIFICATE ? WEFT_TLS_ERROR_TRUST : result);
    }
    if (identity_length == 0 ||
        identity_length > WEFT_TLS_MAX_IDENTITY_BYTES ||
        weft_tls_bytes_have_zero(identity, identity_length)) {
        return weft_tls_fail_new(session, WEFT_TLS_ERROR_IDENTITY);
    }
    terminated_identity = weft_tls_copy_terminated(identity, identity_length);
    if (terminated_identity == NULL) {
        return weft_tls_fail_new(session, WEFT_TLS_ERROR_ALLOCATION);
    }
    mbedtls_ssl_conf_authmode(&session->config, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&session->config, &session->trust_roots, NULL);
    result = weft_tls_setup(session);
    if (result == 0) {
        result = mbedtls_ssl_set_hostname(
            &session->ssl, (const char *) terminated_identity);
    }
    weft_tls_free(terminated_identity);
    if (result != 0) {
        session->last_detail = result;
        return weft_tls_fail_new(session, WEFT_TLS_ERROR_IDENTITY);
    }
    mbedtls_ssl_set_verify(&session->ssl, weft_tls_verify_time, session);
    return session;
}

void *weft_tls_server_new(
    const unsigned char *certificate,
    size_t certificate_length,
    const unsigned char *private_key,
    size_t private_key_length,
    const unsigned char *seed,
    size_t seed_length)
{
    weft_tls_session *session;
    int result;
    session = (weft_tls_session *) weft_tls_calloc(1, sizeof(*session));
    if (session == NULL) {
        return NULL;
    }
    weft_tls_session_init(session);
    result = weft_tls_configure(
        session, MBEDTLS_SSL_IS_SERVER, seed, seed_length);
    if (result != 0) {
        return weft_tls_fail_new(session, result);
    }
    result = weft_tls_parse_certificate_chain(
        &session->own_certificate, certificate, certificate_length);
    if (result != 0) {
        return weft_tls_fail_new(session, result);
    }
    result = weft_tls_parse_private_key(session, private_key, private_key_length);
    if (result != 0) {
        return weft_tls_fail_new(session, result);
    }
    mbedtls_ssl_conf_authmode(&session->config, MBEDTLS_SSL_VERIFY_NONE);
    result = mbedtls_ssl_conf_own_cert(
        &session->config,
        &session->own_certificate,
        &session->own_key);
    if (result == 0) {
        result = weft_tls_setup(session);
    }
    if (result != 0) {
        session->last_detail = result;
        return weft_tls_fail_new(session, WEFT_TLS_ERROR_CONFIGURATION);
    }
    return session;
}

void weft_tls_session_free(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    if (session == NULL) {
        return;
    }
    weft_tls_session_release(session);
    weft_tls_free(session);
}

int64_t weft_tls_last_error(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    return session == NULL ? WEFT_TLS_ERROR_ALLOCATION : session->last_error;
}

int64_t weft_tls_last_detail(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    return session == NULL ? 0 : session->last_detail;
}

int64_t weft_tls_last_count(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    return session == NULL ? 0 : session->last_count;
}

int64_t weft_tls_pending_output(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    return session == NULL ? 0 : (int64_t) session->output_length;
}

static int weft_tls_set_failure(weft_tls_session *session, int result)
{
    uint32_t flags = mbedtls_ssl_get_verify_result(&session->ssl);
    session->last_detail = result;
    if ((flags & MBEDTLS_X509_BADCERT_EXPIRED) != 0) {
        session->last_error = WEFT_TLS_ERROR_EXPIRED;
    } else if ((flags & MBEDTLS_X509_BADCERT_FUTURE) != 0) {
        session->last_error = WEFT_TLS_ERROR_NOT_YET_VALID;
    } else if ((flags & MBEDTLS_X509_BADCERT_CN_MISMATCH) != 0) {
        session->last_error = WEFT_TLS_ERROR_IDENTITY;
    } else if ((flags & MBEDTLS_X509_BADCERT_NOT_TRUSTED) != 0) {
        session->last_error = WEFT_TLS_ERROR_TRUST;
    } else if (flags != 0) {
        session->last_error = WEFT_TLS_ERROR_VERIFICATION;
    } else {
        session->last_error = WEFT_TLS_ERROR_PROTOCOL;
    }
    return (int) session->last_error;
}

static int weft_tls_step_result(weft_tls_session *session, int result)
{
    if (result == MBEDTLS_ERR_SSL_CONN_EOF) {
        session->last_error = WEFT_TLS_ERROR_TRUNCATED;
        session->last_detail = result;
        return WEFT_TLS_ERROR_TRUNCATED;
    }
    if (result == MBEDTLS_ERR_SSL_WANT_WRITE) {
        return WEFT_TLS_STEP_NEED_OUTPUT;
    }
    if (result == MBEDTLS_ERR_SSL_WANT_READ) {
        if (session->output_length > 0) {
            return WEFT_TLS_STEP_NEED_OUTPUT;
        }
        if (session->input_eof && session->input_length == 0) {
            session->last_error = WEFT_TLS_ERROR_TRUNCATED;
            session->last_detail = MBEDTLS_ERR_SSL_CONN_EOF;
            return WEFT_TLS_ERROR_TRUNCATED;
        }
        return WEFT_TLS_STEP_NEED_INPUT;
    }
    if (result == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) {
        return WEFT_TLS_STEP_PEER_CLOSED;
    }
    if (result == 0) {
        return session->output_length > 0 ?
            WEFT_TLS_STEP_NEED_OUTPUT : WEFT_TLS_STEP_DONE;
    }
    return weft_tls_set_failure(session, result);
}

int64_t weft_tls_feed(
    void *raw_session,
    const unsigned char *bytes,
    size_t length)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    size_t available;
    size_t copied;
    if (session == NULL || session->input_eof) {
        return WEFT_TLS_ERROR_STATE;
    }
    weft_tls_compact(
        session->input,
        &session->input_start,
        &session->input_length);
    available = WEFT_TLS_INPUT_CAPACITY - session->input_length;
    copied = length < available ? length : available;
    if (copied > 0) {
        memcpy(session->input + session->input_length, bytes, copied);
        session->input_length += copied;
    }
    return (int64_t) copied;
}

int64_t weft_tls_feed_eof(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    if (session == NULL) {
        return WEFT_TLS_ERROR_STATE;
    }
    session->input_eof = 1;
    return 0;
}

int64_t weft_tls_drain(
    void *raw_session,
    unsigned char *bytes,
    size_t capacity)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    size_t copied;
    if (session == NULL) {
        return WEFT_TLS_ERROR_STATE;
    }
    copied = capacity < session->output_length ? capacity : session->output_length;
    if (copied > 0) {
        memcpy(bytes, session->output + session->output_start, copied);
        session->output_start += copied;
        session->output_length -= copied;
        if (session->output_length == 0) {
            session->output_start = 0;
        }
    }
    return (int64_t) copied;
}

int64_t weft_tls_handshake(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    int result;
    if (session == NULL || session->last_error != 0) {
        return session == NULL ? WEFT_TLS_ERROR_STATE : session->last_error;
    }
    if (session->handshake_done) {
        return session->output_length > 0 ?
            WEFT_TLS_STEP_NEED_OUTPUT : WEFT_TLS_STEP_DONE;
    }
    result = mbedtls_ssl_handshake(&session->ssl);
    if (result == 0) {
        session->handshake_done = 1;
    }
    return weft_tls_step_result(session, result);
}

int64_t weft_tls_read(
    void *raw_session,
    unsigned char *bytes,
    size_t capacity)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    int result;
    if (session == NULL || !session->handshake_done || capacity == 0) {
        return WEFT_TLS_ERROR_STATE;
    }
    session->last_count = 0;
    result = mbedtls_ssl_read(&session->ssl, bytes, capacity);
    if (result > 0) {
        session->last_count = result;
        return WEFT_TLS_STEP_READ;
    }
    if (result == 0) {
        session->last_error = WEFT_TLS_ERROR_TRUNCATED;
        session->last_detail = 0;
        return WEFT_TLS_ERROR_TRUNCATED;
    }
    return weft_tls_step_result(session, result);
}

static int64_t weft_tls_write_continue(weft_tls_session *session)
{
    int result = mbedtls_ssl_write(
        &session->ssl,
        session->write_buffer,
        session->write_length);
    if (result >= 0) {
        session->last_count = result;
        session->write_active = 0;
        session->write_length = 0;
        return WEFT_TLS_STEP_WROTE;
    }
    return weft_tls_step_result(session, result);
}

int64_t weft_tls_write_start(
    void *raw_session,
    const unsigned char *bytes,
    size_t length)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    if (session == NULL ||
        !session->handshake_done ||
        session->write_active ||
        length == 0 ||
        length > WEFT_TLS_WRITE_CAPACITY) {
        return length > WEFT_TLS_WRITE_CAPACITY ?
            WEFT_TLS_ERROR_LIMIT : WEFT_TLS_ERROR_STATE;
    }
    memcpy(session->write_buffer, bytes, length);
    session->write_length = length;
    session->write_active = 1;
    session->last_count = 0;
    return weft_tls_write_continue(session);
}

int64_t weft_tls_write_step(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    if (session == NULL || !session->write_active) {
        return WEFT_TLS_ERROR_STATE;
    }
    return weft_tls_write_continue(session);
}

int64_t weft_tls_close_step(void *raw_session)
{
    weft_tls_session *session = (weft_tls_session *) raw_session;
    int result;
    if (session == NULL || !session->handshake_done) {
        return WEFT_TLS_ERROR_STATE;
    }
    if (session->close_done) {
        return session->output_length > 0 ?
            WEFT_TLS_STEP_NEED_OUTPUT : WEFT_TLS_STEP_DONE;
    }
    result = mbedtls_ssl_close_notify(&session->ssl);
    if (result == 0) {
        session->close_done = 1;
    }
    return weft_tls_step_result(session, result);
}
