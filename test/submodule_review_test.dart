import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

const child = RepositoryId(
  root: '/fixture/repo/nested',
  gitDir: '/fixture/repo/.git/modules/nested',
  commonDir: '/fixture/repo/.git/modules/nested',
  objectFormat: 'sha1',
);

final class SubmoduleClient extends FixtureClient implements GitWorkflowClient {
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    'head': null,
    'indexToken': 'reviewed-parent-index',
    'hasMore': false,
    'entries': [
      {
        'path': RepoPath.text('nested').toJson(),
        'recorded': 'a' * 40,
        'checkedOut': 'b' * 40,
        'workingToken': 'reviewed-child-tip',
        'initialized': true,
        'dirty': false,
        'repository': child.toJson(),
      },
    ],
  };
  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Submodule review cannot create a repository.');
}

void main() {
  for (final allowChild in [true, false]) {
    testWidgets(
      'submodule update obtains child-scoped preparation before parent ($allowChild)',
      (tester) async {
        final client = SubmoduleClient(), prepared = <RepositoryId>[];
        final original = host();
        final configured = GitHost(
          present: original.present,
          openDocument: original.openDocument,
          chooseDirectory: original.chooseDirectory,
          notify: original.notify,
          drafts: original.drafts,
          presentMenu: (_, _, {position}) async => 'updateRecorded',
          prepareMutation: (repository, request) async {
            prepared.add(repository);
            expect(request, isA<SubmoduleMutation>());
            return repository != child || allowChild;
          },
        );
        final session = GitSession(
          client: client,
          repository: repo,
          host: configured,
        );
        await session.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: GitSubmodulesView(session: session)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply submodule operation'));
        await tester.pumpAndSettle();
        expect(prepared, allowChild ? [child, repo] : [child]);
        if (allowChild) {
          final request = client.mutations.single as SubmoduleMutation;
          expect(request.expectedIndex, 'reviewed-parent-index');
          expect(request.contentTokens, {
            RepoPath.text('nested').key: 'reviewed-child-tip',
          });
          expect(request.recursive, isFalse);
        } else {
          expect(client.mutations, isEmpty);
        }
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
