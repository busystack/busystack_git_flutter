import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _Client extends FixtureClient implements GitWorkflowClient {
  _Client({this.head});
  final GitOid? head;
  final reads = <(GitInspection, Completer<Json>)>[];

  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: 'history-review',
    indexToken: 'history-index',
    head: head,
    branch: 'main',
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );

  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) {
    final result = Completer<Json>();
    reads.add((request, result));
    return result.future;
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('History review cannot create a repository.');
}

Json _row(String oid, String path, String subject) => {
  'commit': GitCommit(
    oid: GitOid(oid * 40),
    parents: const [],
    subject: subject,
    author: 'Fixture',
    email: 'fixture@example.invalid',
    date: DateTime.utc(2026),
    message: subject,
  ).toJson(),
  'pathAtCommit': RepoPath.text(path).toJson(),
  'pathInParent': null,
  'status': 'A',
  'deleted': false,
};

Json _page(List<Json> entries, {bool hasMore = false}) => {
  'entries': entries,
  'hasMore': hasMore,
};

Future<(GitSession, ValueNotifier<RepoPath>, List<Widget>)> _mount(
  WidgetTester tester,
  _Client client,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final presented = <Widget>[];
  final testHost = GitHost(
    present: <T>(context, title, child, {bool expanded = false}) async {
      presented.add(child);
      return null;
    },
    openDocument: (_, _, {snapshot}) async {},
    prepareMutation: (_, _) async => true,
    chooseDirectory: (_) async => null,
    notify: (_) {},
    drafts: MemoryGitDraftStore(),
  );
  final session = GitSession(client: client, repository: repo, host: testHost);
  await session.start();
  final path = ValueNotifier(RepoPath.text('new/chapter.md'));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GitHostScope(
          host: testHost,
          child: ValueListenableBuilder<RepoPath>(
            valueListenable: path,
            builder: (_, path, _) =>
                GitFileHistoryView(session: session, path: path),
          ),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    path.dispose();
    session.dispose();
  });
  return (session, path, presented);
}

TextButton _blame(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Blame…'));

void main() {
  testWidgets('successful empty unborn history has no Blame target', (
    tester,
  ) async {
    final client = _Client();
    final (session, _, presented) = await _mount(tester, client);
    expect(session.snapshot!.head, isNull);
    expect(_blame(tester).onPressed, isNull);
    client.reads.single.$2.complete(_page([]));
    await tester.pump();
    expect(_blame(tester).onPressed, isNull);
    expect(
      find.text('No file history is available for this path and revision.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Blame…'));
    expect(presented, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Blame follows selected historical renamed path and revision', (
    tester,
  ) async {
    final client = _Client();
    final (_, _, presented) = await _mount(tester, client);
    client.reads.single.$2.complete(
      _page([
        _row('a', 'new/chapter.md', 'Rename chapter'),
        _row('b', 'old/章.md', 'Original historical chapter'),
      ]),
    );
    await tester.pump();
    final oldBlame = _blame(tester).onPressed!;
    await tester.tap(find.text('Original historical chapter'));
    oldBlame(); // retired before the replacement button has even rebuilt
    expect(presented, isEmpty);
    await tester.pump();
    await tester.tap(find.text('Blame…'));
    final scope = presented.single as GitHostScope;
    final blame = scope.child as GitBlameView;
    expect(blame.path, RepoPath.text('old/章.md'));
    expect(blame.revision, GitOid('b' * 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an existing HEAD does not become an absent history target', (
    tester,
  ) async {
    final client = _Client(head: GitOid('d' * 40));
    final (_, _, presented) = await _mount(tester, client);
    client.reads.single.$2.complete(_page([]));
    await tester.pump();
    expect(_blame(tester).onPressed, isNull);
    expect(
      find.text('No file history is available for this path and revision.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Blame…'));
    expect(presented, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a historical deletion has no committed file to blame', (
    tester,
  ) async {
    final client = _Client(head: GitOid('d' * 40));
    final (_, _, presented) = await _mount(tester, client);
    client.reads.single.$2.complete(
      _page([
        {..._row('a', 'new/chapter.md', 'Remove chapter'), 'deleted': true},
      ]),
    );
    await tester.pump();
    expect(find.text('Remove chapter'), findsOneWidget);
    expect(_blame(tester).onPressed, isNull);
    await tester.tap(find.text('Blame…'));
    expect(presented, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page loading and failure retire old Blame and empty previews', (
    tester,
  ) async {
    final client = _Client();
    final (_, _, presented) = await _mount(tester, client);
    client.reads.single.$2.complete(
      _page([_row('a', 'new/chapter.md', 'First page')], hasMore: true),
    );
    await tester.pump();
    final oldBlame = _blame(tester).onPressed!;
    await tester.tap(find.text('Next page'));
    oldBlame();
    expect(presented, isEmpty);
    await tester.pump();
    expect(_blame(tester).onPressed, isNull);
    client.reads.last.$2.completeError(
      const GitException(GitErrorCode.missingContent),
    );
    await tester.pump();
    expect(find.byType(GitFailurePanel), findsOneWidget);
    expect(_blame(tester).onPressed, isNull);
    expect(find.byType(GitDiffView), findsNothing);
    expect(
      find.text('No file history is available for this path and revision.'),
      findsNothing,
    );
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    client.reads.last.$2.complete(_page([]));
    await tester.pump();
    oldBlame();
    expect(presented, isEmpty);
    expect(find.byType(GitFailurePanel), findsNothing);
    expect(
      find.text('No file history is available for this path and revision.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history path changes and close reject late completions', (
    tester,
  ) async {
    final client = _Client();
    final (_, path, presented) = await _mount(tester, client);
    path.value = RepoPath.text('other/別.md');
    await tester.pump();
    expect(client.reads.length, 2);
    client.reads.last.$2.complete(
      _page([_row('c', 'historical/別.md', 'Current path history')]),
    );
    await tester.pump();
    client.reads.first.$2.complete(
      _page([_row('a', 'obsolete.md', 'Obsolete path history')]),
    );
    await tester.pump();
    expect(find.text('Obsolete path history'), findsNothing);
    final oldBlame = _blame(tester).onPressed!;
    path.value = RepoPath.text('closing.md');
    await tester.pump();
    oldBlame();
    expect(presented, isEmpty);
    await tester.pumpWidget(const SizedBox());
    client.reads.last.$2.completeError(
      const GitException(GitErrorCode.disconnected),
    );
    await tester.pump();
    oldBlame();
    expect(presented, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
