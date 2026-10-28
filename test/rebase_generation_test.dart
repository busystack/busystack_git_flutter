import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

GitOid oid(int value) => GitOid(value.toRadixString(16).padLeft(40, '0'));
GitCommit commit(int value) => GitCommit(
  oid: oid(value),
  parents: [oid(value - 1)],
  subject: 'Commit $value',
  author: 'Fixture',
  email: 'fixture@example.test',
  date: DateTime.utc(2026),
  message: 'Message $value',
);
HistoryPage page(int value) =>
    HistoryPage([commit(value)], nextOffset: 1, hasMore: false, anchor: 'refs');
Json plan({String token = 'plan'}) => {
  'token': token,
  'head': oid(9).value,
  'index': 'index',
  'boundaryExcluded': oid(1).value,
  'todo': '',
  'steps': [
    for (final i in [2, 3])
      {
        'commit': oid(i).value,
        'action': 'pick',
        'subject': 'Commit $i',
        'block': 0,
        'modifier': '',
      },
  ],
};

final class RebaseClient extends FixtureClient implements GitWorkflowClient {
  final plans = <Completer<Json>>[];
  final requests = <GitInspection>[];
  final details = <(HistoryFilter, Completer<HistoryPage>, GitCancellation?)>[];
  List<GitReference> refs = [];
  bool delayDetails = true;
  GitSnapshot? state;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => state ?? snapshot();
  @override
  Future<List<GitReference>> references(RepositoryId repository) async => refs;
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) {
    if (!delayDetails)
      return Future.value(
        page(filter.reference?.endsWith('3') == true ? 3 : 2),
      );
    final pending = Completer<HistoryPage>();
    details.add((filter, pending, cancellation));
    return pending.future;
  }

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) {
    requests.add(request);
    final pending = Completer<Json>();
    plans.add(pending);
    return pending.future;
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Unused');
}

Future<GitSession> showRebase(
  WidgetTester tester,
  RebaseClient client, {
  bool fromLog = true,
  Size size = const Size(1280, 1000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: GitHostScope(
          host: session.host,
          child: GitRebaseView(
            session: session,
            boundary: fromLog ? oid(1) : null,
          ),
        ),
      ),
    ),
  );
  return session;
}

Future<void> prepare(WidgetTester tester, RebaseClient client) async {
  await tester.tap(find.text('Prepare Git plan'));
  await tester.pump();
  client.plans.last.complete(plan());
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'old detail success after clearing plan cannot index an empty selection',
    (tester) async {
      final client = RebaseClient();
      await showRebase(tester, client);
      await prepare(tester, client);
      expect(client.details, hasLength(1));
      await tester.tap(find.text('Include root commits'));
      await tester.pump();
      client.details.first.$2.complete(page(2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(GitCommitFiles), findsNothing);
      expect(client.details.first.$3!.isCancelled, isTrue);
    },
  );
  testWidgets(
    'superseded plan response cannot repopulate a cleared or replaced plan',
    (tester) async {
      final client = RebaseClient();
      await showRebase(tester, client);
      await tester.tap(find.text('Prepare Git plan'));
      await tester.pump();
      await tester.tap(find.text('Autosquash'));
      await tester.pump();
      await tester.tap(find.text('Prepare Git plan'));
      await tester.pump();
      client.plans.last.complete(plan(token: 'new'));
      await tester.pump();
      await tester.pump();
      client.plans.first.complete(plan(token: 'old'));
      await tester.pump();
      expect(client.details, hasLength(1));
      expect(tester.takeException(), isNull);
      client.details.single.$2.complete(page(2));
      await tester.pump();
      expect(find.byType(GitCommitFiles), findsOneWidget);
    },
  );
  testWidgets(
    'rapid selection including returning to same commit ignores older success and error',
    (tester) async {
      final client = RebaseClient();
      await showRebase(tester, client);
      await prepare(tester, client);
      await tester.tap(find.text('Commit 3'));
      await tester.pump();
      await tester.tap(find.text('Commit 2'));
      await tester.pump();
      expect(client.details, hasLength(3));
      client.details.last.$2.complete(page(2));
      await tester.pump();
      client.details.first.$2.completeError(
        const GitException(GitErrorCode.disconnected),
      );
      client.details[1].$2.complete(page(3));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<GitCommitFiles>(find.byType(GitCommitFiles)).commit.oid,
        oid(2),
      );
      expect(find.byType(GitFailurePanel), findsNothing);
    },
  );
  testWidgets(
    'reorder during detail read follows the selected commit identity',
    (tester) async {
      final client = RebaseClient();
      await showRebase(tester, client);
      await prepare(tester, client);
      await tester.tap(find.text('Move down'));
      await tester.pump();
      client.details.single.$2.complete(page(2));
      await tester.pump();
      expect(
        tester.widget<GitCommitFiles>(find.byType(GitCommitFiles)).commit.oid,
        oid(2),
      );
    },
  );
  testWidgets(
    'changing new base or boundary while detail read is pending invalidates it',
    (tester) async {
      for (final title in [
        'Same as upstream boundary',
        '${oid(1).abbreviated} · ${oid(1).abbreviated}',
      ]) {
        final client = RebaseClient();
        await showRebase(tester, client);
        await prepare(tester, client);
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select commit in Log…'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        // Resolve the Log initial page, then select its real revision.
        client.details.last.$2.complete(page(3));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select this commit'));
        await tester.pumpAndSettle();
        client.details.first.$2.complete(page(2));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(GitCommitFiles), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'changed HEAD while a detail read is pending invalidates its plan',
    (tester) async {
      final client = RebaseClient();
      final session = await showRebase(tester, client);
      await prepare(tester, client);
      session.snapshot = GitSnapshot.fromJson({
        ...snapshot().toJson(),
        'head': oid(6).value,
      });
      session.notifyListeners();
      await tester.pump();
      client.details.single.$2.completeError(
        const GitException(GitErrorCode.disconnected),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(GitCommitFiles), findsNothing);
      expect(
        tester.widget<GitFailurePanel>(find.byType(GitFailurePanel)).error.code,
        GitErrorCode.staleReview,
      );
    },
  );

  testWidgets('merge preservation changes invalidate pending plan reads', (
    tester,
  ) async {
    final client = RebaseClient();
    await showRebase(tester, client);
    await tester.tap(find.text('Prepare Git plan'));
    await tester.pump();
    await tester.tap(find.text('Flatten history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Preserve branch structure').last);
    await tester.pump();
    client.plans.single.complete(plan());
    await tester.pump();
    expect(client.details, isEmpty);
    expect(tester.takeException(), isNull);
    expect(find.byType(GitCommitFiles), findsNothing);
  });

  testWidgets('empty plans and a closed view never launch obsolete details', (
    tester,
  ) async {
    final client = RebaseClient();
    await showRebase(tester, client);
    await tester.tap(find.text('Prepare Git plan'));
    await tester.pump();
    client.plans.single.complete({...plan(), 'steps': <Json>[]});
    await tester.pump();
    expect(client.details, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Prepare Git plan'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    client.plans.last.complete(plan());
    await tester.pump();
    expect(client.details, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branches and tags are searchable without entering object IDs', (
    tester,
  ) async {
    final client = RebaseClient()..delayDetails = false;
    client.refs = [
      GitReference(name: 'refs/heads/topic', oid: oid(2), current: true),
      GitReference(name: 'refs/tags/release/東京', oid: oid(8), type: 'tag'),
    ];
    await showRebase(tester, client);
    await tester.tap(find.text('Same as upstream boundary'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '東京');
    await tester.pump();
    expect(find.text('topic'), findsNothing);
    await tester.tap(find.text('release/東京'));
    await tester.pumpAndSettle();
    expect(find.text('release/東京 · ${oid(2).abbreviated}'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Prepare Git plan'));
    await tester.pump();
    client.plans.single.complete(plan());
    await tester.pumpAndSettle();
    expect(find.byType(GitCommitFiles), findsOneWidget);
    // A tag can move without HEAD moving. A reviewed reference must stay bound
    // to the original tag object rather than silently renewing consent.
    client.refs = [
      GitReference(name: 'refs/tags/release/東京', oid: oid(7), type: 'tag'),
    ];
    await tester.tap(find.text('Start rebase'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start rebase').last);
    await tester.pumpAndSettle();
    expect(client.mutations, isEmpty);
    expect(
      tester.widget<GitFailurePanel>(find.byType(GitFailurePanel)).error.code,
      GitErrorCode.staleReview,
    );
  });
  for (final annotatedTag in [false, true]) {
    testWidgets(
      '${annotatedTag ? 'annotated tag' : 'branch'} target retains its reviewed object across delayed A to B to A movement',
      (tester) async {
        final reference = GitReference(
          name: annotatedTag ? 'refs/tags/release' : 'refs/heads/topic',
          oid: oid(8),
          type: annotatedTag ? 'tag' : 'commit',
        );
        final peeledCommit = annotatedTag ? 5 : 8;
        final client = RebaseClient()..refs = [reference];
        await showRebase(tester, client);
        await tester.tap(find.text('Same as upstream boundary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(reference.shortName));
        await tester.pump();
        final pending = client.details.single;

        // Resolve the delayed Git query while another client has moved the
        // name. The name returns to its original object before the fresh refs
        // query, so comparing the final tip alone cannot detect this race.
        client.refs = [
          GitReference(
            name: reference.name,
            oid: oid(12),
            type: reference.type,
          ),
        ];
        final resolvedCommit = pending.$1.reference == reference.name
            ? 12
            : pending.$1.reference == reference.oid.value
            ? peeledCommit
            : throw StateError('Unexpected revision ${pending.$1.reference}');
        client.refs = [reference];
        pending.$2.complete(page(resolvedCommit));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Prepare Git plan'));
        await tester.pump();
        expect(client.requests.single.otherRevision, oid(peeledCommit));
        expect(find.byType(GitFailurePanel), findsNothing);
        client.plans.single.complete({...plan(), 'steps': <Json>[]});
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'an action callback from an obsolete row cannot edit its replacement plan',
    (tester) async {
      final client = RebaseClient();
      await showRebase(tester, client);
      await prepare(tester, client);
      final oldAction = tester
          .widget<DropdownButton<RebaseAction>>(
            find
                .byWidgetPredicate(
                  (widget) => widget is DropdownButton<RebaseAction>,
                )
                .first,
          )
          .onChanged!;
      await tester.tap(find.text('Autosquash'));
      await tester.pump();
      await prepare(tester, client);
      oldAction(RebaseAction.drop);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<DropdownButton<RebaseAction>>(
              find
                  .byWidgetPredicate(
                    (widget) => widget is DropdownButton<RebaseAction>,
                  )
                  .first,
            )
            .value,
        RebaseAction.pick,
      );
      client.details.first.$2.complete(page(2));
      client.details.last.$2.complete(page(2));
      await tester.pump();
    },
  );
  testWidgets(
    'a changed constructor boundary supersedes pending details and prepares the new boundary',
    (tester) async {
      final client = RebaseClient();
      final session = await showRebase(tester, client);
      await prepare(tester, client);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitHostScope(
              host: session.host,
              child: GitRebaseView(session: session, boundary: oid(8)),
            ),
          ),
        ),
      );
      client.details.single.$2.complete(page(2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(GitCommitFiles), findsNothing);
      await tester.tap(find.text('Prepare Git plan'));
      await tester.pump();
      expect(client.requests.last.revision, oid(8));
      client.plans.last.complete(plan());
      await tester.pump();
      await tester.pump();
      client.details.last.$2.complete(page(2));
      await tester.pump();
    },
  );
  testWidgets(
    'configured upstream is visible and selected without an object ID field',
    (tester) async {
      final client = RebaseClient()
        ..state = GitSnapshot.fromJson({
          ...snapshot().toJson(),
          'head': oid(9).value,
          'branch': 'writing/topic',
          'upstream': 'origin/main',
        });
      client.refs = [
        GitReference(
          name: 'refs/heads/writing/topic',
          oid: oid(9),
          current: true,
          upstream: 'refs/remotes/origin/main',
        ),
        GitReference(name: 'refs/remotes/origin/main', oid: oid(1)),
      ];
      await showRebase(tester, client, fromLog: false);
      await tester.pump();
      expect(find.text('Current branch: writing/topic'), findsOneWidget);
      expect(find.text('origin/main · ${oid(1).abbreviated}'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Prepare Git plan'));
      await tester.pump();
      expect(client.requests.single.revision, oid(1));
      client.plans.single.complete(plan());
      await tester.pump();
      await tester.pump();
      client.details.single.$2.complete(page(2));
      await tester.pump();
    },
  );
  testWidgets('detached HEAD remains explicit and needs a reviewed target', (
    tester,
  ) async {
    final client = RebaseClient()
      ..state = GitSnapshot.fromJson({
        ...snapshot().toJson(),
        'head': oid(9).value,
      });
    await showRebase(tester, client, fromLog: false);
    await tester.pump();
    expect(find.text('Current branch: Detached HEAD'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Prepare Git plan'),
          )
          .onPressed,
      isNull,
    );
    expect(client.plans, isEmpty);
  });
  testWidgets(
    'a missing or substituted selected commit is a review failure, not stale details',
    (tester) async {
      final client = RebaseClient();
      await showRebase(tester, client);
      await prepare(tester, client);
      client.details.single.$2.complete(
        HistoryPage([], nextOffset: 0, hasMore: false, anchor: 'refs'),
      );
      await tester.pump();
      expect(
        tester.widget<GitFailurePanel>(find.byType(GitFailurePanel)).error.code,
        GitErrorCode.missingContent,
      );
      await tester.tap(find.text('Commit 3'));
      await tester.pump();
      expect(find.byType(GitFailurePanel), findsNothing);
      client.details.last.$2.complete(page(2));
      await tester.pump();
      expect(
        tester.widget<GitFailurePanel>(find.byType(GitFailurePanel)).error.code,
        GitErrorCode.staleReview,
      );
      expect(find.byType(GitCommitFiles), findsNothing);
    },
  );
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'rebase actions stay reachable at 1280×800 and text scale $scale',
      (tester) async {
        final client = RebaseClient();
        await showRebase(
          tester,
          client,
          size: const Size(1280, 800),
          textScale: scale,
        );
        await tester.ensureVisible(find.text('Prepare Git plan'));
        await prepare(tester, client);
        expect(tester.takeException(), isNull);
        expect(find.text('Start rebase').hitTestable(), findsOneWidget);
        expect(find.text('Cancel plan').hitTestable(), findsOneWidget);
        client.details.single.$2.complete(page(2));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
