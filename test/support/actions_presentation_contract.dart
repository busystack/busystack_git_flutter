import 'dart:async';
import 'dart:ui' as ui;
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs inside each real application's theme, control and icon adapters.
void actionsPresentationContract({
  required GitPresentation presentation,
  required Map<GitGlyph, IconData> icons,
  required IconData actionsGlyph,
  required IconData contextGlyph,
  required Widget Function(
    Widget child,
    Brightness brightness,
    TextDirection direction,
  )
  shell,
  required Widget Function(VoidCallback? activate) nativeReference,
}) {
  final actionHost = GitHost(
    presentation: presentation,
    icons: icons,
    presentMenu: (_, _, {position}) async => null,
    present: <T>(_, _, _, {bool expanded = false}) async => null,
    openDocument: (_, _, {snapshot}) async {},
    prepareMutation: (_, _) async => false,
    chooseDirectory: (_) async => null,
    notify: (_) {},
    drafts: MemoryGitDraftStore(),
  );
  Widget actionScope(Widget child) =>
      GitHostScope(host: actionHost, child: child);
  for (final brightness in Brightness.values) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'native text action exposes one named button with focus $brightness $direction',
        (tester) async {
          final semantics = tester.ensureSemantics();
          var activations = 0;
          await tester.pumpWidget(
            shell(
              actionScope(
                Column(
                  children: [
                    for (final style in GitActionStyle.values)
                      for (final enabled in [true, false])
                        GitButton(
                          variant: style,
                          onPressed: enabled ? () => activations++ : null,
                          child: Text('${style.name} $enabled action'),
                        ),
                  ],
                ),
              ),
              brightness,
              direction,
            ),
          );
          await tester.pumpAndSettle();
          for (final style in GitActionStyle.values) {
            for (final enabled in [true, false]) {
              final label = '${style.name} $enabled action';
              expect(
                tester.getSemantics(find.text(label)),
                matchesSemantics(
                  label: label,
                  textDirection: direction,
                  isButton: true,
                  hasEnabledState: true,
                  isEnabled: enabled,
                  isFocusable: enabled,
                  hasFocusAction: enabled,
                  hasTapAction: enabled,
                ),
                reason:
                    'The accessible name, role, state and action must share one node.',
              );
            }
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            tester
                .getSemantics(find.text('standard true action'))
                .flagsCollection
                .isFocused,
            ui.Tristate.isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(activations, 1);
          semantics.dispose();
        },
      );
      testWidgets(
        'native primary activation exposes its named button and focus $brightness $direction',
        (tester) async {
          final semantics = tester.ensureSemantics();
          var activations = 0;
          await tester.pumpWidget(
            shell(
              actionScope(
                GitActivation(
                  onTap: () => activations++,
                  child: const Text('Select changed line'),
                ),
              ),
              brightness,
              direction,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(find.text('Select changed line')),
            matchesSemantics(
              label: 'Select changed line',
              textDirection: direction,
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasFocusAction: true,
              hasTapAction: true,
            ),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(activations, 1);
          semantics.dispose();
        },
      );
      testWidgets(
        'native Actions semantic icon, anchor and single keyboard activation $brightness $direction',
        (tester) async {
          final pending = Completer<String?>();
          var opens = 0, selected = 0;
          Offset? anchor;
          List<GitMenuEntry>? contents;
          final host = GitHost(
            presentation: presentation,
            icons: icons,
            presentMenu: (_, entries, {position}) {
              opens++;
              contents = entries;
              anchor = position;
              return pending.future;
            },
            present: <T>(_, _, _, {bool expanded = false}) async => null,
            openDocument: (_, _, {snapshot}) async {},
            prepareMutation: (_, _) async => false,
            chooseDirectory: (_) async => null,
            notify: (_) {},
            drafts: MemoryGitDraftStore(),
          );
          await tester.pumpWidget(
            shell(
              GitHostScope(
                host: host,
                child: Column(
                  children: [
                    Row(
                      children: [
                        GitMenuButton(
                          key: const ValueKey('actions'),
                          host: host,
                          role: GitMenuRole.viewActions,
                          entries: const [
                            GitMenuEntry('merge', 'Merge'),
                            GitMenuEntry.separator(),
                            GitMenuEntry('rebase', 'Rebase', enabled: false),
                          ],
                          onSelected: (_) => selected++,
                        ),
                        KeyedSubtree(
                          key: const ValueKey('reference'),
                          child: nativeReference(() {}),
                        ),
                        GitMenuButton(
                          key: const ValueKey('context'),
                          host: host,
                          role: GitMenuRole.entryContext,
                          tooltip: 'Actions for file',
                          entries: const [GitMenuEntry('open', 'Open')],
                          onSelected: (_) {},
                        ),
                      ],
                    ),
                    GitButton.diffInline(
                      onPressed: () {},
                      child: const Text('Expand unchanged context'),
                    ),
                    const GitButton.diffInline(
                      onPressed: null,
                      child: Text('Stage this hunk'),
                    ),
                    GitButton.toolbar(
                      onPressed: () {},
                      child: const Text('Stage file'),
                    ),
                  ],
                ),
              ),
              brightness,
              direction,
            ),
          );
          await tester.pumpAndSettle();
          final action = find.byKey(const ValueKey('actions'));
          expect(icons[GitGlyph.actions], actionsGlyph);
          expect(
            find.descendant(of: action, matching: find.byIcon(actionsGlyph)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('context')),
              matching: find.byIcon(contextGlyph),
            ),
            findsOneWidget,
          );
          expect(
            tester.getSize(action),
            tester.getSize(find.byKey(const ValueKey('reference'))),
          );
          expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(30));
          expect(
            tester.getSize(find.text('Expand unchanged context')).height,
            lessThan(tester.getSize(action).height),
          );
          final semantics = tester.ensureSemantics();
          expect(tester.getSemantics(action).label, contains('Actions'));
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(opens, 1);
          final bounds = tester.getRect(action);
          expect(
            anchor,
            Offset(
              direction == TextDirection.rtl ? bounds.right : bounds.left,
              bounds.bottom,
            ),
          );
          expect(contents!.map((e) => e.id), ['merge', 'rebase']);
          expect(contents!.last.sectionStart, isTrue);
          expect(contents!.last.enabled, isFalse);
          // Accessibility and a second keyboard/pointer event share the same opening.
          final button = tester.widget<GitIconButton>(
            find.descendant(of: action, matching: find.byType(GitIconButton)),
          );
          button.onPressed!();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: tester.getCenter(action));
          await mouse.moveTo(tester.getCenter(action));
          await mouse.down(tester.getCenter(action));
          await tester.pump();
          await mouse.up();
          expect(opens, 1);
          pending.complete('merge');
          await tester.pumpAndSettle();
          expect(selected, 1);
          await mouse.removePointer();
          semantics.dispose();
        },
      );
    }
  }

  testWidgets(
    'entry rows share secondary-click and released-key menus without trailing controls',
    (tester) async {
      final answers = <Completer<String?>>[];
      var selected = 0, activations = 0;
      final owner = ValueNotifier(0);
      addTearDown(owner.dispose);
      final host = GitHost(
        presentation: presentation,
        icons: icons,
        presentMenu: (_, entries, {position}) {
          expect(HardwareKeyboard.instance.isShiftPressed, isFalse);
          expect(
            HardwareKeyboard.instance.logicalKeysPressed,
            isNot(contains(LogicalKeyboardKey.f10)),
          );
          expect(entries.map((e) => e.id), ['inspect', 'disabled']);
          final answer = Completer<String?>();
          answers.add(answer);
          return answer.future;
        },
        present: <T>(_, _, _, {bool expanded = false}) async => null,
        openDocument: (_, _, {snapshot}) async {},
        prepareMutation: (_, _) async => false,
        chooseDirectory: (_) async => null,
        notify: (_) {},
        drafts: MemoryGitDraftStore(),
      );
      await tester.pumpWidget(
        shell(
          GitHostScope(
            host: host,
            child: Center(
              child: SizedBox(
                width: 400,
                child: ValueListenableBuilder<int>(
                  valueListenable: owner,
                  builder: (_, value, _) => GitActionRow(
                    key: const ValueKey('contextual-row'),
                    dense: true,
                    title: Text('Captured row $value'),
                    onTap: value == 2 ? null : () => activations++,
                    trailing: GitMenuButton(
                      host: host,
                      role: GitMenuRole.entryContext,
                      entries: const [
                        GitMenuEntry('inspect', 'Inspect'),
                        GitMenuEntry('disabled', 'Disabled', enabled: false),
                      ],
                      onSelected: (_) => selected++,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Brightness.light,
          TextDirection.ltr,
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('contextual-row'));
      expect(
        find.descendant(of: row, matching: find.byType(GitIconButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(GitMenuButton)),
        findsNothing,
      );
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(activations, 0);
      expect(answers, hasLength(1));
      owner.value++;
      await tester.pump();
      answers[0].complete('inspect');
      await tester.pumpAndSettle();
      expect(
        selected,
        0,
        reason: 'A delayed native reply cannot act on a replaced row',
      );
      await tester.tap(row);
      expect(activations, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
      await tester.pump();
      expect(answers, hasLength(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
      await tester.pump();
      expect(answers, hasLength(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(answers, hasLength(2));
      answers[1].complete('inspect');
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(answers, hasLength(3));
      answers[2].complete('disabled');
      await tester.pumpAndSettle();
      expect(
        selected,
        1,
        reason:
            'Disabled entries cannot execute even after an invalid native reply',
      );
      // Management rows with only contextual actions must remain focusable.
      owner.value = 2;
      await tester.pump();
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(answers, hasLength(4));
      answers[3].complete(null);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(answers, hasLength(5));
      answers[4].complete('inspect');
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(activations, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('native tooltip never intercepts activation of the covered row', (
    tester,
  ) async {
    var activations = 0;
    final host = GitHost(
      presentation: presentation,
      icons: icons,
      presentMenu: (_, _, {position}) async => null,
      present: <T>(_, _, _, {bool expanded = false}) async => null,
      openDocument: (_, _, {snapshot}) async {},
      prepareMutation: (_, _) async => false,
      chooseDirectory: (_) async => null,
      notify: (_) {},
      drafts: MemoryGitDraftStore(),
    );
    await tester.pumpWidget(
      shell(
        GitHostScope(
          host: host,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 250,
              child: Stack(
                children: [
                  Positioned(
                    left: 40,
                    top: 40,
                    width: 180,
                    height: 32,
                    child: GitTooltip(
                      message: 'A visible native tooltip',
                      child: GitButton(
                        onPressed: () {},
                        child: const Text('Hover source'),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 40,
                    top: 76,
                    width: 180,
                    height: 32,
                    child: GitButton(
                      onPressed: () => activations++,
                      child: const Text('Covered destination'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Brightness.light,
        TextDirection.ltr,
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Hover source')));
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    final tooltip = find.text('A visible native tooltip');
    final destination = find.widgetWithText(GitButton, 'Covered destination');
    expect(tooltip, findsOneWidget);
    expect(
      tester.getRect(tooltip).overlaps(tester.getRect(destination)),
      isTrue,
      reason: 'The test must exercise the actual overlay obstruction',
    );
    await tester.tap(destination);
    await tester.pump();
    expect(activations, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });
}
