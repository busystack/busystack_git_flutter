import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

class _HeaderClient extends FixtureClient {
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: 'snapshot',
    indexToken: 'index',
    branch: 'feature/long-native-context-branch',
    head: GitOid('a' * 40),
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
}

void main() {
  testWidgets(
    'Commit context is informational; its separate action owns branch selection',
    (tester) async {
      final client = _HeaderClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(presentation: const YaruGitPresentation()),
      );
      await session.start();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GitHostScope(
            host: session.host,
            child: Scaffold(
              body: SizedBox(
                width: 600,
                child: GitCommitView(
                  session: session,
                  onReview: (_) {},
                  onLog: () {},
                  onBranches: () => opened++,
                  onPush: () {},
                  onMore: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('git-commit-sidebar-header'));
      expect(
        find.descendant(of: header, matching: find.text('Commit')),
        findsOneWidget,
      );
      final branch = find.text('feature/long-native-context-branch');
      await tester.tap(branch);
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(client.mutations, isEmpty);
      expect(
        find.ancestor(of: branch, matching: find.byType(NativeGitActionButton)),
        findsNothing,
      );
      final choose = find.byKey(const ValueKey('git-select-another-branch'));
      expect(find.byTooltip('Select another branch'), findsOneWidget);
      final actions = find
          .descendant(of: header, matching: find.byType(GitIconButton))
          .last;
      expect(tester.getRect(actions).left - tester.getRect(choose).right, 8);
      expect(tester.getRect(header).right - tester.getRect(actions).right, 12);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(client.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
}
