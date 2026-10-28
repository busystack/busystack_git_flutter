import 'dart:convert';
import 'dart:io';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _git = String.fromEnvironment('BUSYSTACK_TEST_GIT');
const _helper = String.fromEnvironment('BUSYSTACK_GIT_HELPER_PATH');

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 400; i++) {
    await tester.runAsync(() => tester.pump());
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    ready(),
    isTrue,
    reason:
        'Real Git review did not finish. '
        '${find.byType(GitFailurePanel).evaluate().map((e) => (e.widget as GitFailurePanel).error)} '
        '${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(" | ")}',
  );
}

void main() {
  testWidgets('real rename and merge-parent review uses actual paths and bytes', (
    tester,
  ) async {
    expect(_git, isNotEmpty);
    expect(_helper, isNotEmpty);
    late Directory fixture;
    late GitEngine engine;
    late BackgroundGitClient background;
    late GitSession session;
    late RepositoryId repository;
    late GitOid root, pureRename, edited, merge, other;
    final baseBytes = utf8.encode(
      '${List.generate(30, (i) => 'Markdown paragraph $i 東京').join('\r\n')}\r\n',
    );
    final mainBytes = utf8.encode(
      utf8.decode(baseBytes).replaceFirst('paragraph 8', 'paragraph eight'),
    );
    final mergedBytes = utf8.encode(
      utf8.decode(mainBytes).replaceFirst('paragraph 20', 'paragraph twenty'),
    );
    Future<List<int>> git(List<String> args, {int exit = 0}) async {
      final result = await Process.run(
        _git,
        args,
        workingDirectory: '${fixture.path}/repo',
        stdoutEncoding: null,
        includeParentEnvironment: false,
        environment: {
          'HOME': '${fixture.path}/home',
          'PATH': '/usr/bin:/bin',
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': '/dev/null',
        },
      );
      expect(result.exitCode, exit, reason: '${result.stderr}');
      return result.stdout as List<int>;
    }

    Future<GitOid> head() async =>
        GitOid(utf8.decode(await git(['rev-parse', 'HEAD'])).trim());
    await tester.runAsync(() async {
      fixture = await Directory.systemTemp.createTemp('busystack-comparison-');
      await Directory('${fixture.path}/home').create();
      await Directory('${fixture.path}/repo/old').create(recursive: true);
      await git(['init', '-b', 'main']);
      await git(['config', 'user.name', 'Fixture']);
      await git(['config', 'user.email', 'fixture@example.invalid']);
      await File('${fixture.path}/repo/old/東京.md').writeAsBytes(baseBytes);
      await File(
        '${fixture.path}/repo/binary.dat',
      ).writeAsBytes([0, 1, 255, 0]);
      await git(['add', '.']);
      await git(['commit', '-m', 'Root']);
      root = await head();
      await git(['branch', 'side']);
      await Directory('${fixture.path}/repo/main').create();
      await git(['mv', 'old/東京.md', 'main/東京.md']);
      await git(['commit', '-m', 'Pure rename']);
      pureRename = await head();
      await File('${fixture.path}/repo/main/東京.md').writeAsBytes(mainBytes);
      await git(['add', '.']);
      await git(['commit', '-m', 'Rename edited']);
      edited = await head();
      await git(['switch', 'side']);
      await Directory('${fixture.path}/repo/side').create();
      await git(['mv', 'old/東京.md', 'side/東京.md']);
      await git(['commit', '-m', 'Other rename']);
      other = await head();
      await git(['switch', 'main']);
      await git(['merge', '--no-ff', 'side'], exit: 1);
      for (final path in ['main/東京.md', 'side/東京.md', 'old/東京.md']) {
        final file = File('${fixture.path}/repo/$path');
        if (await file.exists()) await file.delete();
      }
      await Directory('${fixture.path}/repo/merged').create();
      await File('${fixture.path}/repo/merged/東京.md').writeAsBytes(mergedBytes);
      await git(['add', '-A']);
      await git(['commit', '-m', 'Merge renamed chapter']);
      merge = await head();
      engine = GitEngine(
        runner: ProcessGitRunner(executable: _git, helperPath: _helper),
        helperPath: _helper,
        authorize: (_) => true,
      );
      repository = (await engine.discover('${fixture.path}/repo'))!;
      background = BackgroundGitClient(
        executable: _git,
        helperPath: _helper,
        authorize: (_) => true,
      );
      session = GitSession(
        client: background,
        repository: repository,
        host: GitHost(
          present: <T>(context, title, child, {bool expanded = false}) =>
              showDialog<T>(
                context: context,
                builder: (_) => Dialog(child: child),
              ),
          openDocument: (_, _, {snapshot}) async {},
          prepareMutation: (_, _) async => true,
          chooseDirectory: (_) async => null,
          notify: (_) {},
          drafts: MemoryGitDraftStore(),
        ),
      );
      await session.start();
      expect((await engine.history(repository)).commits.first.oid, merge);
      final pure = await engine.changedFiles(
        repository,
        pureRename,
        parent: root,
      );
      expect(pure.single.index, 'R');
      expect(pure.single.originalPath, RepoPath.text('old/東京.md'));
      expect(
        (await engine.content(
          repository,
          pure.single.path,
          ContentVersion(ContentKind.commit, revision: pureRename),
        )).bytes,
        baseBytes,
      );
      for (final (parent, path, bytes) in [
        (edited, 'main/東京.md', mainBytes),
        (other, 'side/東京.md', baseBytes),
      ]) {
        final files = await engine.changedFiles(
          repository,
          merge,
          parent: parent,
        );
        final change = files.singleWhere(
          (e) => e.path == RepoPath.text('merged/東京.md'),
        );
        expect(change.index, 'R');
        expect(change.originalPath, RepoPath.text(path));
        expect(
          (await engine.content(
            repository,
            change.originalPath!,
            ContentVersion(ContentKind.commit, revision: parent),
          )).bytes,
          bytes,
        );
      }
      await expectLater(
        engine.changedFiles(repository, merge, parent: GitOid('f' * 40)),
        throwsA(
          isA<GitException>().having(
            (e) => e.code,
            'code',
            GitErrorCode.missingContent,
          ),
        ),
      );
    });
    addTearDown(() async {
      session.dispose();
      await background.close();
      await fixture.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitHostScope(
              host: session.host,
              child: GitLogView(session: session),
            ),
          ),
        ),
      ),
    );
    await _waitFor(tester, () => find.text('東京.md').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('東京.md')));
    await _waitFor(
      tester,
      () => find.byType(GitDiffView).evaluate().isNotEmpty,
    );
    var comparison = tester
        .widget<GitDiffView>(find.byType(GitDiffView))
        .comparison;
    expect(comparison.left.revision, edited);
    expect(comparison.leftPath, RepoPath.text('main/東京.md'));
    await tester.runAsync(() async {
      tester
          .widget<DropdownButton<GitOid>>(find.byType(DropdownButton<GitOid>))
          .onChanged!(other);
    });
    await _waitFor(tester, () => find.text('東京.md').evaluate().isNotEmpty);
    await tester.runAsync(() => tester.tap(find.text('東京.md')));
    await tester.pump();
    comparison = tester
        .widget<GitDiffView>(find.byType(GitDiffView))
        .comparison;
    expect(comparison.left.revision, other);
    expect(comparison.leftPath, RepoPath.text('side/東京.md'));
    await tester.runAsync(() async {
      expect(
        (await engine.content(
          repository,
          comparison.leftPath!,
          comparison.left,
        )).bytes,
        baseBytes,
      );
      expect(
        (await engine.content(
          repository,
          comparison.path,
          comparison.right,
        )).bytes,
        mergedBytes,
      );
      final history = await engine.inspect(
        repository,
        GitInspection(
          GitInspectionKind.fileHistory,
          path: RepoPath.text('merged/東京.md'),
        ),
      );
      expect(
        (history['entries'] as List).any(
          (row) => (row['commit'] as Json)['oid'] == merge.value,
        ),
        isTrue,
        reason:
            'File history must expose the merge commit for explicit parent review.',
      );
    });
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitHostScope(
              host: session.host,
              child: GitFileHistoryView(
                session: session,
                path: RepoPath.text('merged/東京.md'),
              ),
            ),
          ),
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.byType(GitDiffView).evaluate().isNotEmpty,
    );
    expect(find.byType(DropdownButton<GitOid>), findsOneWidget);
    await tester.runAsync(() async {
      tester
          .widget<DropdownButton<GitOid>>(find.byType(DropdownButton<GitOid>))
          .onChanged!(other);
    });
    await _waitFor(
      tester,
      () => find.byType(GitDiffView).evaluate().isNotEmpty,
    );
    comparison = tester
        .widget<GitDiffView>(find.byType(GitDiffView))
        .comparison;
    expect(comparison.left.revision, other);
    expect(comparison.leftPath, RepoPath.text('side/東京.md'));
    await _waitFor(
      tester,
      () => find
          .descendant(
            of: find.byType(GitDiffView),
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
