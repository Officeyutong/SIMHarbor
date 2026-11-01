#include "SignalCodec.h"
#include <euicc/euicc.private.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct fake_card {
    unsigned opens, closes, calls, store, gets;
    int mode;
    size_t data_bytes;
};
static int connect_mock(struct euicc_ctx *ctx) {
    (void)ctx;
    return 0;
}
static void disconnect_mock(struct euicc_ctx *ctx) { (void)ctx; }
static int open_mock(struct euicc_ctx *ctx, const uint8_t *aid, uint8_t length) {
    struct fake_card *card = ctx->userdata;
    assert(length == 16 && aid[0] == 0xa0);
    card->opens++;
    return 2;
}
static void close_mock(struct euicc_ctx *ctx, uint8_t channel) {
    struct fake_card *card = ctx->userdata;
    assert(channel == 2);
    card->closes++;
}
static int transmit_mock(struct euicc_ctx *ctx, uint8_t **response, uint32_t *length,
                         const uint8_t *request, uint32_t n) {
    struct fake_card *card = ctx->userdata;
    card->calls++;
    assert(n >= 5 && n <= 260);
    assert(request[0] == 0x82);
    uint8_t reply[5] = {0x90, 0};
    size_t size = 2;
    if (request[1] == 0xe2) {
        assert(n == (uint32_t)request[4] + 5);
        assert(request[3] == card->store);
        card->store++;
        card->data_bytes += request[4];
        assert(request[2] == 0x11 || request[2] == 0x91);
        if (card->mode == 1 && request[2] == 0x91) {
            reply[0] = 0xaa;
            reply[1] = 0x61;
            reply[2] = 2;
            size = 3;
        }
    } else {
        assert(request[1] == 0xc0 && card->mode == 1 && request[4] == 2);
        card->gets++;
        reply[0] = 0xbb;
        reply[1] = 0xcc;
        reply[2] = 0x90;
        reply[3] = 0;
        size = 4;
    }
    if (card->mode == 2) {
        reply[0] = 0x6a;
        reply[1] = 0x88;
        size = 2;
    }
    *response = malloc(size);
    memcpy(*response, reply, size);
    *length = (uint32_t)size;
    return 0;
}
static const struct euicc_apdu_interface fake_interface = {connect_mock, disconnect_mock, open_mock,
                                                           close_mock,   transmit_mock,   NULL};
static void library_case(size_t n, unsigned mss, int mode) {
    uint8_t *request = calloc(n, 1), *response = NULL;
    unsigned length = 0;
    struct fake_card card = {0};
    card.mode = mode;
    struct euicc_ctx ctx = {0};
    ctx.userdata = &card;
    ctx.es10x_mss = (uint8_t)mss;
    ctx.apdu.interface = &fake_interface;
    assert(euicc_init(&ctx) == 0);
    int rc = es10x_command(&ctx, &response, &length, request, (unsigned)n);
    euicc_fini(&ctx);
    if (mode == 2)
        assert(rc < 0);
    else {
        assert(rc == 0);
        assert(card.store == (n + mss - 1) / mss);
        assert(card.data_bytes == n);
    }
    assert(card.opens == 1 && card.closes == 1);
    if (mode == 1) {
        assert(card.gets == 1 && length == 3);
        assert(!memcmp(response, "\xaa\xbb\xcc", 3));
    } else
        assert(length == 0);
    free(response);
    free(request);
}
static void codecs(void) {
    uint8_t bytes[300];
    size_t n;
    assert(!SHDecodeHex("80 e2 91 00 06 BF 3E 03 5C 01 5A", bytes, sizeof bytes, &n) && n == 11);
    assert(!SHValidateAPDU(bytes, n));
    assert(SHDecodeHex("0x80", bytes, sizeof bytes, &n));
    assert(SHDecodeHex("8", bytes, sizeof bytes, &n));
    assert(SHDecodeHex("GG", bytes, sizeof bytes, &n));
    assert(SHDecodeHex(" ", bytes, sizeof bytes, &n));
    assert(SHDecodeHex("0011", bytes, 1, &n));
    assert(!SHDecodeHex("00\tC0\r\n00 00 00", bytes, sizeof bytes, &n));
    assert(!SHValidateAPDU(bytes, n));
    assert(SHValidateAPDU(bytes, 3));
    uint8_t extended[] = {0x80, 0xe2, 0, 0, 0, 1, 0};
    assert(SHValidateAPDU(extended, sizeof extended));
    uint8_t mismatch[] = {0x80, 0xe2, 0, 0, 4, 1};
    assert(SHValidateAPDU(mismatch, sizeof mismatch));
    memset(bytes, 0, sizeof bytes);
    bytes[0] = 0x80;
    bytes[1] = 0xe2;
    bytes[4] = 255;
    assert(!SHValidateAPDU(bytes, 260));
    assert(!SHValidateAPDU(bytes, 261));
    assert(SHValidateAPDU(bytes, 262));
    assert(SHValidateAPDU((uint8_t[]){0x81, 0xc0, 0, 0, 0}, 5));
    assert(SHBindChannel(0x80, 2) == 0x82);
    assert(SHBindChannel(0, 4) == 0x40);
    assert(SHBindChannel(0x80, 19) == 0xcf);
    assert(SHBindChannel(0x10, 4) == 0x50);
    assert(SHBindChannel(0x0c, 4) == 0x60);
    assert(SHBindChannel(0, 20) < 0);
    assert(SHBindChannel(0x81, 1) < 0);
    assert(!SHRawStatusIssue(0x9000));
    assert(strstr(SHRawStatusIssue(0x6115), "GET RESPONSE"));
    assert(strstr(SHRawStatusIssue(0x6100), "ES10 DER"));
    assert(strstr(SHRawStatusIssue(0x6c15), "Le"));
    assert(strstr(SHRawStatusIssue(0x6c00), "does not retry"));
    assert(strstr(SHRawStatusIssue(0x6a82), "non-9000"));
    uint8_t eid[] = {0xbf, 0x3e, 3, 0x5c, 1, 0x5a};
    assert(!SHValidateDER(eid, sizeof eid, 120 * 256));
    assert(SHValidateDER(eid, sizeof eid, 5));
    assert(SHValidateDER(eid, sizeof eid - 1, 100));
    assert(SHValidateDER((uint8_t[]){0x30, 0x80, 0, 0}, 4, 100));
    assert(SHValidateDER((uint8_t[]){0x30, 0x81, 1, 0}, 4, 100));
    assert(SHValidateDER((uint8_t[]){0xbf, 0x80, 0}, 3, 100));
    assert(SHValidateDER((uint8_t[]){0x30, 0, 0x30, 0}, 4, 100));
    memset(bytes, 0, sizeof bytes);
    bytes[0] = 0x30;
    bytes[1] = 0x81;
    bytes[2] = 128;
    assert(!SHValidateDER(bytes, 131, 200));
    // Exercise untrusted lengths/tags under ASan/UBSan, rather than replaying only valid inputs.
    srand(1);
    for (unsigned i = 0; i < 50000; i++) {
        size_t len = (unsigned)rand() % sizeof bytes;
        for (size_t j = 0; j < len; j++)
            bytes[j] = (uint8_t)rand();
        (void)SHValidateAPDU(bytes, len);
        (void)SHValidateDER(bytes, len, 256);
    }
}
int main(void) {
    codecs();
    library_case(6, 120, 0);
    library_case(120, 120, 0);
    library_case(121, 120, 0);
    library_case(309, 120, 1);
    library_case(6, 120, 2);
    library_case(6 * 256, 6, 0);
    library_case(120 * 256, 120, 0);
    library_case(255 * 256, 255, 0);
    puts(
        "PASS: hex/APDU/DER validation, channel mapping, malformed-input sanitizer checks, real libeuicc 256-block and 61xx mock-card flows");
    return 0;
}
