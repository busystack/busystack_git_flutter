import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _AmendClient extends FixtureClient {
  var head = GitOid('a' * 40);
  bool staged = true;
  final pendingHistory = Completer<HistoryPage>();
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => currentSnapshot();

  GitSnapshot currentSnapshot() => GitSnapshot(
    repository: repo,
    token: 'amend-review',
    indexToken: 'amend-index',
    head: head,
    branch: 'main',
    changes: [
      if (staged)
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
  for (final pushFails in [false, true]) {
    testWidgets(
      'message-only amend commits once before canceled/failed Push, failed: $pushFails',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _AmendClient()
          ..staged = false
          ..pending = Completer<GitOutcome>();
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
                message: 'old message',
              ),
            ],
            nextOffset: 1,
            hasMore: false,
            anchor: 'head',
          ),
        );
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        var pushes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                child: GitCommitView(
                  session: session,
                  onReview: (_) {},
                  onLog: () {},
                  onBranches: () {},
                  onPush: () {
                    pushes++;
                    if (pushFails)
                      session.reportFailure(
                        const GitException(GitErrorCode.commandFailed),
                      );
                  },
                  onMore: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final input = find.widgetWithText(TextField, 'Commit message');
        await tester.enterText(input, 'normal A');
        expect(session.canCommit!(), isFalse); // Empty index never auto-stages.
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.enterText(input, 'submitted B');
        expect(session.canCommit!(), isTrue);
        final operation = session.commitAction!(true);
        await tester.pump();
        await tester.enterText(input, 'newer C');
        final request = client.mutations.single as CommitIndex;
        expect(request.amend, isTrue);
        expect(request.message, 'submitted B');
        client.head = GitOid('b' * 40);
        client.pending!.complete(
          GitOutcome(
            phase: GitOperationPhase.completed,
            createdCommit: client.head,
            snapshot: client.currentSnapshot(),
          ),
        );
        await operation;
        await tester.pumpAndSettle();
        expect(pushes, 1);
        expect(client.mutations, hasLength(1));
        expect(find.text('newer C'), findsOneWidget);
        expect(session.draft, 'normal A');
        expect(session.outcome!.createdCommit, client.head);
        await session.commitAction!(true);
        expect(client.mutations, hasLength(1));
        expect(pushes, 1);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  for (final fails in [false, true]) {
    for (final newerTyping in [false, true]) {
      testWidgets(
        'amend completion after closing view preserves own draft, failure: $fails, newer: $newerTyping',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = _AmendClient()..pending = Completer<GitOutcome>();
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
                  message: 'old message',
                ),
              ],
              nextOffset: 1,
              hasMore: false,
              anchor: 'head',
            ),
          );
          final session = GitSession(
            client: client,
            repository: repo,
            host: host(),
          );
          await session.start();
          Future<void> mount() => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 500,
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
          await mount();
          await tester.pumpAndSettle();
          final input = find.widgetWithText(TextField, 'Commit message');
          await tester.enterText(input, 'normal A');
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          await tester.enterText(input, 'submitted B');
          final oldHead = client.head;
          final amendKey = '${repo.presentationKey}:amend:${oldHead.value}';
          final operation = session.commitAction!(false);
          await tester.pump();
          if (newerTyping) await tester.enterText(input, 'newer C');
          await tester.pumpWidget(const SizedBox());
          if (!fails) client.head = GitOid('b' * 40);
          client.pending!.complete(
            GitOutcome(
              phase: fails
                  ? GitOperationPhase.failed
                  : GitOperationPhase.completed,
              createdCommit: fails ? null : client.head,
              error: fails
                  ? const GitException(GitErrorCode.commandFailed)
                  : null,
              snapshot: client.currentSnapshot(),
            ),
          );
          await operation;
          await session.flushMessageDrafts();
          expect(session.draft, 'normal A');
          expect(
            await session.host.drafts.read(amendKey),
            newerTyping
                ? 'newer C'
                : fails
                ? 'submitted B'
                : '',
          );
          await mount();
          await tester.pumpAndSettle();
          expect(
            find.text(
              newerTyping
                  ? 'newer C'
                  : fails
                  ? 'submitted B'
                  : 'normal A',
            ),
            findsOneWidget,
          );
          if (newerTyping && !fails) expect(session.canCommit!(), isFalse);
          expect(client.mutations, hasLength(1));
          await tester.pumpWidget(const SizedBox());
          session.dispose();
        },
      );
    }
  }

  for (final newerTyping in [false, true]) {
    testWidgets(
      'successful amend preserves draft ownership, newer typing: $newerTyping',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _AmendClient()..pending = Completer<GitOutcome>();
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
                message: 'old message',
              ),
            ],
            nextOffset: 1,
            hasMore: false,
            anchor: 'head',
          ),
        );
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
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
        await tester.enterText(input, 'normal A');
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.enterText(input, 'submitted B');
        final oldHead = client.head;
        final amendKey = '${repo.presentationKey}:amend:${oldHead.value}';
        final operation = session.commitAction!(false);
        await tester.pump();
        expect(client.mutations.single, isA<CommitIndex>());
        expect((client.mutations.single as CommitIndex).message, 'submitted B');
        if (newerTyping) await tester.enterText(input, 'newer C');
        client.head = GitOid('b' * 40);
        client.pending!.complete(
          GitOutcome(
            phase: GitOperationPhase.completed,
            createdCommit: client.head,
            snapshot: client.currentSnapshot(),
          ),
        );
        await operation;
        await tester.pumpAndSettle();
        await session.flushMessageDrafts();
        expect(session.draft, 'normal A');
        expect(
          await session.host.drafts.read(repo.presentationKey),
          'normal A',
        );
        expect(
          await session.host.drafts.read(amendKey),
          newerTyping ? 'newer C' : '',
        );
        expect(find.text(newerTyping ? 'newer C' : 'normal A'), findsOneWidget);
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox)).value,
          newerTyping,
        );
        if (newerTyping) {
          expect(session.canCommit!(), isFalse);
          expect(
            find.textContaining('HEAD ${oldHead.abbreviated}'),
            findsOneWidget,
          );
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          expect(find.text('normal A'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

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
