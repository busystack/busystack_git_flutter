import 'dart:convert';
import 'dart:io';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _git = String.fromEnvironment('BUSYSTACK_TEST_GIT');
const _helper = String.fromEnvironment('BUSYSTACK_GIT_HELPER_PATH');

Future<void> _ready(WidgetTester tester, bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 12)),
      reason:
          'Real conflict review did not finish: ${find.byType(GitFailurePanel).evaluate().map((e) => (e.widget as GitFailurePanel).error)}; '
          'panes ${tester.widgetList<GitTextPane>(find.byType(GitTextPane)).map((p) => {'actions': p.regionActions.map((a) => '${a.label}:${a.start}-${a.end}:${a.onInvoke != null}').toList(), 'anchor': p.geometry?.anchor(), 'scroll': p.scrollController?.hasClients == true ? p.scrollController!.offset : null})}; '
          'buttons ${tester.widgetList<GitIconButton>(find.byType(GitIconButton)).map((b) => b.tooltip)}',
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
}

void main() {
  for (final atEofWithoutLf in [false, true]) {
    testWidgets(
      'real Git grouped markers retain manual result and exact bytes EOF_without_LF=$atEofWithoutLf',
      (tester) async {
        expect(_git, isNotEmpty);
        expect(_helper, isNotEmpty);
        late Directory fixture;
        late RepositoryId repo;
        late BackgroundGitClient client;
        late GitSession session;
        const path = 'conflict-日本語.md';
        final base = atEofWithoutLf
            ? '# Introduction\nbase region\n# Between regions\nbase second region'
            : '# Introduction\nbase region\n# Between regions\nbase second region\n# Conclusion\nunchanged one\nunchanged two\nunchanged three\nbase tail\n';
        final ours = base
            .replaceFirst('base region', 'current region')
            .replaceFirst('base second region', 'current second region');
        final theirs = base
            .replaceFirst('base region', 'incoming region')
            .replaceFirst('base second region', 'incoming second region')
            .replaceFirst('base tail', 'non-conflicting incoming tail');
        late List<int> working, stagedClean;
        Future<List<int>> git(List<String> args, {int expected = 0}) async {
          final value = await Process.run(
            _git,
            args,
            workingDirectory: '${fixture.path}/repo',
            includeParentEnvironment: false,
            stdoutEncoding: null,
            environment: {
              'HOME': '${fixture.path}/home',
              'PATH': '/usr/bin:/bin',
              'GIT_CONFIG_NOSYSTEM': '1',
              'GIT_CONFIG_GLOBAL': '/dev/null',
            },
          );
          expect(value.exitCode, expected, reason: '${value.stderr}');
          return value.stdout as List<int>;
        }

        await tester.runAsync(() async {
          fixture = await Directory.systemTemp.createTemp(
            'bsg-conflict-group-',
          );
          await Directory('${fixture.path}/repo').create();
          await Directory('${fixture.path}/home').create();
          await git(['init', '-b', 'main']);
          await git(['config', 'user.name', 'Fixture']);
          await git(['config', 'user.email', 'fixture@example.invalid']);
          await git(['config', 'merge.conflictStyle', 'merge']);
          final file = File('${fixture.path}/repo/$path');
          await file.writeAsString(base);
          await File(
            '${fixture.path}/repo/clean.md',
          ).writeAsString('base clean\n');
          await git(['add', '.']);
          await git(['commit', '-m', 'Base']);
          await git(['switch', '-c', 'incoming']);
          await file.writeAsString(theirs);
          await File(
            '${fixture.path}/repo/clean.md',
          ).writeAsString('incoming clean\n');
          await git(['commit', '-am', 'Incoming']);
          await git(['switch', 'main']);
          await file.writeAsString(ours);
          await git(['commit', '-am', 'Current']);
          await git(['merge', 'incoming'], expected: 1);
          working = await file.readAsBytes();
          stagedClean = await git(['show', ':clean.md']);
          expect(
            RegExp(
              r'^<<<<<<< ',
              multiLine: true,
            ).allMatches(utf8.decode(working)),
            hasLength(1),
          );
          final engine = GitEngine(
            runner: ProcessGitRunner(executable: _git, helperPath: _helper),
            helperPath: _helper,
            authorize: (_) => true,
          );
          repo = (await engine.discover('${fixture.path}/repo'))!;
          final preview = await engine.content(
            repo,
            RepoPath.text(path),
            const ContentVersion(ContentKind.mergePreview),
          );
          expect(
            RegExp(r'^<{32} ', multiLine: true).allMatches(preview.text!),
            hasLength(2),
          );
          client = BackgroundGitClient(
            executable: _git,
            helperPath: _helper,
            authorize: (_) => true,
          );
          session = GitSession(
            client: client,
            repository: repo,
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
        });
        addTearDown(() async {
          await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
          session.dispose();
          await client.close();
          await fixture.delete(recursive: true);
        });
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? clipboard;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') return {'text': clipboard};
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.runAsync(
          () => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: GitConflictView(
                  session: session,
                  path: RepoPath.text(path),
                ),
              ),
            ),
          ),
        );
        await _ready(
          tester,
          () => find.byType(GitTextPane).evaluate().length == 3,
        );
        GitTextPane pane(int i) => tester
            .widgetList<GitTextPane>(find.byType(GitTextPane))
            .elementAt(i);
        await _ready(
          tester,
          () => pane(0).regionActions.any(
            (a) => a.label == 'Accept left region' && a.onInvoke != null,
          ),
        );
        final controller = pane(1).controller!;
        expect(utf8.encode(controller.text), working);
        expect(
          pane(0).regionActions.where((a) => a.label == 'Accept left region'),
          hasLength(1),
        );
        expect(find.text('Region 1/1 · 0 reviewed'), findsOneWidget);
        final retired = pane(0).regionActions.first.onInvoke!;
        final field = find.descendant(
          of: find.byType(GitTextPane).at(1),
          matching: find.byType(TextField),
        );
        await tester.tap(field);
        final edited = TextEditingValue(
          text: 'manual prefix\n${controller.text}',
          selection: const TextSelection(baseOffset: 1, extentOffset: 5),
          composing: const TextRange(start: 0, end: 6),
        );
        tester.testTextInput.updateEditingValue(edited);
        retired();
        expect(controller.value, edited);
        // The obsolete action is exercised before any debounce time. Now allow
        // the fake-zone edit timer to request fresh background correspondence.
        await tester.pump(const Duration(milliseconds: 80));
        await _ready(
          tester,
          () => pane(0).regionActions.any(
            (a) => a.label == 'Accept left region' && a.onInvoke != null,
          ),
        );
        expect(controller.value, edited);
        // Finish the IME transaction before invoking a separate region command;
        // pending-composition cancellation has its own supported Undo behavior.
        tester.testTextInput.updateEditingValue(
          edited.copyWith(composing: TextRange.empty),
        );
        final button = find.descendant(
          of: find.byType(GitTextPane).at(0),
          matching: find.byTooltip('Accept left region'),
        );
        await _ready(tester, () => button.evaluate().isNotEmpty);
        await tester.tap(button);
        await _ready(
          tester,
          () => find
              .text('Result regions with conflict markers: 0')
              .evaluate()
              .isNotEmpty,
        );
        final expected =
            'manual prefix\n${ours.replaceFirst('base tail', 'non-conflicting incoming tail')}';
        expect(utf8.encode(controller.text), utf8.encode(expected));
        expect(controller.text.endsWith('\n'), !atEofWithoutLf);
        await tester.tap(field);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(utf8.encode(clipboard!), utf8.encode(expected));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(controller.text, edited.text);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(controller.text, expected);
        await tester.runAsync(() async {
          expect(
            await File('${fixture.path}/repo/$path').readAsBytes(),
            working,
          );
          expect(await git(['show', ':clean.md']), stagedClean);
          expect(
            utf8
                .decode(await git(['ls-files', '-u', '--', path]))
                .trim()
                .split('\n'),
            hasLength(3),
          );
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
