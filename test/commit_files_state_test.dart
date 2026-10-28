import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

GitCommit _commit(String id) => GitCommit(
  oid: GitOid(id * 40),
  parents: const [],
  subject: 'Reviewed commit $id',
  author: 'Fixture',
  email: 'fixture@example.invalid',
  date: DateTime.utc(2026),
  message: 'Preserved message $id',
);

final class _FilesClient extends FixtureClient {
  final reads = <Completer<List<GitChange>>>[];

  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) {
    final read = Completer<List<GitChange>>();
    reads.add(read);
    return read.future;
  }
}

void main() {
  testWidgets(
    'expanded outgoing comparison returns to its file scroll and splitter geometry',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _FilesClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitCommitFiles(session: session, commit: _commit('a')),
          ),
        ),
      );
      client.reads.single.complete([
        for (var i = 0; i < 30; i++)
          GitChange(
            path: RepoPath.text('chapter-$i.md'),
            index: 'M',
            worktree: '.',
          ),
      ]);
      await tester.pump();
      final files = find.byWidgetPredicate(
        (w) => w is ListView && w.key is PageStorageKey,
      );
      final scroll = tester.widget<ListView>(files).controller!;
      scroll.jumpTo(200);
      await tester.pump();
      await tester.drag(
        find.bySemanticsLabel('Resize Git panes'),
        const Offset(0, 50),
      );
      await tester.pump();
      final offset = scroll.offset,
          geometry = tester.getRect(files),
          split = session.split('outgoingFilesPreviewSplit', .32);
      final state = tester.state(find.byType(GitDiffView));
      await tester.tap(find.byTooltip('Review difference'));
      await tester.pump();
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pump();
      expect(scroll.offset, closeTo(offset, .01));
      expect(tester.getRect(files), geometry);
      expect(session.split('outgoingFilesPreviewSplit', .32), split);
      expect(tester.state(find.byType(GitDiffView)), same(state));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'outgoing files stay inline, navigate the reviewed list, and replace rename paths for each parent',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _FilesClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      final firstParent = GitOid('b' * 40), secondParent = GitOid('c' * 40);
      final commit = GitCommit(
        oid: GitOid('a' * 40),
        parents: [firstParent, secondParent],
        subject: 'merge',
        author: 'Fixture',
        email: 'fixture@example.invalid',
        date: DateTime.utc(2026),
        message: 'merge review',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitCommitFiles(session: session, commit: commit),
          ),
        ),
      );
      client.reads.single.complete([
        GitChange(
          path: RepoPath.text('renamed.md'),
          originalPath: RepoPath.text('old-first.md'),
          index: 'R',
          worktree: '.',
        ),
        GitChange(path: RepoPath.text('second.md'), index: 'M', worktree: '.'),
      ]);
      await tester.pump();
      var preview = tester.widget<GitDiffView>(find.byType(GitDiffView));
      expect(preview.comparison.left.revision, firstParent);
      expect(preview.comparison.leftPath, RepoPath.text('old-first.md'));
      expect(find.byType(Dialog), findsNothing);
      final oldNext = preview.onNextFile!;
      oldNext();
      await tester.pump();
      preview = tester.widget<GitDiffView>(find.byType(GitDiffView));
      expect(preview.comparison.path, RepoPath.text('second.md'));
      final beforeExpansion = tester.state(find.byType(GitDiffView));
      await tester.tap(find.byTooltip('Review difference'));
      await tester.pump();
      expect(tester.state(find.byType(GitDiffView)), same(beforeExpansion));
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pump();
      expect(tester.state(find.byType(GitDiffView)), same(beforeExpansion));
      tester
          .widget<DropdownButton<GitOid>>(find.byType(DropdownButton<GitOid>))
          .onChanged!(secondParent);
      await tester.pump();
      oldNext();
      await tester.pump();
      expect(find.byType(GitDiffView), findsNothing);
      client.reads.last.complete([
        GitChange(
          path: RepoPath.text('renamed.md'),
          originalPath: RepoPath.text('old-second.md'),
          index: 'R',
          worktree: '.',
        ),
      ]);
      await tester.pump();
      preview = tester.widget<GitDiffView>(find.byType(GitDiffView));
      expect(preview.comparison.left.revision, secondParent);
      expect(preview.comparison.leftPath, RepoPath.text('old-second.md'));
      expect(preview.onNextFile, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same commit ID in another repository cannot retain or restore the old outgoing files',
    (tester) async {
      final first = _FilesClient(), second = _FilesClient();
      final firstSession = GitSession(
        client: first,
        repository: repo,
        host: host(),
      );
      const other = RepositoryId(
        root: '/fixture/other',
        gitDir: '/fixture/other/.git',
        commonDir: '/fixture/other/.git',
        objectFormat: 'sha1',
      );
      final secondSession = GitSession(
        client: second,
        repository: other,
        host: host(),
      );
      addTearDown(firstSession.dispose);
      addTearDown(secondSession.dispose);
      Future<void> mount(GitSession session) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitCommitFiles(session: session, commit: _commit('a')),
          ),
        ),
      );
      await mount(firstSession);
      await mount(secondSession);
      expect(second.reads, hasLength(1));
      second.reads.single.complete([]);
      await tester.pumpAndSettle();
      first.reads.single.complete([
        GitChange(
          path: RepoPath.text('obsolete.md'),
          index: 'M',
          worktree: '.',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('obsolete.md'), findsNothing);
      expect(find.byType(GitDiffView), findsNothing);
      expect(find.text('No changed files'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('push commit details distinguish loading, failure and empty', (
    tester,
  ) async {
    final client = _FilesClient();
    final session = GitSession(client: client, repository: repo, host: host());
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitFiles(session: session, commit: _commit('a')),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    client.reads.single.completeError(
      const GitException(GitErrorCode.disconnected),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GitFailurePanel), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    expect(find.textContaining('Preserved message a'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(GitFailurePanel),
        matching: find.text('Refresh'),
      ),
    );
    await tester.pump();
    expect(client.reads, hasLength(2));
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    client.reads.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(GitFailurePanel), findsNothing);
    expect(find.bySemanticsLabel('Loading changed files'), findsNothing);
    expect(find.text('No changed files'), findsOneWidget);
    expect(find.bySemanticsLabel('No changed files'), findsOneWidget);
    expect(client.mutations, isEmpty);
  });

  testWidgets('an older file read cannot replace newer push selection', (
    tester,
  ) async {
    final client = _FilesClient();
    final session = GitSession(client: client, repository: repo, host: host());
    addTearDown(session.dispose);
    Future<void> select(String id) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitFiles(session: session, commit: _commit(id)),
        ),
      ),
    );
    await select('a');
    await select('b');
    expect(client.reads, hasLength(2));
    client.reads.last.complete([]);
    await tester.pumpAndSettle();
    client.reads.first.complete([
      GitChange(path: RepoPath.text('obsolete.md'), index: 'M', worktree: '.'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('obsolete.md'), findsNothing);
    expect(find.text('No changed files'), findsOneWidget);
    expect(find.textContaining('Preserved message b'), findsOneWidget);
    expect(client.mutations, isEmpty);
  });
}
