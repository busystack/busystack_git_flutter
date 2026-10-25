import 'dart:async';
import 'dart:convert';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'conflict_editor_test.dart' show ConflictClient;
import 'support/presentation_fixture.dart';

final class SlowConflictClient extends FixtureClient
    implements GitWorkflowClient {
  final source = ConflictClient();
  final readingSavedContent = Completer<void>();
  Completer<void>? savedContentBarrier;
  List<int>? savedBytes;
  String get workingToken =>
      savedBytes == null ? 'working-bytes' : 'saved-working-bytes';
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) => source.status(repository, cancellation: cancellation, policy: policy);
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    ...await source.inspect(repository, request, cancellation: cancellation),
    'working': {'token': workingToken},
  };
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    final barrier = savedContentBarrier;
    if (barrier != null) {
      if (!readingSavedContent.isCompleted) readingSavedContent.complete();
      await barrier.future;
    }
    final value = await source.content(
      repository,
      path,
      version,
      cancellation: cancellation,
    );
    if (version.kind != ContentKind.workingTree) return value;
    return GitContent(
      path: path,
      version: version,
      availability: value.availability,
      mode: value.mode,
      token: workingToken,
      bytes: savedBytes ?? value.bytes,
    );
  }

  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    if (request case ResolveConflict(stageResult: false, bytes: final bytes?)) {
      savedBytes = bytes;
      savedContentBarrier = Completer<void>();
    }
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
  }) => throw StateError('Conflict review never creates a repository.');
}

void main() {
  testWidgets(
    'saving a conflict keeps editing and staging unavailable until refreshed versions are ready',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = SlowConflictClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitConflictView(session: session, path: client.source.path),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final editable = find.byWidgetPredicate(
        (w) => w is TextField && !w.readOnly,
      );
      const manual = 'Manual café 😀 resolution\n';
      await tester.enterText(editable, manual);
      tester.widget<TextField>(editable).controller!.selection =
          const TextSelection.collapsed(offset: 7);
      await tester.tap(find.text('Save result draft'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.readingSavedContent.isCompleted, isTrue);
      expect(client.mutations, hasLength(1));
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Accept left region'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.byWidgetPredicate((w) => w is TextField && !w.readOnly),
        findsNothing,
      );
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .any((w) => w.controller!.text == manual),
        isTrue,
      );
      client.savedContentBarrier!.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editable).controller!.text, manual);
      expect(
        tester.widget<TextField>(editable).controller!.selection.extentOffset,
        7,
      );
      await tester.tap(find.text('Apply result and stage resolution'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply and stage'));
      await tester.pumpAndSettle();
      final staged = client.mutations.last as ResolveConflict;
      expect(staged.stageResult, isTrue);
      expect(staged.expectedWorking, 'saved-working-bytes');
      expect(staged.bytes, utf8.encode(manual));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
