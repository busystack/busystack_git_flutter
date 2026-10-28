import 'dart:convert';
import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _HistoryClient extends FixtureClient implements GitWorkflowClient {
  final parent = GitOid('b' * 40), commit = GitOid('a' * 40);
  final contentCalls = <(RepoPath, ContentVersion)>[];
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    'entries': [
      {
        'commit': GitCommit(
          oid: commit,
          parents: [parent],
          subject: 'Rename chapter',
          author: 'Fixture',
          email: 'fixture@example.invalid',
          date: DateTime.utc(2026),
          message: 'Rename chapter',
        ).toJson(),
        'pathAtCommit': RepoPath.text('new/chapter.md').toJson(),
        'pathInParent': RepoPath.text('old/chapter.md').toJson(),
        'status': 'R100',
        'deleted': false,
      },
    ],
    'hasMore': false,
  };

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('History inspection must not create a repository.');

  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    contentCalls.add((path, version));
    return GitContent(
      path: path,
      version: version,
      availability: ContentAvailability.present,
      token: '${path.key}:${version.revision}',
      mode: '100644',
      bytes: utf8.encode('same text\n'),
    );
  }
}

final class _MergeHistoryClient extends _HistoryClient {
  final otherParent = GitOid('c' * 40);
  final reads = <(GitOid?, Completer<List<GitChange>>)>[];
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    final data = await super.inspect(
      repository,
      request,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    final row = (data['entries'] as List).single as Json;
    (row['commit'] as Json)['parents'] = [parent.value, otherParent.value];
    return data;
  }

  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) {
    final completer = Completer<List<GitChange>>();
    reads.add((parent, completer));
    return completer.future;
  }

  List<GitChange> changes(String from) => [
    GitChange(
      path: RepoPath.text('new/chapter.md'),
      originalPath: RepoPath.text(from),
      index: 'R',
      worktree: '.',
      headMode: '100644',
      indexMode: '100644',
    ),
  ];
}

Future<GitSession> _mountHistory(
  WidgetTester tester,
  FixtureClient client,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GitHostScope(
          host: session.host,
          child: GitFileHistoryView(
            session: session,
            path: RepoPath.text('new/chapter.md'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return session;
}

void main() {
  testWidgets('merge history reads rename metadata for each selected parent', (
    tester,
  ) async {
    final client = _MergeHistoryClient();
    await _mountHistory(tester, client);
    expect(client.reads.single.$1, client.parent);
    client.reads.single.$2.complete(client.changes('old/chapter.md'));
    await tester.pump();
    expect(
      tester.widget<GitDiffView>(find.byType(GitDiffView)).comparison.leftPath,
      RepoPath.text('old/chapter.md'),
    );
    final oldPicker = tester.widget<DropdownButton<GitOid>>(
      find.byType(DropdownButton<GitOid>),
    );
    oldPicker.onChanged!(client.otherParent);
    oldPicker.onChanged!(
      client.parent,
    ); // obsolete callback must already be retired
    await tester.pump();
    expect(client.reads.last.$1, client.otherParent);
    expect(find.byType(GitDiffView), findsNothing);
    client.reads.last.$2.complete(client.changes('side/東京.md'));
    await tester.pump();
    final comparison = tester
        .widget<GitDiffView>(find.byType(GitDiffView))
        .comparison;
    expect(comparison.left.revision, client.otherParent);
    expect(comparison.leftPath, RepoPath.text('side/東京.md'));
    expect(comparison.path, RepoPath.text('new/chapter.md'));
    expect(comparison.right.revision, client.commit);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable merge parent is an error and late reads cannot restore it',
    (tester) async {
      final client = _MergeHistoryClient();
      await _mountHistory(tester, client);
      final picker = tester.widget<DropdownButton<GitOid>>(
        find.byType(DropdownButton<GitOid>),
      );
      picker.onChanged!(client.otherParent);
      await tester.pump();
      client.reads.last.$2.completeError(
        const GitException(GitErrorCode.missingContent),
      );
      await tester.pumpAndSettle();
      client.reads.first.$2.complete(client.changes('obsolete.md'));
      await tester.pump();
      expect(find.byType(GitFailurePanel), findsOneWidget);
      expect(find.byType(GitDiffView), findsNothing);
      expect(find.text('No changes'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(GitFailurePanel),
          matching: find.text('Refresh'),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      client.reads.last.$2.complete(client.changes('late.md'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('file history previews the renamed file against its parent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _HistoryClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHostScope(
            host: session.host,
            child: GitFileHistoryView(
              session: session,
              path: RepoPath.text('new/chapter.md'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      client.contentCalls.any(
        (call) =>
            call.$1.display == 'old/chapter.md' &&
            call.$2.revision == client.parent,
      ),
      isTrue,
    );
    expect(
      client.contentCalls.any(
        (call) =>
            call.$1.display == 'new/chapter.md' &&
            call.$2.revision == client.commit,
      ),
      isTrue,
    );
    expect(find.byType(GitDiffView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
