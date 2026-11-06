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
          availability: version.kind == ContentKind.absent
              ? ContentAvailability.absent
              : ContentAvailability.present,
          token: 'captured',
          mode: version.kind == ContentKind.absent ? '000000' : '100644',
          bytes: version.kind == ContentKind.absent
              ? const []
              : utf8.encode('captured revision text\n'),
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

Future<GitSession> _mount(
  WidgetTester tester,
  _ChangedFilesClient client,
) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  await tester.pumpWidget(_screen(session));
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return session;
}

Widget _screen(GitSession session) => GitTestApp(
  home: Scaffold(
    body: Row(
      children: [
        Expanded(child: GitLogView(session: session)),
        Expanded(child: GitReviewContent(controller: session.feature)),
      ],
    ),
  ),
);

GitReview _active(WidgetTester tester) => tester
    .widget<GitReviewContent>(find.byType(GitReviewContent))
    .controller
    .tabs
    .active!;

Future<void> _settle(WidgetTester tester, _ChangedFilesClient client) async {
  if (client.deferContent) {
    await tester.pump(const Duration(milliseconds: 50));
    return;
  }
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  } while (find
          .descendant(
            of: find.byType(GitReviewContent),
            matching: find.byType(GitLoading),
          )
          .evaluate()
          .isNotEmpty &&
      DateTime.now().isBefore(deadline));
  expect(
    find.descendant(
      of: find.byType(GitReviewContent),
      matching: find.byType(GitLoading),
    ),
    findsNothing,
  );
  await tester.pumpAndSettle();
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
  await _settle(tester, client);
  await tester.tap(find.text('review.md'));
  await _settle(tester, client);
  expect(find.byType(GitDiffView), findsOneWidget);
}

Future<void> _filter(WidgetTester tester) async {
  final message = find.widgetWithText(TextField, 'Message');
  await tester.enterText(message, 'no matching commit');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  for (final closeReview in [false, true]) {
    testWidgets(
      'empty filter preserves independent review unless explicitly closed=$closeReview',
      (tester) async {
        final client = _ChangedFilesClient();
        final session = await _mount(tester, client);
        await _selectFile(tester, client);
        final retained = _active(tester);
        if (closeReview) session.feature.close(retained.id);
        client.historyCommits = [];
        await _filter(tester);
        await _settle(tester, client);
        expect(tester.takeException(), isNull);
        expect(
          find.byType(GitDiffView),
          closeReview ? findsNothing : findsOneWidget,
        );
        if (!closeReview) expect(_active(tester), same(retained));
        expect(
          find.text('No commits match the current filters.'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(GitLogView),
            matching: find.textContaining('review.md'),
          ),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'filter replacement rejects stale file reads and preserves captured tab navigation',
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
      await _settle(tester, client);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(_active(tester).comparison.path, RepoPath.text('chapter/next.md'));
      expect(_active(tester).comparison.right.revision, GitOid('a' * 40));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed replacement history preserves captured review and closing rejects late completion',
    (tester) async {
      final client = _ChangedFilesClient();
      await _mount(tester, client);
      await _selectFile(tester, client);
      client.pendingHistory = Completer<HistoryPage>();
      await _filter(tester);
      client.pendingHistory!.completeError(
        const GitException(GitErrorCode.disconnected),
      );
      await _settle(tester, client);
      expect(find.byType(GitFailurePanel), findsOneWidget);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(_active(tester).comparison.right.revision, GitOid('a' * 40));
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
    'empty changed files preserve captured navigation and repository replacement retires the surface',
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
      await _settle(tester, client);
      obsolete!();
      await _settle(tester, client);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(_active(tester).comparison.right.revision, GitOid('a' * 40));
      expect(find.text('No changed files'), findsOneWidget);
      final replacement = _ChangedFilesClient()..historyCommits = [];
      final session = GitSession(
        client: replacement,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(_screen(session));
      await _settle(tester, client);
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

  testWidgets(
    'changed merge parent preserves independent review and rejects old row callbacks',
    (tester) async {
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
          .widget<GitChangeRow>(find.widgetWithText(GitChangeRow, 'next.md'))
          .onTap;
      final picker = tester.widget<GitChoice<GitOid>>(
        find.byType(GitChoice<GitOid>),
      );
      picker.onChanged!(GitOid('d' * 40));
      await tester.pump();
      oldRow();
      await tester.pump();
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(_active(tester).comparison.left.revision, GitOid('c' * 40));
      expect(client.comparedParents.last, GitOid('d' * 40));
      client.reads.last.complete([]);
      await _settle(tester, client);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(_active(tester).comparison.left.revision, GitOid('c' * 40));
      expect(find.text('No changed files'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh Log'));
      await tester.pump();
      expect(client.comparedParents.last, GitOid('d' * 40));
      client.reads.last.complete([]);
      await _settle(tester, client);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh and rapid filters cannot retarget a late captured comparison',
    (tester) async {
      final client = _ChangedFilesClient()..deferContent = true;
      await _mount(tester, client);
      await _selectFile(tester, client);
      expect(client.contentReads, hasLength(2));
      await tester.tap(find.byTooltip('Refresh Log'));
      await tester.pump();
      client.reads.last.complete([]);
      await _settle(tester, client);
      final older = Completer<HistoryPage>();
      client.pendingHistory = older;
      await _filter(tester);
      final newer = Completer<HistoryPage>();
      client.pendingHistory = newer;
      await _filter(tester);
      newer.complete(
        const HistoryPage([], nextOffset: 0, hasMore: false, anchor: 'new'),
      );
      await _settle(tester, client);
      older.complete(
        HistoryPage(
          client.historyCommits,
          nextOffset: 2,
          hasMore: false,
          anchor: 'old',
        ),
      );
      client.completeContent();
      client.deferContent = false;
      await _settle(tester, client);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(_active(tester).comparison.right.revision, GitOid('a' * 40));
      expect(find.text('Current commit'), findsNothing);
      expect(
        find.textContaining('captured revision text', findRichText: true),
        findsWidgets,
      );
      expect(
        find.text('No commits match the current filters.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed changed-files request clears selector files while preserving captured tab navigation',
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
      await _settle(tester, client);
      oldNext();
      await _settle(tester, client);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(_active(tester).comparison.path, RepoPath.text('chapter/next.md'));
      expect(_active(tester).comparison.right.revision, GitOid('a' * 40));
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
    await _settle(tester, client);
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
    await _settle(tester, client);
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
    await _settle(tester, client);
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
      await _settle(tester, client);
      expect(find.text('No changed files'), findsOneWidget);
      client.reads.first.complete([
        GitChange(
          path: RepoPath.text('obsolete.md'),
          index: 'M',
          worktree: '.',
        ),
      ]);
      await _settle(tester, client);
      expect(find.text('obsolete.md'), findsNothing);
      expect(find.text('No changed files'), findsOneWidget);
      expect(find.text('Details: Older commit'), findsOneWidget);
    },
  );
}
