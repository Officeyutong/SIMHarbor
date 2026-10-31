#!/usr/bin/env python3
"""Exercise release policy against real temporary Git histories, with no network."""
from pathlib import Path
import importlib.util,subprocess,tempfile,json
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('version_policy',ROOT/'ci/version_policy.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args],text=True,stderr=subprocess.DEVNULL).strip()
def commit(repo,name):git(repo,'add','.');git(repo,'commit','-qm',name);return git(repo,'rev-parse','HEAD')
def event(before,default='main'):return {'before':before,'repository':{'default_branch':default}}
with tempfile.TemporaryDirectory(prefix='ci-policy-') as folder:
    repo=Path(folder);git(repo,'init','-qb','main');git(repo,'config','user.name','CI fixture');git(repo,'config','user.email','fixture@users.noreply.github.com')
    (repo/'VERSION').write_text('1.0.0\n');first=commit(repo,'initial')
    assert module.policy(repo,event('0'*40),'push','refs/heads/main')['should_release']
    (repo/'README.md').write_text('Documentation change\n');commit(repo,'docs')
    assert not module.policy(repo,event(first),'push','refs/heads/main')['should_release']
    (repo/'BUILD_NUMBER').write_text('2\n');commit(repo,'build only')
    assert not module.policy(repo,event(first),'push','refs/heads/main')['should_release']
    (repo/'VERSION').write_text('1.0.1\n');commit(repo,'version bump')
    (repo/'README.md').write_text('Follow-up in same push\n');commit(repo,'follow up')
    assert module.policy(repo,event(first),'push','refs/heads/main')['should_release']
    assert not module.policy(repo,event(first),'push','refs/heads/feature')['should_release']
    assert not module.policy(repo,event(first),'push','refs/tags/v1.0.1')['should_release']
    assert not module.policy(repo,event(first),'workflow_dispatch','refs/heads/main')['should_release']
    deleted=event(first);deleted['deleted']=True
    assert not module.policy(repo,deleted,'push','refs/heads/main')['should_release']
    assert not module.policy(repo,event('f'*40),'push','refs/heads/main')['should_release']
    assert not module.policy(repo,{},'push','refs/heads/main')['should_release']
    (repo/'VERSION').write_text('1.0.0\n');commit(repo,'revert version')
    assert not module.policy(repo,event(first),'push','refs/heads/main')['should_release']
    (repo/'VERSION').write_text('1.0.0\n\n');assert not module.policy(repo,event(first),'push','refs/heads/main')['should_release']
    for invalid in ['1.0','v1.0.0','1.0.0; echo invalid','1.0.0-beta.1','01.0.0']:
        (repo/'VERSION').write_text(invalid)
        try:module.policy(repo,event(first),'push','refs/heads/main')
        except ValueError:pass
        else:raise AssertionError('Invalid version accepted')
with tempfile.TemporaryDirectory(prefix='ci-added-version-') as folder:
    repo=Path(folder);git(repo,'init','-qb','main');git(repo,'config','user.name','CI fixture');git(repo,'config','user.email','fixture@users.noreply.github.com');(repo/'README').write_text('fixture');before=commit(repo,'before VERSION')
    (repo/'VERSION').write_text('1.0.0');commit(repo,'introduce VERSION');assert module.policy(repo,event(before),'push','refs/heads/main')['should_release']
print('PASS: initial push, unchanged/build-only/multi-commit bumps, branch/tag/manual/delete, unavailable baseline, revert and invalid version policy')
