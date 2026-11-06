#!/usr/bin/env python3
"""Adversarial ownership checks; no Flutter rendering or source allowlists."""
from pathlib import Path
import unittest
from check_consumer_consistency import check_screen_ownership, check_workspace_ownership, check_review_ownership


class OwnershipTest(unittest.TestCase):
    def test_thin_host_mounts_are_permitted(self):
        check_screen_ownership('Widget build(c) => git.GitFeatureSidebar(controller: session.feature);', 'sidebar bridge')
        check_screen_ownership('Widget build(c) => git.GitWorkspace(session: session);', 'browser bridge')
        check_workspace_ownership((Path(__file__).resolve().parents[1] / 'lib/src/workspace.dart').read_text())

    def test_host_panels_and_primitives_are_rejected_with_import_prefixes(self):
        for name in ['GitCommitView', 'GitLogView', 'GitDiffView', 'GitBranchesView',
                     'GitChangeRow', 'GitReferenceRow', 'GitHistoryLayout',
                     'GitDiffDocumentSelection', 'GitFeatureHeader', 'GitReviewTabStrip']:
            for prefix in ['', 'git.', 'anotherAlias.']:
                with self.subTest(name=name, prefix=prefix), self.assertRaises(AssertionError):
                    check_screen_ownership(f'Widget build(c) => {prefix}{name}(session: session);', 'duplicate panel')

    def test_old_workspace_switcher_split_and_preview_are_rejected(self):
        good = 'GitFeatureSidebar(); GitReviewContent();'
        for old in ['git.GitChoiceBar(segments: choices)', 'other.GitSplitter(first: staging)', '_compactReview']:
            with self.subTest(old=old), self.assertRaises(AssertionError):
                check_workspace_ownership(good + old)

    def test_ordinary_workflows_cannot_construct_diffs(self):
        for name in ['log_view.dart', 'history_actions.dart', 'network_views.dart', 'new_preview.dart']:
            for call in ['GitDiffView(', 'alias.GitDiffView(', 'alias.GitDiffView.named(']:
                with self.subTest(name=name, call=call), self.assertRaises(AssertionError):
                    check_review_ownership('return ' + call + ');', name)
        root = Path(__file__).resolve().parents[1]
        for path in (root / 'lib/src').glob('*.dart'):
            check_review_ownership(path.read_text(), path.name)
        feature = (root / 'lib/src/feature.dart').read_text()
        with self.assertRaises(AssertionError):
            check_review_ownership(feature + '\nGitDiffView();', 'feature.dart')

    def test_missing_canonical_workspace_mount_is_rejected(self):
        for incomplete in ['GitFeatureSidebar();', 'GitReviewContent();', 'return oldWorkspace;']:
            with self.subTest(source=incomplete), self.assertRaises(AssertionError):
                check_workspace_ownership(incomplete)


if __name__ == '__main__':
    unittest.main()
