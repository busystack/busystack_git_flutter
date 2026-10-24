import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

void main() {
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
