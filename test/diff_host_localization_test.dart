import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  for (final view in GitSidebarView.values) {
    for (final width in [1000.0, 1600.0]) {
      testWidgets(
        'RTL content preserves host navigation ownership $view $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final session = GitSession(
            client: FixtureClient(),
            repository: repo,
            host: host(),
          );
          await session.start();
          await tester.pumpWidget(
            GitTestApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: GitFeatureSidebar(
                    controller: session.feature,
                    view: view,
                    onSelectView: session.feature.select,
                    onReview: session.feature.open,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('repo'), findsNothing);
          expect(
            Directionality.of(tester.element(find.byType(GitFeatureSidebar))),
            TextDirection.rtl,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          session.dispose();
        },
      );
    }
  }
  testWidgets(
    'Index editor title uses its bound host outside an ancestor scope',
    (tester) async {
      String? shown;
      final boundHost = GitHost(
        presentation: const TestGitPresentation(),
        icons: testGitIcons,
        presentMenu: testGitMenu,

        present: <T>(context, title, child, {bool expanded = false}) async {
          shown = title;
          return null;
        },
        localize: (template, values) =>
            template == GitMessages.editStagedContentArg0
            ? 'تحرير المحتوى · ${values['arg0']}'
            : template,
        openDocument: (_, _, {snapshot}) async {},
        prepareMutation: (_, _) async => true,
        chooseDirectory: (_) async => null,
        notify: (_) {},
        drafts: MemoryGitDraftStore(),
      );
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: boundHost,
      );
      await session.start();
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(
            body: GitDiffView(
              session: session,
              comparison: GitComparison(
                RepoPath.text('docs/日本語.md'),
                const ContentVersion.index(),
                const ContentVersion.working(),
              ),
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
        if (find
            .byKey(const ValueKey('git-diff-toolbar'))
            .evaluate()
            .isNotEmpty)
          break;
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('git-diff-overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Index in Three-Way View…'));
      await tester.pump();
      expect(shown, 'تحرير المحتوى · docs/日本語.md');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
