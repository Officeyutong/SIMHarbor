#!/usr/bin/env python3
"""Generate isolated X.509 fixtures and exercise registeredID matching."""
import pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="simharbor-oid-") as tmp:
    folder = pathlib.Path(tmp)
    def cert(name, san, extra=None):
        pem, der = folder / (name + ".pem"), folder / (name + ".der")
        cmd = ["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-subj", "/CN=fixture.invalid", "-days", "1", "-keyout", str(folder / (name + ".key")), "-out", str(pem)]
        if san: cmd += ["-addext", "subjectAltName=" + san]
        if extra: cmd += ["-addext", extra]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["openssl", "x509", "-in", str(pem), "-outform", "DER", "-out", str(der)], check=True)
        return der
    a=cert("match", "RID:1.3.6.1.4.1.31746,DNS:fixture.invalid")
    b=cert("absent", "DNS:fixture.invalid")
    c=cert("duplicate", "RID:1.3.6.1.4.1.31746,RID:1.3.6.1.4.1.31746")
    d=cert("wrong_location", "DNS:fixture.invalid", "certificatePolicies=1.3.6.1.4.1.31746")
    e=cert("critical", "critical,RID:1.3.6.1.4.1.31746")
    f=cert("no_san", None)
    exe=folder / "check"
    subprocess.run(["clang++-22", "-std=c++17", "-fsanitize=address,undefined", "-g", str(root / "tests/test_server_oid.cpp"), "-o", str(exe)], check=True)
    subprocess.run([str(exe),str(a),str(b),str(c),str(d),str(e),str(f)],check=True)
print("PASS: X.509 registeredID match, mismatch, absence, duplicate, wrong location and malformed input")
