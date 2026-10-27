import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  for (final approve in [true, false]) {
    testWidgets(
      'repeated ${approve ? 'approval' : 'cancellation'} preserves the parent Git review',
      (tester) async {
        final session = GitSession(
          client: FixtureClient(),
          repository: repo,
          host: host(),
        );
        addTearDown(session.dispose);
        final navigator = GlobalKey<NavigatorState>();
        Future<bool>? decision;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Application home')),
          ),
        );
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const Text('Parent Git review'),
                    TextButton(
                      onPressed: () {
                        decision = gitConfirm(
                          context,
                          session,
                          'Review operation',
                          'The reviewed repository remains bound to this action.',
                          action: 'Approve reviewed action',
                        );
                      },
                      child: const Text('Open confirmation'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open confirmation'));
        await tester.pumpAndSettle();
        final VoidCallback submit = approve
            ? tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!
            : tester
                  .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
                  .onPressed!;
        // Native actions can already be queued while a closing route is mounted.
        submit();
        submit();
        await tester.pumpAndSettle();
        expect(await decision, approve);
        expect(find.text('Parent Git review'), findsOneWidget);
        expect(find.text('Application home'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
