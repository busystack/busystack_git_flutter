import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

GitCommit _commit(String id) => GitCommit(
  oid: GitOid(id * 40),
  parents: const [],
  subject: 'Reviewed commit $id',
  author: 'Fixture',
  email: 'fixture@example.invalid',
  date: DateTime.utc(2026),
  message: 'Preserved message $id',
);

final class _FilesClient extends FixtureClient {
  final reads = <Completer<List<GitChange>>>[];

  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) {
    final read = Completer<List<GitChange>>();
    reads.add(read);
    return read.future;
  }
}

void main() {
  testWidgets('push commit details distinguish loading, failure and empty', (
    tester,
  ) async {
    final client = _FilesClient();
    final session = GitSession(client: client, repository: repo, host: host());
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitFiles(session: session, commit: _commit('a')),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    client.reads.single.completeError(
      const GitException(GitErrorCode.disconnected),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GitFailurePanel), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    expect(find.textContaining('Preserved message a'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(GitFailurePanel),
        matching: find.text('Refresh'),
      ),
    );
    await tester.pump();
    expect(client.reads, hasLength(2));
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    client.reads.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(GitFailurePanel), findsNothing);
    expect(find.bySemanticsLabel('Loading changed files'), findsNothing);
    expect(find.text('No changed files'), findsOneWidget);
    expect(find.bySemanticsLabel('No changed files'), findsOneWidget);
    expect(client.mutations, isEmpty);
  });

  testWidgets('an older file read cannot replace newer push selection', (
    tester,
  ) async {
    final client = _FilesClient();
    final session = GitSession(client: client, repository: repo, host: host());
    addTearDown(session.dispose);
    Future<void> select(String id) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitFiles(session: session, commit: _commit(id)),
        ),
      ),
    );
    await select('a');
    await select('b');
    expect(client.reads, hasLength(2));
    client.reads.last.complete([]);
    await tester.pumpAndSettle();
    client.reads.first.complete([
      GitChange(path: RepoPath.text('obsolete.md'), index: 'M', worktree: '.'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('obsolete.md'), findsNothing);
    expect(find.text('No changed files'), findsOneWidget);
    expect(find.textContaining('Preserved message b'), findsOneWidget);
    expect(client.mutations, isEmpty);
  });
}
