#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
export THEOS="${THEOS:-${SIMHARBOR_THEOS:-$HERE/.deps/theos}}"
export PATH="$THEOS/toolchain/linux/iphone/bin:$PATH"
export TARGET_CC="$HERE/ccwrap.sh"
export TARGET_CXX="$HERE/ccwrap.sh"
if [[ ! -f "$THEOS/makefiles/common.mk" ]]; then
    echo 'Missing Theos; run python3 ci/bootstrap.py first.' >&2
    exit 1
fi
python3 scripts/sync_version.py
python3 scripts/build_docs.py
python3 scripts/fetch_gum.py
python3 scripts/generate_pairing_key.py
trap 'python3 "$HERE/scripts/generate_pairing_key.py" --clean' EXIT
make clean package FINALPACKAGE=1 "$@"
echo 'Package output: packages/'
