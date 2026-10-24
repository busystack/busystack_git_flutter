import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final class CreationClient extends FixtureClient implements GitWorkflowClient {
  GitCreation? requested;
  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    requested = request;
    return const GitCreationOutcome(
      phase: GitOperationPhase.completed,
      repository: repo,
      createdDirectory: true,
      destinationStillExists: true,
    );
  }

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Creation does not inspect an existing repository.');
}

void main() {
  testWidgets(
    'creation returns a repository after closing its dialog before host navigation',
    (tester) async {
      final client = CreationClient();
      RepositoryId? opened;
      bool? hostRouteCurrent;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final created = await showDialog<RepositoryId>(
                      context: context,
                      builder: (_) => Dialog(
                        child: SizedBox(
                          width: 560,
                          child: GitCreationView(
                            client: client,
                            chooseDirectory: (_) async => null,
                          ),
                        ),
                      ),
                    );
                    // The application may replace its workspace from this point onwards.
                    opened = created;
                    if (context.mounted)
                      hostRouteCurrent = ModalRoute.of(context)!.isCurrent;
                  },
                  child: const Text('Open clone dialog'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open clone dialog'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText ==
                  'Repository URL or local Git source',
        ),
        '/fixture/source',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Final clone destination',
        ),
        '/fixture/destination',
      );
      await tester.tap(find.text('Clone'));
      await tester.pumpAndSettle();
      expect(client.requested!.destination, '/fixture/destination');
      expect(opened, repo);
      expect(hostRouteCurrent, isTrue);
      expect(find.byType(GitCreationView), findsNothing);
      expect(find.text('Open clone dialog'), findsOneWidget);
    },
  );
}
