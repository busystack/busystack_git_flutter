#!/usr/bin/env python3
"""Verify the same reviewed shared source and native contract gates in both apps."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile

workspace = Path(__file__).resolve().parents[2]
shared = workspace / 'busystack_git_flutter'
revision = subprocess.check_output(['git', '-C', str(shared), 'rev-parse', 'HEAD'], text=True).strip()
archives = []
for name in ['busymark', 'busyfiles']:
    root = workspace / name
    manifest = json.loads((root / 'tool/shared_dependencies.json').read_text())
    pin = next(d for d in manifest['dependencies'] if d['name'] == shared.name)
    assert pin['revision'] == revision, f'{name}: shared UI revision differs from reviewed HEAD'
    archive = root / pin['archive']
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == pin['sha256'], f'{name}: archive checksum differs'
    with tarfile.open(archive) as source:
        files = {m.name.removeprefix(shared.name + '/'): source.extractfile(m).read()
                 for m in source.getmembers() if m.isfile()}
    for folder in ['lib', 'test', 'tool', 'docs', 'linux']:
        for path in (shared / folder).rglob('*'):
            if path.is_file() and not any(p in path.parts for p in ['build', '.dart_tool', '__pycache__']):
                key = path.relative_to(shared).as_posix()
                assert files.get(key) == path.read_bytes(), f'{name}: archive differs at {key}'
    archives.append(pin['sha256'])
    libraries = root / ('lib' if name == 'busymark' else 'apps/busyfiles_ui/lib')
    for path in libraries.rglob('*.dart'):
        assert not re.search(r'class\s+Git(?:CommitView|BranchesView|LogView|DiffView|HistoricalChangeTree|IndexEditor)\b', path.read_text()), f'{name}: duplicated shared Git workflow in {path}'
    gate = root / ('tools/check_git_presentation.sh' if name == 'busymark' else 'scripts/verify.sh')
    assert 'check_native_presentation.dart' in gate.read_text(), f'{name}: missing native audit gate'
    host = 'BusyMarkGitPresentation' if name == 'busymark' else 'BusyFilesGitPresentation'
    assert f'--host-root {host}' in gate.read_text(), f'{name}: missing resolved host rendering audit'
    assert 'check_consumer_consistency.py' in gate.read_text(), f'{name}: missing archive consistency gate'
    contract = root / ('test/src/git/actions_native_contract_test.dart' if name == 'busymark' else 'apps/busyfiles_ui/test/git_actions_native_contract_test.dart')
    assert 'actionsPresentationContract(' in contract.read_text(), f'{name}: missing actual-host semantic regression'
assert len(set(archives)) == 1, 'Consumer source archives differ'
print(f'Both consumers use {revision}, matching archives and native contract tests.')
