import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
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
