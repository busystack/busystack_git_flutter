import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  for (final dismiss in [true, false]) {
    testWidgets(
      'late index completion preserves ${dismiss ? 'its parent review' : 'a newer modal review'}',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = FixtureClient()..pending = Completer<GitOutcome>();
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        addTearDown(session.dispose);
        await session.start();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Files home')),
          ),
        );
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const Text('Repository review'),
                    TextButton(
                      onPressed: () => unawaited(
                        showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            child: SizedBox(
                              width: 1200,
                              height: 800,
                              child: GitIndexEditor(
                                session: session,
                                path: RepoPath.text('notes.md'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Open index'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open index'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Write edited result to this index entry'));
        await tester.pump();
        expect(client.mutations.single, isA<WriteIndex>());
        if (dismiss) {
          navigator.currentState!.pop();
        } else {
          unawaited(
            showDialog<void>(
              context: navigator.currentContext!,
              builder: (_) => const Dialog(child: Text('Other review')),
            ),
          );
          await tester.pump();
        }
        // The dismissed route remains mounted through its reverse animation. A
        // late successful write must not pop the now-current repository review.
        client.pending!.complete(
          GitOutcome(phase: GitOperationPhase.completed, snapshot: snapshot()),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        if (!dismiss) {
          expect(find.text('Other review'), findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
        }
        expect(find.byType(GitIndexEditor), findsNothing);
        expect(find.text('Repository review'), findsOneWidget);
        expect(find.text('Open index'), findsOneWidget);
        expect(find.text('Files home'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
