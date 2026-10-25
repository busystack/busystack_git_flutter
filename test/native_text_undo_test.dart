import 'package:busystack_git_flutter/src/text_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> historyKey(WidgetTester tester, {bool redo = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  Future<void> open(
    WidgetTester tester,
    TextEditingController controller, {
    ValueChanged<String>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitTextPane(
            label: 'Index',
            controller: controller,
            onChanged: onChanged,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('immediate undo and redo retain the latest bytes and caret', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'old\r\n');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await open(tester, controller, onChanged: changes.add);
    const edited = 'new 😀\r\n';
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: edited,
        selection: TextSelection.collapsed(offset: edited.length),
      ),
    );
    await tester.pump();
    await historyKey(tester);
    expect(controller.text, 'old\r\n');
    await historyKey(tester, redo: true);
    expect(controller.text, edited);
    expect(controller.selection.extentOffset, edited.length);
    expect(changes, containsAllInOrder([edited, 'old\r\n', edited]));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('IME preedit is one committed undo operation', (tester) async {
    final controller = TextEditingController(text: 'base ');
    addTearDown(controller.dispose);
    await open(tester, controller);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base ue9',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 5, end: 8),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base é',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    await historyKey(tester);
    expect(controller.text, 'base ');
    await historyKey(tester, redo: true);
    expect(controller.text, 'base é');
    expect(controller.value.composing, TextRange.empty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('cancelling IME composition preserves an existing redo', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'base ');
    addTearDown(controller.dispose);
    await open(tester, controller);
    await tester.enterText(find.byType(TextField), 'base saved');
    await tester.pump(const Duration(milliseconds: 600));
    await historyKey(tester);
    expect(controller.text, 'base ');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base uf1',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 5, end: 8),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'base ',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    await historyKey(tester, redo: true);
    expect(controller.text, 'base saved');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
