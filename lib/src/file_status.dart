import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/widgets.dart';
import 'host.dart';
import 'messages.dart';

enum GitFileStatus {
  unchanged,
  added,
  modified,
  deleted,
  renamed,
  copied,
  conflicted,
  untracked,
  ignored,
  typeChanged,
  unknown,
}

enum GitStatusContext { staged, unstaged, historical }

enum GitEntryIdentity { file, directory, symlink, submodule, changeGroup }

/// Presentation only: engine XY values and historical metadata remain intact.
GitFileStatus gitFileStatus(GitChange change, GitStatusContext context) {
  if (context != GitStatusContext.historical) {
    if (change.conflicted) return GitFileStatus.conflicted;
    if (change.untracked) return GitFileStatus.untracked;
    if (change.ignored) return GitFileStatus.ignored;
  }
  return switch (context == GitStatusContext.unstaged
      ? change.worktree
      : change.index) {
    '.' || ' ' => GitFileStatus.unchanged,
    'A' => GitFileStatus.added,
    'M' => GitFileStatus.modified,
    'D' => GitFileStatus.deleted,
    'R' => GitFileStatus.renamed,
    'C' => GitFileStatus.copied,
    'U' => GitFileStatus.conflicted,
    '?' => GitFileStatus.untracked,
    '!' => GitFileStatus.ignored,
    'T' => GitFileStatus.typeChanged,
    _ => GitFileStatus.unknown,
  };
}

GitEntryIdentity gitEntryIdentity(GitChange change, GitStatusContext context) {
  if (change.directory) return GitEntryIdentity.directory;
  final modes = context == GitStatusContext.unstaged
      ? [change.worktreeMode, change.indexMode]
      : [change.indexMode, change.headMode];
  final mode = modes.where((mode) => mode != '000000').firstOrNull;
  if (mode == '120000') return GitEntryIdentity.symlink;
  if (mode == '160000' || change.submodule.startsWith('S'))
    return GitEntryIdentity.submodule;
  return GitEntryIdentity.file;
}

String gitFileStatusDescription(
  BuildContext context,
  GitFileStatus status,
  GitStatusContext side,
) {
  final label = gitString(context, switch (status) {
    GitFileStatus.unchanged => GitMessages.fileUnchanged,
    GitFileStatus.added => GitMessages.fileAdded,
    GitFileStatus.modified => GitMessages.fileModified,
    GitFileStatus.deleted => GitMessages.fileDeleted,
    GitFileStatus.renamed => GitMessages.fileRenamed,
    GitFileStatus.copied => GitMessages.fileCopied,
    GitFileStatus.conflicted => GitMessages.fileConflicted,
    GitFileStatus.untracked => GitMessages.untracked,
    GitFileStatus.ignored => GitMessages.fileIgnored,
    GitFileStatus.typeChanged => GitMessages.fileTypeChanged,
    GitFileStatus.unknown => GitMessages.statusNotInspected,
  });
  return gitString(
    context,
    switch (side) {
      GitStatusContext.staged => GitMessages.fileStatusStaged,
      GitStatusContext.unstaged => GitMessages.fileStatusUnstaged,
      GitStatusContext.historical => GitMessages.fileStatusHistorical,
    },
    values: {'status': label},
  );
}
