import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  for (final workspaceLog in [false, true]) {
    for (final width in [1000.0, 1600.0]) {
      testWidgets(
        'literal repository path keeps its rendered leading slash in RTL ${workspaceLog ? 'Log workspace' : 'Commit'} at $width',
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
            MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
                  child: Scaffold(
                    body: workspaceLog
                        ? GitWorkspace(session: session)
                        : GitCommitView(
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
            ),
          );
          await tester.pumpAndSettle();
          if (workspaceLog) {
            await tester.tap(
              find.descendant(
                of: find.byType(SegmentedButton<bool>),
                matching: find.text('Log'),
              ),
            );
            await tester.pumpAndSettle();
          }
          final path = find.text(repo.root).hitTestable();
          expect(path, findsOneWidget);
          final chrome = workspaceLog
              ? find.byType(SegmentedButton<bool>)
              : find.text(GitMessages.commitScopeEntireRepository);
          expect(Directionality.of(tester.element(chrome)), TextDirection.rtl);
          void expectLiteralGlyphOrder(Finder text) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: text, matching: find.byType(RichText)),
            );
            final slash = paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 1),
                )
                .single;
            final firstLetter = paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 1, extentOffset: 2),
                )
                .single;
            expect(slash.right, lessThanOrEqualTo(firstLetter.left));
            expect(paragraph.text.toPlainText(), repo.root);
          }

          expectLiteralGlyphOrder(path);
          final tooltip = find
              .ancestor(of: path, matching: find.byType(Tooltip))
              .first;
          tester.state<TooltipState>(tooltip).ensureTooltipVisible();
          await tester.pumpAndSettle();
          final tooltipText = find.byWidgetPredicate(
            (widget) =>
                widget is RichText && widget.text.toPlainText() == repo.root,
          );
          expect(tooltipText, findsNWidgets(2));
          for (final element in tooltipText.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final slash = paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 1),
                )
                .single;
            final firstLetter = paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 1, extentOffset: 2),
                )
                .single;
            expect(slash.right, lessThanOrEqualTo(firstLetter.left));
          }
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
        MaterialApp(
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
            .text('Edit HEAD | Index | Working Tree…')
            .evaluate()
            .isNotEmpty)
          break;
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit HEAD | Index | Working Tree…'));
      await tester.pump();
      expect(shown, 'تحرير المحتوى · docs/日本語.md');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
