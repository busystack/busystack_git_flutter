import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final class _PolicyClient extends FixtureClient implements GitWorkflowClient {
  _PolicyClient(this.rebase, {this.ff});
  final String rebase;
  final String? ff;
  final inspections = <GitInspection>[];
  bool fetched = false;
  @override
  Future<List<GitReference>> references(RepositoryId repository) async => [
    for (final name in [
      'review/main',
      'feature',
      if (fetched) 'fetched/source',
    ])
      GitReference(
        name: 'refs/remotes/team/upstream/$name',
        oid: GitOid('a' * 40),
      ),
    GitReference(
      name: 'refs/remotes/my/publish/existing',
      oid: GitOid('b' * 40),
    ),
  ];
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    token: 'review',
    indexToken: 'reviewed-index',
    head: GitOid('a' * 40),
    branch: 'topic',
    upstream: 'team/upstream/review/main',
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    inspections.add(request);
    return switch (request.kind) {
      GitInspectionKind.remotes => {
        'remotes': [
          for (final name in ['team', 'team/upstream', 'my/publish'])
            {
              'name': name,
              'fetchUrls': ['/fixture/remote.git'],
              'pushUrls': ['/fixture/remote.git'],
            },
        ],
      },
      GitInspectionKind.commitOptions => {
        'upstreamRemote': 'team/upstream',
        'upstreamBranch': 'refs/heads/review/main',
        'pushRemote': 'my/publish',
        'pullRebase': rebase,
        'pullFf': ff,
      },
      GitInspectionKind.pushReview => {
        'token': 'destination-review',
        'outgoing': <Json>[],
        'destinations': [
          {'url': '/fixture/remote.git', 'expectedTip': 'b' * 40},
        ],
        'tags': <String, String>{},
        'forceAllowed': true,
        'needsFetch': false,
      },
      _ => throw StateError('Unexpected inspection ${request.kind}'),
    };
  }

  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    if (pending != null) return pending!.future;
    if (request is FetchRemote) fetched = true;
    return GitOutcome(
      phase: GitOperationPhase.completed,
      snapshot: await status(repository),
    );
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Network review cannot create repositories.');
}

Future<void> _show(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: SizedBox(
                  width: 700,
                  child: SingleChildScrollView(child: child),
                ),
              ),
            ),
            child: const Text('Open review'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'queued Pull submit cannot act after its reviewed source changes',
    (tester) async {
      final client = _PolicyClient('false');
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await session.start();
      await _show(tester, GitPullView(session: session));
      final oldSubmit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Pull with selected strategy'),
          )
          .onPressed!;
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byWidgetPredicate(
              (w) =>
                  w is DropdownButtonFormField<String> &&
                  w.decoration.labelText == 'Source branch',
            ),
          )
          .onChanged!('feature');
      await tester.pump();
      oldSubmit();
      await tester.pumpAndSettle();
      expect(client.mutations, isEmpty);
      await tester.tap(find.text('Pull with selected strategy'));
      await tester.pumpAndSettle();
      expect((client.mutations.single as PullRemote).branch, 'feature');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'source remote with a shorter name cannot borrow another remotes cached branches',
    (tester) async {
      final client = _PolicyClient('false');
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await session.start();
      await _show(tester, GitPullView(session: session));
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byWidgetPredicate(
              (w) =>
                  w is DropdownButtonFormField<String> &&
                  w.decoration.labelText == 'Source remote',
            ),
          )
          .onChanged!('team');
      await tester.pump();
      final source = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Source branch',
        ),
      );
      expect(source.initialValue, isNull);
      expect(source.onChanged, isNull);
      expect(client.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Pull identifies cached branches and explicitly fetches without losing source or strategy',
    (tester) async {
      final client = _PolicyClient('merges');
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await session.start();
      await _show(tester, GitPullView(session: session));
      expect(find.text('Cached tracking'), findsOneWidget);
      expect(client.mutations, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, 'Fetch'));
      await tester.pumpAndSettle();
      final remote = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Remote to fetch',
        ),
      );
      expect(remote.initialValue, 'team/upstream');
      await tester.tap(find.widgetWithText(FilledButton, 'Fetch'));
      await tester.pumpAndSettle();
      expect(client.mutations.single, isA<FetchRemote>());
      expect(find.byType(GitFetchView), findsNothing);
      final source = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Source branch',
        ),
      );
      expect(source.initialValue, 'review/main');
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Source branch',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('fetched/source'), findsOneWidget);
      await tester.tap(find.text('fetched/source'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<PullStrategy>>(
              find.byType(DropdownButtonFormField<PullStrategy>),
            )
            .initialValue,
        PullStrategy.rebase,
      );
      await tester.tap(find.text('Pull with selected strategy'));
      await tester.pumpAndSettle();
      expect(client.mutations, hasLength(2));
      final pull = client.mutations.last as PullRemote;
      expect(pull.remote, 'team/upstream');
      expect(pull.branch, 'fetched/source');
      expect(pull.strategy, PullStrategy.rebase);
      expect(pull.preserveMerges, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'uncertain push retains a reconciliation warning until destinations are reviewed',
    (tester) async {
      final client = _PolicyClient('true')..pending = Completer<GitOutcome>();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitPushView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Push'));
      await tester.pump();
      expect(client.mutations.single, isA<PushReviewed>());
      client.pending!.complete(
        GitOutcome(
          phase: GitOperationPhase.uncertain,
          snapshot: await client.status(repo),
          error: const GitException(GitErrorCode.cancelled),
        ),
      );
      await tester.pumpAndSettle();
      const warning =
          'The operation needs reconciliation. Review the resulting repository or remote state before repeating it.';
      expect(find.text(warning), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Push'))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(warning), findsOneWidget);
      expect(client.mutations, hasLength(1));
      await tester.tap(find.text('Review destinations'));
      await tester.pumpAndSettle();
      expect(
        client.inspections.where((e) => e.kind == GitInspectionKind.pushReview),
        hasLength(2),
      );
      expect(find.text(warning), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Push'))
            .onPressed,
        isNotNull,
      );
      expect(client.mutations, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  for (final preserving in [false, true]) {
    testWidgets(
      'pull reviews complete upstream and configured policy ($preserving)',
      (tester) async {
        final client = _PolicyClient(
          preserving ? 'merges' : 'false',
          ff: preserving ? null : 'false',
        );
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        await _show(tester, GitPullView(session: session));
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byWidgetPredicate(
                  (w) =>
                      w is DropdownButtonFormField<String> &&
                      w.decoration.labelText == 'Source remote',
                ),
              )
              .initialValue,
          'team/upstream',
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is DropdownButtonFormField<String> &&
                      widget.decoration.labelText == 'Source branch',
                ),
              )
              .initialValue,
          'review/main',
        );
        expect(
          find.text(
            preserving
                ? 'Rebase local history while preserving local merge commits.'
                : 'Merge with a merge commit, including when fast-forward is possible.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Pull with selected strategy'));
        await tester.pumpAndSettle();
        final request = client.mutations.single as PullRemote;
        expect(request.remote, 'team/upstream');
        expect(request.branch, 'review/main');
        expect(
          request.strategy,
          preserving ? PullStrategy.rebase : PullStrategy.merge,
        );
        expect(request.preserveMerges, preserving);
        expect(request.noFastForward, !preserving);
        expect(request.expectedHead, GitOid('a' * 40));
        expect(request.expectedIndex, 'reviewed-index');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets(
    'interactive pull preference requires an explicit ordinary strategy',
    (tester) async {
      final client = _PolicyClient('interactive');
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await _show(tester, GitPullView(session: session));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Pull with selected strategy'),
            )
            .onPressed,
        isNull,
      );
      expect(client.mutations, isEmpty);
      await tester.tap(find.text('Use reviewed ordinary rebase for this pull'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pull with selected strategy'));
      await tester.pumpAndSettle();
      expect(
        (client.mutations.single as PullRemote).strategy,
        PullStrategy.rebase,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('Pull source choices follow the selected remote', (tester) async {
    final client = _PolicyClient('false');
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await _show(tester, GitPullView(session: session));
    final source = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Source branch',
    );
    await tester.tap(source);
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsOneWidget);
    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull with selected strategy'));
    await tester.pumpAndSettle();
    expect((client.mutations.single as PullRemote).branch, 'feature');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'Push selects existing destinations and invalidates prior review',
    (tester) async {
      final client = _PolicyClient('false');
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitPushView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      final destination = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Destination reference',
      );
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(find.text('existing'), findsOneWidget);
      await tester.tap(find.text('existing'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a destination and review the outgoing commits.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Review destinations'));
      await tester.pumpAndSettle();
      expect(client.inspections.last.destination, 'refs/heads/existing');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'push uses the configured publishing remote without splitting its name',
    (tester) async {
      final client = _PolicyClient('true');
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitPushView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      final review = client.inspections.singleWhere(
        (e) => e.kind == GitInspectionKind.pushReview,
      );
      expect(review.remote, 'my/publish');
      expect(review.destination, 'refs/heads/topic');
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
