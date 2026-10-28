import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:busystack_git_flutter/src/reference_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _Candidates extends FixtureClient {
  Completer<HistoryPage>? read;
  @override
  Future<List<GitReference>> references(RepositoryId repository) async => [
    GitReference(name: 'refs/heads/feature', oid: GitOid('a' * 40)),
    GitReference(name: 'refs/tags/release', oid: GitOid('b' * 40), type: 'tag'),
    GitReference(
      name: 'refs/tags/blob-content',
      oid: GitOid('c' * 40),
      type: 'blob',
    ),
    GitReference(
      name: 'refs/tags/tree-content',
      oid: GitOid('d' * 40),
      type: 'tree',
    ),
    GitReference(name: 'refs/remotes/origin/HEAD', oid: GitOid('a' * 40)),
    GitReference(name: 'refs/stash', oid: GitOid('e' * 40)),
  ];
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) => read!.future;
}

void main() {
  for (final fails in [false, true]) {
    testWidgets(
      'revision picker offers commit candidates and retains failed review, failure: $fails',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _Candidates()..read = Completer<HistoryPage>();
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        addTearDown(session.dispose);
        GitRevisionTarget? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await gitChooseRevision(
                      context,
                      session,
                      'Choose source',
                    );
                  },
                  child: const Text('Choose source'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose source'));
        await tester.pumpAndSettle();
        expect(find.text('feature'), findsOneWidget);
        expect(find.text('release'), findsOneWidget);
        expect(find.text('blob-content'), findsNothing);
        expect(find.text('tree-content'), findsNothing);
        expect(find.text('origin/HEAD'), findsNothing);
        expect(find.text('refs/stash'), findsNothing);
        await tester.tap(find.text('feature'));
        await tester.pump();
        if (fails) {
          client.read!.completeError(
            StateError('Connection ended while resolving source'),
          );
        } else {
          client.read!.complete(
            HistoryPage(
              [
                GitCommit(
                  oid: GitOid('a' * 40),
                  parents: const [],
                  subject: 'feature',
                  author: 'Fixture',
                  email: 'fixture@example.invalid',
                  date: DateTime.utc(2026),
                ),
              ],
              nextOffset: 1,
              hasMore: false,
              anchor: 'refs',
            ),
          );
        }
        await tester.pumpAndSettle();
        if (fails) {
          expect(result, isNull);
          expect(find.byType(GitFailurePanel), findsOneWidget);
          expect(find.text('feature'), findsOneWidget);
        } else {
          expect(result!.oid, GitOid('a' * 40));
          expect(result!.reference, 'refs/heads/feature');
          expect(result!.referenceTip, GitOid('a' * 40));
          expect(find.text('feature'), findsNothing);
        }
        expect(client.mutations, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
