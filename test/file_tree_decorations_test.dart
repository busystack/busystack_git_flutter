import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';
import 'support/presentation_fixture.dart' as fixture;

const repository = RepositoryId(
  root: '/repo',
  gitDir: '/repo/.git',
  commonDir: '/repo/.git',
  objectFormat: 'sha1',
);

GitSnapshot snapshot(
  List<GitChange> changes, {
  RepositoryId repo = repository,
}) => GitSnapshot(
  repository: repo,
  token: 'same-token',
  indexToken: 'index',
  changes: changes,
  operation: const RepositoryOperation(GitOperationKind.none),
  observedAt: DateTime.utc(2026),
);

GitChange change(
  String path,
  String worktree, {
  String index = '.',
  String? original,
}) => GitChange(
  path: RepoPath.text(path),
  index: index,
  worktree: worktree,
  originalPath: original == null ? null : RepoPath.text(original),
);

class _DecorationChangesClient extends fixture.FixtureClient {
  @override
  Future<GitSnapshot> status(
    RepositoryId repo, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => snapshot([
    change('topics/named-export-presets.md', 'M'),
    change('topics/releasev051.md', 'D'),
  ], repo: repo);
}

void main() {
  testWidgets(
    'deleted topics file remains reviewable in the real shared Changes tree',
    (tester) async {
      final host = fixture.host();
      final session = GitSession(
        client: _DecorationChangesClient(),
        repository: repository,
        host: host,
      );
      addTearDown(session.dispose);
      await session.start();
      final opened = <GitComparison>[];
      await tester.pumpWidget(
        fixture.GitTestApp(
          home: Scaffold(
            body: GitHostScope(
              host: host,
              child: GitChangeTree(session: session, onReview: opened.add),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('releasev051.md'), findsWidgets);
      final deleted = tester
          .widgetList<GitChangeRow>(find.byType(GitChangeRow))
          .where((row) => row.status == GitFileStatus.deleted);
      expect(deleted, hasLength(1));
      await tester.tap(find.text('releasev051.md').first);
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single.path.utf8Path, 'topics/releasev051.md');
    },
  );
  test(
    'modified plus deleted topics mark location, never deleted/conflicted',
    () {
      final status = snapshot([
        change('topics/named-export-presets.md', 'M'),
        change('topics/releasev051.md', 'D'),
      ]);
      final tree = GitFileTreeDecorations.fromSnapshot(status);
      final topics = tree.forUri('file:///repo/topics', directory: true)!;
      expect(topics.directoryState, GitDirectoryChangeState.immediate);
      expect(topics.status, isNull);
      expect(topics.immediateCount, 2);
      expect(topics.descendantCount, 0);
      expect(topics.deletedCount, 1);
      expect(topics.marker, '•');
      expect(
        tree.forUri('file:///repo/topics/named-export-presets.md')!.status,
        GitFileStatus.modified,
      );
      expect(
        status.changes.last.worktree,
        'D',
        reason: 'Deletion remains in the Git Changes snapshot.',
      );
      expect(tree.forUri('file:///repo/topics/clean.md'), isNull);
    },
  );

  test('all file categories retain their own status and both XY sides', () {
    final status = snapshot([
      change('modified', 'M'),
      change('added', '.', index: 'A'),
      change('deleted', 'D'),
      change('renamed', '.', index: 'R', original: 'before'),
      change('copied', '.', index: 'C', original: 'source'),
      change('untracked', '?', index: '?'),
      change('conflicted', 'U', index: 'U'),
      change('type', 'T'),
      change('ignored/a', '!', index: '!'),
      change('clean', '.'),
      change('added-modified', 'M', index: 'A'),
      change('modified-deleted', 'D', index: 'M'),
    ]);
    final tree = GitFileTreeDecorations.fromSnapshot(status);
    for (final value in {
      'modified': GitFileStatus.modified,
      'added': GitFileStatus.added,
      'deleted': GitFileStatus.deleted,
      'renamed': GitFileStatus.renamed,
      'copied': GitFileStatus.copied,
      'untracked': GitFileStatus.untracked,
      'conflicted': GitFileStatus.conflicted,
      'type': GitFileStatus.typeChanged,
      'added-modified': GitFileStatus.modified,
      'modified-deleted': GitFileStatus.deleted,
    }.entries) {
      expect(tree.forUri('file:///repo/${value.key}')!.status, value.value);
    }
    expect(tree.forUri('file:///repo/ignored', directory: true), isNull);
    expect(tree.forUri('file:///repo/ignored/a'), isNull);
    expect(tree.forUri('file:///repo/clean'), isNull);
    expect(tree.forUri('file:///repo/added-modified')!.change!.index, 'A');
  });

  test(
    'immediate and descendant counts include deletions and clear with status',
    () {
      final tree = GitFileTreeDecorations.fromSnapshot(
        snapshot([change('outer/inner/a', 'D'), change('outer/inner/b', 'M')]),
      );
      expect(
        tree
            .forUri('file:///repo/outer/inner', directory: true)!
            .directoryState,
        GitDirectoryChangeState.immediate,
      );
      final outer = tree.forUri('file:///repo/outer', directory: true)!;
      expect(outer.directoryState, GitDirectoryChangeState.descendant);
      expect(outer.descendantCount, 2);
      expect(outer.deletedCount, 1);
      expect(tree.forUri('file:///repo', directory: true)!.descendantCount, 2);
      expect(
        GitFileTreeDecorations.fromSnapshot(
          snapshot([]),
        ).forUri('file:///repo/outer'),
        isNull,
      );
    },
  );

  test(
    'rename marks source and destination directories once; copy leaves source clean',
    () {
      final tree = GitFileTreeDecorations.fromSnapshot(
        snapshot([
          change('new/nested/a', '.', index: 'R', original: 'old/a'),
          change('copy/b', '.', index: 'C', original: 'source/b'),
        ]),
      );
      expect(
        tree.forUri('file:///repo/old', directory: true)!.immediateCount,
        1,
      );
      expect(
        tree.forUri('file:///repo/new', directory: true)!.descendantCount,
        1,
      );
      expect(tree.forUri('file:///repo', directory: true)!.pathCount, 2);
      expect(tree.forUri('file:///repo/source', directory: true), isNull);
      expect(
        tree.forUri('file:///repo/old/a'),
        isNull,
        reason: 'Do not invent a source filesystem row.',
      );
      final nested = GitFileTreeDecorations.fromSnapshot(
        snapshot([change('old/nested/a', '.', index: 'R', original: 'old/a')]),
      );
      expect(
        nested.forUri('file:///repo/old', directory: true)!.immediateCount,
        1,
      );
      expect(nested.forUri('file:///repo/old', directory: true)!.pathCount, 1);
    },
  );

  test(
    'staging and unstaging preserve path status; restoring removes both file and directory decorations',
    () {
      GitFileTreeDecorations tree(String index, String working) =>
          GitFileTreeDecorations.fromSnapshot(
            snapshot([change('dir/a', working, index: index)]),
          );
      expect(
        tree('A', 'M').forUri('file:///repo/dir/a')!.status,
        GitFileStatus.modified,
      );
      expect(
        tree('M', '.').forUri('file:///repo/dir/a')!.status,
        GitFileStatus.modified,
      );
      expect(
        tree('.', 'M').forUri('file:///repo/dir/a')!.status,
        GitFileStatus.modified,
      );
      expect(tree('.', '.').forUri('file:///repo/dir/a'), isNull);
      expect(
        tree('.', '.').forUri('file:///repo/dir', directory: true),
        isNull,
      );
    },
  );

  test(
    'byte paths, gitlinks, opaque directories and repository scopes stay separate',
    () {
      final path = RepoPath([100, 105, 114, 47, 255, 10, 37, 35]);
      final status = snapshot([
        GitChange(path: path, index: '.', worktree: 'M'),
        GitChange(
          path: RepoPath.text('dir/submodule'),
          index: '.',
          worktree: 'M',
          submodule: 'S.M.',
        ),
        GitChange(
          path: RepoPath.text('opaque'),
          index: '?',
          worktree: '?',
          directory: true,
        ),
      ]);
      final tree = GitFileTreeDecorations.fromSnapshot(status);
      expect(
        identical(tree, GitFileTreeDecorations.fromSnapshot(status)),
        isTrue,
      );
      expect(
        tree.forUri(gitLocalFileUri(repository, path))!.status,
        GitFileStatus.modified,
      );
      expect(tree.forUri('file:///repo/dir', directory: true)!.pathCount, 2);
      expect(
        tree.forUri('file:///repo/opaque', directory: true)!.directoryState,
        GitDirectoryChangeState.immediate,
      );
      expect(tree.forUri('file:///repo/opaque/uninspected'), isNull);
      for (final uri in [
        'nextcloud://account/dir',
        'file://remote/repo/dir',
        'file:///other/dir',
        'file:///repo/dir?x',
        'file:///repo/dir%2Fa',
        'file:///repo/dir/%FE%0A%25%23',
      ]) {
        expect(tree.forUri(uri), isNull, reason: uri);
      }
      const other = RepositoryId(
        root: '/other',
        gitDir: '/other/.git',
        commonDir: '/other/.git',
        objectFormat: 'sha1',
      );
      final next = GitFileTreeDecorations.fromSnapshot(
        snapshot([change('dir/b', 'M')], repo: other),
      );
      expect(next.forUri('file:///repo/dir'), isNull);
      expect(next.forUri('file:///other/dir')!.pathCount, 1);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '$brightness: distinct legible statuses, directory explanations and clean refresh',
      (tester) async {
        final status = snapshot([
          change('topics/named-export-presets.md', 'M'),
          change('topics/releasev051.md', 'D'),
        ]);
        final tree = GitFileTreeDecorations.fromSnapshot(status);
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? createYaruDarkTheme(primaryColor: YaruColors.orange)
                : createYaruLightTheme(primaryColor: YaruColors.orange),
            home: Builder(
              builder: (context) {
                final topics = tree.forUri(
                  'file:///repo/topics',
                  directory: true,
                )!;
                final style = gitTreeDecorationStyle(context, topics);
                final ancestor = tree.forUri('file:///repo', directory: true)!;
                final ancestorStyle = gitTreeDecorationStyle(context, ancestor);
                expect(
                  ancestor.directoryState,
                  GitDirectoryChangeState.descendant,
                );
                expect(ancestorStyle.color, isNot(style.color));
                expect(
                  style.color,
                  isNot(gitFilenameStyle(context, GitFileStatus.deleted).color),
                );
                expect(
                  topics.description(context),
                  contains('2 directly in this directory'),
                );
                expect(topics.description(context), contains('1 deleted'));
                final colors = [
                  for (final status in [
                    GitFileStatus.modified,
                    GitFileStatus.added,
                    GitFileStatus.deleted,
                    GitFileStatus.renamed,
                    GitFileStatus.copied,
                    GitFileStatus.untracked,
                    GitFileStatus.conflicted,
                  ])
                    gitFilenameStyle(context, status).color,
                ];
                expect(colors.toSet(), hasLength(7));
                final background = NativeGitSurface.of(context).sidebar;
                for (final color in [
                  ...colors,
                  style.color,
                  ancestorStyle.color,
                ]) {
                  final a = color!.computeLuminance(),
                      b = background.computeLuminance();
                  expect(
                    ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
                    greaterThanOrEqualTo(4.5),
                  );
                }
                return Text('topics', style: style);
              },
            ),
          ),
        );
        expect(find.text('topics'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
