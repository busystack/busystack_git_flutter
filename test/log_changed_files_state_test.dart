import 'dart:async';
import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

GitCommit _commit(String id, String subject) => GitCommit(
  oid: GitOid(id * 40),
  parents: const [],
  subject: subject,
  author: 'Fixture',
  email: 'fixture@example.invalid',
  date: DateTime.utc(2026),
  message: 'Details: $subject',
);

final class _ChangedFilesClient extends FixtureClient {
  _ChangedFilesClient() {
    historyCommits = [
      _commit('a', 'Current commit'),
      _commit('b', 'Older commit'),
    ];
  }
  final reads = <Completer<List<GitChange>>>[];
  Completer<HistoryPage>? pendingHistory;
  bool deferContent = false;
  final contentReads = <(RepoPath, ContentVersion, Completer<GitContent>)>[];
  final comparedParents = <GitOid?>[];
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) {
    if (!deferContent)
      return super.content(
        repository,
        path,
        version,
        cancellation: cancellation,
      );
    final completer = Completer<GitContent>();
    contentReads.add((path, version, completer));
    return completer.future;
  }

  void completeContent() {
    for (final (path, version, completer) in contentReads) {
      if (completer.isCompleted) continue;
      completer.complete(
        GitContent(
          path: path,
          version: version,
          availability: ContentAvailability.present,
          token: 'obsolete',
          mode: '100644',
          bytes: utf8.encode('obsolete preview text\n'),
        ),
      );
    }
  }

  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) =>
      pendingHistory?.future ??
      super.history(
        repository,
        filter: filter,
        offset: offset,
        limit: limit,
        anchor: anchor,
        cancellation: cancellation,
      );
  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) {
    comparedParents.add(parent);
    final result = Completer<List<GitChange>>();
    reads.add(result);
    return result.future;
  }
}

Future<void> _mount(WidgetTester tester, _ChangedFilesClient client) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: GitLogView(session: session)),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}

Future<void> _selectFile(
  WidgetTester tester,
  _ChangedFilesClient client,
) async {
  client.reads.last.complete([
    GitChange(
      path: RepoPath.text('chapter/review.md'),
      index: 'M',
      worktree: '.',
    ),
    GitChange(
      path: RepoPath.text('chapter/next.md'),
      index: 'M',
      worktree: '.',
    ),
  ]);
  await tester.pumpAndSettle();
  await tester.tap(find.text('review.md'));
  await tester.pump();
  expect(find.byType(GitDiffView), findsOneWidget);
}

Future<void> _filter(WidgetTester tester) async {
  final message = find.widgetWithText(TextField, 'Message');
  await tester.enterText(message, 'no matching commit');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  for (final expanded in [false, true]) {
    testWidgets(
      'empty filter retires ${expanded ? 'expanded' : 'inline'} review',
      (tester) async {
        final client = _ChangedFilesClient();
        await _mount(tester, client);
        await _selectFile(tester, client);
        if (expanded) {
          await tester.tap(find.byTooltip('Review difference'));
          await tester.pump();
        }
        client.historyCommits = [];
        await _filter(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(GitDiffView), findsNothing);
        expect(
          find.text('No commits match the current filters.'),
          findsOneWidget,
        );
        expect(find.textContaining('review.md'), findsNothing);
      },
    );
  }

  testWidgets(
    'filter replacement invalidates pending file and navigation callbacks immediately',
    (tester) async {
      final client = _ChangedFilesClient();
      await _mount(tester, client);
      await _selectFile(tester, client);
      final preview = tester.widget<GitDiffView>(find.byType(GitDiffView));
      await tester.tap(find.text('Older commit'));
      await tester.pump();
      client.pendingHistory = Completer<HistoryPage>();
      await _filter(tester);
      client.reads.last.complete([
        GitChange(
          path: RepoPath.text('obsolete.md'),
          index: 'M',
          worktree: '.',
        ),
      ]);
      await tester.pump();
      expect(find.text('obsolete.md'), findsNothing);
      preview.onNextFile?.call();
      client.pendingHistory!.complete(
        const HistoryPage([], nextOffset: 0, hasMore: false, anchor: 'empty'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GitDiffView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed replacement history retires preview and closing rejects late completion',
    (tester) async {
      final client = _ChangedFilesClient();
      await _mount(tester, client);
      await _selectFile(tester, client);
      client.pendingHistory = Completer<HistoryPage>();
      await _filter(tester);
      client.pendingHistory!.completeError(
        const GitException(GitErrorCode.disconnected),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GitFailurePanel), findsOneWidget);
      expect(find.byType(GitDiffView), findsNothing);
      expect(find.text('No changed files'), findsNothing);
      client.pendingHistory = Completer<HistoryPage>();
      await tester.tap(find.byTooltip('Refresh Log'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      client.pendingHistory!.complete(
        const HistoryPage([], nextOffset: 0, hasMore: false, anchor: 'empty'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty changed files and repository switch retire selected preview',
    (tester) async {
      final client = _ChangedFilesClient();
      await _mount(tester, client);
      await _selectFile(tester, client);
      final obsolete = tester
          .widget<GitDiffView>(find.byType(GitDiffView))
          .onNextFile;
      expect(obsolete, isNotNull);
      await tester.tap(find.text('Older commit'));
      await tester.pump();
      client.reads.last.complete([]);
      await tester.pumpAndSettle();
      obsolete!();
      await tester.pump();
      expect(find.byType(GitDiffView), findsNothing);
      expect(find.text('No changed files'), findsOneWidget);
      final replacement = _ChangedFilesClient()..historyCommits = [];
      final session = GitSession(
        client: replacement,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitLogView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GitDiffView), findsNothing);
      expect(
        find.text('No commits match the current filters.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('changed merge parent retires preview and old row callbacks', (
    tester,
  ) async {
    final client = _ChangedFilesClient();
    final merge = client.historyCommits.first;
    client.historyCommits = [
      GitCommit(
        oid: merge.oid,
        parents: [GitOid('c' * 40), GitOid('d' * 40)],
        subject: merge.subject,
        author: merge.author,
        email: merge.email,
        date: merge.date,
        message: merge.message,
      ),
    ];
    await _mount(tester, client);
    await _selectFile(tester, client);
    final oldRow = tester
        .widget<ListTile>(find.widgetWithText(ListTile, 'next.md'))
        .onTap!;
    final picker = tester.widget<DropdownButton<GitOid>>(
      find.byType(DropdownButton<GitOid>),
    );
    picker.onChanged!(GitOid('d' * 40));
    await tester.pump();
    oldRow();
    await tester.pump();
    expect(find.byType(GitDiffView), findsNothing);
    expect(client.comparedParents.last, GitOid('d' * 40));
    client.reads.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(GitDiffView), findsNothing);
    expect(find.text('No changed files'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh Log'));
    await tester.pump();
    expect(client.comparedParents.last, GitOid('d' * 40));
    client.reads.last.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh and rapid filters cannot restore late preview content', (
    tester,
  ) async {
    final client = _ChangedFilesClient()..deferContent = true;
    await _mount(tester, client);
    await _selectFile(tester, client);
    expect(client.contentReads, hasLength(2));
    await tester.tap(find.byTooltip('Refresh Log'));
    await tester.pump();
    client.reads.last.complete([]);
    await tester.pumpAndSettle();
    final older = Completer<HistoryPage>();
    client.pendingHistory = older;
    await _filter(tester);
    final newer = Completer<HistoryPage>();
    client.pendingHistory = newer;
    await _filter(tester);
    newer.complete(
      const HistoryPage([], nextOffset: 0, hasMore: false, anchor: 'new'),
    );
    await tester.pumpAndSettle();
    older.complete(
      HistoryPage(
        client.historyCommits,
        nextOffset: 2,
        hasMore: false,
        anchor: 'old',
      ),
    );
    client.completeContent();
    await tester.pump();
    expect(find.byType(GitDiffView), findsNothing);
    expect(find.text('Current commit'), findsNothing);
    expect(find.textContaining('obsolete preview text'), findsNothing);
    expect(find.text('No commits match the current filters.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed changed-files request clears review and stale file actions',
    (tester) async {
      final client = _ChangedFilesClient();
      await _mount(tester, client);
      await _selectFile(tester, client);
      final oldNext = tester
          .widget<GitDiffView>(find.byType(GitDiffView))
          .onNextFile!;
      await tester.tap(find.text('Older commit'));
      await tester.pump();
      client.reads.last.completeError(
        const GitException(GitErrorCode.disconnected),
      );
      await tester.pumpAndSettle();
      oldNext();
      await tester.pump();
      expect(find.byType(GitDiffView), findsNothing);
      expect(find.byType(GitFailurePanel), findsOneWidget);
      expect(find.text('Details: Older commit'), findsOneWidget);
      expect(find.text('No changed files'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changed files distinguish loading from an empty commit', (
    tester,
  ) async {
    final client = _ChangedFilesClient();
    await _mount(tester, client);
    expect(client.reads, hasLength(1));
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    client.reads.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading changed files'), findsNothing);
    expect(find.text('No changed files'), findsOneWidget);
    expect(find.bySemanticsLabel('No changed files'), findsOneWidget);
    expect(find.bySemanticsLabel('Changed files'), findsOneWidget);
    expect(find.text('Current commit'), findsOneWidget);
  });

  testWidgets('changed-files errors retry without reloading the commit table', (
    tester,
  ) async {
    final client = _ChangedFilesClient();
    await _mount(tester, client);
    client.reads.single.completeError(
      const GitException(
        GitErrorCode.disconnected,
        diagnostic: 'Fixture disconnected while reading changed files.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GitFailurePanel), findsOneWidget);
    expect(find.text('Current commit'), findsOneWidget);
    expect(find.text('No changed files'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(GitFailurePanel),
        matching: find.text('Refresh'),
      ),
    );
    await tester.pump();
    expect(client.reads, hasLength(2));
    expect(find.bySemanticsLabel('Loading changed files'), findsOneWidget);
    client.reads.last.complete([
      GitChange(
        path: RepoPath.text('chapter/new.md'),
        index: 'A',
        worktree: '.',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('new.md'), findsOneWidget);
    expect(find.byType(GitFailurePanel), findsNothing);
    expect(client.historyFilters, hasLength(1));
    expect(client.mutations, isEmpty);
  });

  testWidgets(
    'a stale changed-files completion cannot replace newer selection',
    (tester) async {
      final client = _ChangedFilesClient();
      await _mount(tester, client);
      await tester.tap(find.text('Older commit'));
      await tester.pump();
      expect(client.reads, hasLength(2));
      client.reads.last.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('No changed files'), findsOneWidget);
      client.reads.first.complete([
        GitChange(
          path: RepoPath.text('obsolete.md'),
          index: 'M',
          worktree: '.',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('obsolete.md'), findsNothing);
      expect(find.text('No changed files'), findsOneWidget);
      expect(find.text('Details: Older commit'), findsOneWidget);
    },
  );
}
