import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'presentation_fixture.dart' show FixtureClient, repo;

/// Executes the real feature surfaces with the consumer's actual native host.
/// Unavailable content deliberately exercises honest error paths; this fixture
/// cannot approve a repository mutation or manufacture a successful operation.
final class _UnavailableClient extends FixtureClient
    implements GitWorkflowClient {
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    if (request.kind == GitInspectionKind.commitOptions) return {};
    throw const GitException(GitErrorCode.missingContent);
  }

  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => throw const GitException(GitErrorCode.missingContent);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected native surface operation: ${invocation.memberName}',
  );
}

Future<void> exerciseNativeGitSurfaces(
  WidgetTester tester, {
  required GitHost host,
  required Future<void> Function(Widget) mount,
  required Type nativeField,
}) async {
  final client = _UnavailableClient();
  final session = GitSession(client: client, repository: repo, host: host);
  final path = RepoPath.text('chapter/notes.md');
  final revision = GitOid('a' * 40);
  final commit = GitCommit(
    oid: revision,
    parents: const [],
    subject: 'Native commit',
    author: 'Fixture',
    email: 'fixture@example.invalid',
    date: DateTime.utc(2026),
  );
  await tester.runAsync(session.start);
  try {
    final surfaces = <Widget>[
      GitCommitView(
        session: session,
        onReview: (_) {},
        onLog: () {},
        onBranches: () {},
        onPush: () {},
        onMore: (_) {},
      ),
      GitLogView(session: session),
      GitLogView(session: session, inspector: true),
      GitDiffView(
        session: session,
        comparison: GitComparison(
          path,
          const ContentVersion(ContentKind.indexVersion),
          const ContentVersion(ContentKind.workingTree),
        ),
        initialSideBySide: true,
      ),
      GitIndexEditor(session: session, path: path),
      GitConflictView(session: session, path: path),
      GitBranchesView(session: session),
      GitRemotesView(session: session),
      GitMergeView(session: session),
      GitFetchView(session: session),
      GitPullView(session: session),
      GitPushView(session: session),
      GitRebaseView(session: session),
      GitStashesView(session: session),
      GitCreateStashView(session: session),
      GitWorktreesView(session: session),
      GitSubmodulesView(session: session),
      GitRecoveryView(session: session),
      GitTagView(session: session, target: revision),
      GitRevisionComparison(
        session: session,
        left: revision,
        right: GitOid('b' * 40),
      ),
      GitSnapshotView(session: session, revision: revision),
      GitFileHistoryView(session: session, path: path),
      GitCherryPickView(session: session, commits: [commit]),
      GitOperationView(session: session),
      GitCreationView(client: client, chooseDirectory: (_) async => null),
      GitCreationView(
        client: client,
        chooseDirectory: (_) async => null,
        initialize: true,
      ),
    ];
    for (final surface in surfaces) {
      debugPrint('Native surface contract: ${surface.runtimeType}');
      await mount(KeyedSubtree(key: UniqueKey(), child: surface));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((widget) => identical(widget, surface)),
        findsOneWidget,
        reason: '${surface.runtimeType} must retain a native UI destination',
      );
      expect(tester.takeException(), isNull, reason: '${surface.runtimeType}');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DropdownButton<Object>), findsNothing);
      for (final element in find.byType(GitTextField).evaluate()) {
        expect(
          find.descendant(
            of: find.byElementPredicate((value) => identical(value, element)),
            matching: find.byType(nativeField),
          ),
          findsOneWidget,
          reason: '${surface.runtimeType} must use the actual host input',
        );
      }
    }
    await mount(const SizedBox());
    await tester.pumpAndSettle();
    for (final kind in GitPromptKind.values) {
      debugPrint('Native prompt contract: $kind');
      final context = tester.element(find.byType(GitHostScope).first);
      final cancellation = GitCancellation();
      final response = presentGitPrompt(
        context,
        host.present,
        GitPrompt(
          repository: repo,
          operationId: 'native-contract',
          kind: kind,
          title: 'Native prompt',
        ),
        cancellation,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(nativeField), findsOneWidget);
      cancellation.cancel();
      await tester.pumpAndSettle();
      expect(await response, isNull);
      expect(find.byType(nativeField), findsNothing);
    }
    expect(client.mutations, isEmpty);
  } finally {
    await mount(const SizedBox());
    session.dispose();
  }
}
