#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?Run through build.sh or set THEOS}"
compile=false
for argument in "$@"; do
    case "$argument" in -c | -S | -E | -M | -MM | -MMD | -MD | -MF) compile=true ;; esac
done
if "$compile"; then
    for argument in "$@"; do
        case "$argument" in *.c) exec "${SIMHARBOR_CC:-clang-22}" "$@" ;; esac
    done
    exec "${SIMHARBOR_CXX:-clang++-22}" "$@"
else
    exec "$THEOS/toolchain/linux/iphone/bin/clang++" "$@"
fi
