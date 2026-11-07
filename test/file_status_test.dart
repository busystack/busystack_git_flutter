import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GitChange change(
    String index,
    String worktree, {
    String mode = '100644',
    String oldMode = '100644',
  }) => GitChange(
    path: RepoPath.text('日本語/deleted.md'),
    originalPath: RepoPath.text('before.md'),
    index: index,
    worktree: worktree,
    indexMode: mode,
    headMode: oldMode,
    worktreeMode: '000000',
  );
  test(
    'the same path styles the reviewed side, including historical deletion',
    () {
      final addedThenModified = change('A', 'M');
      expect(
        gitFileStatus(addedThenModified, GitStatusContext.staged),
        GitFileStatus.added,
      );
      expect(
        gitFileStatus(addedThenModified, GitStatusContext.unstaged),
        GitFileStatus.modified,
      );
      final modifiedThenDeleted = change('M', 'D');
      expect(
        gitFileStatus(modifiedThenDeleted, GitStatusContext.staged),
        GitFileStatus.modified,
      );
      expect(
        gitFileStatus(modifiedThenDeleted, GitStatusContext.unstaged),
        GitFileStatus.deleted,
      );
      expect(
        gitFileStatus(change('D', 'M'), GitStatusContext.historical),
        GitFileStatus.deleted,
      );
    },
  );
  for (final entry in {
    'R': GitFileStatus.renamed,
    'C': GitFileStatus.copied,
    'T': GitFileStatus.typeChanged,
    'U': GitFileStatus.conflicted,
    '?': GitFileStatus.untracked,
    '!': GitFileStatus.ignored,
    '.': GitFileStatus.unchanged,
    'X': GitFileStatus.unknown,
  }.entries) {
    test('preserves ${entry.value} without reclassifying unknown as clean', () {
      expect(
        gitFileStatus(change(entry.key, '.'), GitStatusContext.staged),
        entry.value,
      );
    });
  }
  test(
    'deleted identities come from recorded modes without probing live paths',
    () {
      expect(
        gitEntryIdentity(
          change('D', '.', mode: '000000', oldMode: '120000'),
          GitStatusContext.historical,
        ),
        GitEntryIdentity.symlink,
      );
      expect(
        gitEntryIdentity(
          change('D', '.', mode: '000000', oldMode: '160000'),
          GitStatusContext.historical,
        ),
        GitEntryIdentity.submodule,
      );
    },
  );
}
