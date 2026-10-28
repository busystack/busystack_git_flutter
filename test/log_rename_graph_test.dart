import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

GitCommit _commit(String id, List<GitOid> parents) => GitCommit(
  oid: GitOid(id * 40),
  parents: parents,
  subject: 'Renamed chapter',
  author: 'Fixture',
  email: 'fixture@example.invalid',
  date: DateTime.utc(2026),
  message: 'Renamed chapter',
);

final class _RenameClient extends FixtureClient {
  final calls = <(RepoPath, ContentVersion)>[];
  late final parent = _commit('b', []);
  late final renamed = _commit('a', [parent.oid]);

  _RenameClient() {
    historyCommits = [renamed, parent];
  }

  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) async => [
    GitChange(
      path: RepoPath.text('new/chapter.md'),
      originalPath: RepoPath.text('old/chapter.md'),
      index: 'R',
      worktree: '.',
    ),
  ];

  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    calls.add((path, version));
    return GitContent(
      path: path,
      version: version,
      availability: ContentAvailability.present,
      token: '${version.revision}:${path.key}',
      mode: '100644',
      bytes: utf8.encode('chapter\n'),
    );
  }
}

void main() {
  testWidgets('Log compares old and new rename paths at their own revisions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _RenameClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GitLogView(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('chapter.md'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(GitDiffView), findsOneWidget);
    await tester.tap(find.byTooltip('Review difference'));
    await tester.pump();
    expect(find.text('Log'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Log').last);
    await tester.pump();
    expect(find.byType(GitDiffView), findsOneWidget);
    expect(
      client.calls.any(
        (call) =>
            call.$1.utf8Path == 'old/chapter.md' &&
            call.$2.revision == client.parent.oid,
      ),
      isTrue,
    );
    expect(
      client.calls.any(
        (call) =>
            call.$1.utf8Path == 'new/chapter.md' &&
            call.$2.revision == client.renamed.oid,
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  test('more than eight graph lanes retain distinct horizontal positions', () {
    final main = _commit('a', [
      GitOid('b' * 40),
      for (var i = 0; i < 12; i++) GitOid('${i + 10}' * 20),
    ]);
    final rows = graphRows([main]);
    expect(rows.single.width, greaterThan(8));
    expect(
      rows.single.edges.map((e) => e.$2).toSet().length,
      main.parents.length,
    );
  });
}
