import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

void main() {
  testWidgets(
    'progress wrapping keeps the commit editor and actions stationary',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _ProgressClient();
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
              width: 350,
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
      await tester.enterText(find.byType(TextField), 'draft stays here');
      final state = session.snapshot!;
      final operation = session.mutate(
        CommitIndex(
          'request',
          expectedHead: state.head,
          expectedIndex: state.indexToken,
        ),
      );
      await tester.pump();
      client.progress!(
        const GitProgress(GitOperationPhase.running, text: 'Connecting'),
      );
      await tester.pump();
      final editor = tester.getRect(find.byType(TextField));
      final action = tester.getRect(find.text('Commit staged (1)'));
      for (final text in [
        'Receiving a long remote progress message that wraps onto multiple lines',
        'Receiving objects\nResolving deltas',
        'Connected',
      ]) {
        client.progress!(GitProgress(GitOperationPhase.running, text: text));
        await tester.pump();
        expect(tester.getRect(find.byType(TextField)), editor);
        expect(tester.getRect(find.text('Commit staged (1)')), action);
        expect(find.text('draft stays here'), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      client.completion.complete(
        GitOutcome(phase: GitOperationPhase.completed, snapshot: snapshot()),
      );
      await operation;
      await tester.pumpAndSettle();
      session.dispose();
    },
  );
  testWidgets('failed processes expose exit status even without stderr', (
    tester,
  ) async {
    for (final diagnostic in ['', 'Rebasing (1/6)']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitFailurePanel(
              key: ValueKey(diagnostic),
              error: GitException(
                GitErrorCode.commandFailed,
                exitCode: 137,
                diagnostic: diagnostic,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          diagnostic.isEmpty
              ? 'Exit status: 137'
              : 'Exit status: 137\nRebasing (1/6)',
        ),
        findsOneWidget,
      );
    }
  });
  testWidgets(
    'file selection reviews without staging; explicit file action mutates the index',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient(),
          session = GitSession(
            client: FixtureClient(),
            repository: repo,
            host: host(),
          );
      final target = GitSession(client: client, repository: repo, host: host());
      await target.start();
      await session.start();
      final reviews = <GitComparison>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: GitCommitView(
                session: target,
                onReview: reviews.add,
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
      await tester.tap(find.text('notes.md').last);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(client.mutations, isEmpty);
      expect(reviews.single.left.kind, ContentKind.indexVersion);
      expect(reviews.single.right.kind, ContentKind.workingTree);
      await tester.tap(find.byTooltip('Stage file'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(client.mutations.single, isA<StagePaths>());
      target.dispose();
      session.dispose();
    },
  );
  testWidgets(
    'failure and async commit preserve a subsequently edited message draft',
    (tester) async {
      final client = FixtureClient(),
          target = GitSession(
            client: FixtureClient(),
            repository: repo,
            host: host(),
          );
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await target.start();
      client.pending = Completer<GitOutcome>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 350,
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
      await tester.enterText(find.byType(TextField), 'first draft');
      await tester.pump();
      await tester.tap(find.text('Commit staged (1)'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'next draft');
      await tester.pump();
      client.pending!.complete(
        GitOutcome(
          phase: GitOperationPhase.completed,
          snapshot: snapshot(),
          createdCommit: GitOid('a' * 40),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.draft, 'next draft');
      expect(find.text('next draft'), findsOneWidget);
      session.dispose();
      target.dispose();
    },
  );
  test(
    'graph connects actual merge parents and retains lanes across loaded pages',
    () {
      GitCommit commit(String id, List<String> parents) => GitCommit(
        oid: GitOid(id * 40),
        parents: parents.map((e) => GitOid(e * 40)).toList(),
        subject: id,
        author: 'author',
        email: 'a@example.invalid',
        date: DateTime.utc(2026),
      );
      final commits = [
        commit('a', ['b', 'c']),
        commit('b', ['d']),
        commit('c', ['d']),
        commit('d', []),
      ];
      final first = graphRows(commits.take(2).toList()),
          all = graphRows(commits);
      expect(first.first.edges.where((e) => e.$3).length, 2);
      expect(all[1].edges, first[1].edges);
      expect(all[2].lane, 1);
    },
  );
  testWidgets(
    'diff parsing crosses the isolate boundary without capturing widget state',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitDiffView(
              session: session,
              comparison: GitComparison(
                RepoPath.text('a.md'),
                const ContentVersion.index(),
                const ContentVersion.working(),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('Side by side'), findsOneWidget);
      expect(find.textContaining('Index ·'), findsOneWidget);
      expect(find.byType(GitFailurePanel), findsNothing);
      expect(tester.takeException(), isNull);
      session.dispose();
    },
  );
}

class _ProgressClient extends FixtureClient {
  final completion = Completer<GitOutcome>();
  void Function(GitProgress)? progress;
  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) {
    progress = onProgress;
    return completion.future;
  }
}
