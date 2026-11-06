import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

GitReview review(
  ContentVersion left,
  ContentVersion right, {
  String token = 'snapshot-A',
  String? oldPath,
  RepositoryId repository = repo,
}) => GitReview(
  repository,
  comparison: GitComparison(
    RepoPath.text('notes.md'),
    left,
    right,
    leftPath: oldPath == null ? null : RepoPath.text(oldPath),
  ),
  reviewToken: token,
);

class _ChangingSnapshotClient extends FixtureClient {
  String token = 'review';
  int contentReads = 0;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    token: token,
    indexToken: 'index',
    changes: snapshot().changes,
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) {
    contentReads++;
    return super.content(repository, path, version, cancellation: cancellation);
  }
}

void main() {
  testWidgets(
    'delayed sidebar menu cannot navigate a replacement repository or newer view',
    (tester) async {
      final original = host();
      Completer<String?>? pending;
      final configured = GitHost(
        presentation: original.presentation,
        icons: original.icons,
        present: original.present,
        presentMenu: (_, entries, {position}) {
          expect(entries.map((entry) => entry.id), ['files', 'commit', 'log']);
          pending = Completer<String?>();
          return pending!.future;
        },
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: original.drafts,
      );
      final first = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: configured,
      );
      final second = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: configured,
      );
      await first.start();
      await second.start();
      var active = first;
      var choices = 0, files = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        GitTestApp(
          home: StatefulBuilder(
            builder: (_, update) {
              rebuild = update;
              return Scaffold(
                body: GitFeatureSidebar(
                  controller: active.feature,
                  view: active.feature.view,
                  onSelectView: (_) => rebuild(() => choices++),
                  onReview: (_) {},
                  destinations: [
                    GitSidebarDestination(
                      id: 'files',
                      label: 'Files',
                      onSelect: () => files++,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(GitSidebarSelector));
      await tester.pump();
      rebuild(() => active = second);
      await tester.pump();
      pending!.complete('log');
      await tester.pumpAndSettle();
      expect(choices, 0);
      expect(first.feature.view, GitSidebarView.commit);
      expect(second.feature.view, GitSidebarView.commit);
      await tester.tap(find.byType(GitSidebarSelector));
      await tester.pump();
      second.feature.toggleSidebar();
      pending!.complete('files');
      await tester.pumpAndSettle();
      expect(files, 0);
      rebuild(() {});
      await tester.pump();
      await tester.tap(find.byType(GitSidebarSelector));
      await tester.pump();
      pending!.complete('log');
      await tester.pumpAndSettle();
      expect(choices, 1);
      expect(second.feature.view, GitSidebarView.log);
      await tester.pumpWidget(const SizedBox());
      first.dispose();
      second.dispose();
    },
  );
  testWidgets(
    'queued tab menu cannot close a newer review and explicit close others preserves its target',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = host();
      Completer<String?>? pending;
      var guards = 0;
      final configured = GitHost(
        presentation: original.presentation,
        icons: original.icons,
        present: original.present,
        presentMenu: (_, entries, {position}) {
          expect(entries.map((entry) => entry.id), ['close', 'others', 'all']);
          pending = Completer<String?>();
          return pending!.future;
        },
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: original.drafts,
      );
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: configured,
      );
      await session.start();
      final first = session.feature.capture(
        GitComparison(
          RepoPath.text('first.md'),
          const ContentVersion.index(),
          const ContentVersion.working(),
        ),
      );
      final second = session.feature.capture(
        GitComparison(
          RepoPath.text('second.md'),
          const ContentVersion.index(),
          const ContentVersion.working(),
        ),
      );
      session.feature.open(first);
      session.feature.open(second);
      await tester.pumpWidget(
        GitTestApp(
          home: GitHostScope(
            host: configured,
            child: ListenableBuilder(
              listenable: session.feature,
              builder: (_, _) => Align(
                alignment: Alignment.topLeft,
                child: GitReviewTabStrip(
                  controller: session.feature,
                  mayClose: () async {
                    guards++;
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(ValueKey('git-review-tab:${first.id}'));
      await tester.tap(target, buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(pending, isNotNull);
      final third = session.feature.capture(
        GitComparison(
          RepoPath.text('third.md'),
          const ContentVersion.index(),
          const ContentVersion.working(),
        ),
      );
      session.feature.open(third);
      pending!.complete('all');
      await tester.pumpAndSettle();
      expect(guards, 0);
      expect(session.feature.tabs.entries, [first, second, third]);
      await tester.tap(target, buttons: kSecondaryMouseButton);
      await tester.pump();
      pending!.complete('others');
      await tester.pumpAndSettle();
      expect(guards, 1);
      expect(session.feature.tabs.entries, [first]);
      expect(session.feature.tabs.active, same(first));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'a queued mutable tab rejects a replaced snapshot before reading content',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _ChangingSnapshotClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      final review = session.feature.capture(
        GitComparison(
          RepoPath.text('notes.md'),
          const ContentVersion.index(),
          const ContentVersion.working(),
        ),
      );
      client.token = 'newer external index';
      session.feature.open(review);
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(body: GitWorkspace(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        client.contentReads,
        0,
        reason:
            'Changed content cannot be loaded under the earlier captured identity.',
      );
      expect(find.textContaining('Repository changed'), findsWidgets);
      expect(session.feature.tabs.active, same(review));
      expect(client.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  test(
    'review identities distinguish snapshots, both paths, worktrees and merge parents',
    () {
      final a = ContentVersion(ContentKind.commit, revision: GitOid('a' * 40));
      final b = ContentVersion(ContentKind.commit, revision: GitOid('b' * 40));
      final c = ContentVersion(ContentKind.commit, revision: GitOid('c' * 40));
      final entries = [
        review(const ContentVersion.index(), const ContentVersion.working()),
        review(
          const ContentVersion.index(),
          const ContentVersion.working(),
          token: 'snapshot-B',
        ),
        review(a, const ContentVersion.index()),
        review(a, c),
        review(b, c),
        review(a, c, oldPath: 'before-rename.md'),
        review(
          a,
          c,
          repository: const RepositoryId(
            root: '/fixture/worktree',
            gitDir: '/fixture/repo/.git/worktrees/worktree',
            commonDir: '/fixture/repo/.git',
            objectFormat: 'sha1',
          ),
        ),
      ];
      var tabs = const GitReviewTabs();
      for (final entry in entries) {
        tabs = tabs.open(entry);
      }
      expect(tabs.entries.length, entries.length);
      tabs = tabs.open(review(a, c, token: 'irrelevant current status'));
      expect(tabs.entries.length, entries.length);
      expect(tabs.active, same(entries[3]));
      expect(tabs.entries[4].comparison.left.revision, b.revision);
      expect(tabs.entries[5].comparison.leftPath!.utf8Path, 'before-rename.md');
    },
  );

  test(
    'tab close and activation preserve immutable entries and a valid neighbor',
    () {
      final first = review(
        ContentVersion(ContentKind.commit, revision: GitOid('a' * 40)),
        const ContentVersion.index(),
      );
      final second = review(
        const ContentVersion.index(),
        const ContentVersion.working(),
      );
      final tabs = const GitReviewTabs().open(first).open(second);
      expect(tabs.close(second.id).active, same(first));
      expect(tabs.close(first.id).active, same(second));
      expect(tabs.activate('missing'), same(tabs));
      expect(tabs.close('missing'), same(tabs));
      expect(tabs.close(first.id).close(second.id).entries, isEmpty);
    },
  );

  testWidgets(
    'canonical view changes retain independent reviews, draft and loaded diff state',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      session.setDraft('unsaved authoring draft');
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(body: GitWorkspace(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      final first = session.feature.capture(
        GitComparison(
          RepoPath.text('notes.md'),
          ContentVersion(ContentKind.commit, revision: GitOid('a' * 40)),
          const ContentVersion.index(),
        ),
      );
      final second = session.feature.capture(
        GitComparison(
          RepoPath.text('notes.md'),
          const ContentVersion.index(),
          const ContentVersion.working(),
        ),
      );
      session.feature.open(first);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final firstState = tester.state(find.byType(GitDiffView));
      session.feature.open(second);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(session.feature.tabs.entries, [first, second]);
      expect(
        tester
            .widget<GitDiffView>(find.byType(GitDiffView))
            .comparison
            .right
            .kind,
        ContentKind.workingTree,
      );
      session.feature.select(GitSidebarView.log);
      await tester.pumpAndSettle();
      expect(session.feature.tabs.active, same(second));
      session.feature.activate(first.id);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(GitDiffView)), same(firstState));
      expect(
        session.feature.tabs.entries[0].comparison.left.kind,
        ContentKind.commit,
      );
      expect(session.draft, 'unsaved authoring draft');
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
