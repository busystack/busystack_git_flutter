import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _AmendClient extends FixtureClient {
  final head = GitOid('a' * 40);
  final pendingHistory = Completer<HistoryPage>();
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    token: 'amend-review',
    indexToken: 'amend-index',
    head: head,
    branch: 'main',
    changes: [
      GitChange(path: RepoPath.text('note.md'), index: 'M', worktree: '.'),
    ],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );

  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) => pendingHistory.future;
}

void main() {
  testWidgets('late HEAD message cannot overwrite typing or normal draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _AmendClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: GitCommitView(
              session: session,
              onReview: (_) {},
              onLog: () {},
              onBranches: () {},
              onPush: () {},
              onMore: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'Commit message');
    await tester.enterText(input, 'normal draft');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.enterText(input, 'edited amend draft');
    client.pendingHistory.complete(
      HistoryPage(
        [
          GitCommit(
            oid: client.head,
            parents: const [],
            subject: 'old',
            author: 'Fixture',
            email: 'fixture@example.invalid',
            date: DateTime.utc(2026),
            message: 'previous HEAD message',
          ),
        ],
        nextOffset: 1,
        hasMore: false,
        anchor: 'head',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('edited amend draft'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('normal draft'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('edited amend draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
