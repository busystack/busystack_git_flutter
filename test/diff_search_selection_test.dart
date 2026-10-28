import 'dart:async';
import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _ReviewClient extends FixtureClient {
  static const before = 'first old\ncontext\nsecond old\nend\n';
  static const after =
      'first new needle\ncontext\nsecond new needle needle\nend\n';
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode(
      version.kind == ContentKind.indexVersion ? before : after,
    ),
  );
}

Future<(GitSession, _ReviewClient)> _review(
  WidgetTester tester, {
  GitHost? presentationHost,
  Future<List<(int, int, int)>> Function(List<String>, String)? searchMatches,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = _ReviewClient();
  final session = GitSession(
    client: client,
    repository: repo,
    host: presentationHost ?? host(),
  );
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GitDiffView(
          session: session,
          searchMatches: searchMatches,
          comparison: GitComparison(
            RepoPath.text('chapter/notes.md'),
            const ContentVersion.index(),
            const ContentVersion.working(),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return (session, client);
}

Future<void> _finishSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final loading = find.byKey(const ValueKey('git-diff-search-loading'));
  for (var step = 0; step < 200 && loading.evaluate().isNotEmpty; step++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(loading, findsNothing);
  await tester.pumpAndSettle();
}

final class _FarSearchClient extends FixtureClient {
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode(
      [
        for (var line = 0; line < 300; line++)
          if (line == 20)
            version.kind == ContentKind.indexVersion
                ? 'old line'
                : 'changed needle'
          else if (line == 245)
            'distant unchanged needle'
          else
            'unchanged line $line',
      ].join('\n'),
    ),
  );
}

final class _LongSearchClient extends FixtureClient {
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode(
      version.kind == ContentKind.indexVersion
          ? 'old\n'
          : 'begin ${'Unicode prose 界 ' * 100}needle ${'long Markdown prose ' * 150}needle end\n',
    ),
  );
}

final class _ManyMatchesClient extends FixtureClient {
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode(
      [
        for (var line = 0; line < 10020; line++)
          if (line == 0)
            version.kind == ContentKind.indexVersion ? 'old' : 'new'
          else
            'needle $line',
      ].join('\n'),
    ),
  );
}

void main() {
  testWidgets(
    'mouse text selection copies through Clipboard without selecting staged lines',
    (tester) async {
      await _review(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          if (call.method == 'Clipboard.getData') return {'text': copied};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final origin =
          tester.getTopLeft(find.text('first new needle')) + const Offset(1, 8);
      final mouse = await tester.startGesture(
        origin,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(origin + const Offset(92, 0));
      await mouse.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, isNotEmpty);
      expect('first new needle', contains(copied));
      expect(find.textContaining('0 changed lines selected'), findsOneWidget);
    },
  );

  testWidgets('file navigation shortcuts apply only within Git focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var previous = 0, next = 0;
    final session = GitSession(
      client: _ReviewClient(),
      repository: repo,
      host: host(),
    );
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(
                width: 300,
                child: TextField(key: ValueKey('authoring-input')),
              ),
              Expanded(
                child: GitDiffView(
                  session: session,
                  onPreviousFile: () => previous++,
                  onNextFile: () => next++,
                  comparison: GitComparison(
                    RepoPath.text('chapter/notes.md'),
                    const ContentVersion.index(),
                    const ContentVersion.working(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('authoring-input')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(next, 0);
    await tester.tap(find.byTooltip('Search comparison'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextField, 'Search'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(next, 1);
    expect(previous, 1);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  for (final wrap in [false, true]) {
    testWidgets(
      'current search substring is visible within a long paragraph wrap=$wrap',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = GitSession(
          client: _LongSearchClient(),
          repository: repo,
          host: host(),
        );
        await session.start();
        session.setViewState('diffWrap', wrap);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GitDiffView(
                session: session,
                comparison: GitComparison(
                  RepoPath.text('paragraph.md'),
                  const ContentVersion.index(),
                  const ContentVersion.working(),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search comparison'));
        await tester.pump();
        await tester.enterText(
          find.widgetWithText(TextField, 'Search'),
          'needle',
        );
        await _finishSearch(tester);
        await tester.tap(find.byTooltip('Next search match'));
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.textContaining('begin '),
            matching: find.byType(RichText),
          ),
        );
        final text = paragraph.text.toPlainText(),
            offset = paragraph.text.toPlainText().lastIndexOf('needle');
        expect(text.substring(offset, offset + 6), 'needle');
        final match = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: offset, extentOffset: offset + 6),
            )
            .first
            .toRect();
        final point = paragraph.localToGlobal(match.center);
        final viewport = tester.getRect(find.byType(ListView));
        expect(point.dy, inInclusiveRange(viewport.top, viewport.bottom));
        if (!wrap) {
          final pane = tester.getRect(
            find.byKey(const ValueKey('git-diff-right-horizontal')),
          );
          expect(point.dx, inInclusiveRange(pane.left, pane.right));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets('match indexing stays bounded and explicitly reports its limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = GitSession(
      client: _ManyMatchesClient(),
      repository: repo,
      host: host(),
    );
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitDiffView(
            session: session,
            comparison: GitComparison(
              RepoPath.text('many.md'),
              const ContentVersion.index(),
              const ContentVersion.working(),
            ),
          ),
        ),
      ),
    );
    for (
      var step = 0;
      step < 400 && find.byTooltip('Search comparison').evaluate().isEmpty;
      step++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search comparison'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'needle');
    await _finishSearch(tester);
    expect(find.text('1 of 10000 matches'), findsOneWidget);
    expect(
      find.text(
        'Showing the first 10000 matches. Refine the search to review more.',
      ),
      findsOneWidget,
    );
    expect(tester.widgetList<Text>(find.byType(Text)).length, lessThan(300));
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('out of order background search cannot restore an older query', (
    tester,
  ) async {
    final pending = <String, Completer<List<(int, int, int)>>>{};
    await _review(
      tester,
      searchMatches: (lines, query) {
        final completion = Completer<List<(int, int, int)>>();
        pending[query] = completion;
        return completion.future;
      },
    );
    await tester.tap(find.byTooltip('Search comparison'));
    await tester.pump();
    final input = find.widgetWithText(TextField, 'Search');
    await tester.enterText(input, 'needle');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(input, 'context');
    await tester.pump(const Duration(milliseconds: 100));
    final contextLine = computeTextDiff(
      _ReviewClient.before,
      _ReviewClient.after,
    ).edits.indexWhere((line) => line.text.startsWith('context'));
    pending['context']!.complete([(contextLine, 0, 7)]);
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 matches'), findsOneWidget);
    pending['needle']!.complete([(1, 10, 16), (4, 11, 17), (4, 18, 24)]);
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 matches'), findsOneWidget);
    expect(find.text('1 of 3 matches'), findsNothing);
    await tester.enterText(input, 'later');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    pending['later']!.completeError(StateError('obsolete worker completion'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'old hunk, file, gutter and source callbacks cannot retarget a new review',
    (tester) async {
      final (session, client) = await _review(tester);
      final stageFile = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Stage whole file'),
          )
          .onPressed!;
      final stageHunk = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Stage this hunk').first,
          )
          .onPressed!;
      final openSource = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Open current file'),
          )
          .onPressed!;
      final firstChanged = computeTextDiff(
        _ReviewClient.before,
        _ReviewClient.after,
      ).changedIndices.first;
      final selectLine = tester
          .widget<InkWell>(
            find.byKey(ValueKey('git-diff-stage-line-$firstChanged')),
          )
          .onTap!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitDiffView(
              session: session,
              comparison: GitComparison(
                RepoPath.text('other.md'),
                const ContentVersion.index(),
                const ContentVersion.working(),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      stageFile();
      stageHunk();
      selectLine();
      openSource();
      await tester.pump();
      expect(client.mutations, isEmpty);
      expect(find.textContaining('0 changed lines selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search reveals unbuilt collapsed context and restores context on close',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = GitSession(
        client: _FarSearchClient(),
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitDiffView(
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('distant unchanged needle'), findsNothing);
      await tester.tap(find.byTooltip('Search comparison'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search'),
        'needle',
      );
      await _finishSearch(tester);
      expect(find.text('1 of 2 matches'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 matches'), findsOneWidget);
      final distant = find.text('distant unchanged needle');
      expect(distant, findsNWidgets(2));
      final viewport = tester.getRect(find.byType(ListView));
      expect(
        tester.getRect(distant.at(0)).top,
        inInclusiveRange(viewport.top, viewport.bottom),
      );
      expect(tester.widgetList<Text>(find.byType(Text)).length, lessThan(150));
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.text('distant unchanged needle'), findsNothing);
      expect(session.option('diffCollapse', true), isTrue);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'source navigation uses the current-file host flow and excludes historical revisions',
    (tester) async {
      final opened = <RepoPath>[];
      final base = host();
      final presentationHost = GitHost(
        present: base.present,
        openDocument: (repository, path, {snapshot}) async {
          expect(snapshot, isNull);
          opened.add(path);
        },
        prepareMutation: base.prepareMutation,
        chooseDirectory: base.chooseDirectory,
        notify: base.notify,
        drafts: MemoryGitDraftStore(),
      );
      final (session, _) = await _review(
        tester,
        presentationHost: presentationHost,
      );
      await tester.tap(find.text('Open current file'));
      expect(opened, [RepoPath.text('chapter/notes.md')]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitDiffView(
              session: session,
              comparison: GitComparison(
                RepoPath.text('chapter/notes.md'),
                ContentVersion(ContentKind.commit, revision: GitOid('a' * 40)),
                ContentVersion(ContentKind.commit, revision: GitOid('b' * 40)),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open current file'), findsNothing);
      expect(opened, hasLength(1));
    },
  );

  testWidgets('copyable text and gutter changed-line selection are distinct', (
    tester,
  ) async {
    await _review(tester);
    await tester.tap(find.text('first new needle'));
    await tester.pump();
    expect(find.textContaining('0 changed lines selected'), findsOneWidget);
    final changed = computeTextDiff(
      _ReviewClient.before,
      _ReviewClient.after,
    ).changedIndices;
    await tester.tap(
      find.byKey(ValueKey('git-diff-stage-line-${changed.first}')),
    );
    await tester.pump();
    expect(find.textContaining('1 changed lines selected'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(
      find.byKey(ValueKey('git-diff-stage-line-${changed.last}')),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      find.textContaining('${changed.length} changed lines selected'),
      findsOneWidget,
    );
  });

  testWidgets(
    'keyboard Shift arrows extend and shrink real changed-line ranges',
    (tester) async {
      final (_, client) = await _review(tester);
      final changed = computeTextDiff(
        _ReviewClient.before,
        _ReviewClient.after,
      ).changedIndices;
      await tester.tap(
        find.byKey(ValueKey('git-diff-stage-line-${changed.first}')),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 changed lines selected'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.textContaining('3 changed lines selected'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 changed lines selected'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Stage selected changed lines'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        (client.mutations.single as WriteIndex).bytes,
        utf8.encode('first new needle\ncontext\nsecond old\nend\n'),
      );
    },
  );

  testWidgets('search navigation identifies its current match and wraps', (
    tester,
  ) async {
    await _review(tester);
    await tester.tap(find.byTooltip('Search comparison'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'needle');
    await _finishSearch(tester);
    expect(find.text('1 of 3 matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Next search match'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Next search match'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 matches'), findsOneWidget);
    final spans = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((rich) {
          final result = <TextSpan>[];
          void visit(InlineSpan span) {
            if (span is TextSpan) {
              result.add(span);
              for (final child in span.children ?? <InlineSpan>[]) visit(child);
            }
          }

          visit(rich.text);
          return result;
        })
        .where(
          (span) =>
              span.text == 'needle' &&
              span.style?.decoration == TextDecoration.underline,
        );
    expect(spans, hasLength(1));
    await tester.tap(find.byTooltip('Next search match'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous search match'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 matches'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
