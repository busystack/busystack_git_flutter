import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

GitHost menuHost(GitPresentMenu menu, {GitPresentSurface? surface}) {
  final original = host();
  return GitHost(
    present: surface ?? original.present,
    presentMenu: menu,
    openDocument: original.openDocument,
    prepareMutation: original.prepareMutation,
    chooseDirectory: original.chooseDirectory,
    notify: original.notify,
    drafts: original.drafts,
    translate: (_, text) => 'translated $text',
  );
}

void main() {
  testWidgets('choosing a Log row owns arrow keys and the Git context menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FixtureClient()
      ..historyCommits = [
        for (final id in ['a', 'b'])
          GitCommit(
            oid: GitOid(id * 40),
            parents: const [],
            subject: 'Commit $id',
            author: 'Fixture',
            email: 'fixture@example.invalid',
            date: DateTime.utc(2026),
            message: 'Message $id',
          ),
      ];
    var gitMenus = 0, outsideMenus = 0;
    final original = host();
    final configured = GitHost(
      present: original.present,
      presentMenu: (_, entries, {position}) async {
        gitMenus++;
        expect(entries.map((e) => e.id), contains('Open snapshot'));
        return null;
      },
      openDocument: original.openDocument,
      chooseDirectory: original.chooseDirectory,
      notify: original.notify,
      drafts: original.drafts,
      prepareMutation: original.prepareMutation,
    );
    final session = GitSession(
      client: client,
      repository: repo,
      host: configured,
    );
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.f10)
                outsideMenus++;
              return KeyEventResult.ignored;
            },
            child: GitLogView(session: session),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Commit a').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('b' * 40), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(gitMenus, 1);
    expect(outsideMenus, 0);
    expect(find.text('b' * 40), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'repository menu uses the invoking control as its native anchor',
    (tester) async {
      Size? anchorSize;
      final original = host();
      final configured = GitHost(
        present: original.present,
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: original.drafts,
        presentMenu: (context, entries, {position}) async {
          anchorSize = (context.findRenderObject()! as RenderBox).size;
          expect(
            entries.map((e) => e.id),
            containsAll(['fetch', 'pull', 'push', 'recovery']),
          );
          return null;
        },
      );
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: configured,
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 350,
                child: GitCommitView(
                  session: session,
                  onReview: (_) {},
                  onLog: () {},
                  onBranches: () {},
                  onPush: () {},
                  onMore: (anchor) => GitWorkflowUi(anchor, session).more(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Repository actions'));
      await tester.pumpAndSettle();
      expect(anchorSize, isNotNull);
      expect(anchorSize!.width, lessThanOrEqualTo(56));
      expect(anchorSize!.height, lessThanOrEqualTo(56));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('operation banner opens actual continuation controls directly', (
    tester,
  ) async {
    var menuCalls = 0;
    final session = GitSession(
      client: _ContinuingClient(),
      repository: repo,
      host: host(),
    );
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitView(
            session: session,
            onReview: (_) {},
            onLog: () {},
            onBranches: () {},
            onPush: () {},
            onMore: (_) => menuCalls++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review operation'));
    await tester.pumpAndSettle();
    expect(find.byType(GitOperationView), findsOneWidget);
    expect(find.text('abort…'), findsOneWidget);
    expect(find.text('skip…'), findsNothing);
    expect(menuCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'native menus preserve checked states, raw refs and cancellation',
    (tester) async {
      List<GitMenuEntry>? received;
      var fallbackCount = 0;
      final configured = menuHost(
        (_, entries, {position}) async {
          received = entries;
          return null;
        },
        surface: <T>(context, title, child, {bool expanded = false}) async {
          fallbackCount++;
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => configured.menu(context, 'Options', const [
                GitMenuEntry('signoff', 'Sign-off trailer', checked: true),
                GitMenuEntry(
                  'configured',
                  'Use configured signing',
                  checked: true,
                  radio: true,
                ),
                GitMenuEntry(
                  'unsigned',
                  'Do not sign',
                  checked: false,
                  radio: true,
                ),
                GitMenuEntry.separator(),
                GitMenuEntry('tag', 'v1/Unicode-版本', localize: false),
                GitMenuEntry('disabled', 'Delete', enabled: false),
              ]),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(received!.map((e) => e.id), [
        'signoff',
        'configured',
        'unsigned',
        'tag',
        'disabled',
      ]);
      expect(received![0].checked, isTrue);
      expect(received![0].radio, isFalse);
      expect(received![1].radio, isTrue);
      expect(received![2].checked, isFalse);
      expect(received![3].label, 'v1/Unicode-版本');
      expect(received![3].sectionStart, isTrue);
      expect(received![4].enabled, isFalse);
      expect(fallbackCount, 0);
    },
  );

  testWidgets('an unavailable native menu uses the host dialog', (
    tester,
  ) async {
    var fallbackCount = 0;
    final configured = menuHost(
      (_, _, {position}) async {
        throw const GitException(GitErrorCode.unavailable);
      },
      surface: <T>(context, title, child, {bool expanded = false}) async {
        fallbackCount++;
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => configured.menu(context, 'Options', const [
              GitMenuEntry('open', 'Open'),
            ]),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(fallbackCount, 1);
  });

  testWidgets(
    'line-numbered panes reveal wrapped positions and retain composing input and undo',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = List.generate(
        160,
        (i) => 'Line $i: ${'long prose ' * 15}\n',
      ).join();
      final result = TextEditingController(text: content);
      final undo = UndoHistoryController();
      final scroll = ScrollController();
      addTearDown(result.dispose);
      addTearDown(undo.dispose);
      addTearDown(scroll.dispose);
      Future<void> show(int? offset) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: GitTextPane(
                label: 'Index · editable UTF-8',
                controller: result,
                undoController: undo,
                scrollController: scroll,
                revealOffset: offset,
              ),
            ),
          ),
        ),
      );
      await show(null);
      await tester.pumpAndSettle();
      final target = content.indexOf('Line 120:');
      await show(target);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final caret = render.getLocalRectForCaret(TextPosition(offset: target));
      expect(caret.top, inInclusiveRange(0, 60));
      await tester.tap(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '日本語 composing',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();
      expect(result.value.composing, const TextRange(start: 0, end: 3));
      expect(result.text, '日本語 composing');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapsed and enlarged Commit layouts retain the draft without overflow',
    (tester) async {
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: host(),
      );
      await session.start();
      session.setDraft('retained message');
      for (final size in [
        Size.zero,
        const Size(280, 160),
        const Size(350, 700),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
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
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(session.draft, 'retained message');
        expect(tester.takeException(), isNull, reason: '$size');
      }
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}

final class _ContinuingClient extends FixtureClient {
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: 'merge',
    indexToken: 'unmerged',
    changes: [
      GitChange(path: RepoPath.text('conflict.md'), index: 'U', worktree: 'U'),
    ],
    operation: const RepositoryOperation(
      GitOperationKind.merge,
      unmerged: true,
    ),
    observedAt: DateTime.utc(2026),
  );
}
