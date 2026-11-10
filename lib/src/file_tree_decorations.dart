import 'dart:convert';

import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/widgets.dart';

import 'file_status.dart';
import 'host.dart';
import 'messages.dart';

enum GitDirectoryChangeState { immediate, descendant }

/// A filesystem browser decoration, distinct from a Git Changes row. Directory
/// state describes *where* changes are; it never inherits a child's operation.
final class GitTreeDecoration {
  const GitTreeDecoration.file(GitChange change)
    : change = change,
      directoryState = null,
      immediateCount = 0,
      descendantCount = 0,
      deletedCount = 0;

  const GitTreeDecoration.directory({
    required this.immediateCount,
    required this.descendantCount,
    required this.deletedCount,
  }) : change = null,
       directoryState = immediateCount > 0
           ? GitDirectoryChangeState.immediate
           : GitDirectoryChangeState.descendant;

  final GitChange? change;
  final GitDirectoryChangeState? directoryState;
  final int immediateCount, descendantCount, deletedCount;
  int get pathCount => immediateCount + descendantCount;

  /// Working-tree operations take precedence over staged operations on the
  /// *same path*. Both sides remain available in the explanation.
  GitFileStatus? get status {
    final entry = change;
    if (entry == null) return null;
    final working = gitFileStatus(entry, GitStatusContext.unstaged);
    return working == GitFileStatus.unchanged
        ? gitFileStatus(entry, GitStatusContext.staged)
        : working;
  }

  String get marker => switch (directoryState) {
    GitDirectoryChangeState.immediate => '•',
    GitDirectoryChangeState.descendant => '◦',
    null => switch (status) {
      GitFileStatus.modified => 'M',
      GitFileStatus.added => 'A',
      GitFileStatus.deleted => 'D',
      GitFileStatus.renamed => 'R',
      GitFileStatus.copied => 'C',
      GitFileStatus.untracked => '?',
      GitFileStatus.conflicted => '!',
      GitFileStatus.typeChanged => 'T',
      _ => '',
    },
  };

  String description(BuildContext context) => describe(
    (message, values) => gitString(context, message, values: values),
  );

  String describe(String Function(String, Map<String, Object?>) localize) {
    if (directoryState != null) {
      return localize(GitMessages.directoryChanges, {
        'immediate': immediateCount,
        'descendant': descendantCount,
        'deleted': deletedCount,
      });
    }
    final entry = change!;
    String side(GitStatusContext side) => localize(
      side == GitStatusContext.staged
          ? GitMessages.fileStatusStaged
          : GitMessages.fileStatusUnstaged,
      {
        'status': localize(
          gitFileStatusMessage(gitFileStatus(entry, side)),
          const {},
        ),
      },
    );
    if (entry.untracked) return localize(GitMessages.untracked, const {});
    return [
      if (entry.staged || entry.conflicted) side(GitStatusContext.staged),
      if (entry.unstaged || entry.conflicted) side(GitStatusContext.unstaged),
    ].join('; ');
  }
}

/// Immutable, byte-safe lookup built once per status snapshot. No filesystem or
/// Git operations are performed here. Hosts retain discovery/trust/watch policy.
final class GitFileTreeDecorations {
  GitFileTreeDecorations({
    required RepositoryId repository,
    required Iterable<GitChange> changes,
  }) {
    final trimmedRoot = repository.root.replaceFirst(RegExp(r'/+$'), '');
    final root = trimmedRoot.isEmpty ? '/' : trimmedRoot;
    final prefix = utf8.encode(root == '/' ? root : '$root/');
    final rootKey = base64Encode(utf8.encode(root));
    final directories = <String, List<int>>{};

    Map<String, bool> parents(RepoPath path) {
      final result = <String, bool>{};
      var slash = path.bytes.lastIndexOf(47);
      var immediate = true;
      while (slash >= 0) {
        final relative = path.bytes.sublist(0, slash);
        result[base64Encode([...prefix, ...relative])] = immediate;
        immediate = false;
        slash = relative.lastIndexOf(47);
      }
      result[rootKey] = immediate;
      return result;
    }

    for (final change in changes) {
      if (change.ignored) continue;
      final decoration = GitTreeDecoration.file(change);
      if (decoration.status == GitFileStatus.unchanged) continue;
      final key = base64Encode([...prefix, ...change.path.bytes]);
      _files[key] = decoration;
      final locations = parents(change.path);
      // Opaque directory records and gitlinks count as single repository entries.
      // Their internal files belong to another repository or were not inspected.
      if (change.directory || change.submodule.startsWith('S')) {
        locations[key] = true;
      }
      // A rename changes both locations, once per common ancestor. A copy does
      // not change its source. Immediate changes win over descendant-only ones.
      final original = change.originalPath;
      if (original != null && (change.index == 'R' || change.worktree == 'R')) {
        for (final source in parents(original).entries) {
          locations[source.key] =
              source.value || (locations[source.key] ?? false);
        }
      }
      for (final location in locations.entries) {
        final counts = directories.putIfAbsent(location.key, () => [0, 0, 0]);
        counts[location.value ? 0 : 1]++;
        if (change.index == 'D' || change.worktree == 'D') counts[2]++;
      }
    }
    for (final entry in directories.entries) {
      _directories[entry.key] = GitTreeDecoration.directory(
        immediateCount: entry.value[0],
        descendantCount: entry.value[1],
        deletedCount: entry.value[2],
      );
    }
  }

  static final _snapshots = Expando<GitFileTreeDecorations>();
  factory GitFileTreeDecorations.fromSnapshot(GitSnapshot snapshot) =>
      _snapshots[snapshot] ??= GitFileTreeDecorations(
        repository: snapshot.repository,
        changes: snapshot.changes,
      );

  final _files = <String, GitTreeDecoration>{};
  final _directories = <String, GitTreeDecoration>{};

  GitTreeDecoration? forUri(String uri, {bool directory = false}) {
    final key = _fileUriPathKey(uri);
    return key == null
        ? null
        : directory
        ? _directories[key]
        : _files[key] ?? _directories[key];
  }
}

// Decode URI octets rather than display text: invalid UTF-8 names must never
// alias another path, and remote/provider URIs must never receive local status.
String? _fileUriPathKey(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'file' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.host.isNotEmpty && uri.host != 'localhost')
    return null;
  final raw = RegExp(
    r'^file:(?://[^/]*)?(/[^?#]*)',
  ).firstMatch(uri.toString())?.group(1);
  if (raw == null) return null;
  final bytes = <int>[];
  for (var i = 0; i < raw.length; i++) {
    if (raw.codeUnitAt(i) == 37) {
      if (i + 2 >= raw.length) return null;
      final byte = int.tryParse(raw.substring(i + 1, i + 3), radix: 16);
      if (byte == null || byte == 0 || byte == 47) return null;
      bytes.add(byte);
      i += 2;
    } else {
      bytes.add(raw.codeUnitAt(i));
    }
  }
  while (bytes.length > 1 && bytes.last == 47) {
    bytes.removeLast();
  }
  return base64Encode(bytes);
}

String gitLocalFileUri(RepositoryId repository, RepoPath path) =>
    '${Uri.directory(repository.root)}${path.bytes.map((byte) => byte == 47
        ? '/'
        : byte >= 65 && byte <= 90 || byte >= 97 && byte <= 122 || byte >= 48 && byte <= 57 || const [45, 46, 95, 126].contains(byte)
        ? String.fromCharCode(byte)
        : '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}').join()}';
