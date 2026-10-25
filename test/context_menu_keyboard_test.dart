import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  testWidgets('change-tree native menus wait for all trigger releases', (
    tester,
  ) async {
    final original = host();
    var menus = 0;
    final configured = GitHost(
      present: original.present,
      openDocument: original.openDocument,
      prepareMutation: original.prepareMutation,
      chooseDirectory: original.chooseDirectory,
      notify: original.notify,
      drafts: original.drafts,
      presentMenu: (_, entries, {position}) async {
        expect(HardwareKeyboard.instance.isShiftPressed, isFalse);
        expect(
          HardwareKeyboard.instance.logicalKeysPressed,
          isNot(contains(LogicalKeyboardKey.f10)),
        );
        expect(
          HardwareKeyboard.instance.logicalKeysPressed,
          isNot(contains(LogicalKeyboardKey.contextMenu)),
        );
        expect(entries.map((e) => e.id), contains('stage'));
        menus++;
        return null;
      },
    );
    final session = GitSession(
      client: FixtureClient(),
      repository: repo,
      host: configured,
    );
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHostScope(
            host: configured,
            child: GitChangeTree(session: session, onReview: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('notes.md').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
      await tester.pump();
      expect(menus, attempt);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
      await tester.pump();
      expect(menus, attempt);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(menus, attempt + 1);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(menus, 3);

    // A pointer selection while the keys are held must not retarget the menu.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
    await tester.tap(find.text('notes.md').last);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(menus, 3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(menus, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
