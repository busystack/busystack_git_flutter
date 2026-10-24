import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  for (final external in [false, true]) {
    testWidgets(
      'late staging completion preserves ${external ? 'host document navigation' : 'navigation to Log'}',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = FixtureClient()..pending = Completer<GitOutcome>();
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        final reviews = <GitComparison>[];
        var logOpened = false;
        var reviewContext = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
                child: GitCommitView(
                  session: session,
                  onReview: reviews.add,
                  reviewContext: () => reviewContext,
                  onLog: () => logOpened = true,
                  onBranches: () {},
                  onPush: () {},
                  onMore: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Stage file'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        expect(client.mutations.single, isA<StagePaths>());
        if (external) {
          // The host may navigate by a shortcut without rebuilding this sidebar
          // before the command response arrives.
          reviewContext++;
        } else {
          await tester.tap(find.byTooltip('Log'));
          await tester.pump();
          expect(logOpened, true);
        }
        client.pending!.complete(
          GitOutcome(phase: GitOperationPhase.completed, snapshot: snapshot()),
        );
        await tester.pumpAndSettle();
        expect(
          reviews,
          isEmpty,
          reason:
              'An earlier stage must not reopen a diff after Log was selected.',
        );
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
