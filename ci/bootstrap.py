#!/usr/bin/env python3
"""Install pinned public Theos, SDK and Linux toolchain into the ignored cache."""

from pathlib import Path
import hashlib, json, os, shutil, subprocess, tarfile, tempfile, urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEPS = ROOT / ".deps"


def run(*args):
    subprocess.run(args, check=True)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def checkout(record, path, sparse=None):
    if not (path / ".git").exists():
        path.mkdir(parents=True, exist_ok=True)
        run("git", "init", "-q", str(path))
        run("git", "-C", str(path), "remote", "add", "origin", record["url"])
    run("git", "-C", str(path), "config", "remote.origin.promisor", "true")
    run("git", "-C", str(path), "config", "remote.origin.partialclonefilter", "blob:none")
    head = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True, text=True
    )
    if head.returncode or head.stdout.strip() != record["commit"]:
        run(
            "git",
            "-C",
            str(path),
            "-c",
            "protocol.version=2",
            "fetch",
            "--depth=1",
            "--filter=blob:none",
            "origin",
            record["commit"],
        )
        if sparse:
            run("git", "-C", str(path), "sparse-checkout", "init", "--cone")
            run("git", "-C", str(path), "sparse-checkout", "set", sparse)
        run("git", "-C", str(path), "checkout", "--detach", record["commit"])


def main():
    config = json.loads((ROOT / "ci/dependencies.json").read_text())
    DEPS.mkdir(exist_ok=True)
    theos = DEPS / "theos"
    checkout(config["theos"], theos)
    run("git", "-C", str(theos), "submodule", "update", "--init", "--recursive", "--depth", "1")
    sdk = DEPS / "sdk-source"
    checkout(config["sdk"], sdk, config["sdk"]["directory"])
    target = theos / "sdks" / config["sdk"]["directory"]
    target.parent.mkdir(exist_ok=True)
    relative = os.path.relpath(sdk / config["sdk"]["directory"], target.parent)
    if target.is_symlink() and os.readlink(target) != relative:
        target.unlink()
    if not target.exists():
        target.symlink_to(relative, target_is_directory=True)
    record = config["toolchain"]
    stamp = DEPS / "toolchain.sha256"
    binary = theos / "toolchain/linux/iphone/bin/clang++"
    if not binary.exists() or not stamp.exists() or stamp.read_text().strip() != record["sha256"]:
        with tempfile.TemporaryDirectory(prefix="toolchain-", dir=DEPS) as folder:
            folder = Path(folder)
            archive = folder / "toolchain.tar.xz"
            with (
                urllib.request.urlopen(record["url"], timeout=300) as response,
                archive.open("wb") as out,
            ):
                shutil.copyfileobj(response, out)
            if digest(archive) != record["sha256"]:
                raise SystemExit("Toolchain archive checksum mismatch")
            with tarfile.open(archive, "r:xz") as tar:
                tar.extractall(folder / "unpack", filter="data")
            dest = theos / "toolchain/linux"
            if dest.exists():
                shutil.rmtree(dest)
            shutil.move(str(folder / "unpack/linux"), dest)
        stamp.write_text(record["sha256"] + "\n")
    run("python3", str(ROOT / "scripts/fetch_gum.py"))
    print("Pinned Linux build dependencies ready.")


if __name__ == "__main__":
    main()
