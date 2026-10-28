import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _BranchClient extends FixtureClient implements GitWorkflowClient {
  _BranchClient({this.readOnly = false}) {
    historyCommits = [
      GitCommit(
        oid: GitOid('a' * 40),
        parents: const [],
        subject: 'Current',
        author: 'Fixture',
        email: 'fixture@example.invalid',
        date: DateTime.utc(2026),
        message: 'Current',
      ),
    ];
  }
  final bool readOnly;
  GitOid feature = GitOid('b' * 40);
  final inspections = <GitInspection>[];
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    head: GitOid('a' * 40),
    branch: 'main',
    token: 'review',
    indexToken: 'index',
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
    capabilities: GitCapabilities(
      writeMetadata: !readOnly,
      replaceWorkingFiles: !readOnly,
    ),
  );
  @override
  Future<List<GitReference>> references(RepositoryId repository) async => [
    GitReference(name: 'refs/heads/main', oid: GitOid('a' * 40), current: true),
    GitReference(name: 'refs/heads/feature', oid: feature),
  ];
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    inspections.add(request);
    return {'steps': [], 'token': 'plan'};
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Unused');
}

Future<GitSession> _mount(
  WidgetTester tester,
  _BranchClient client, {
  required Future<String?> Function(List<GitMenuEntry>) menu,
  bool allowMutation = true,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final original = host();
  final configured = GitHost(
    present: original.present,
    openDocument: original.openDocument,
    prepareMutation: (_, _) async => allowMutation,
    chooseDirectory: original.chooseDirectory,
    notify: original.notify,
    drafts: original.drafts,
    presentMenu: (_, entries, {position}) => menu(entries),
  );
  final session = GitSession(
    client: client,
    repository: repo,
    host: configured,
  );
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: GitLogView(session: session)),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return session;
}

Future<void> _context(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(ListTile, 'feature'),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'branch click filters; actual context menu exposes directed safe operations',
    (tester) async {
      final client = _BranchClient();
      final menus = <List<GitMenuEntry>>[];
      await _mount(
        tester,
        client,
        menu: (entries) async {
          menus.add(entries);
          return null;
        },
      );
      await tester.tap(find.widgetWithText(ListTile, 'feature'));
      await tester.pumpAndSettle();
      expect(client.historyFilters.last.reference, 'refs/heads/feature');
      expect(menus, isEmpty);
      expect(client.mutations, isEmpty);
      await _context(tester);
      expect(
        menus.single.map((e) => e.id),
        containsAll([
          'switch',
          'create',
          'rename',
          'delete',
          'compare',
          'merge',
          'rebase',
        ]),
      );
      expect(
        menus.single.singleWhere((e) => e.id == 'merge').label,
        'Merge feature into main',
      );
      expect(
        menus.single.singleWhere((e) => e.id == 'rebase').label,
        'Rebase main onto feature',
      );
      expect(client.mutations, isEmpty);
    },
  );

  testWidgets(
    'Log switch uses reviewed branch tip HEAD and index through shared action',
    (tester) async {
      final client = _BranchClient();
      await _mount(tester, client, menu: (_) async => 'switch');
      await _context(tester);
      expect(client.mutations, hasLength(1));
      final request = client.mutations.single as BranchMutation;
      expect(request.action, BranchAction.switchBranch);
      expect(request.name, 'feature');
      expect(request.expectedTip, client.feature);
      expect(request.expectedHead, GitOid('a' * 40));
      expect(request.expectedIndex, 'index');
    },
  );

  testWidgets('protected documents veto the shared Log switch', (tester) async {
    final client = _BranchClient();
    await _mount(
      tester,
      client,
      menu: (_) async => 'switch',
      allowMutation: false,
    );
    await _context(tester);
    expect(client.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'read-only branch context retains comparison and disables mutation',
    (tester) async {
      final client = _BranchClient(readOnly: true);
      final menus = <List<GitMenuEntry>>[];
      await _mount(
        tester,
        client,
        menu: (entries) async {
          menus.add(entries);
          return null;
        },
      );
      await _context(tester);
      for (final entry in menus.single.where((e) => e.id != 'compare')) {
        expect(entry.enabled, isFalse, reason: entry.id);
      }
      expect(
        menus.single.singleWhere((e) => e.id == 'compare').enabled,
        isTrue,
      );
      expect(client.mutations, isEmpty);
    },
  );

  testWidgets(
    'late branch-menu completion cannot mutate refreshed references',
    (tester) async {
      final client = _BranchClient();
      final pending = Completer<String?>();
      await _mount(tester, client, menu: (_) => pending.future);
      await tester.tap(
        find.widgetWithText(ListTile, 'feature'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      client.feature = GitOid('c' * 40);
      await tester.tap(find.byTooltip('Refresh Log'));
      await tester.pumpAndSettle();
      pending.complete('switch');
      await tester.pumpAndSettle();
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Log merge opens existing focused review with immutable source', (
    tester,
  ) async {
    final client = _BranchClient();
    await _mount(tester, client, menu: (_) async => 'merge');
    await _context(tester);
    expect(find.byType(GitMergeView), findsOneWidget);
    expect(
      tester.widget<GitMergeView>(find.byType(GitMergeView)).source!.oid,
      client.feature,
    );
    expect(find.textContaining('Destination: main'), findsOneWidget);
    expect(client.mutations, isEmpty);
  });

  testWidgets(
    'Log rebase initial source retains reference identity and rejects moved tip',
    (tester) async {
      final client = _BranchClient();
      await _mount(tester, client, menu: (_) async => 'rebase');
      await _context(tester);
      final view = tester.widget<GitRebaseView>(find.byType(GitRebaseView));
      expect(view.source!.name, 'refs/heads/feature');
      expect(view.source!.oid, client.feature);
      client.feature = GitOid('c' * 40);
      await tester.tap(find.text('Prepare Git plan'));
      await tester.pumpAndSettle();
      expect(client.inspections, isEmpty);
      expect(client.mutations, isEmpty);
      expect(find.byType(GitFailurePanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Create from Log uses selected revision without staging other files',
    (tester) async {
      final client = _BranchClient();
      await _mount(tester, client, menu: (_) async => 'create');
      await _context(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        'topic',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      final request = client.mutations.single as BranchMutation;
      expect(request.action, BranchAction.create);
      expect(request.start, client.feature);
      expect(request.name, 'topic');
      expect(request.expectedHead, GitOid('a' * 40));
      expect(request.expectedIndex, 'index');
      expect(request.upstream, isNull);
      expect(client.mutations.whereType<StagePaths>(), isEmpty);
    },
  );
  for (final action in ['rename', 'delete']) {
    testWidgets('Log $action reuses reviewed tip-bound operation', (
      tester,
    ) async {
      final client = _BranchClient();
      await _mount(tester, client, menu: (_) async => action);
      await _context(tester);
      if (action == 'rename') {
        await tester.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          'renamed',
        );
        await tester.tap(find.text('Apply'));
      } else {
        expect(client.mutations, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      }
      await tester.pumpAndSettle();
      final request = client.mutations.single as BranchMutation;
      expect(
        request.action,
        action == 'rename' ? BranchAction.rename : BranchAction.delete,
      );
      expect(request.name, 'feature');
      expect(request.expectedTip, client.feature);
      expect(request.expectedHead, GitOid('a' * 40));
      expect(request.expectedIndex, 'index');
      if (action == 'rename') expect(request.newName, 'renamed');
      if (action == 'delete') expect(request.forceDeleteReviewed, isFalse);
    });
  }

  testWidgets(
    'current branch context omits working-tree mutations and disables deletion',
    (tester) async {
      final client = _BranchClient();
      final menus = <List<GitMenuEntry>>[];
      await _mount(
        tester,
        client,
        menu: (entries) async {
          menus.add(entries);
          return null;
        },
      );
      await tester.tap(
        find.widgetWithText(ListTile, 'main'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(menus.single.map((e) => e.id), isNot(contains('switch')));
      expect(menus.single.map((e) => e.id), isNot(contains('merge')));
      expect(menus.single.map((e) => e.id), isNot(contains('rebase')));
      expect(
        menus.single.singleWhere((e) => e.id == 'delete').enabled,
        isFalse,
      );
      expect(client.mutations, isEmpty);
    },
  );
}
