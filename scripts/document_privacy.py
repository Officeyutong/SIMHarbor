"""Checks for private data in authored documentation; never prints matched values."""

import re

RULES = {
    "private device IPv4 address": re.compile(
        r"(?<![\d.])(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?![\d.])"
    ),
    "literal subscriber/card identifier": re.compile(r"(?<![\w])\d{15,34}(?![\w])"),
    "actual profile/operator attribution": re.compile(
        r"(?i)\b(?:CMLink(?![-_])|Vodafone(?: ES)?|3 Hong Kong)\b"
    ),
    "private installation path": re.compile(
        r"(?i)\.jbroot-[0-9a-f]{8,}|/Containers/(?:Data|Bundle)/Application/[0-9a-f-]{36}"
    ),
    "literal login credential": re.compile(
        r"(?i)(?:password|passwd|密码)[\"']?\s*[:=]\s*[`\"']?(?!\[|<|\$|your|example|redacted)[A-Za-z0-9+/=_-]{6,}"
    ),
    "hardware address": re.compile(r"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"),
}
ACTIVATION = re.compile(r"LPA:1\$([^\s$`\"<>]+)\$([^\s`\"<>]+)")


def issues(text):
    found = [name for name, pattern in RULES.items() if pattern.search(text)]
    for match in ACTIVATION.finditer(text):
        if match[1] not in {"server", "example.invalid"}:
            found.append("non-placeholder activation code")
            break
    return found
