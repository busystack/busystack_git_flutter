import 'package:busystack_git_flutter/busystack_git_flutter.dart' as git;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Run through each actual host, using its native adapter and theme.
Future<void> filenamePresentationContract(
  WidgetTester tester, {
  required Future<void> Function(Widget) mount,
}) async {
  final selected = ValueNotifier<bool>(false);
  addTearDown(selected.dispose);
  BuildContext? rowContext;
  await mount(
    Builder(
      builder: (context) {
        rowContext = context;
        return SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: ValueListenableBuilder<bool>(
              valueListenable: selected,
              builder: (_, value, _) => Column(
                children: [
                  for (final status in git.GitFileStatus.values)
                    SizedBox(
                      height: git.GitHostScope.of(context)!.rowHeight(context),
                      child: git.GitChangeRow(
                        title: '${status.name}.md',
                        depth: 0,
                        selected: value,
                        status: status,
                        statusDescription: git.gitFileStatusDescription(
                          context,
                          status,
                          git.GitStatusContext.staged,
                        ),
                        onPointerDown: (_) {},
                        onTap: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  for (final value in [false, true]) {
    selected.value = value;
    await tester.pumpAndSettle();
    final colors = git.NativeGitSurface.of(rowContext!);
    final background = value
        ? Color.alphaBlend(colors.controlActive, colors.sidebar)
        : colors.sidebar;
    for (final status in git.GitFileStatus.values) {
      final text = tester.widget<Text>(find.text('${status.name}.md'));
      final color = text.style!.color!;
      final luminances = [
        background.computeLuminance(),
        color.computeLuminance(),
      ]..sort();
      final contrast = (luminances.last + .05) / (luminances.first + .05);
      expect(
        contrast,
        greaterThanOrEqualTo(MediaQuery.highContrastOf(rowContext!) ? 7 : 4.5),
        reason: '$status selected=$value',
      );
      final row = find.ancestor(
        of: find.text('${status.name}.md'),
        matching: find.byType(git.NativeGitTreeRow),
      );
      expect(
        find.descendant(of: row, matching: find.byType(Icon)),
        status == git.GitFileStatus.conflicted
            ? findsNWidgets(2)
            : findsOneWidget,
      );
    }
    for (final marker in ['A', 'M', 'D', 'R', 'C', 'U', 'T', '?', '!']) {
      expect(find.text(marker), findsNothing);
    }
    final added = tester.widget<Text>(find.text('added.md')).style!;
    final modified = tester.widget<Text>(find.text('modified.md')).style!;
    final deleted = tester.widget<Text>(find.text('deleted.md')).style!;
    expect(added.color, isNot(modified.color));
    expect(added.color, isNot(deleted.color));
    expect(
      tester.widget<Text>(find.text('untracked.md')).style!.fontStyle,
      FontStyle.italic,
    );
    expect(
      tester.widget<Text>(find.text('conflicted.md')).style!.decoration,
      TextDecoration.underline,
    );
  }
  expect(tester.takeException(), isNull);
}
