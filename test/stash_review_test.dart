import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final class _StashClient extends FixtureClient implements GitWorkflowClient {
  final identity = GitOid('a' * 40);
  String selector = 'stash@{0}';
  _StashClient() {
    historyCommits = [
      GitCommit(
        oid: identity,
        parents: [GitOid('b' * 40), GitOid('c' * 40)],
        subject: 'On main: Reviewed writing',
        author: 'Writer',
        email: 'writer@example.invalid',
        date: DateTime.utc(2026),
        message: 'On main: Reviewed writing',
      ),
    ];
  }

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    'hasMore': false,
    'entries': [
      {
        'identity': identity.value,
        'selector': selector,
        'message': 'On main: Reviewed writing',
        'time': 1790000000,
      },
    ],
  };

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Stash review cannot create a repository.');
}

void main() {
  Future<GitSession> showCreation(
    WidgetTester tester,
    FixtureClient client,
    List<GitChange> changes,
  ) async {
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    session.snapshot = GitSnapshot(
      repository: repo,
      token: 'stash-review',
      indexToken: 'reviewed-index',
      changes: changes,
      operation: const RepositoryOperation(GitOperationKind.none),
      observedAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHostScope(
            host: session.host,
            child: GitCreateStashView(session: session),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
    return session;
  }

  testWidgets(
    'stash creation explains an empty eligible set and cannot submit it',
    (tester) async {
      final client = FixtureClient();
      await showCreation(tester, client, []);
      expect(
        find.text('No eligible changes for these stash options.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create stash'),
            )
            .onPressed,
        isNull,
      );
      expect(client.mutations, isEmpty);
    },
  );

  testWidgets(
    'staged-only stash excludes hidden selections from its reviewed request',
    (tester) async {
      final client = FixtureClient()..pending = Completer<GitOutcome>();
      final staged = RepoPath.text('staged.md'),
          working = RepoPath.text('working.md'),
          untracked = RepoPath.text('untracked.md');
      await showCreation(tester, client, [
        GitChange(path: staged, index: 'M', worktree: '.'),
        GitChange(path: working, index: '.', worktree: 'M'),
        GitChange(path: untracked, index: '?', worktree: '?'),
      ]);
      await tester.tap(find.text('All eligible paths in this repository'));
      await tester.tap(find.text('Include untracked files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('staged.md'));
      await tester.tap(find.text('untracked.md'));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stash only staged changes (--staged)').last);
      await tester.pumpAndSettle();
      expect(find.text('working.md'), findsNothing);
      expect(find.text('untracked.md'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Create stash'));
      await tester.pump();
      final request = client.mutations.single as StashMutation;
      expect(request.paths, [staged]);
      expect(request.stagedOnly, isTrue);
      expect(request.includeUntracked, isFalse);
      expect(request.expectedIndex, 'reviewed-index');
      expect(request.expectedWorkingToken, 'stash-review');
      client.pending!.complete(
        const GitOutcome(phase: GitOperationPhase.failed, snapshot: null),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refreshing a stale stash review retains its name and eligible selection',
    (tester) async {
      final client = FixtureClient()..pending = Completer<GitOutcome>();
      await showCreation(tester, client, snapshot().changes);
      await tester.enterText(find.byType(TextField), 'Preserved stash name');
      await tester.tap(find.text('All eligible paths in this repository'));
      await tester.pump();
      await tester.tap(find.text('chapter/notes.md'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create stash'));
      await tester.pump();
      expect(client.mutations, hasLength(1));
      client.pending!.complete(
        const GitOutcome(
          phase: GitOperationPhase.failed,
          snapshot: null,
          error: GitException(GitErrorCode.staleReview),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Refresh'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Preserved stash name',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'chapter/notes.md'),
            )
            .value,
        isTrue,
      );
      client.pending = Completer<GitOutcome>();
      await tester.tap(find.widgetWithText(FilledButton, 'Create stash'));
      await tester.pump();
      final request = client.mutations.last as StashMutation;
      expect(request.expectedWorkingToken, snapshot().token);
      expect(request.expectedIndex, snapshot().indexToken);
      expect(request.message, 'Preserved stash name');
      expect(request.paths, [RepoPath.text('chapter/notes.md')]);
      client.pending!.complete(
        const GitOutcome(phase: GitOperationPhase.failed, snapshot: null),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large stash path selection materializes only viewport rows', (
    tester,
  ) async {
    final changes = List.generate(
      10000,
      (index) => GitChange(
        path: RepoPath.text('notes/${index.toString().padLeft(5, '0')}.md'),
        index: 'M',
        worktree: '.',
      ),
    );
    await showCreation(tester, FixtureClient(), changes);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(
      (list.childrenDelegate as SliverChildBuilderDelegate).childCount,
      changes.length,
    );
    expect(find.byType(CheckboxListTile).evaluate().length, lessThan(30));
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('notes/09999.md'), findsOneWidget);
    expect(find.byType(CheckboxListTile).evaluate().length, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'apply retains reviewed stash details and actions across selector changes',
    (tester) async {
      final client = _StashClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitStashesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('On main: Reviewed writing').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Apply and retain'));
      await tester.pumpAndSettle();
      final request = client.mutations.single as StashMutation;
      expect(request.action, StashAction.apply);
      expect(request.identity, client.identity);
      expect(request.restoreIndex, isTrue);
      expect(request.expectedWorkingToken, snapshot().token);

      // Another client may insert a newer stash without removing this object.
      client.selector = 'stash@{1}';
      await session.refresh();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Drop stash…'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Select a stash to inspect its changes'), findsNothing);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'On main: Reviewed writing'),
            )
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
