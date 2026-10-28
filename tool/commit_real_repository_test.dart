import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String? _runtimeSetting(String key, String defined) =>
    defined.isNotEmpty ? defined : Platform.environment[key];
final _gitExecutable = _runtimeSetting(
  'BUSYSTACK_TEST_GIT',
  const String.fromEnvironment('BUSYSTACK_TEST_GIT'),
);
final _gitHelper = _runtimeSetting(
  'BUSYSTACK_GIT_HELPER_PATH',
  const String.fromEnvironment('BUSYSTACK_GIT_HELPER_PATH'),
);

// Native acceptance invokes this suite explicitly with the pinned Git runtime
// and BusyStack process helper. No alternate executable or mocks replace Git.
final class _IsolatedRunner implements GitRunner {
  _IsolatedRunner(this.home)
    : process = ProcessGitRunner(
        executable: _gitExecutable,
        helperPath: _gitHelper,
      );
  final String home;
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
      'HOME': home,
      'XDG_CONFIG_HOME': home,
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

final class _DelayedClient implements GitClient {
  _DelayedClient(this.engine);
  final GitEngine engine;
  final started = Completer<void>(), proceed = Completer<void>();
  final historyLoaded = Completer<void>();
  final requests = <GitMutation>[];
  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    requests.add(request);
    started.complete();
    await proceed.future;
    return engine.mutate(
      repository,
      request,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  @override
  Future<RepositoryId?> discover(
    String path, {
    GitCancellation? cancellation,
  }) => engine.discover(path, cancellation: cancellation);
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) => engine.status(repository, cancellation: cancellation, policy: policy);
  @override
  Future<List<GitReference>> references(RepositoryId repository) =>
      engine.references(repository);
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) async {
    try {
      final page = await engine.history(
        repository,
        filter: filter,
        offset: offset,
        limit: limit,
        anchor: anchor,
        cancellation: cancellation,
      );
      if (!historyLoaded.isCompleted) historyLoaded.complete();
      return page;
    } on Object catch (error, stack) {
      if (!historyLoaded.isCompleted) historyLoaded.completeError(error, stack);
      rethrow;
    }
  }

  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) => engine.content(repository, path, version, cancellation: cancellation);
  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) => engine.changedFiles(repository, revision, parent: parent);
  @override
  Stream<void> watch(RepositoryId repository) => Stream<void>.multi((_) {});
}

void main() {
  for (final stageOutsideFolder in [false, true]) {
    testWidgets(
      'real amend preserves later draft and repository-wide index, staged outside folder: $stageOutsideFolder',
      (tester) async {
        final git = _gitExecutable;
        expect(
          git,
          isNotNull,
          reason: 'Native acceptance requires the controlled Git runtime.',
        );
        expect(
          _gitHelper,
          isNotNull,
          reason: 'Native acceptance requires the existing process supervisor.',
        );
        late Directory fixture;
        late _DelayedClient client;
        late RepositoryId repository;
        late GitSession session;
        late List<int> outsideExpected;
        final workingBytes = utf8.encode(
          'long Markdown paragraph 東京\r\nmanual unstaged text without newline',
        );
        Future<List<int>> runGit(List<String> args) async {
          final result = await Process.run(
            git!,
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
          expect(result.exitCode, 0, reason: '${result.stderr}');
          return result.stdout as List<int>;
        }

        await tester.runAsync(() async {
          fixture = await Directory.systemTemp.createTemp(
            'busystack-real-commit-',
          );
          await Directory('${fixture.path}/home').create();
          await Directory('${fixture.path}/repo/book').create(recursive: true);
          await runGit(['init', '-b', 'main']);
          await runGit(['config', 'user.name', 'Fixture']);
          await runGit(['config', 'user.email', 'fixture@example.invalid']);
          await File(
            '${fixture.path}/repo/book/東京.md',
          ).writeAsString('one\r\noriginal\r\n');
          await File(
            '${fixture.path}/repo/outside.md',
          ).writeAsString('outside original\n');
          await runGit(['add', '--', '.']);
          await runGit(['commit', '-m', 'Original HEAD']);
          outsideExpected = utf8.encode(
            stageOutsideFolder
                ? 'outside staged\r\nno final newline'
                : 'outside original\n',
          );
          if (stageOutsideFolder) {
            await File(
              '${fixture.path}/repo/outside.md',
            ).writeAsBytes(outsideExpected);
            await runGit(['add', '--', 'outside.md']);
          }
          await File(
            '${fixture.path}/repo/book/東京.md',
          ).writeAsBytes(workingBytes);
          client = _DelayedClient(
            GitEngine(
              runner: _IsolatedRunner('${fixture.path}/home'),
              authorize: (_) => true,
              helperPath: _gitHelper,
            ),
          );
          repository = (await client.discover('${fixture.path}/repo/book'))!;
          final drafts = MemoryGitDraftStore();
          session = GitSession(
            client: client,
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
              drafts: drafts,
            ),
          );
          await session.start();
        });
        addTearDown(() async {
          session.dispose();
          await fixture.delete(recursive: true);
        });
        tester.view.physicalSize = const Size(1300, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final oldHead = session.snapshot!.head!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                child: GitCommitView(
                  session: session,
                  onReview: (_) {},
                  onLog: () {},
                  onBranches: () {},
                  onPush: () {},
                  onMore: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final input = find.widgetWithText(TextField, 'Commit message');
        await tester.enterText(input, 'normal A');
        await tester.runAsync(() async {
          await tester.tap(find.byType(Checkbox));
          await client.historyLoaded.future.timeout(
            const Duration(seconds: 10),
          );
        });
        await tester.pumpAndSettle();
        await tester.enterText(input, 'submitted B');
        late Future<void> operation;
        await tester.runAsync(() async {
          operation = session.commitAction!(false);
          await client.started.future.timeout(const Duration(seconds: 10));
        });
        await tester.pump();
        await tester.enterText(input, 'newer C');
        await tester.runAsync(() async {
          client.proceed.complete();
          await operation.timeout(const Duration(seconds: 15));
        });
        await tester.pumpAndSettle();
        await session.flushMessageDrafts();
        expect(client.requests, hasLength(1));
        expect((client.requests.single as CommitIndex).message, 'submitted B');
        expect(
          session.outcome?.completed,
          isTrue,
          reason: '${session.failure}',
        );
        expect(session.draft, 'normal A');
        expect(find.text('newer C'), findsOneWidget);
        expect(session.canCommit!(), isFalse);
        await tester.runAsync(() async {
          expect(
            utf8.decode(await runGit(['log', '-1', '--format=%B'])),
            'submitted B\n\n',
          );
          expect(await runGit(['show', 'HEAD:outside.md']), outsideExpected);
          expect(await runGit(['show', ':outside.md']), outsideExpected);
          expect(
            await File('${fixture.path}/repo/book/東京.md').readAsBytes(),
            workingBytes,
          );
          expect(
            utf8.decode(await runGit(['show', 'HEAD:book/東京.md'])),
            'one\r\noriginal\r\n',
          );
          expect(
            await session.host.drafts.read(
              '${repository.presentationKey}:amend:${oldHead.value}',
            ),
            'newer C',
          );
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
