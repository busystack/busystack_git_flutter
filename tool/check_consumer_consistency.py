#!/usr/bin/env python3
"""Verify the same reviewed shared source and native contract gates in both apps."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile
from shared_source_archives import tree_digest

def check_screen_ownership(source, location):
    # Match calls regardless of an import prefix. Shared layout primitives in
    # host source would let another Commit/Log/history/review panel emerge.
    duplicate = re.search(
        r'\b(?:GitCommitView|GitLogView|GitDiffView|GitBranchesView|'
        r'GitChangeRow|GitReferenceRow|GitHistoryLayout|GitDiffDocumentSelection|'
        r'GitFeatureHeader|GitReviewTabStrip)\s*\(', source)
    assert duplicate is None, f'{location}: app-owned Git screen/layout composition'


def check_workspace_ownership(source):
    assert 'GitFeatureSidebar(' in source and 'GitReviewContent(' in source
    assert not re.search(r'\b(?:GitChoiceBar|GitSplitter)\s*\(|\b_compactReview\b', source), 'Retired GitWorkspace composition returned'


def check_review_ownership(source, location):
    # Only the canonical ordinary review and the specialized editable conflict
    # transaction may construct a diff. Named constructors count as well.
    calls = re.findall(r'\bGitDiffView(?:\.\w+)?\s*\(', source)
    expected = {'feature.dart': 1, 'conflict_view.dart': 1, 'diff_view.dart': 1}
    assert len(calls) == expected.get(Path(location).name, 0), f'{location}: competing diff construction'
    if Path(location).name == 'feature.dart':
        surface = source.index('class GitReviewSurface ')
        assert source.index('GitDiffView(', surface) > surface
    if Path(location).name == 'conflict_view.dart':
        assert re.search(r'Future<void> compareBase\(int stage\).*?GitDiffView\(.*?ContentKind\.conflictStage, stage: 1.*?ContentKind\.conflictStage, stage: stage', source, re.S), 'Only captured conflict-stage inspection is exempt'


def check_feature_contracts(feature, native, presentation, workspace, messages):
    assert not re.search(r'\b(?:GitFeatureHeader|GitSidebarSelector)\s*\(', feature), 'Git content must not replace application navigation'
    assert 'reserveStatus' not in native, 'Reserved status column returned'
    assert not re.search(r'final String\?\s+status\s*[,;]', presentation), 'Rows must receive semantic status'
    assert re.search(r'gitFilenameStyle\(\s*context,\s*status', native), 'Shared filename status resolver missing'
    assert re.search(r'commitAndPush\s*=\s*[\'"]Commit and Push[\'"]', messages), 'Commit and Push caption changed'
    for source, parameter in [(feature, 'mayClose'), (workspace, 'mayCloseReview')]:
        assert 'required this.' + parameter in source, 'Dismissal guard must be required'
        assert not re.search(r'Function\(\)\?\s*' + parameter + r'\b', source), 'Dismissal guard must be nonnullable'
    assert 'selected: visible' not in native, 'Expanded history sidebar must not select/accent its toggle'


def main():
    workspace = Path(__file__).resolve().parents[2]
    shared = workspace / 'busystack_git_flutter'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--consumer', action='append', type=Path,
                        help='Exact consumer checkout for an isolated CI/build workspace; default checks both hosts')
    args = parser.parse_args()
    consumers = [p.resolve() for p in args.consumer] if args.consumer else [workspace / name for name in ['busymark', 'busyfiles']]
    assert consumers and len(set(consumers)) == len(consumers), 'Consumer selection must be explicit and non-duplicated'
    revision = subprocess.check_output(['git', '-C', str(shared), 'rev-parse', 'HEAD'], text=True).strip() if (shared / '.git').exists() else None
    check_feature_contracts(*[(shared / path).read_text() for path in ['lib/src/feature.dart', 'lib/src/linux_native.dart', 'lib/src/presentation.dart', 'lib/src/workspace.dart', 'lib/src/messages.dart']])
    archives, revisions = [], []
    for root in consumers:
        name = root.name
        assert name in ['busymark', 'busyfiles'], 'Unknown consumer checkout'
        assert root.parent == workspace, 'Consumer must use this exact sibling shared source'
        manifest = json.loads((root / 'tool/shared_dependencies.json').read_text())
        pin = next(d for d in manifest['dependencies'] if d['name'] == shared.name)
        if revision is not None:
            assert pin['revision'] == revision, f'{name}: shared UI revision differs from reviewed HEAD'
        assert tree_digest(shared) == pin['tree_sha256'], f'{name}: actual compiled shared tree differs from pinned archive'
        revisions.append(pin['revision'])
        archive = root / pin['archive']
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == pin['sha256'], f'{name}: archive checksum differs'
        with tarfile.open(archive) as source:
            files = {m.name.removeprefix(shared.name + '/'): source.extractfile(m).read()
                     for m in source.getmembers() if m.isfile()}
        for key in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'AGENTS.md', '.github/workflows/check.yml']:
            path = shared / key
            if path.exists():
                assert files.get(key) == path.read_bytes(), f'{name}: archive differs at {key}'
        for folder in ['lib', 'test', 'tool', 'docs', 'linux']:
            for path in (shared / folder).rglob('*'):
                if path.is_file() and not any(p in path.parts for p in ['build', '.dart_tool', '__pycache__']):
                    key = path.relative_to(shared).as_posix()
                    assert files.get(key) == path.read_bytes(), f'{name}: archive differs at {key}'
        archives.append(pin['sha256'])
        libraries = root / ('lib' if name == 'busymark' else 'apps/busyfiles_ui/lib')
        for path in libraries.rglob('*.dart'):
            assert not re.search(r'class\s+Git(?:CommitView|BranchesView|LogView|DiffView|HistoricalChangeTree|IndexEditor|SidebarTab|ChangesView|ProjectHistoryView|FileHistoryView|AuthorIdentityDialog)\b', path.read_text()), f'{name}: duplicated shared Git workflow in {path}'
        gate = root / ('tools/check_git_presentation.sh' if name == 'busymark' else 'scripts/verify.sh')
        assert 'check_native_presentation.dart' in gate.read_text(), f'{name}: missing native audit gate'
        host = 'BusyMarkGitPresentation' if name == 'busymark' else 'BusyFilesGitPresentation'
        design = libraries / ('src/app/busymark_design.dart' if name == 'busymark' else 'src/app/busyfiles_design.dart')
        source = design.read_text()
        adapter = re.search(r'final class ' + host + r' extends git\.YaruGitPresentation\s*\{([^{}]*)\}', source)
        assert adapter, f'{name}: native Git renderer must be the canonical shared implementation'
        assert re.fullmatch(r'\s*const ' + host + r'\(\);\s*', adapter[1]), f'{name}: app-owned Git visual override'
        for path in libraries.rglob('*.dart'):
            source = path.read_text()
            check_screen_ownership(source, f'{name}: {path}')
        workspace_source = (shared / 'lib/src/workspace.dart').read_text()
        check_workspace_ownership(workspace_source)
        for path in (shared / 'lib/src').glob('*.dart'):
            check_review_ownership(path.read_text(), path.name)

        assert f'--host-root {host}' in gate.read_text(), f'{name}: missing resolved host rendering audit'
        assert 'check_consumer_consistency.py' in gate.read_text(), f'{name}: missing archive consistency gate'
        contract = root / ('test/src/git/actions_native_contract_test.dart' if name == 'busymark' else 'apps/busyfiles_ui/test/git_actions_native_contract_test.dart')
        assert 'actionsPresentationContract(' in contract.read_text(), f'{name}: missing actual-host semantic regression'
    assert len(set(archives)) == 1, 'Consumer source archives differ'
    assert len(set(revisions)) == 1, 'Consumer shared revisions differ'
    print(f'{len(consumers)} consumer(s) use {revisions[0]}, matching exact source trees, archives and native contract tests.')


if __name__ == '__main__':
    main()
