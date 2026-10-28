import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _TreeClient extends FixtureClient {
  late final reviewed = GitSnapshot(
    repository: repo,
    token: 'nested-review',
    indexToken: 'nested-index',
    changes: [
      GitChange(
        path: RepoPath.text('book/chapter/one.md'),
        index: '.',
        worktree: 'M',
      ),
      GitChange(
        path: RepoPath.text('book/chapter/two.md'),
        index: '.',
        worktree: 'M',
      ),
      GitChange(
        path: RepoPath.text('book/appendix.md'),
        index: '.',
        worktree: 'M',
      ),
      GitChange(
        path: RepoPath.text('other/readme.md'),
        index: '.',
        worktree: 'M',
      ),
      GitChange(
        path: RepoPath.text('book/nested-repo'),
        index: '?',
        worktree: '?',
        directory: true,
      ),
    ],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );

  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => reviewed;
}

void main() {
  testWidgets('nested directory staging uses reviewed descendants only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _TreeClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHostScope(
            host: session.host,
            child: SizedBox(
              width: 440,
              child: GitChangeTree(session: session, onReview: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('book'), findsWidgets);
    expect(find.text('chapter'), findsOneWidget);
    expect(find.text('one.md'), findsOneWidget);
    final chapter = find
        .ancestor(of: find.text('chapter'), matching: find.byType(InkWell))
        .first;
    await tester.tap(
      find.descendant(
        of: chapter,
        matching: find.byTooltip('Stage selected files'),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.mutations, hasLength(1));
    final request = client.mutations.single as StagePaths;
    expect(request.paths.map((path) => path.display).toSet(), {
      'book/chapter/one.md',
      'book/chapter/two.md',
    });
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
