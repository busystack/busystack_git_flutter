import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final class _BranchesClient extends FixtureClient implements GitWorkflowClient {
  _BranchesClient({this.readOnly = false});
  final bool readOnly;
  String branch = 'main';
  Completer<List<GitReference>>? pendingReferences;
  List<GitReference> get refs => [
    for (final name in ['main', 'feature'])
      GitReference(
        name: 'refs/heads/$name',
        oid: GitOid('a' * 40),
        current: branch == name,
      ),
  ];
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    token: branch,
    indexToken: '$branch-index',
    head: GitOid('a' * 40),
    branch: branch,
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
    capabilities: GitCapabilities(
      writeMetadata: !readOnly,
      replaceWorkingFiles: !readOnly,
    ),
  );
  @override
  Future<List<GitReference>> references(RepositoryId repository) async =>
      pendingReferences == null ? refs : pendingReferences!.future;
  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    branch = (request as BranchMutation).name;
    pendingReferences = Completer<List<GitReference>>();
    return GitOutcome(
      phase: GitOperationPhase.completed,
      snapshot: await status(repository),
    );
  }

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Branch-list presentation must not invoke workflows.');
  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Branch-list presentation cannot clone a repository.');
}

void main() {
  GitHost configuredHost(void Function(List<GitMenuEntry>) menu) {
    final original = host();
    return GitHost(
      present: original.present,
      openDocument: original.openDocument,
      prepareMutation: original.prepareMutation,
      chooseDirectory: original.chooseDirectory,
      notify: original.notify,
      drafts: original.drafts,
      presentMenu: (_, values, {position}) async {
        menu(values);
        return null;
      },
    );
  }

  testWidgets(
    'branch menus wait for reconciled references after branch creation',
    (tester) async {
      final client = _BranchesClient();
      final menus = <List<GitMenuEntry>>[];
      final session = GitSession(
        client: client,
        repository: repo,
        host: configuredHost(menus.add),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitBranchesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New branch…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        'feature',
      );
      await tester.tap(find.text('Apply'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(client.pendingReferences, isNotNull);
      final control = find.byWidgetPredicate(
        (w) => w is GitMenuButton && w.tooltip == 'Actions for refs/heads/main',
      );
      expect(tester.widget<GitMenuButton>(control).enabled, isFalse);
      final button = find.descendant(
        of: control,
        matching: find.byType(GitIconButton),
      );
      expect(tester.widget<GitIconButton>(button).onPressed, isNull);
      expect(
        tester.widget<GitIconButton>(button).tooltip,
        contains('Refreshing branch metadata'),
      );
      await tester.tap(button);
      await tester.pump();
      expect(menus, isEmpty);
      client.pendingReferences!.complete(client.refs);
      await tester.pumpAndSettle();
      expect(tester.widget<GitMenuButton>(control).enabled, isTrue);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final switchAction = menus.single.singleWhere((e) => e.id == 'switch');
      expect(switchAction.label, 'Switch to main');
      expect(switchAction.enabled, isTrue);
      expect(client.mutations, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'read-only references retain comparison while disabling mutations',
    (tester) async {
      final client = _BranchesClient(readOnly: true);
      final menus = <List<GitMenuEntry>>[];
      final session = GitSession(
        client: client,
        repository: repo,
        host: configuredHost(menus.add),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitBranchesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'New branch…'))
            .onPressed,
        isNull,
      );
      expect(
        find.text(
          'Repository metadata is read-only. Branch inspection and comparison remain available.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is GitMenuButton &&
              w.tooltip == 'Actions for refs/heads/feature',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        menus.single.singleWhere((e) => e.id == 'compare').enabled,
        isTrue,
      );
      for (final entry in menus.single.where(
        (e) => const {
          'switch',
          'merge',
          'rename',
          'upstream',
          'delete',
          'remoteDelete',
        }.contains(e.id),
      )) {
        expect(entry.enabled, isFalse, reason: entry.id);
      }
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
