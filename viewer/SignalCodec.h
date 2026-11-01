#pragma once
#include <stddef.h>
#include <stdint.h>
// Pure C, shared by the app and Linux offline tests. Returns an English error or NULL.
const char *SHDecodeHex(const char *text, uint8_t *out, size_t capacity, size_t *length);
const char *SHValidateAPDU(const uint8_t *bytes, size_t length);
const char *SHValidateDER(const uint8_t *bytes, size_t length, size_t maximum);
int SHBindChannel(uint8_t cla, int channel);
const char *SHRawStatusIssue(uint16_t status);
