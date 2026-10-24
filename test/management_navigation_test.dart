import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

const linked = RepositoryId(
  root: '/fixture/linked',
  gitDir: '/fixture/repo/.git/worktrees/linked',
  commonDir: '/fixture/repo/.git',
  objectFormat: 'sha1',
);

final class NavigationClient extends FixtureClient
    implements GitWorkflowClient {
  @override
  Future<List<GitReference>> references(RepositoryId repository) async => [
    GitReference(
      name: 'refs/heads/linked',
      oid: GitOid('a' * 40),
      worktreePath: linked.root,
    ),
  ];

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    'entries': [
      if (request.kind == GitInspectionKind.worktrees)
        {'path': linked.root, 'branch': 'refs/heads/linked', 'dirty': false}
      else
        {
          'path': RepoPath.text('vendor/child').toJson(),
          'recorded': 'a' * 40,
          'checkedOut': 'a' * 40,
          'initialized': true,
          'dirty': false,
          'repository': linked.toJson(),
        },
    ],
    'hasMore': false,
  };

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) =>
      throw StateError('Opening an existing folder must not create anything.');
}

void main() {
  for (final action in ['worktrees', 'submodules', 'branches']) {
    testWidgets(
      '$action navigation closes its management dialog before retiring the host workspace',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final original = host();
        final client = NavigationClient();
        late GitSession session;
        late BuildContext hostContext;
        late StateSetter rebuild;
        String? opened;
        bool? hostRouteCurrent;
        final configured = GitHost(
          present: <T>(context, title, child, {bool expanded = false}) =>
              showDialog<T>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(width: 800, height: 560, child: child),
                ),
              ),
          presentMenu: (_, entries, {position}) async =>
              entries.any((e) => e.id == action) ? action : 'open',
          openDocument: original.openDocument,
          chooseDirectory: original.chooseDirectory,
          notify: original.notify,
          drafts: original.drafts,
          prepareMutation: original.prepareMutation,
          openFolder: (path) async {
            hostRouteCurrent = ModalRoute.of(hostContext)!.isCurrent;
            session.dispose();
            rebuild(() => opened = path);
          },
        );
        session = GitSession(
          client: client,
          repository: repo,
          host: configured,
        );
        await session.start();
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                hostContext = context;
                rebuild = setState;
                return Scaffold(
                  body: opened == null
                      ? TextButton(
                          onPressed: () =>
                              GitWorkflowUi(context, session).more(),
                          child: const Text('Repository actions'),
                        )
                      : Text('Opened $opened'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Repository actions'));
        await tester.pumpAndSettle();
        final rowMenu = find.byTooltip(
          action == 'branches' ? 'Actions for refs/heads/linked' : 'Actions',
        );
        expect(rowMenu, findsOneWidget);
        await tester.tap(rowMenu);
        await tester.pumpAndSettle();
        expect(opened, linked.root);
        expect(hostRouteCurrent, isTrue);
        expect(find.text('Opened ${linked.root}'), findsOneWidget);
        expect(find.byType(GitWorktreesView), findsNothing);
        expect(find.byType(GitSubmodulesView), findsNothing);
        expect(find.byType(GitBranchesView), findsNothing);
        expect(client.mutations, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
