import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

class _Client extends FixtureClient implements GitWorkflowClient {
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: 'review',
    indexToken: 'index',
    head: GitOid('a' * 40),
    branch: 'main',
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
  @override
  Future<List<GitReference>> references(RepositoryId repository) async => [
    GitReference(name: 'refs/heads/main', oid: GitOid('a' * 40), current: true),
  ];
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Opening an action must not run it');
  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Opening Clone must not clone');
}

void main() {
  testWidgets(
    'compact repository grouping preserves every destination and shared defaults',
    (tester) async {
      final client = _Client();
      List<GitMenuEntry> menu = [];
      String? chosen;
      final surfaces = <Widget>[];
      final original = host();
      final configured = GitHost(
        presentation: const TestGitPresentation(),
        icons: testGitIcons,
        presentMenu: (_, entries, {position}) async {
          menu = entries;
          return chosen;
        },
        present: <T>(context, title, child, {bool expanded = false}) async {
          surfaces.add((child as GitHostScope).child);
          return null;
        },
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: MemoryGitDraftStore(),
        revokeRepositoryTrust: (_) async {},
      );
      final session = GitSession(
        client: client,
        repository: repo,
        host: configured,
      );
      await session.start();
      addTearDown(session.dispose);
      late BuildContext current;
      await tester.pumpWidget(
        GitTestApp(
          home: Builder(
            builder: (context) {
              current = context;
              return GitHostScope(host: configured, child: const SizedBox());
            },
          ),
        ),
      );
      final ui = GitWorkflowUi(current, session);
      Future<void> compact() => ui.more(
        showBranches: false,
        includeRefresh: true,
        showBranchOperations: false,
      );
      await compact();
      expect(menu.map((e) => e.id), [
        'refresh',
        'fetch',
        'pull',
        'push',
        'remotes',
        'conflicts',
        'stashes',
        'worktrees',
        'submodules',
        'recovery',
        'clone',
        'revokeTrust',
      ]);
      expect(menu.where((e) => e.sectionStart).map((e) => e.id), [
        'fetch',
        'conflicts',
        'stashes',
        'clone',
        'revokeTrust',
      ]);
      chosen = 'conflicts';
      await compact();
      expect(surfaces.last, isA<GitOperationView>());
      chosen = 'clone';
      await compact();
      expect(surfaces.last, isA<GitCreationView>());
      chosen = null;
      await ui.more();
      expect(
        menu.map((e) => e.id),
        containsAll(['branches', 'merge', 'rebase', 'clone']),
      );
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['merge', 'rebase']) {
    testWidgets(
      'Branches exposes complete general $action with only the current branch',
      (tester) async {
        final client = _Client();
        final original = host();
        Widget? presented;
        List<GitMenuEntry>? menu;
        final configured = GitHost(
          presentation: const TestGitPresentation(),
          icons: testGitIcons,
          presentMenu: (_, entries, {position}) async {
            menu = entries;
            return action;
          },
          present: <T>(context, title, child, {bool expanded = false}) async {
            presented = (child as GitHostScope).child;
            return null;
          },
          openDocument: original.openDocument,
          prepareMutation: original.prepareMutation,
          chooseDirectory: original.chooseDirectory,
          notify: original.notify,
          drafts: MemoryGitDraftStore(),
        );
        final session = GitSession(
          client: client,
          repository: repo,
          host: configured,
        );
        await session.start();
        addTearDown(session.dispose);
        await tester.pumpWidget(
          GitTestApp(
            home: Scaffold(
              body: GitHostScope(
                host: configured,
                child: GitBranchesView(session: session),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('git-branch-workflows')));
        await tester.pumpAndSettle();
        expect(menu!.map((e) => e.id), ['merge', 'rebase']);
        if (action == 'merge') {
          expect(presented, isA<GitMergeView>());
          expect((presented as GitMergeView).source, isNull);
        } else {
          expect(presented, isA<GitRebaseView>());
          expect((presented as GitRebaseView).source, isNull);
          expect((presented as GitRebaseView).boundary, isNull);
        }
        expect(client.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
