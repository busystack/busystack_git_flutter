import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _ReviewClient extends FixtureClient implements GitWorkflowClient {
  final plans = <GitInspection>[];
  final statusReads = <Completer<GitSnapshot>>[];
  bool delayStatus = false, hasRemote = true;
  Completer<Json>? options;
  GitSnapshot state(String oid) => GitSnapshot(
    repository: repo,
    token: 'review-$oid',
    indexToken: 'index-$oid',
    head: GitOid(oid * 40),
    branch: 'main',
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) {
    if (!delayStatus) return Future.value(state('a'));
    final read = Completer<GitSnapshot>();
    statusReads.add(read);
    return read.future;
  }

  @override
  Future<List<GitReference>> references(RepositoryId repository) async => [
    GitReference(name: 'refs/remotes/origin/main', oid: GitOid('a' * 40)),
  ];
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    switch (request.kind) {
      case GitInspectionKind.remotes:
        return {
          'remotes': [
            if (hasRemote)
              {
                'name': 'origin',
                'fetchUrls': ['/fixture/remote.git'],
                'pushUrls': ['/fixture/remote.git'],
              },
          ],
        };
      case GitInspectionKind.commitOptions:
        return options == null ? {'pushRemote': 'origin'} : options!.future;
      case GitInspectionKind.pushReview:
        plans.add(request);
        return {
          'token': 'plan-${plans.length}',
          'destination': request.destination,
          'outgoing': <Json>[],
          'destinations': [
            {'url': '/fixture/remote.git', 'expectedTip': 'a' * 40},
          ],
          'tags': <String, String>{},
          'forceAllowed': true,
          'needsFetch': false,
        };
      default:
        throw StateError('Unexpected request ${request.kind}');
    }
  }

  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    if (request is RemoteMutation && request.action == RemoteAction.add)
      hasRemote = true;
    return GitOutcome(phase: GitOperationPhase.completed, snapshot: state('a'));
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Not a creation workflow');
}

Future<GitSession> _mount(WidgetTester tester, _ReviewClient client) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: GitPushView(session: session)),
    ),
  );
  await tester.pump();
  return session;
}

void main() {
  testWidgets(
    'a missing configured publishing remote requires an explicit destination choice',
    (tester) async {
      final client = _ReviewClient()
        ..options = (Completer<Json>()..complete({'pushRemote': 'missing'}));
      await _mount(tester, client);
      await tester.pumpAndSettle();
      expect(client.plans, isEmpty);
      final remote = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Remote',
        ),
      );
      expect(remote.initialValue, isNull);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Push'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Push creates a missing remote through existing management and preserves a deliberately new branch',
    (tester) async {
      final client = _ReviewClient()..hasRemote = false;
      await _mount(tester, client);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'new remote branch'),
        'brand/new',
      );
      expect(client.plans, isEmpty);
      await tester.tap(find.text('Manage remotes…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add remote…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Remote name'),
        'origin',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Repository URL or local source'),
        '/fixture/remote.git',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(client.mutations.single, isA<RemoteMutation>());
      Navigator.of(tester.element(find.byType(GitRemotesView))).pop();
      await tester.pumpAndSettle();
      expect(client.plans.single.destination, 'refs/heads/brand/new');
      expect(find.text('brand/new'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Push'));
      await tester.pumpAndSettle();
      expect(client.mutations, hasLength(2));
      expect(client.mutations.last, isA<PushReviewed>());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'older identical Push review cannot replace a newer status snapshot',
    (tester) async {
      final client = _ReviewClient();
      await _mount(tester, client);
      await tester.pumpAndSettle();
      client.plans.clear();
      client.delayStatus = true;
      final review = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Review destinations'),
          )
          .onPressed!;
      review();
      await tester.pump();
      review(); // Deliberately exercise an already queued native callback.
      await tester.pump();
      expect(client.statusReads, hasLength(2));
      client.statusReads.last.complete(client.state('b'));
      await tester.pumpAndSettle();
      client.statusReads.first.complete(client.state('a'));
      await tester.pumpAndSettle();
      expect(client.plans, hasLength(1));
      expect(client.plans.single.revision, GitOid('b' * 40));
      expect(find.textContaining('bbbbbbb'), findsWidgets);
      expect(client.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'queued destination change invalidates force confirmation consent',
    (tester) async {
      final client = _ReviewClient();
      await _mount(tester, client);
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'new remote branch');
      // Choose new branch so the destination editor participates in the review.
      final chooser = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Destination reference',
        ),
      );
      chooser.onChanged!('__new__');
      await tester.pumpAndSettle();
      await tester.enterText(field, 'reviewed');
      await tester.tap(find.text('Review destinations'));
      await tester.pumpAndSettle();
      final changed = tester.widget<TextField>(field).onChanged!;
      await tester.tap(find.text('Force with reviewed lease…'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Force with lease'),
        findsOneWidget,
      );
      changed('different');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Force with lease'));
      await tester.pumpAndSettle();
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Push configuration cannot be edited before options finish loading',
    (tester) async {
      final client = _ReviewClient()..options = Completer<Json>();
      await _mount(tester, client);
      await tester.pump();
      final chooser = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Destination reference',
        ),
      );
      expect(chooser.onChanged, isNull);
      client.options!.complete({'pushRemote': 'origin'});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
