import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class BomIndexClient extends FixtureClient {
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode('\uFEFFOriginal prose\r\n'),
  );

  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    return GitOutcome(
      phase: GitOperationPhase.failed,
      snapshot: snapshot(),
      error: const GitException(GitErrorCode.staleReview),
    );
  }
}

void main() {
  for (final removeBom in [false, true]) {
    testWidgets(
      removeBom
          ? 'index editor reviews a deliberate BOM removal and retains the draft on cancel'
          : 'index editor preserves its BOM and exact line endings',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = BomIndexClient();
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GitIndexEditor(
                session: session,
                path: RepoPath.text('prose.md'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editable = find.byWidgetPredicate(
          (w) => w is TextField && !w.readOnly,
        );
        expect(
          tester.widget<TextField>(editable).controller!.text,
          '\uFEFFOriginal prose\r\n',
        );
        expect(find.text('UTF-8 with byte-order mark (BOM)'), findsOneWidget);
        final edited = '${removeBom ? '' : '\uFEFF'}Reviewed prose\r\n';
        await tester.enterText(editable, edited);
        await tester.tap(find.text('Write edited result to this index entry'));
        await tester.pumpAndSettle();
        if (removeBom) {
          expect(client.mutations, isEmpty);
          expect(
            find.textContaining('removes the UTF-8 byte-order mark'),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(editable).controller!.text, edited);
          expect(client.mutations, isEmpty);
          await tester.tap(
            find.text('Write edited result to this index entry'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Write changed encoding'));
          await tester.pumpAndSettle();
        }
        expect(
          (client.mutations.single as WriteIndex).bytes,
          utf8.encode(edited),
        );
        expect(tester.widget<TextField>(editable).controller!.text, edited);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
