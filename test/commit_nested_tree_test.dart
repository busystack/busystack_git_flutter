import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _TreeClient extends FixtureClient {
  _TreeClient({this.staged = false});
  final bool staged;
  late final reviewed = GitSnapshot(
    repository: repo,
    token: 'nested-review',
    indexToken: 'nested-index',
    changes: [
      GitChange(
        path: RepoPath.text('book/chapter/one.md'),
        index: staged ? 'M' : '.',
        worktree: staged ? '.' : 'M',
      ),
      GitChange(
        path: RepoPath.text('book/chapter/two.md'),
        index: staged ? 'M' : '.',
        worktree: staged ? '.' : 'M',
      ),
      GitChange(
        path: RepoPath.text('book/appendix.md'),
        index: staged ? 'M' : '.',
        worktree: staged ? '.' : 'M',
      ),
      GitChange(
        path: RepoPath.text('other/readme.md'),
        index: staged ? 'M' : '.',
        worktree: staged ? '.' : 'M',
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

  GitSnapshot? later;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => later ?? reviewed;
}

void main() {
  for (final staged in [false, true]) {
    for (final target in ['one.md', 'chapter', 'Unstaged']) {
      for (final keyboard in [false, true]) {
        testWidgets(
          'contextual-only native policy stages reviewed $target keyboard=$keyboard staged=$staged',
          (tester) async {
            final client = _TreeClient(staged: staged);
            final base = host();
            final opened = <GitComparison>[];
            final menus = <GitMenuEntry>[];
            var allowStaging = !keyboard;
            final configured = GitHost(
              presentation: const TestGitPresentation(
                entryActionPlacement: GitEntryActionPlacement.contextMenu,
              ),
              icons: base.icons,
              present: base.present,
              openDocument: base.openDocument,
              prepareMutation: base.prepareMutation,
              chooseDirectory: base.chooseDirectory,
              notify: base.notify,
              drafts: base.drafts,
              presentMenu: (_, entries, {position}) async {
                menus.addAll(entries);
                return allowStaging ? 'stage' : null;
              },
            );
            final session = GitSession(
              client: client,
              repository: repo,
              host: configured,
            );
            await session.start();
            await tester.pumpWidget(
              GitTestApp(
                home: Scaffold(
                  body: GitHostScope(
                    host: configured,
                    child: GitChangeTree(
                      session: session,
                      onReview: opened.add,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widgetList<GitChangeRow>(find.byType(GitChangeRow))
                  .every((row) => row.trailing == null),
              isTrue,
            );
            final row = find
                .text(
                  target == 'Unstaged'
                      ? (staged ? 'Staged (4)' : 'Unstaged (4)')
                      : target,
                )
                .first;
            if (keyboard) {
              await tester.tap(row, buttons: kSecondaryMouseButton);
              await tester.pumpAndSettle();
              expect(client.mutations, isEmpty);
              allowStaging = true;
              menus.clear();
              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.f10);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            } else {
              await tester.tap(row, buttons: kSecondaryMouseButton);
            }
            await tester.pumpAndSettle();
            expect(
              opened,
              isEmpty,
              reason: 'Context staging never opens a comparison',
            );
            expect(menus.any((entry) => entry.id == 'stage'), isTrue);
            expect(client.mutations, hasLength(1));
            final request = client.mutations.single as StagePaths;
            expect(request.unstage, staged);
            final expected = target == 'one.md'
                ? {'book/chapter/one.md'}
                : target == 'chapter'
                ? {'book/chapter/one.md', 'book/chapter/two.md'}
                : {
                    'book/chapter/one.md',
                    'book/chapter/two.md',
                    'book/appendix.md',
                    'other/readme.md',
                  };
            expect(request.paths.map((p) => p.utf8Path).toSet(), expected);
            expect(
              request.paths.any((p) => p.utf8Path!.contains('nested-repo')),
              isFalse,
            );
            await tester.pumpWidget(const SizedBox());
            session.dispose();
          },
        );
      }
    }
  }

  testWidgets('a native staging menu cannot apply after a new index review', (
    tester,
  ) async {
    final client = _TreeClient();
    final base = host();
    final answer = Completer<String?>();
    final configured = GitHost(
      presentation: const TestGitPresentation(
        entryActionPlacement: GitEntryActionPlacement.contextMenu,
      ),
      icons: base.icons,
      present: base.present,
      openDocument: base.openDocument,
      prepareMutation: base.prepareMutation,
      chooseDirectory: base.chooseDirectory,
      notify: base.notify,
      drafts: base.drafts,
      presentMenu: (_, entries, {position}) => answer.future,
    );
    final session = GitSession(
      client: client,
      repository: repo,
      host: configured,
    );
    await session.start();
    await tester.pumpWidget(
      GitTestApp(
        home: Scaffold(
          body: GitHostScope(
            host: configured,
            child: GitChangeTree(session: session, onReview: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('chapter'), buttons: kSecondaryMouseButton);
    await tester.pump();
    client.later = GitSnapshot(
      repository: repo,
      token: 'new-review',
      indexToken: 'new-index',
      changes: client.reviewed.changes,
      operation: const RepositoryOperation(GitOperationKind.none),
      observedAt: DateTime.utc(2026),
    );
    await session.refresh();
    await tester.pump();
    answer.complete('stage');
    await tester.pumpAndSettle();
    expect(client.mutations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

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
      GitTestApp(
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
