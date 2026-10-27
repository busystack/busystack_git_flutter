import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

class ControlledClient extends FixtureClient {
  int statusReads = 0;
  Completer<GitSnapshot>? read;
  GitCancellation? cancelledRead;
  GitException? readFailure;
  GitOutcome? result;
  GitSnapshot? state;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) {
    statusReads++;
    cancelledRead = cancellation;
    if (readFailure != null) return Future.error(readFailure!);
    return read?.future ?? Future.value(state ?? snapshot());
  }

  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    return result ??
        GitOutcome(phase: GitOperationPhase.completed, snapshot: snapshot());
  }
}

class PausedContentClient extends ControlledClient {
  final contentGate = Completer<void>();
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    await contentGate.future;
    return super.content(repository, path, version, cancellation: cancellation);
  }
}

void main() {
  testWidgets(
    'a repository refresh during content loading keeps staging stale',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = PausedContentClient();
      final session = GitSession(
        client: client,
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
                RepoPath.text('chapter/notes.md'),
                const ContentVersion.index(),
                const ContentVersion.working(),
              ),
            ),
          ),
        ),
      );
      client.state = GitSnapshot(
        repository: repo,
        token: 'external',
        indexToken: 'external-index',
        changes: snapshot().changes,
        operation: const RepositoryOperation(GitOperationKind.none),
        observedAt: DateTime.utc(2026),
      );
      await session.refresh();
      client.contentGate.complete();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The reviewed index or working content changed.'),
        findsOneWidget,
      );
      expect(find.text('Stage selected changed lines'), findsNothing);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'opening a file diff reuses the observed repository snapshot and explicit refresh scans once',
    (tester) async {
      final client = ControlledClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      expect(client.statusReads, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitDiffView(
              session: session,
              comparison: GitComparison(
                RepoPath.text('chapter/notes.md'),
                const ContentVersion.index(),
                const ContentVersion.working(),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(client.statusReads, 1);
      expect(find.text('Stage selected changed lines'), findsOneWidget);
      expect(find.textContaining('Read-only comparison'), findsNothing);
      await tester.tap(find.byTooltip('Refresh comparison'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(client.statusReads, 2);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'historical comparisons identify read-only review without staging selection',
    (tester) async {
      final client = ControlledClient();
      final session = GitSession(
        client: client,
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
                RepoPath.text('chapter/notes.md'),
                ContentVersion(ContentKind.commit, revision: GitOid('1' * 40)),
                ContentVersion(ContentKind.commit, revision: GitOid('2' * 40)),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Read-only comparison'), findsOneWidget);
      expect(find.textContaining('changed lines selected'), findsNothing);
      expect(find.text('Stage whole file'), findsNothing);
      expect(find.text('Unstage whole file'), findsNothing);
      expect(find.text('Stage selected changed lines'), findsNothing);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'host translations apply to UI labels without translating repository filenames',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = host();
      final translated = GitHost(
        present: original.present,
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: original.drafts,
        translate: (key, fallback) => switch (fallback) {
          'Staged' => 'Im Index',
          'Unstaged' => 'Arbeitskopie',
          'Commit message' => 'Commit-Nachricht',
          'Stage file' => 'Datei vormerken',
          'notes.md' => 'must never be used',
          _ => fallback,
        },
      );
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: translated,
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
      expect(find.text('Im Index (1)'), findsOneWidget);
      expect(find.text('Arbeitskopie (1)'), findsOneWidget);
      expect(find.text('notes.md'), findsNWidgets(2));
      expect(find.text('must never be used'), findsNothing);
      expect(find.byTooltip('Datei vormerken'), findsOneWidget);
      expect(find.text('Commit-Nachricht'), findsOneWidget);
      session.dispose();
    },
  );
  testWidgets(
    'external snapshot changes mark an open mutable diff stale until explicit review refresh',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ControlledClient(),
          session = GitSession(
            client: ControlledClient(),
            repository: repo,
            host: host(),
          );
      final target = GitSession(client: client, repository: repo, host: host());
      await session.start();
      await target.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitDiffView(
              session: target,
              comparison: GitComparison(
                RepoPath.text('chapter/notes.md'),
                const ContentVersion.index(),
                const ContentVersion.working(),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      client.state = GitSnapshot(
        repository: repo,
        token: 'external',
        indexToken: 'external-index',
        changes: snapshot().changes,
        operation: const RepositoryOperation(GitOperationKind.none),
        observedAt: DateTime.utc(2026),
      );
      await target.refresh();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The reviewed index or working content changed.'),
        findsOneWidget,
      );
      expect(find.text('Stage selected changed lines'), findsNothing);
      expect(client.mutations, isEmpty);
      await tester.tap(find.text('Refresh comparison'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The reviewed index or working content changed.'),
        findsNothing,
      );
      expect(find.text('Stage selected changed lines'), findsOneWidget);
      target.dispose();
      session.dispose();
    },
  );
  test(
    'a pending read cannot replace a mutation result and background refresh preserves actionable failures',
    () async {
      final client = ControlledClient(),
          session = GitSession(
            client: ControlledClient(),
            repository: repo,
            host: host(),
          );
      final target = GitSession(client: client, repository: repo, host: host());
      await target.start();
      await session.start();
      client.read = Completer<GitSnapshot>();
      final pending = target.refresh();
      final cancellation = client.cancelledRead!;
      const failure = GitException(
        GitErrorCode.staleReview,
        diagnostic: 'Index changed elsewhere',
      );
      client.result = GitOutcome(
        phase: GitOperationPhase.failed,
        snapshot: snapshot(),
        error: failure,
      );
      target.setDraft('retained');
      await target.mutate(
        CommitIndex('retained', expectedHead: null, expectedIndex: 'index'),
      );
      expect(cancellation.isCancelled, isTrue);
      client.read!.complete(
        GitSnapshot(
          repository: repo,
          token: 'obsolete',
          indexToken: 'old',
          changes: [],
          operation: const RepositoryOperation(GitOperationKind.none),
          observedAt: DateTime.utc(2025),
        ),
      );
      await pending;
      expect(target.snapshot!.token, 'review');
      expect(target.failure, same(failure));
      client.read = null;
      await target.refresh();
      expect(target.failure, same(failure));
      await target.refresh(clearOperationFailure: true);
      expect(target.failure, isNull);
      client.readFailure = const GitException(GitErrorCode.disconnected);
      await target.refresh();
      expect(target.snapshot!.changes, hasLength(1));
      expect(target.failure!.code, GitErrorCode.disconnected);
      expect(target.draft, 'retained');
      target.dispose();
      session.dispose();
    },
  );
  test('invalid persisted view preferences fall back without crashing', () {
    final session = GitSession(
      client: FixtureClient(),
      repository: repo,
      host: host(),
    );
    session.viewState = {
      'split': 'invalid',
      'wrap': 7,
      'nan': double.nan,
      'large': 99,
    };
    expect(session.split('split', .3), .3);
    expect(session.split('nan', .4), .4);
    expect(session.split('large', .3), .95);
    expect(session.option('wrap', true), isTrue);
    session.dispose();
  });
  testWidgets(
    'an uncertain commit retains the draft and never opens push or repeats the mutation',
    (tester) async {
      final client = ControlledClient(),
          session = GitSession(
            client: FixtureClient(),
            repository: repo,
            host: host(),
          );
      final target = GitSession(client: client, repository: repo, host: host());
      await session.start();
      await target.start();
      client.result = GitOutcome(
        phase: GitOperationPhase.uncertain,
        snapshot: snapshot(),
        createdCommit: GitOid('b' * 40),
        error: const GitException(
          GitErrorCode.uncertainOutcome,
          diagnostic: 'Review the resulting commit',
        ),
      );
      var pushes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitCommitView(
              session: target,
              onReview: (_) {},
              onLog: () {},
              onBranches: () {},
              onPush: () => pushes++,
              onMore: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'message stays');
      await tester.pump();
      await tester.tap(find.text('Commit and Push…'));
      await tester.pumpAndSettle();
      expect(client.mutations, hasLength(1));
      expect(pushes, 0);
      expect(target.draft, 'message stays');
      expect(find.text('message stays'), findsOneWidget);
      expect(find.byType(GitFailurePanel), findsOneWidget);
      target.dispose();
      session.dispose();
    },
  );
  testWidgets(
    'stale index write preserves editable result and explicit reload control',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ControlledClient(),
          session = GitSession(
            client: ControlledClient(),
            repository: repo,
            host: host(),
          );
      final target = GitSession(client: client, repository: repo, host: host());
      await target.start();
      await session.start();
      client.result = GitOutcome(
        phase: GitOperationPhase.failed,
        snapshot: snapshot(),
        error: const GitException(GitErrorCode.staleReview),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitIndexEditor(session: target, path: RepoPath.text('a')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate((w) => w is TextField && !w.readOnly),
        'manual index result\n',
      );
      await tester.tap(find.text('Write edited result to this index entry'));
      await tester.pumpAndSettle();
      expect(client.mutations.single, isA<WriteIndex>());
      expect(find.text('manual index result\n'), findsOneWidget);
      expect(find.text('Reload versions…'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is TextField && !w.readOnly),
        findsOneWidget,
      );
      expect(find.byType(GitFailurePanel), findsOneWidget);
      target.dispose();
      session.dispose();
    },
  );
  testWidgets(
    'narrow three-pane review exposes sources without losing the result draft',
    (tester) async {
      final result = TextEditingController(text: 'manual result');
      addTearDown(result.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: GitRevisionPanes(
                labels: const ['Left source', 'Result', 'Right source'],
                panes: [
                  (scroll) => GitTextPane(
                    label: 'Actual left revision',
                    text: 'left text',
                    scrollController: scroll,
                  ),
                  (scroll) => GitTextPane(
                    label: 'Editable result',
                    controller: result,
                    scrollController: scroll,
                  ),
                  (scroll) => GitTextPane(
                    label: 'Actual right revision',
                    text: 'right text',
                    scrollController: scroll,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'saved manual draft');
      await tester.tap(find.text('Left source'));
      await tester.pumpAndSettle();
      expect(find.text('left text'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is TextField && !w.readOnly),
        findsNothing,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.text('Right source'));
      await tester.pumpAndSettle();
      expect(find.text('right text'), findsOneWidget);
      await tester.tap(find.text('Result'));
      await tester.pumpAndSettle();
      expect(find.text('saved manual draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching to Log removes Commit semantics and preserves its message on return',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final client = FixtureClient()
        ..historyCommits = [
          GitCommit(
            oid: GitOid('a' * 40),
            parents: [],
            subject: 'Actual commit row',
            author: 'Fixture author',
            email: 'fixture@example.invalid',
            date: DateTime.utc(2026),
          ),
        ];
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitWorkspace(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a retained draft');
      await tester.tap(find.text('Log').first);
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsOneWidget);
      expect(find.bySemanticsLabel('Commit message'), findsNothing);
      expect(find.text('Actual commit row'), findsOneWidget);
      expect(find.text('a retained draft'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Commit').first);
      await tester.pumpAndSettle();
      expect(find.text('a retained draft'), findsOneWidget);
      session.dispose();
      semantics.dispose();
    },
  );
  testWidgets(
    'Log keeps branch identity and a recovered operation visible across refresh',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ControlledClient()
        ..state = GitSnapshot.fromJson({
          ...snapshot().toJson(),
          'branch': 'writing/main',
          'head': 'a' * 40,
        });
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      var branchReviews = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitWorkspace(
              session: session,
              onBranches: () => branchReviews++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'preserved commit draft');
      await tester.tap(find.text('Log').first);
      await tester.pumpAndSettle();
      expect(find.text(repo.root), findsOneWidget);
      expect(find.text('writing/main'), findsOneWidget);
      await tester.tap(find.text('writing/main'));
      expect(branchReviews, 1);
      final filter = find.widgetWithText(TextField, 'Message');
      await tester.enterText(filter, 'preserved history filter');
      client.state = GitSnapshot.fromJson({
        ...snapshot().toJson(),
        'head': 'b' * 40,
        'operation': const RepositoryOperation(
          GitOperationKind.merge,
          unmerged: true,
        ).toJson(),
      });
      await session.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('Detached HEAD · ${GitOid('b' * 40).abbreviated}'),
        findsOneWidget,
      );
      expect(
        find.text('Merge in progress · unresolved conflicts'),
        findsOneWidget,
      );
      expect(find.text('Review operation'), findsOneWidget);
      expect(find.text('preserved history filter'), findsOneWidget);
      await tester.tap(find.text('Commit').first);
      await tester.pumpAndSettle();
      expect(find.text('preserved commit draft'), findsOneWidget);
      expect(find.text('Review operation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
