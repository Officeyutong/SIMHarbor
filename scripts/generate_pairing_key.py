#!/usr/bin/env python3
"""Generate one random IPC pairing key for the app and tweak in this build."""

from pathlib import Path
import argparse, os, secrets

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--clean", action="store_true")
args = parser.parse_args()
path = ROOT / "shared/PairingKey.h"
if args.clean:
    path.unlink(missing_ok=True)
else:
    data = (
        '#pragma once\n// Generated per build; never commit this file.\n#define SH_PAIRING_KEY @"'
        + secrets.token_hex(32)
        + '"\n'
    )
    # Restrict permissions at creation, even when a previous interrupted build left a file.
    path.unlink(missing_ok=True)
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(data)
    print("Generated build-local IPC pairing header (value omitted).")
