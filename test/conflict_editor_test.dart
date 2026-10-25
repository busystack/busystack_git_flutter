import 'dart:convert';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final class ConflictClient extends FixtureClient implements GitWorkflowClient {
  final path = RepoPath.text('prose.md');
  final ids = [for (var i = 1; i <= 3; i++) GitOid('$i' * 40)];
  bool raced = false;
  String prefix = '';
  String workingLineEnding = '\n';
  int reads = 0;
  String left = 'Introduction\nCurrent prose\nConclusion\n',
      right = 'Introduction\nIncoming prose\nConclusion\n';
  String get working =>
      'Introduction\n<<<<<<< HEAD\nCurrent prose\n=======\nIncoming prose\n>>>>>>> incoming\nConclusion\n'
          .replaceAll('\n', workingLineEnding);
  String get preview =>
      'Introduction\n${'<' * 32} FIXTURE_LEFT\nCurrent prose\n${'|' * 32} FIXTURE_BASE\nOriginal prose\n${'=' * 32}\nIncoming prose\n${'>' * 32} FIXTURE_RIGHT\nConclusion\n';
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    token: raced && ++reads > 1 ? 'changed' : 'review',
    indexToken: 'conflicted-index',
    head: ids.first,
    operation: RepositoryOperation(
      GitOperationKind.merge,
      head: ids.first,
      other: ids.last,
      unmerged: true,
    ),
    changes: [GitChange(path: path, index: 'U', worktree: 'U')],
    observedAt: DateTime.utc(2026),
  );
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    'kind': 'content',
    'baseAvailable': true,
    'marker': 'FIXTURE',
    'leftLabel': 'Current history · 1111111',
    'rightLabel': 'Incoming content · 3333333',
    'leftRevision': ids.first.value,
    'rightRevision': ids.last.value,
    'working': {'token': 'working-bytes'},
    'stages': {
      for (var stage = 1; stage <= 3; stage++)
        '$stage': {'mode': '100644', 'oid': ids[stage - 1].value},
    },
  };
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    mode: '100644',
    oid: version.kind == ContentKind.conflictStage
        ? ids[version.stage - 1]
        : null,
    token: version.kind == ContentKind.workingTree
        ? 'working-bytes'
        : version.label,
    bytes: utf8.encode(
      '$prefix${switch (version.kind) {
        ContentKind.mergePreview => preview,
        ContentKind.workingTree => working,
        _ => switch (version.stage) {
          2 => left,
          3 => right,
          _ => 'Introduction\nOriginal prose\nConclusion\n',
        },
      }}',
    ),
  );
  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Conflict review never creates a repository.');
}

void main() {
  testWidgets(
    'conflict draft reviews line-ending conversion before saving working bytes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ConflictClient()..workingLineEnding = '\r\n';
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitConflictView(session: session, path: client.path),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) => w is TextField && !w.readOnly,
      );
      const pasted = 'Manual prose\n';
      await tester.enterText(field, pasted);
      await tester.tap(find.text('Save result draft'));
      // The refreshed merge regions run in a real isolate. Keep the real
      // event loop moving before settling the now-visible loading state.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(client.mutations, isEmpty);
      expect(
        find.textContaining('from CRLF line endings to LF line endings'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, pasted);
      expect(client.mutations, isEmpty);
      await tester.tap(find.text('Save result draft'));
      // The refreshed merge regions run in a real isolate. Keep the real
      // event loop moving before settling the now-visible loading state.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save reviewed result'));
      // The refreshed merge regions run in a real isolate. Keep the real
      // event loop moving before settling the now-visible loading state.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(
        (client.mutations.single as ResolveConflict).bytes,
        utf8.encode(pasted),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  for (final removeBom in [false, true]) {
    testWidgets(
      removeBom
          ? 'conflict draft reviews BOM removal without losing manual text on cancel'
          : 'conflict draft preserves BOM and CRLF working bytes',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = ConflictClient()
          ..prefix = '\uFEFF'
          ..workingLineEnding = '\r\n';
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GitConflictView(session: session, path: client.path),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        final editable = find.byWidgetPredicate(
          (w) => w is TextField && !w.readOnly,
        );
        expect(
          tester.widget<TextField>(editable).controller!.text,
          '\uFEFF${client.working}',
        );
        expect(
          find.textContaining('UTF-8 with byte-order mark (BOM)'),
          findsOneWidget,
        );
        final edited = '${removeBom ? '' : '\uFEFF'}Manual prose\r\n';
        await tester.enterText(editable, edited);
        await tester.tap(find.text('Save result draft'));
        // The refreshed merge regions run in a real isolate. Keep the real
        // event loop moving before settling the now-visible loading state.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        if (removeBom) {
          expect(client.mutations, isEmpty);
          expect(
            find.textContaining('removes the UTF-8 byte-order mark'),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(editable).controller!.text, edited);
          expect(client.mutations, isEmpty);
          await tester.tap(find.text('Save result draft'));
          // The refreshed merge regions run in a real isolate. Keep the real
          // event loop moving before settling the now-visible loading state.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save reviewed result'));
          // The refreshed merge regions run in a real isolate. Keep the real
          // event loop moving before settling the now-visible loading state.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
        }
        final request = client.mutations.single as ResolveConflict;
        expect(request.bytes, utf8.encode(edited));
        expect(request.stageResult, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets(
    'authoritative stage contents load off the UI isolate and region acceptance retains manual editing',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ConflictClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitConflictView(session: session, path: client.path),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current history · 1111111'), findsOneWidget);
      expect(find.text('Incoming content · 3333333'), findsOneWidget);
      expect(find.text('Region 1/1 · 0 reviewed'), findsOneWidget);
      final editable = find.byWidgetPredicate(
        (w) => w is TextField && !w.readOnly,
      );
      expect(editable, findsOneWidget);
      expect(
        tester.widget<TextField>(editable).decoration!.labelText,
        'Editable conflict result',
      );
      expect(
        find.byWidgetPredicate((w) => w is TextField && w.readOnly),
        findsNWidgets(2),
      );
      await tester.tap(find.text('Accept left region'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editable).controller!.text, client.left);
      await tester.enterText(editable, 'Manually combined prose\n');
      await tester.pump();
      await tester.tap(find.text('Keep manual result for region'));
      await tester.pump();
      expect(
        tester.widget<TextField>(editable).controller!.text,
        'Manually combined prose\n',
      );
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'conflict sources that change during loading are rejected instead of offered for staging',
    (tester) async {
      final client = ConflictClient()..raced = true;
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitConflictView(session: session, path: client.path),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GitFailurePanel), findsOneWidget);
      expect(find.text('Apply result and stage resolution'), findsNothing);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
