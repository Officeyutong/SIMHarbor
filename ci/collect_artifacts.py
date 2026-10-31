#!/usr/bin/env python3
"""Copy the built deb and public build provenance, never pairing headers or caches."""
from pathlib import Path
import hashlib,json,plistlib,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
version=(ROOT/'VERSION').read_text().strip();build=(ROOT/'BUILD_NUMBER').read_text().strip();dist=ROOT/'dist';dist.mkdir(exist_ok=True)
packages=list((ROOT/'packages').glob('*_'+version+'_iphoneos-arm64e.deb'))
if len(packages)!=1:raise SystemExit('Expected exactly one roothide package')
package=packages[0]
assert subprocess.check_output(['dpkg-deb','-f',str(package),'Version'],text=True).strip()==version
assert subprocess.check_output(['dpkg-deb','-f',str(package),'Architecture'],text=True).strip()=='iphoneos-arm64e'
with tempfile.TemporaryDirectory(prefix='deb-check-') as folder:
    subprocess.run(['dpkg-deb','-x',str(package),folder],check=True);app=next(Path(folder).rglob('ESTKLog.app'))
    info=plistlib.loads((app/'Info.plist').read_bytes());assert info['CFBundleShortVersionString']==version and info['CFBundleVersion']==build
    for language in ['en','zh-Hans']:
        name='Documentation-'+language+'.json';assert (app/name).read_bytes()==(ROOT/'viewer/Resources'/name).read_bytes()
name='SIMHarbor_'+version+'_roothide.deb';shutil.copy2(package,dist/name)
commit=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip()
(dist/'build-info.json').write_text(json.dumps({'version':version,'build':build,'commit':commit,'architecture':'iphoneos-arm64e','dependencies':json.loads((ROOT/'ci/dependencies.json').read_text())},indent=2)+'\n')
(dist/'SHA256SUMS').write_text(hashlib.sha256((dist/name).read_bytes()).hexdigest()+'  '+name+'\n')
print('Verified and collected '+name)
