import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart' show host;

final class _IsolatedRunner implements GitRunner {
  _IsolatedRunner(this.directory)
    : process = ProcessGitRunner(
        executable: const String.fromEnvironment('BUSYSTACK_TEST_GIT').isEmpty
            ? Platform.environment['BUSYSTACK_TEST_GIT']
            : const String.fromEnvironment('BUSYSTACK_TEST_GIT'),
        helperPath:
            const String.fromEnvironment('BUSYSTACK_GIT_HELPER_PATH').isEmpty
            ? Platform.environment['BUSYSTACK_GIT_HELPER_PATH']
            : const String.fromEnvironment('BUSYSTACK_GIT_HELPER_PATH'),
      );
  final Directory directory;
  final ProcessGitRunner process;
  @override
  Future<GitRunResult> run(
    List<String> arguments, {
    required String cwd,
    List<int>? input,
    GitCancellation? cancellation,
    Duration? deadline,
    void Function(List<int>)? onStdout,
    void Function(String)? onProgress,
    String Function(String)? redactDiagnostic,
    Map<String, String> environment = const {},
    Map<int, List<int>> byteArguments = const {},
    int? maximumBytes,
  }) => process.run(
    arguments,
    cwd: cwd,
    input: input,
    cancellation: cancellation,
    deadline: deadline,
    onStdout: onStdout,
    onProgress: onProgress,
    redactDiagnostic: redactDiagnostic,
    byteArguments: byteArguments,
    maximumBytes: maximumBytes,
    environment: {
      'HOME': directory.path,
      'XDG_CONFIG_HOME': directory.path,
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_AUTHOR_NAME': 'Fixture',
      'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
      'GIT_COMMITTER_NAME': 'Fixture',
      'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
      ...environment,
    },
  );
}

void main() {
  testWidgets(
    'rapid Unstage writes exact index bytes and preserves working and unrelated index',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory fixture;
      late _IsolatedRunner runner;
      late GitSession session;
      late BackgroundGitClient client;
      Future<Uint8List> git(List<String> arguments) async {
        final result = await runner.run(arguments, cwd: fixture.path);
        expect(
          result.success,
          isTrue,
          reason: '${arguments.first}: ${result.diagnostic}',
        );
        return result.stdout;
      }

      await tester.runAsync(() async {
        fixture = await Directory.systemTemp.createTemp('bsg-index-regions-');
        runner = _IsolatedRunner(fixture);
        await runner.process.verify();
        await git(['init', '--initial-branch=main']);
        await File('${fixture.path}/note.md').writeAsString('one\nold\nend\n');
        await File(
          '${fixture.path}/unrelated.md',
        ).writeAsString('old unrelated\n');
        await git(['add', '.']);
        await git(['commit', '-m', 'base']);
        await File(
          '${fixture.path}/note.md',
        ).writeAsString('one\nstaged\nend\n');
        await File(
          '${fixture.path}/unrelated.md',
        ).writeAsString('staged unrelated\n');
        await git(['add', '.']);
        await File(
          '${fixture.path}/note.md',
        ).writeAsString('one\nstaged\nend\nunstaged\n');
        client = BackgroundGitClient(
          executable: runner.process.executable,
          helperPath: runner.process.helperPath,
          authorize: (_) => true,
        );
        final repository = (await client.discover(fixture.path))!;
        session = GitSession(
          client: client,
          repository: repository,
          host: host(),
        );
        await session.start();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        session.dispose();
        await tester.runAsync(() async {
          await client.close();
          await fixture.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitIndexEditor(
              session: session,
              path: RepoPath.text('note.md'),
              computeDiff: (a, b) async => computeTextDiff(a, b),
            ),
          ),
        ),
      );
      final unstage = find.widgetWithText(TextButton, 'Unstage this hunk');
      for (var i = 0; i < 100 && unstage.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        unstage,
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map(
              (widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '',
            )
            .join('\n'),
      );
      final callback = tester.widget<TextButton>(unstage).onPressed!;
      callback();
      callback(); // Reuse the actual mounted action without a frame or debounce.
      final draft = tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Editable index content'),
          )
          .controller!;
      expect(draft.text, 'one\nold\nend\n');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Write edited result to this index entry'));
      for (var i = 0; i < 100 && session.running; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(session.failure, isNull);
      expect(session.outcome?.completed, isTrue);
      await tester.runAsync(() async {
        expect(await git(['show', ':note.md']), utf8.encode('one\nold\nend\n'));
        expect(
          await git(['show', ':unrelated.md']),
          utf8.encode('staged unrelated\n'),
        );
        expect(
          await File('${fixture.path}/note.md').readAsBytes(),
          utf8.encode('one\nstaged\nend\nunstaged\n'),
        );
        expect(
          await File('${fixture.path}/unrelated.md').readAsBytes(),
          utf8.encode('staged unrelated\n'),
        );
      });
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
    },
  );
}
