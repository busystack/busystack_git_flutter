import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

GitCommit _commit(String id, String subject) => GitCommit(
  oid: GitOid(id * 40),
  parents: const [],
  subject: subject,
  author: 'Fixture',
  email: 'fixture@example.invalid',
  date: DateTime.utc(2026),
  message: 'Details: $subject',
);

final class _ChangedFilesClient extends FixtureClient {
  _ChangedFilesClient() {
    historyCommits = [
      _commit('a', 'Current commit'),
      _commit('b', 'Older commit'),
    ];
  }
  final reads = <Completer<List<GitChange>>>[];
  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) {
    final result = Completer<List<GitChange>>();
    reads.add(result);
    return result.future;
  }
}

Future<void> _mount(WidgetTester tester, _ChangedFilesClient client) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: GitLogView(session: session)),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

void main() {
  testWidgets('changed files distinguish loading from an empty commit', (
    tester,
  ) async {
    final client = _ChangedFilesClient();
    await _mount(tester, client);
    expect(client.reads, hasLength(1));
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    client.reads.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading changed files'), findsNothing);
    expect(find.text('No changed files'), findsOneWidget);
    expect(find.text('Current commit'), findsOneWidget);
  });

  testWidgets('changed-files errors retry without reloading the commit table', (
    tester,
  ) async {
    final client = _ChangedFilesClient();
    await _mount(tester, client);
    client.reads.single.completeError(
      const GitException(
        GitErrorCode.disconnected,
        diagnostic: 'Fixture disconnected while reading changed files.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GitFailurePanel), findsOneWidget);
    expect(find.text('Current commit'), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(GitFailurePanel),
        matching: find.text('Refresh'),
      ),
    );
    await tester.pump();
    expect(client.reads, hasLength(2));
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    client.reads.last.complete([
      GitChange(
        path: RepoPath.text('chapter/new.md'),
        index: 'A',
        worktree: '.',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('new.md'), findsOneWidget);
    expect(find.byType(GitFailurePanel), findsNothing);
    expect(client.historyFilters, hasLength(1));
    expect(client.mutations, isEmpty);
  });

  testWidgets(
    'a stale changed-files completion cannot replace newer selection',
    (tester) async {
      final client = _ChangedFilesClient();
      await _mount(tester, client);
      await tester.tap(find.text('Older commit'));
      await tester.pump();
      expect(client.reads, hasLength(2));
      client.reads.last.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('No changed files'), findsOneWidget);
      client.reads.first.complete([
        GitChange(
          path: RepoPath.text('obsolete.md'),
          index: 'M',
          worktree: '.',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('obsolete.md'), findsNothing);
      expect(find.text('No changed files'), findsOneWidget);
      expect(find.text('Details: Older commit'), findsOneWidget);
    },
  );
}
