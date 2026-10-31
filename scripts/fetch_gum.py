#!/usr/bin/env python3
"""Download the official pinned Gum devkits; verify archive and library hashes."""
from pathlib import Path
import hashlib,json,shutil,tarfile,tempfile,urllib.request
ROOT=Path(__file__).resolve().parents[1]
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def main():
    vendor=ROOT/'vendor/frida-gum';data=json.loads((vendor/'PROVENANCE.json').read_text())
    for record in data['archives']:
        target=vendor/record['architecture'];library=target/'libfrida-gum.a';header=target/'frida-gum.h'
        if library.exists() and header.exists() and digest(library)==record['library_sha256'] and digest(header)==record['header_sha256']:continue
        with tempfile.TemporaryDirectory(prefix='gum-devkit-') as folder:
            archive=Path(folder)/'devkit.tar.xz'
            with urllib.request.urlopen(record['url'],timeout=180) as response,archive.open('wb') as out:shutil.copyfileobj(response,out)
            if digest(archive)!=record['archive_sha256']:raise SystemExit('Gum archive checksum mismatch')
            target.mkdir(parents=True,exist_ok=True)
            with tarfile.open(archive,'r:xz') as tar:
                for name in ['libfrida-gum.a','frida-gum.h']:
                    member=tar.getmember(name)
                    if not member.isfile():raise SystemExit('Unexpected Gum archive entry')
                    with tar.extractfile(member) as src,(target/name).open('wb') as dst:shutil.copyfileobj(src,dst)
            if digest(library)!=record['library_sha256'] or digest(header)!=record['header_sha256']:raise SystemExit('Gum static library checksum mismatch')
        print('Verified Frida Gum '+data['version']+' '+record['architecture'])
if __name__=='__main__':main()
