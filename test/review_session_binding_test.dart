import 'dart:async';
import 'dart:convert';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

class _ReviewClient extends FixtureClient {
  bool newFile = false;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: newFile ? 'after' : 'before',
    indexToken: 'index',
    changes: [
      for (final path in ['a.md', if (newFile) 'new.md', 'b.md'])
        GitChange(path: RepoPath.text(path), index: 'M', worktree: '.'),
    ],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
}

final class _LongReviewClient extends FixtureClient {
  _LongReviewClient({this.longLines = false}) {
    historyCommits = [
      for (var i = 0; i < 90; i++)
        GitCommit(
          oid: GitOid((i + 1).toRadixString(16).padLeft(40, '0')),
          parents: [GitOid('f' * 40)],
          subject: 'Commit $i',
          author: 'Fixture',
          email: 'fixture@example.invalid',
          date: DateTime.utc(2026),
          message: 'Commit $i',
        ),
    ];
  }
  final bool longLines;
  int reads = 0;
  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) async => [
    for (final path in ['a.md', 'b.md'])
      GitChange(path: RepoPath.text(path), index: 'M', worktree: '.'),
  ];
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    reads++;
    return GitContent(
      path: path,
      version: version,
      availability: version.kind == ContentKind.absent
          ? ContentAvailability.absent
          : ContentAvailability.present,
      token: version.label,
      mode: '100644',
      bytes: utf8.encode(
        [
          for (var i = 0; i < 160; i++)
            '${version.kind.name} ${version.revision?.value ?? ''} paragraph $i 東京 ${longLines ? 'long Markdown prose ' * 20 : ''}',
        ].join('\n'),
      ),
    );
  }
}

Future<void> _reviewReady(WidgetTester tester) async {
  final elapsed = Stopwatch()..start();
  while (find.byType(GitDiffView).evaluate().isEmpty ||
      find
          .descendant(
            of: find.byType(GitDiffView),
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .isNotEmpty) {
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'Review content must finish',
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  await tester.pump();
}

void main() {
  testWidgets(
    'equivalent endpoint rebuild retains loaded comparison and scroll',
    (tester) async {
      final client = _LongReviewClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      final revision = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: revision,
              builder: (_, value, _) => GitDiffView(
                session: session,
                comparison: GitComparison(
                  RepoPath.text('a.md'),
                  ContentVersion(
                    ContentKind.commit,
                    revision: GitOid('a' * 40),
                  ),
                  const ContentVersion.index(),
                  leftPath: value == 0 ? null : RepoPath.text('a.md'),
                ),
              ),
            ),
          ),
        ),
      );
      await _reviewReady(tester);
      final state = tester.state(find.byType(GitDiffView));
      final scroll = tester
          .widget<ListView>(
            find.descendant(
              of: find.byType(GitDiffView),
              matching: find.byType(ListView),
            ),
          )
          .controller!;
      scroll.jumpTo(100);
      await tester.pump();
      final before = client.reads;
      revision.value++;
      await tester.pump();
      expect(
        client.reads,
        before,
        reason: 'Same path/revisions must not restart content requests',
      );
      expect(tester.state(find.byType(GitDiffView)), same(state));
      expect(scroll.offset, 100);
      expect(
        find.descendant(
          of: find.byType(GitDiffView),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      revision.dispose();
      session.dispose();
    },
  );

  testWidgets('Log expansion returns to same table preview split and scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _LongReviewClient(longLines: true);
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    session.setViewState('diffWrap', false);
    session.setViewState('logDetailsSplit', .57);
    session.setViewState('logPreviewSplit', .68);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GitLogView(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    final table = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    table.jumpTo(500);
    await tester.pump();
    await tester.tap(find.text('a.md'));
    await _reviewReady(tester);
    expect(table.offset, 500);
    final state = tester.state(find.byType(GitDiffView));
    final scroll = tester
        .widget<ListView>(
          find.descendant(
            of: find.byType(GitDiffView),
            matching: find.byType(ListView),
          ),
        )
        .controller!;
    scroll.jumpTo(100);
    ScrollController horizontal(String side) => tester
        .widget<SingleChildScrollView>(
          find.descendant(
            of: find.byKey(ValueKey('git-diff-$side-horizontal')),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .controller!;
    final left = horizontal('left'), right = horizontal('right');
    left.jumpTo(120);
    right.jumpTo(180);
    await tester.pump();
    final tableBounds = tester.getRect(find.byType(CustomScrollView));
    final reads = client.reads;
    await tester.tap(find.byTooltip('Review difference'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(GitDiffView)), same(state));
    expect(client.reads, reads);
    expect(table.hasClients, isTrue);
    expect(table.offset, 500);
    await tester.tap(find.widgetWithText(TextButton, 'Log').last);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(GitDiffView)), same(state));
    expect(client.reads, reads);
    expect(table.offset, 500);
    expect(scroll.offset, 100);
    expect(left.offset, 120);
    expect(right.offset, 180);
    expect(tester.getRect(find.byType(CustomScrollView)), tableBounds);
    expect(session.split('logDetailsSplit', 0), .57);
    expect(session.split('logPreviewSplit', 0), .68);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('file navigation retains its reviewed list through refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _ReviewClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GitWorkspace(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.md').first);
    await _reviewReady(tester);
    expect(
      tester
          .widget<GitDiffView>(find.byType(GitDiffView))
          .comparison
          .path
          .utf8Path,
      'a.md',
    );
    final next = tester
        .widget<GitDiffView>(find.byType(GitDiffView))
        .onNextFile!;
    client.newFile = true;
    await session.refresh();
    await tester.pumpAndSettle();
    next();
    await _reviewReady(tester);
    expect(
      tester
          .widget<GitDiffView>(find.byType(GitDiffView))
          .comparison
          .path
          .utf8Path,
      'b.md',
    );
    next(); // A retained callback cannot advance an unrelated new selection.
    await tester.pump();
    expect(
      tester
          .widget<GitDiffView>(find.byType(GitDiffView))
          .comparison
          .path
          .utf8Path,
      'b.md',
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('retired Commit completion cannot retarget a new session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final oldClient = FixtureClient()..pending = Completer<GitOutcome>();
    final newClient = FixtureClient();
    final oldSession = GitSession(
      client: oldClient,
      repository: repo,
      host: host(),
    );
    final newSession = GitSession(
      client: newClient,
      repository: repo,
      host: host(),
    );
    await oldSession.start();
    await newSession.start();
    oldSession.setDraft('submitted in original session');
    newSession.setDraft('new session draft');
    var oldPush = 0, newPush = 0;
    final active = ValueNotifier(oldSession);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<GitSession>(
            valueListenable: active,
            builder: (_, session, _) => GitCommitView(
              key: const ValueKey('same host slot'),
              session: session,
              onReview: (_) {},
              onLog: () {},
              onBranches: () {},
              onMore: (_) {},
              onPush: () {
                if (session == oldSession) {
                  oldPush++;
                } else {
                  newPush++;
                }
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final completion = oldSession.commitAction!(true);
    await tester.pump();
    expect(oldClient.mutations.single, isA<CommitIndex>());
    active.value = newSession;
    await tester.pumpAndSettle();
    expect(find.text('new session draft'), findsOneWidget);
    expect(oldSession.commitAction, isNull);
    oldClient.pending!.complete(
      GitOutcome(
        phase: GitOperationPhase.completed,
        snapshot: snapshot(),
        createdCommit: GitOid('b' * 40),
      ),
    );
    await tester.pumpAndSettle();
    await completion;
    expect(oldSession.draft, isEmpty);
    expect(newSession.draft, 'new session draft');
    expect(newClient.mutations, isEmpty);
    expect([oldPush, newPush], [0, 0]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    active.dispose();
    oldSession.dispose();
    newSession.dispose();
  });
}
