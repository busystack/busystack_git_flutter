import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final class _StashClient extends FixtureClient implements GitWorkflowClient {
  final identity = GitOid('a' * 40);
  String selector = 'stash@{0}';
  _StashClient() {
    historyCommits = [
      GitCommit(
        oid: identity,
        parents: [GitOid('b' * 40), GitOid('c' * 40)],
        subject: 'On main: Reviewed writing',
        author: 'Writer',
        email: 'writer@example.invalid',
        date: DateTime.utc(2026),
        message: 'On main: Reviewed writing',
      ),
    ];
  }

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    'hasMore': false,
    'entries': [
      {
        'identity': identity.value,
        'selector': selector,
        'message': 'On main: Reviewed writing',
        'time': 1790000000,
      },
    ],
  };

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Stash review cannot create a repository.');
}

void main() {
  testWidgets(
    'apply retains reviewed stash details and actions across selector changes',
    (tester) async {
      final client = _StashClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitStashesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('On main: Reviewed writing').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Apply and retain'));
      await tester.pumpAndSettle();
      final request = client.mutations.single as StashMutation;
      expect(request.action, StashAction.apply);
      expect(request.identity, client.identity);
      expect(request.restoreIndex, isTrue);

      // Another client may insert a newer stash without removing this object.
      client.selector = 'stash@{1}';
      await session.refresh();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Drop stash…'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Select a stash to inspect its changes'), findsNothing);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'On main: Reviewed writing'),
            )
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
