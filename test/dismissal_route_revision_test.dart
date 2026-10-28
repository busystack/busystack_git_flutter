import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

class _Pops extends NavigatorObserver {
  final names = <String?>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name);
  }
}

class _Review {
  _Review() {
    text.addListener(() => textRevision++);
  }
  final navigation = GlobalKey<NavigatorState>();
  final text = TextEditingController(text: 'saved');
  final source = ValueNotifier(0), otherAllowsPop = ValueNotifier(true);
  final observer = _Pops();
  late final changes = Listenable.merge([text, source]);
  var textRevision = 0, confirmations = 0;
  var decision = Completer<bool>();
  bool get clean => text.text == 'saved';

  Widget app() => MaterialApp(
    navigatorKey: navigation,
    navigatorObservers: [observer],
    home: Scaffold(
      body: Column(
        children: [
          const Text('Parent document'),
          TextButton(
            onPressed: () => navigation.currentState!.push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'editor'),
                builder: (context) => ValueListenableBuilder<bool>(
                  valueListenable: otherAllowsPop,
                  builder: (context, allowed, _) => PopScope<void>(
                    canPop: allowed,
                    child: GitDraftGuard(
                      host: host(),
                      canDismiss: clean,
                      isDismissible: () => clean,
                      revisionChanges: changes,
                      revisionIdentity: () => (textRevision, source.value),
                      confirmDiscard: () {
                        confirmations++;
                        return decision.future;
                      },
                      child: Scaffold(
                        body: Column(
                          children: [
                            const Text('Editable review'),
                            TextField(controller: text),
                            TextButton(
                              onPressed: () =>
                                  unawaited(Navigator.of(context).maybePop()),
                              child: const Text('Close editor'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Open review'),
          ),
        ],
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
  }

  Future<void> closeWithoutFrame(WidgetTester tester) async {
    await tester.tap(find.text('Close editor'));
    await tester.idle(); // Flush microtasks only; deliberately no frame.
  }

  void dispose() {
    text.dispose();
    source.dispose();
    otherAllowsPop.dispose();
  }
}

void main() {
  testWidgets('typing then Close before a frame preserves value on Cancel', (
    tester,
  ) async {
    final review = _Review();
    addTearDown(review.dispose);
    await review.open(tester);
    await tester.enterText(find.byType(TextField), 'manual draft');
    review.text.value = review.text.value.copyWith(
      selection: const TextSelection(baseOffset: 1, extentOffset: 4),
      composing: const TextRange(start: 0, end: 3),
    );
    final before = review.text.value;
    await review.closeWithoutFrame(tester);
    expect(review.confirmations, 1);
    expect(review.observer.names, isEmpty);
    review.decision.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Editable review'), findsOneWidget);
    expect(review.text.value, before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'repeated immediate Close confirms once and pops only its review',
    (tester) async {
      final review = _Review();
      addTearDown(review.dispose);
      await review.open(tester);
      await tester.enterText(find.byType(TextField), 'manual draft');
      await review.closeWithoutFrame(tester);
      await review.closeWithoutFrame(tester);
      expect(review.confirmations, 1);
      review.decision.complete(true);
      await tester.pumpAndSettle();
      expect(review.observer.names, ['editor']);
      expect(find.text('Parent document'), findsOneWidget);
      expect(find.text('Editable review'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'approved discard respects another veto and restores its own guard',
    (tester) async {
      final review = _Review()..otherAllowsPop.value = false;
      addTearDown(review.dispose);
      await review.open(tester);
      await tester.enterText(find.byType(TextField), 'manual draft');
      await review.closeWithoutFrame(tester);
      review.decision.complete(true);
      await tester.pumpAndSettle();
      expect(review.observer.names, isEmpty);
      expect(find.text('Editable review'), findsOneWidget);

      review.decision = Completer<bool>();
      await review.closeWithoutFrame(tester);
      expect(review.confirmations, 2);
      review.decision.complete(false);
      await tester.pumpAndSettle();
      expect(review.text.text, 'manual draft');
      review.otherAllowsPop.value = true;
      await tester.pumpAndSettle();
      review.decision = Completer<bool>();
      await review.closeWithoutFrame(tester);
      expect(review.confirmations, 3);
      review.decision.complete(true);
      await tester.pumpAndSettle();
      expect(review.observer.names, ['editor']);
      expect(find.text('Parent document'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('new typing cannot inherit a pending discard decision', (
    tester,
  ) async {
    final review = _Review();
    addTearDown(review.dispose);
    await review.open(tester);
    await tester.enterText(find.byType(TextField), 'submitted B');
    await review.closeWithoutFrame(tester);
    review.text.text = 'newer C';
    review.decision.complete(true);
    await tester.pumpAndSettle();
    expect(review.observer.names, isEmpty);
    expect(find.text('Editable review'), findsOneWidget);
    expect(review.text.text, 'newer C');
    review.decision = Completer<bool>();
    await review.closeWithoutFrame(tester);
    expect(review.confirmations, 2);
    review.decision.complete(true);
    await tester.pumpAndSettle();
    expect(review.observer.names, ['editor']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a replaced source invalidates pending consent without a text edit',
    (tester) async {
      final review = _Review();
      addTearDown(review.dispose);
      await review.open(tester);
      await tester.enterText(find.byType(TextField), 'manual draft');
      await review.closeWithoutFrame(tester);
      review.source.value++;
      review.decision.complete(true);
      await tester.pumpAndSettle();
      expect(review.observer.names, isEmpty);
      expect(find.text('Editable review'), findsOneWidget);
      expect(review.text.text, 'manual draft');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late close completion and retired listeners cannot pop a replacement',
    (tester) async {
      final review = _Review();
      addTearDown(review.dispose);
      await review.open(tester);
      await tester.enterText(find.byType(TextField), 'manual draft');
      await review.closeWithoutFrame(tester);
      review.navigation.currentState!
          .pop(); // Explicit successful owner completion.
      await tester.pumpAndSettle();
      unawaited(
        review.navigation.currentState!.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'replacement'),
            builder: (_) => const Scaffold(body: Text('Replacement review')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      review.text.text = 'retired input';
      review.decision.complete(true);
      await tester.pumpAndSettle();
      expect(review.observer.names, ['editor']);
      expect(find.text('Replacement review'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
