import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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
    for (final name in ['refs/remotes/origin/main', 'refs/tags/v1'])
      GitReference(name: name, oid: GitOid('a' * 40)),
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
      presentation: const TestGitPresentation(),
      icons: testGitIcons,

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
        GitTestApp(
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
      expect(
        find.byWidgetPredicate(
          (w) => w is GitMenuButton && w.tooltip.startsWith('Actions for '),
        ),
        findsNothing,
      );
      await tester.tap(find.text('main'), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(
        menus,
        isEmpty,
        reason: 'Refreshing references cannot authorize stale actions',
      );
      client.pendingReferences!.complete(client.refs);
      await tester.pumpAndSettle();
      await tester.tap(find.text('main'), buttons: kSecondaryMouseButton);
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
        GitTestApp(
          home: Scaffold(body: GitBranchesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GitButton>(find.widgetWithText(GitButton, 'New branch…'))
            .onPressed,
        isNull,
      );
      expect(
        find.text(
          'Repository metadata is read-only. Branch inspection and comparison remain available.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('feature'), buttons: kSecondaryMouseButton);
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
  testWidgets(
    'reference search preserves editing across resize and keyboard menus never mutate',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _BranchesClient();
      final menus = <List<GitMenuEntry>>[];
      final session = GitSession(
        client: client,
        repository: repo,
        host: configuredHost(menus.add),
      );
      addTearDown(session.dispose);
      await session.start();
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(body: GitBranchesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      for (final query in ['feature', 'origin', 'v1']) {
        await tester.enterText(field, query);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(
            GitActionRow,
            query == 'origin' ? 'origin/main' : query,
          ),
          findsOneWidget,
        );
        expect(find.text('main'), findsNothing);
      }
      await tester.enterText(field, 'feature');
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      const value = TextEditingValue(
        text: 'feature',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 4),
      );
      editor.controller.value = value;
      await tester.pump();
      tester.view.physicalSize = const Size(360, 700);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.value,
        value,
      );
      // An IME arrow remains an editor key, never a result/menu activation.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(menus, isEmpty);
      editor.controller.value = const TextEditingValue(
        text: 'feature',
        selection: TextSelection.collapsed(offset: 7),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // The collapsible Local group is now a real keyboard tree item.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(menus, hasLength(1));
      expect(menus.single.any((e) => e.id == 'switch'), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(menus, hasLength(2));
      await tester.tap(field);
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(find.text('main'), findsOneWidget);
      expect(find.text('feature'), findsOneWidget);
      expect(find.text('origin/main'), findsOneWidget);
      expect(find.text('v1'), findsOneWidget);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
