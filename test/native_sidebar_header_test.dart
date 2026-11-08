import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

class _HeaderClient extends FixtureClient {
  _HeaderClient({
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.known = true,
  });
  final String? upstream;
  final int ahead, behind;
  final bool known;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: 'snapshot',
    upstream: upstream,
    ahead: ahead,
    behind: behind,
    trackingCountsKnown: known,
    indexToken: 'index',
    branch: 'feature/long-native-context-branch',
    head: GitOid('a' * 40),
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
}

void main() {
  for (final value in [
    (
      upstream: 'origin/main',
      ahead: 0,
      behind: 0,
      known: true,
      label: 'Tracks origin/main',
    ),
    (
      upstream: 'origin/main',
      ahead: 3,
      behind: 2,
      known: true,
      label: 'Tracks origin/main · ↑3 ↓2',
    ),
    (
      upstream: 'origin/main',
      ahead: 0,
      behind: 0,
      known: false,
      label: 'Tracks origin/main',
    ),
    (upstream: null, ahead: 0, behind: 0, known: false, label: 'No upstream'),
  ]) {
    testWidgets('Commit tracking ${value.label} known=${value.known}', (
      tester,
    ) async {
      final session = GitSession(
        client: _HeaderClient(
          upstream: value.upstream,
          ahead: value.ahead,
          behind: value.behind,
          known: value.known,
        ),
        repository: repo,
        host: host(presentation: const YaruGitPresentation()),
      );
      addTearDown(session.dispose);
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: GitHostScope(
            host: session.host,
            child: Scaffold(
              body: GitCommitView(
                session: session,
                onReview: (_) {},
                onLog: () {},
                onBranches: () {},
                onPush: () {},
                onMore: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tracking = find.text(value.label);
      expect(tracking, findsOneWidget);
      final branch = find.text('feature/long-native-context-branch');
      expect(tester.getTopLeft(tracking).dx, tester.getTopLeft(branch).dx);
      expect(
        tester.getTopLeft(tracking).dy - tester.getBottomLeft(branch).dy,
        2,
      );
      expect(find.textContaining('↑0 ↓0'), findsNothing);
    });
  }

  testWidgets('informational header stays separate from neighboring actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const NativeSidebarHeader(
                  title: 'Git Log',
                  contextLine: Text('Selected subject'),
                ),
                Semantics(
                  button: true,
                  onTap: () {},
                  child: const Text('Commit details'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(NativeSidebarHeader)),
        matchesSemantics(label: 'Git Log\nSelected subject', isButton: false),
      );
    } finally {
      semantics.dispose();
    }
  });
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
      expect(
        find.descendant(
          of: header,
          matching: find.byIcon(gitLinuxIcons[GitGlyph.branch]!),
        ),
        findsOneWidget,
      );
      expect(
        find.byIcon(gitLinuxIcons[GitGlyph.selectCommit]!),
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
      expect(find.byTooltip('Select branch'), findsOneWidget);
      final actions = find
          .descendant(of: header, matching: find.byType(GitIconButton))
          .last;
      expect(tester.getRect(actions).left - tester.getRect(choose).right, 4);
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
