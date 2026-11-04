import 'dart:async';
import 'package:busystack_git_flutter/src/native_table.dart';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

GitCommit _commit(String id) => GitCommit(
  oid: GitOid(id * 40),
  parents: id == 'a' ? [GitOid('b' * 40)] : const [],
  subject: 'Subject $id',
  author: 'Author $id',
  email: '$id@example.invalid',
  date: DateTime.utc(2026),
  message: 'Full message $id\n${'Long metadata\n' * 40}',
);

class _Client extends FixtureClient {
  _Client() {
    historyCommits = [_commit('a'), _commit('b')];
  }
  final changed = <(GitOid, GitOid?)>[];
  bool samePath = false;
  Completer<List<GitChange>>? delayed;
  Completer<HistoryPage>? delayedHistory;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: 'snapshot',
    indexToken: 'index',
    head: GitOid('a' * 40),
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) async {
    historyFilters.add(filter);
    if (filter.reference != null && delayedHistory != null) {
      final pending = delayedHistory!;
      delayedHistory = null;
      return pending.future;
    }
    return HistoryPage(
      historyCommits
          .where(
            (commit) =>
                filter.reference == null ||
                commit.oid.value == filter.reference,
          )
          .toList(),
      nextOffset: 2,
      hasMore: false,
      anchor: 'refs',
    );
  }

  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) async {
    changed.add((revision, parent));
    if (delayed case final pending?) {
      delayed = null;
      return pending.future;
    }
    return [
      GitChange(
        path: RepoPath.text(
          samePath ? 'dir/shared.md' : 'dir/new-$revision.md',
        ),
        originalPath: RepoPath.text('old.md'),
        index: 'R',
        worktree: ' ',
      ),
    ];
  }
}

Future<GitSession> _mount(
  WidgetTester tester,
  _Client client, {
  void Function(GitComparison, List<GitComparison>)? review,
  GitPresentMenu? menu,
}) async {
  tester.view.physicalSize = const Size(1200, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final original = host();
  final nativeHost = GitHost(
    presentation: const TestGitPresentation(),
    icons: testGitIcons,
    presentMenu: (context, entries, {position}) async {
      if (entries.any((e) => e.id == 'selectCommit')) return 'selectCommit';
      return (menu ?? testGitMenu)(context, entries, position: position);
    },
    present: <T>(context, title, child, {bool expanded = false}) =>
        showDialog<T>(
          context: context,
          builder: (_) =>
              Dialog(child: SizedBox(width: 1050, height: 700, child: child)),
        ),
    openDocument: original.openDocument,
    prepareMutation: original.prepareMutation,
    chooseDirectory: original.chooseDirectory,
    notify: original.notify,
    drafts: MemoryGitDraftStore(),
  );
  final session = GitSession(
    client: client,
    repository: repo,
    host: nativeHost,
  );
  await session.start();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    GitTestApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 300,
            child: GitLogView(
              session: session,
              inspector: true,
              onReview: review,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

void main() {
  testWidgets(
    'inspector information precedes independently scrollable files and ordinary activation captures endpoints',
    (tester) async {
      final client = _Client();
      GitComparison? opened;
      List<GitComparison>? context;
      await _mount(
        tester,
        client,
        review: (comparison, files) {
          opened = comparison;
          context = files;
        },
      );
      final button = find.byKey(const ValueKey('git-selected-commit'));
      final info = find.byWidgetPredicate(
        (widget) =>
            widget.key is PageStorageKey &&
            '${widget.key}'.contains('git-commit-information:'),
      );
      final files = find.byKey(const ValueKey('git-changed-files'));
      expect(
        tester.getTopLeft(button).dy,
        lessThan(tester.getTopLeft(info).dy),
      );
      expect(tester.getTopLeft(info).dy, lessThan(tester.getTopLeft(files).dy));
      expect(find.text('Changed files (1)').hitTestable(), findsOneWidget);
      expect(find.text('new-${'a' * 40}.md').hitTestable(), findsOneWidget);
      await tester.tap(find.text('new-${'a' * 40}.md'));
      expect(opened!.left.revision, GitOid('b' * 40));
      expect(opened!.right.revision, GitOid('a' * 40));
      expect(opened!.leftPath!.utf8Path, 'old.md');
      expect(context!.single.toJson(), opened!.toJson());
      expect(client.mutations, isEmpty);
      expect(find.byType(GitSplitter), findsNothing);
      expect(
        find.descendant(of: info, matching: find.byType(Scrollable)),
        findsNothing,
      );
      // Metadata is content driven; dragging it cannot resize or scroll the file list.
      await tester.drag(info, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text('new-${'a' * 40}.md').hitTestable(), findsOneWidget);
    },
  );
  testWidgets(
    'modal browsing and cancellation never apply a candidate; confirmation applies once',
    (tester) async {
      final client = _Client();
      var opened = 0;
      final session = await _mount(tester, client, review: (_, _) => opened++);
      await tester.tap(find.byKey(const ValueKey('git-commit-actions')));
      await tester.pumpAndSettle();
      expect(find.byType(GitLogView), findsNWidgets(2));
      final table = tester.widget<GitNativeTable>(
        find.byType(GitNativeTable).last,
      );
      expect(table.rowAt(table.selected.single).id, 'a' * 40);
      expect(
        find.text(GitMessages.commitDetails),
        findsNothing,
        reason:
            'The selector must not expose the obsolete expanded details route',
      );
      expect(find.byKey(const ValueKey('git-history-toolbar')), findsOneWidget);

      await tester.tap(find.text('Subject b'));
      await tester.pumpAndSettle();
      expect(session.viewState['inspectorRevision'], 'a' * 40);
      expect(opened, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(session.viewState['inspectorRevision'], 'a' * 40);
      await tester.tap(find.byKey(const ValueKey('git-commit-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subject b'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select this commit'));
      await tester.pumpAndSettle();
      expect(session.viewState['inspectorRevision'], 'b' * 40);
      expect(opened, 0);
      expect(client.mutations, isEmpty);
      expect(find.byType(GitLogView), findsOneWidget);
    },
  );
  testWidgets(
    'selector keeps contextual historical operations and compact details',
    (tester) async {
      final menus = <GitMenuEntry>[];
      final client = _Client();
      await _mount(
        tester,
        client,
        menu: (_, entries, {position}) async {
          menus.addAll(entries);
          return null;
        },
      );
      await tester.tap(find.byKey(const ValueKey('git-commit-actions')));
      await tester.pumpAndSettle();
      final table = tester.widget<GitNativeTable>(
        find.byType(GitNativeTable).last,
      );
      table.onRequest(const GitNativeTableRequest('context', 0, 0));
      await tester.pumpAndSettle();
      expect(
        menus.map((e) => e.label),
        containsAll([
          GitMessages.viewCommitDetails,
          GitMessages.copyCommitHash,
          GitMessages.createBranch2,
          GitMessages.createTag,
          GitMessages.compareRevisions,
          GitMessages.openSnapshot,
          GitMessages.cherryPickOperation,
          GitMessages.revertCommit,
          GitMessages.interactiveRebaseAfterThisBoundary,
          GitMessages.resetCurrentBranch,
        ]),
      );
      expect(client.mutations, isEmpty);
    },
  );

  testWidgets(
    'unavailable immutable history is never replaced by another commit',
    (tester) async {
      final client = _Client();
      final session = await _mount(tester, client);
      client.historyCommits = [_commit('b')];
      final log = tester.widget<GitLogView>(find.byType(GitLogView));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: GitLogView(session: session, inspector: log.inspector),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.viewState['inspectorRevision'], 'a' * 40);
      expect(find.byType(GitFailurePanel), findsOneWidget);
      expect(find.text('Subject b'), findsNothing);
    },
  );
  testWidgets(
    'confirmed selection retires delayed inspector history and dependent files',
    (tester) async {
      final client = _Client();
      final session = await _mount(tester, client);
      final pending = client.delayedHistory = Completer<HistoryPage>();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: GitLogView(session: session, inspector: true),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('git-commit-actions')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.tap(find.text('Subject b'));
      await tester.pump();
      await tester.tap(find.text('Select this commit'));
      await tester.pumpAndSettle();
      expect(session.viewState['inspectorRevision'], 'b' * 40);
      pending.complete(
        HistoryPage(
          [_commit('a')],
          nextOffset: 1,
          hasMore: false,
          anchor: 'refs',
        ),
      );
      await tester.pumpAndSettle();
      expect(session.viewState['inspectorRevision'], 'b' * 40);
      expect(find.text('new-${'b' * 40}.md'), findsOneWidget);
      expect(find.text('new-${'a' * 40}.md'), findsNothing);
      expect(client.mutations, isEmpty);
    },
  );

  for (final action in ['review', 'history', 'snapshot']) {
    testWidgets(
      'delayed historical file $action cannot retarget the same path at a new commit',
      (tester) async {
        final client = _Client()..samePath = true;
        final pending = Completer<String?>();
        final opened = <GitComparison>[];
        final session = await _mount(
          tester,
          client,
          review: (comparison, _) => opened.add(comparison),
          menu: (_, entries, {position}) => pending.future,
        );
        final file = RepoPath.text('dir/shared.md');
        await tester.tap(
          find.byKey(ValueKey('git-historical-menu:${file.key}')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('git-commit-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Subject b'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select this commit'));
        await tester.pumpAndSettle();
        expect(session.viewState['inspectorRevision'], 'b' * 40);
        pending.complete(action);
        await tester.pumpAndSettle();
        expect(opened, isEmpty);
        expect(find.byType(GitFileHistoryView), findsNothing);
        expect(find.byType(GitSnapshotView), findsNothing);
        expect(client.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'parent navigation resolves immutable history outside the one-commit inspector',
    (tester) async {
      final client = _Client();
      final session = await _mount(tester, client);
      await tester.ensureVisible(find.text('Parent bbbbbbbbbb'));
      await tester.tap(find.text('Parent bbbbbbbbbb'));
      await tester.pumpAndSettle();
      expect(session.viewState['inspectorRevision'], 'b' * 40);
      expect(client.changed.last, (GitOid('b' * 40), null));
      expect(client.mutations, isEmpty);
    },
  );
}
