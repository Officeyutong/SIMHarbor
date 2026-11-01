#include "SignalCodec.h"
static int nibble(unsigned char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
const char *SHDecodeHex(const char *text, uint8_t *out, size_t capacity, size_t *length) {
    *length = 0;
    int high = -1;
    size_t n = 0;
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
            continue;
        int v = nibble(*p);
        if (v < 0)
            return "Use hexadecimal bytes and whitespace only.";
        if (high < 0) {
            high = v;
            continue;
        }
        if (n == capacity)
            return "The signal exceeds the size limit.";
        out[n++] = (uint8_t)((high << 4) | v);
        high = -1;
    }
    if (high >= 0)
        return "Hexadecimal input must contain complete byte pairs.";
    if (!n)
        return "Enter a signal before sending.";
    *length = n;
    return NULL;
}
const char *SHValidateAPDU(const uint8_t *b, size_t n) {
    if (n < 4 || n > 261)
        return "A short APDU must contain 4 to 261 bytes.";
    // The user supplies the basic-channel CLA. The app binds the allocated channel.
    if ((b[0] & 0x43) != 0)
        return "Use a basic-channel CLA, such as 00 or 80. The app sets the channel.";
    if (n <= 5)
        return NULL;
    if (b[4] == 0)
        return "Extended-length APDUs are not supported by this transport.";
    if (n != (size_t)b[4] + 5 && n != (size_t)b[4] + 6)
        return "APDU length does not match Lc and optional Le.";
    return NULL;
}
const char *SHValidateDER(const uint8_t *b, size_t n, size_t maximum) {
    if (n < 2 || n > maximum)
        return "DER input must fit within 256 APDU blocks.";
    size_t p = 1;
    if ((b[0] & 31) == 31) {
        if (p >= n || (b[p] & 127) == 0)
            return "Invalid DER tag.";
        size_t count = 0;
        do {
            if (p >= n || ++count > 4)
                return "Invalid DER tag.";
        } while (b[p++] & 128);
    }
    if (p >= n)
        return "Missing DER length.";
    size_t length = b[p++];
    if (length & 128) {
        size_t count = length & 127;
        length = 0;
        if (!count || count > sizeof(size_t) || count > n - p || b[p] == 0)
            return "Invalid DER length.";
        for (size_t i = 0; i < count; i++) {
            if (length > (SIZE_MAX >> 8))
                return "Invalid DER length.";
            length = (length << 8) | b[p++];
        }
        if (length < 128)
            return "Invalid DER length.";
    }
    return length == n - p ? NULL : "DER must contain exactly one complete TLV.";
}
int SHBindChannel(uint8_t cla, int channel) {
    if (channel < 0 || channel > 19 || (cla & 0x43))
        return -1;
    if (channel < 4)
        return (cla & 0xfc) | channel;
    return (cla & 0x90) | 0x40 | ((cla & 0x0c) ? 0x20 : 0) | (channel - 4);
}
const char *SHRawStatusIssue(uint16_t status) {
    if (status == 0x9000)
        return NULL;
    if ((status & 0xff00) == 0x6100)
        return "More response data is available (61xx). Raw APDU mode stopped before GET RESPONSE. Fill the Get EID example to use ES10 DER and collect the complete response.";
    if ((status & 0xff00) == 0x6c00)
        return "The card requested a different response length (6Cxx). Raw APDU mode does not retry. Check SW2 and the command's Le before sending a corrected command.";
    return "Stopped after a non-9000 status. Check the response before continuing.";
}
