import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
        final original = host();
        final configured = GitHost(
          presentation: const TestGitPresentation(
            entryActionPlacement: GitEntryActionPlacement.contextMenu,
          ),
          icons: original.icons,
          present: original.present,
          presentMenu: (_, entries, {position}) async =>
              entries.any((entry) => entry.id == 'stage') ? 'stage' : null,
          openDocument: original.openDocument,
          prepareMutation: original.prepareMutation,
          chooseDirectory: original.chooseDirectory,
          notify: original.notify,
          drafts: original.drafts,
        );
        final session = GitSession(
          client: client,
          repository: repo,
          host: configured,
        );
        await session.start();
        final reviews = <GitComparison>[];
        var reviewContext = 0;
        await tester.pumpWidget(
          GitTestApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
                child: ListenableBuilder(
                  listenable: session.feature,
                  builder: (_, _) => GitFeatureSidebar(
                    controller: session.feature,
                    view: session.feature.view,
                    onSelectView: session.feature.select,
                    onReview: (review) => reviews.add(review.comparison),
                    reviewContext: external ? () => reviewContext : null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('notes.md').last,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        expect(client.mutations.single, isA<StagePaths>());
        if (external) {
          // The host may navigate by a shortcut without rebuilding this sidebar
          // before the command response arrives.
          reviewContext++;
        } else {
          session.feature.select(GitSidebarView.log);
          await tester.pump();
          expect(session.feature.view, GitSidebarView.log);
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
