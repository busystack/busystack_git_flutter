import 'dart:convert';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

class _Client extends FixtureClient {
  var absent = false, empty = false;
  final head = GitOid('a' * 40);
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    head: head,
    token: mutations.isEmpty ? 'review' : 'review-${mutations.length}',
    indexToken: mutations.isEmpty ? 'index' : 'index-${mutations.length}',
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
  }) async => GitContent(
    path: path,
    version: version,
    availability:
        absent &&
            const {
              ContentKind.workingTree,
              ContentKind.normalizedWorking,
            }.contains(version.kind)
        ? ContentAvailability.absent
        : ContentAvailability.present,
    mode:
        absent &&
            const {
              ContentKind.workingTree,
              ContentKind.normalizedWorking,
            }.contains(version.kind)
        ? '000000'
        : '100644',
    token: version.label,
    bytes:
        empty ||
            absent &&
                const {
                  ContentKind.workingTree,
                  ContentKind.normalizedWorking,
                }.contains(version.kind)
        ? []
        : utf8.encode(
            version.kind == ContentKind.indexVersion
                ? 'old\ncontext\n'
                : 'new\ncontext\n',
          ),
  );
  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    return GitOutcome(
      phase: GitOperationPhase.completed,
      snapshot: await status(repository),
    );
  }
}

Future<void> _ready(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (find.byType(GitLoading).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Comparison never became ready');
}

void main() {
  testWidgets(
    'tab header ownership, checked mode choices and every toolbar destination',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = host(), client = _Client();
      String? choice;
      List<GitMenuEntry> entries = [];
      Widget? presented;
      final configured = GitHost(
        presentation: const TestGitPresentation(),
        icons: testGitIcons,
        presentMenu: (_, menu, {position}) async {
          entries = menu;
          return choice;
        },
        present: <T>(context, title, child, {bool expanded = false}) async {
          presented = (child as GitHostScope).child;
          return null;
        },
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: MemoryGitDraftStore(),
      );
      final session = GitSession(
        client: client,
        repository: repo,
        host: configured,
      );
      await session.start();
      addTearDown(session.dispose);
      Future<void> mount({bool header = false}) async {
        await tester.pumpWidget(
          GitTestApp(
            home: Scaffold(
              body: GitDiffView(
                session: session,
                showFileHeader: header,
                comparison: GitComparison(
                  RepoPath.text('chapter/notes.md'),
                  const ContentVersion.index(),
                  const ContentVersion.working(),
                ),
                onPreviousFile: () {},
                onNextFile: () {},
              ),
            ),
          ),
        );
        await _ready(tester);
      }

      await mount();
      expect(find.byKey(const ValueKey('git-diff-file-header')), findsNothing);
      expect(find.byType(GitChoiceBar<bool>), findsNothing);
      choice = 'unified';
      await tester.tap(find.byKey(const ValueKey('git-diff-mode')));
      await tester.pumpAndSettle();
      expect(entries.map((e) => e.id), ['side', 'unified']);
      expect(entries.first.checked, isTrue);
      expect(session.option('diffUnified', false), isTrue);
      expect(find.text('Unified'), findsOneWidget);
      choice = 'side';
      await tester.tap(find.byKey(const ValueKey('git-diff-mode')));
      await tester.pumpAndSettle();
      expect(entries.last.checked, isTrue);
      expect(session.option('diffUnified', true), isFalse);
      choice = 'index';
      await tester.tap(find.byKey(const ValueKey('git-diff-overflow')));
      await _ready(tester);
      expect(
        entries.singleWhere((e) => e.id == 'index').label,
        GitMessages.editIndexInThreeWayView,
      );
      expect(presented, isA<GitIndexEditor>());
      expect(
        (presented as GitIndexEditor).path,
        RepoPath.text('chapter/notes.md'),
      );
      expect(client.mutations, isEmpty);
      await mount(header: true);
      expect(
        find.byKey(const ValueKey('git-diff-file-header')),
        findsOneWidget,
      );
      expect(find.byTooltip('Refresh comparison'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final staged in [false, true]) {
    testWidgets(
      'contextual ${staged ? 'Unstage' : 'Stage'} lines and file retain reviewed transactions',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _Client();
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        addTearDown(session.dispose);
        await tester.pumpWidget(
          GitTestApp(
            home: Scaffold(
              body: GitDiffView(
                session: session,
                showFileHeader: false,
                comparison: GitComparison(
                  RepoPath.text('chapter/notes.md'),
                  staged
                      ? ContentVersion(
                          ContentKind.commit,
                          revision: client.head,
                        )
                      : const ContentVersion.index(),
                  staged
                      ? const ContentVersion.index()
                      : const ContentVersion.working(),
                ),
              ),
            ),
          ),
        );
        await _ready(tester);
        final caption = staged
            ? 'Unstage selected lines'
            : 'Stage selected lines';
        expect(find.text(caption), findsNothing);
        expect(
          find.text(staged ? 'Unstage file' : 'Stage file'),
          findsOneWidget,
        );
        final gutter = find
            .byWidgetPredicate(
              (w) =>
                  w is GitActivation &&
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(
                    'git-diff-stage-line-',
                  ),
            )
            .first;
        await tester.tap(gutter);
        await tester.pumpAndSettle();
        expect(find.text(caption).hitTestable(), findsOneWidget);
        await tester.tap(find.text(caption));
        await _ready(tester);
        expect(client.mutations.single, isA<WriteIndex>());
        expect((client.mutations.single as WriteIndex).expectedIndex, 'index');
        expect(
          (client.mutations.single as WriteIndex).bytes,
          utf8.encode(staged ? 'new\nold\ncontext\n' : 'context\n'),
        );
        await tester.tap(find.text(staged ? 'Unstage file' : 'Stage file'));
        await _ready(tester);
        expect(client.mutations, hasLength(2));
        expect(client.mutations.last, isA<StagePaths>());
        final request = client.mutations.last as StagePaths;
        expect(request.unstage, staged);
        expect(request.expectedIndex, 'index-1');
        expect(request.paths, [RepoPath.text('chapter/notes.md')]);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'genuine absence and an existing empty file have different primary metadata',
    (tester) async {
      final client = _Client()..absent = true;
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      addTearDown(session.dispose);
      Future<void> mount(String identity) async {
        await tester.pumpWidget(
          GitTestApp(
            home: Scaffold(
              body: GitDiffView(
                key: ValueKey(identity),
                session: session,
                comparison: GitComparison(
                  RepoPath.text('chapter/notes.md'),
                  const ContentVersion.index(),
                  const ContentVersion.working(),
                ),
              ),
            ),
          ),
        );
        await _ready(tester);
      }

      await mount('absent');
      expect(
        find.textContaining(
          'Working Tree · Git normalized · \u2066chapter/notes.md\u2069 · Absent',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('000000 · 0 bytes'), findsNothing);
      client.absent = false;
      client.empty = true;
      await mount('empty');
      expect(
        find.textContaining(
          'Working Tree · Git normalized · \u2066chapter/notes.md\u2069 · Absent',
        ),
        findsNothing,
      );
      expect(find.textContaining('100644 · 0 bytes'), findsNWidgets(2));
      expect(client.mutations, isEmpty);
    },
  );
  testWidgets(
    'historical comparisons retain modes, refresh and read-only actions',
    (tester) async {
      final client = _Client();
      final original = host();
      List<GitMenuEntry> menu = [];
      final configured = GitHost(
        presentation: const TestGitPresentation(),
        icons: testGitIcons,
        presentMenu: (_, entries, {position}) async {
          menu = entries;
          return null;
        },
        present: original.present,
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: MemoryGitDraftStore(),
      );
      final session = GitSession(
        client: client,
        repository: repo,
        host: configured,
      );
      await session.start();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(
            body: GitDiffView(
              session: session,
              showFileHeader: false,
              comparison: GitComparison(
                RepoPath.text('chapter/notes.md'),
                ContentVersion(ContentKind.commit, revision: GitOid('b' * 40)),
                ContentVersion(ContentKind.commit, revision: client.head),
              ),
            ),
          ),
        ),
      );
      await _ready(tester);
      await tester.tap(find.byKey(const ValueKey('git-diff-overflow')));
      await tester.pumpAndSettle();
      expect(
        menu.map((e) => e.id),
        isNot(contains(anyOf('file', 'lines', 'index'))),
      );
      expect(find.text('Stage file'), findsNothing);
      expect(find.byKey(const ValueKey('git-diff-open-source')), findsNothing);
      expect(find.byType(GitChoiceBar<bool>), findsNothing);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
