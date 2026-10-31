#!/usr/bin/env bash
# Ubuntu 24.04 runner/container, LLVM's signed apt repository.
set -euo pipefail
if [[ $(id -u) == 0 ]]; then AS_ROOT=(); else AS_ROOT=(sudo); fi
export DEBIAN_FRONTEND=noninteractive
"${AS_ROOT[@]}" apt-get update -qq
"${AS_ROOT[@]}" apt-get install -y --no-install-recommends ca-certificates curl gnupg git python3 build-essential fakeroot rsync xz-utils zstd libxml2 libtinfo6 file dpkg-dev
key=$(mktemp)
trap 'python3 -c "from pathlib import Path; import sys; Path(sys.argv[1]).unlink(missing_ok=True)" "$key"' EXIT
curl -fsSL --retry 3 https://apt.llvm.org/llvm-snapshot.gpg.key -o "$key"
fingerprint=$(gpg --show-keys --with-colons "$key" | awk -F: '$1 == "fpr" {print $10; exit}')
[[ "$fingerprint" == 6084F3CF814B57C1CF12EFD515CF4D18AF4F7421 ]] || { echo 'Unexpected LLVM apt signing key' >&2; exit 1; }
"${AS_ROOT[@]}" gpg --dearmor --yes -o /usr/share/keyrings/simharbor-llvm.gpg "$key"
echo 'deb [signed-by=/usr/share/keyrings/simharbor-llvm.gpg] https://apt.llvm.org/noble/ llvm-toolchain-noble-22 main' | "${AS_ROOT[@]}" tee /etc/apt/sources.list.d/simharbor-llvm.list > /dev/null
"${AS_ROOT[@]}" apt-get update -qq
"${AS_ROOT[@]}" apt-get install -y --no-install-recommends clang-22 libclang-rt-22-dev
