import 'dart:async';
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
    if (pending != null) return pending!.future;
    return GitOutcome(
      phase: GitOperationPhase.failed,
      snapshot: snapshot(),
      error: const GitException(GitErrorCode.staleReview),
    );
  }
}

void main() {
  testWidgets(
    'clipboard line-ending conversion requires review before writing the index',
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
      final field = find.byWidgetPredicate(
        (w) => w is TextField && !w.readOnly,
      );
      const pasted = '\uFEFFPasted prose\n';
      await tester.enterText(field, pasted);
      await tester.tap(find.text('Write edited result to this index entry'));
      await tester.pumpAndSettle();
      expect(client.mutations, isEmpty);
      expect(
        find.textContaining('from CRLF line endings to LF line endings'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, pasted);
      expect(client.mutations, isEmpty);
      await tester.tap(find.text('Write edited result to this index entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write reviewed index result'));
      await tester.pumpAndSettle();
      expect(
        (client.mutations.single as WriteIndex).bytes,
        utf8.encode(pasted),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'pending index write freezes reviewed text and preserves it after failure',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = BomIndexClient()..pending = Completer<GitOutcome>();
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
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Editable index content',
      );
      const edited = '\uFEFFReviewed prose\r\n';
      await tester.enterText(field, edited);
      await tester.tap(find.text('Write edited result to this index entry'));
      await tester.pump();
      expect(
        (client.mutations.single as WriteIndex).bytes,
        utf8.encode(edited),
      );
      expect(tester.widget<TextField>(field).readOnly, isTrue);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Undo'))
            .onPressed,
        isNull,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      client.pending!.complete(
        GitOutcome(
          phase: GitOperationPhase.failed,
          snapshot: snapshot(),
          error: const GitException(GitErrorCode.staleReview),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).readOnly, isFalse);
      expect(tester.widget<TextField>(field).controller!.text, edited);
      expect(client.mutations, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

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
        expect(
          find.textContaining('UTF-8 with byte-order mark (BOM)'),
          findsOneWidget,
        );
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
          await tester.tap(find.text('Write reviewed index result'));
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
