import 'dart:async';
import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'conflict_editor_test.dart' show ConflictClient;
import 'support/presentation_fixture.dart';
import 'conflict_refresh_test.dart' show SlowConflictClient;

final class _MixedClient extends FixtureClient implements GitWorkflowClient {
  final source = ConflictClient();
  String context = 'Prelude\n';
  String get left => '${context}Left one\nBetween\nLeft two\nTail\n';
  String get right => '${context}Right one\nBetween\nRight two\nTail\n';
  String block(String a, String b, {bool preview = false}) => preview
      ? '${'<' * 32} FIXTURE_LEFT\n$a\n${'|' * 32} FIXTURE_BASE\nBase\n${'=' * 32}\n$b\n${'>' * 32} FIXTURE_RIGHT\n'
      : '<<<<<<< HEAD\n$a\n=======\n$b\n>>>>>>> incoming\n';
  String get working =>
      '$context${block('Left one', 'Right one')}Between\n${block('Left two', 'Right two')}Saved custom Tail\n';
  String get preview =>
      '$context${block('Left one', 'Right one', preview: true)}Between\n${block('Left two', 'Right two', preview: true)}Git preview Tail\n';
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) => source.status(repository, cancellation: cancellation, policy: policy);
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => source.inspect(
    repository,
    request,
    cancellation: cancellation,
    onProgress: onProgress,
  );
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    final value = await source.content(
      repository,
      path,
      version,
      cancellation: cancellation,
    );
    final text = switch (version.kind) {
      ContentKind.workingTree => working,
      ContentKind.mergePreview => preview,
      _ =>
        version.stage == 2
            ? left
            : version.stage == 3
            ? right
            : '${context}Base\nBetween\nBase\nTail\n',
    };
    return GitContent(
      path: path,
      version: version,
      availability: value.availability,
      token: value.token,
      mode: value.mode,
      oid: value.oid,
      bytes: utf8.encode(text),
    );
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Unused');
}

final class _InvalidEncodingClient extends _MixedClient {
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    final value = await super.content(
      repository,
      path,
      version,
      cancellation: cancellation,
    );
    return GitContent(
      path: path,
      version: version,
      availability: ContentAvailability.present,
      token: value.token,
      mode: value.mode,
      oid: value.oid,
      bytes: [255, 254, 195],
    );
  }
}

// Git merge normally groups nearby edits into one working-file marker block,
// while the independently requested diff3 preview may expose two regions.
final class _GroupedClient extends _MixedClient {
  @override
  String get working =>
      '$context${block('Left one\nBetween\nLeft two', 'Right one\nBetween\nRight two')}Saved custom Tail\n';
}

final class _RepeatedClient extends _MixedClient {
  @override
  String get left =>
      '${context}Left repeat\nBetween distinct chapters\nLeft repeat\nTail\n';
  @override
  String get right =>
      '${context}Right repeat\nBetween distinct chapters\nRight repeat\nTail\n';
  @override
  String get working =>
      '$context${block('Left repeat', 'Right repeat')}Between distinct chapters\n${block('Left repeat', 'Right repeat')}Saved custom Tail\n';
  @override
  String get preview =>
      '$context${block('Left repeat', 'Right repeat', preview: true)}Between distinct chapters\n${block('Left repeat', 'Right repeat', preview: true)}Git preview Tail\n';
}

final class _DelayedMixedClient extends _MixedClient {
  final mutationCompletion = Completer<GitOutcome>();
  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) {
    mutations.add(request);
    return mutationCompletion.future;
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final elapsed = Stopwatch()..start();
  while (!done()) {
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 6)),
      reason:
          'Conflict correspondence did not finish: ${find.byType(GitFailurePanel).evaluate().map((e) => (e.widget as GitFailurePanel).error)}; ${tester.widgetList<GitTextPane>(find.byType(GitTextPane)).map((p) => p.regionActions.length)}; ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(" | ")}',
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  await tester.pump();
}

GitTextPane _pane(WidgetTester tester, int index) =>
    tester.widgetList<GitTextPane>(find.byType(GitTextPane)).elementAt(index);
Future<GitSession> _mount(
  WidgetTester tester,
  _MixedClient client, {
  Future<List<TextDiff>> Function(String, String, String)? computeDiffs,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: GitConflictView(
          session: session,
          path: client.source.path,
          computeDiffs: computeDiffs,
        ),
      ),
    ),
  );
  await _until(tester, () => find.byType(GitTextPane).evaluate().length == 3);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return session;
}

Future<void> _mapped(WidgetTester tester) async {
  await tester.pump();
  await _until(
    tester,
    () => _pane(tester, 0).regionActions.any((a) => a.onInvoke != null),
  );
}

void main() {
  testWidgets('actual grouped result block owns one local source transfer', (
    tester,
  ) async {
    final client = _GroupedClient();
    await _mount(tester, client);
    await _until(
      tester,
      () =>
          tester
              .widget<GitRevisionPanes>(find.byType(GitRevisionPanes))
              .mapOffset!(0, 1, 0) !=
          null,
    );
    final result = _pane(tester, 1).controller!;
    expect(result.text, client.working);
    final leftActions = _pane(
      tester,
      0,
    ).regionActions.where((a) => a.label == 'Accept left region').toList();
    expect(leftActions, hasLength(1));
    expect(find.text('Region 1/1 · 0 reviewed'), findsOneWidget);
    expect(
      find.text('Result regions with conflict markers: 1'),
      findsOneWidget,
    );
    expect(leftActions.single.start, client.left.indexOf('Left one'));
    expect(leftActions.single.end, client.left.indexOf('Tail'));
    _pane(tester, 0).regionActions
        .firstWhere((a) => a.label == 'Ignore left suggestion')
        .onInvoke!();
    await tester.pump();
    expect(result.text, client.working);
    final source = find.byType(GitTextPane).at(0);
    await tester.tap(
      find.descendant(
        of: source,
        matching: find.byTooltip('Accept left region'),
      ),
    );
    await _until(
      tester,
      () => find
          .text('Result regions with conflict markers: 0')
          .evaluate()
          .isNotEmpty,
    );
    expect(
      result.text,
      'Prelude\nLeft one\nBetween\nLeft two\nSaved custom Tail\n',
    );
    expect(result.text, isNot(contains('Git preview Tail')));
    expect(client.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new grouped callback can safely act before debounce', (
    tester,
  ) async {
    final client = _GroupedClient();
    await _mount(tester, client);
    await _mapped(tester);
    final result = _pane(tester, 1).controller!;
    final obsolete = _pane(tester, 0).regionActions.first.onInvoke!;
    result.value = TextEditingValue(
      text: 'manual prefix\n${result.text}',
      selection: const TextSelection(baseOffset: 1, extentOffset: 5),
      composing: const TextRange(start: 0, end: 6),
    );
    final edited = result.value;
    obsolete();
    expect(result.value, edited);
    await tester.pump(); // No debounce time passes before the new action.
    tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Accept left region'),
        )
        .onPressed!();
    expect(
      result.text,
      'manual prefix\nPrelude\nLeft one\nBetween\nLeft two\nSaved custom Tail\n',
    );
    expect(result.selection, edited.selection);
    expect(result.value.composing, edited.composing);
    obsolete();
    expect(result.text, startsWith('manual prefix\nPrelude\nLeft one\n'));
    expect(client.mutations, isEmpty);
  });

  testWidgets('copied member block cannot share grouped source ownership', (
    tester,
  ) async {
    final client = _GroupedClient();
    await _mount(tester, client);
    await _mapped(tester);
    final result = _pane(tester, 1).controller!;
    result.text += client.block('Left two', 'Right two');
    final edited = result.text;
    await _until(
      tester,
      () =>
          tester
              .widget<GitRevisionPanes>(find.byType(GitRevisionPanes))
              .mapOffset!(0, 1, 0) !=
          null,
    );
    expect(_pane(tester, 0).regionActions, isEmpty);
    expect(_pane(tester, 2).regionActions, isEmpty);
    expect(
      find.text('Result regions with conflict markers: 2'),
      findsOneWidget,
    );
    expect(result.text, edited);
    expect(client.mutations, isEmpty);
  });

  testWidgets(
    'local conflict controls align with source and preserve saved manual content',
    (tester) async {
      final client = _MixedClient();
      await _mount(tester, client);
      await _mapped(tester);
      final result = _pane(tester, 1).controller!;
      expect(result.text, client.working);
      final source = find.byType(GitTextPane).at(0);
      final button = find
          .descendant(
            of: source,
            matching: find.byTooltip('Accept left region'),
          )
          .first;
      expect(button, findsOneWidget);
      final action = _pane(
        tester,
        0,
      ).regionActions.firstWhere((a) => a.label == 'Accept left region');
      final field = tester
          .state<EditableTextState>(
            find.descendant(of: source, matching: find.byType(EditableText)),
          )
          .renderEditable;
      final caret = field.localToGlobal(
        field.getLocalRectForCaret(TextPosition(offset: action.start)).topLeft,
      );
      expect((tester.getRect(button).center.dy - caret.dy).abs(), lessThan(45));
      final original = result.value;
      _pane(tester, 0).regionActions
          .firstWhere((a) => a.label == 'Ignore left suggestion')
          .onInvoke!();
      await tester.pump();
      expect(result.value, original);
      expect(
        find.text('Result regions with conflict markers: 2'),
        findsOneWidget,
      );
      await tester.tap(button);
      await _mapped(tester);
      expect(
        result.text,
        'Prelude\nLeft one\nBetween\n${client.block('Left two', 'Right two')}Saved custom Tail\n',
      );
      expect(result.text, contains('Saved custom Tail'));
      expect(result.text, isNot(contains('Git preview Tail')));
      expect(
        find.text('Result regions with conflict markers: 1'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Next conflict region'));
      await tester.pump();
      expect(result.selection.start, result.text.indexOf('<<<<<<< HEAD'));
      expect(result.selection.textInside(result.text), contains('Left two'));
      expect(
        result.selection.textInside(result.text),
        isNot(contains('Left one')),
      );
      expect(client.mutations, isEmpty);
      final revisionPanes = tester.widget<GitRevisionPanes>(
        find.byType(GitRevisionPanes),
      );
      final map = revisionPanes.mapOffset!;
      expect(
        map(0, 1, client.left.indexOf('Between')),
        result.text.indexOf('Between'),
      );
      expect(
        map(1, 2, result.text.indexOf('Between')),
        client.right.indexOf('Between'),
      );
      final last = _pane(tester, 2).regionActions
          .firstWhere((a) => a.label == 'Accept right region')
          .onInvoke!;
      last();
      await _until(
        tester,
        () => find
            .text('Result regions with conflict markers: 0')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        result.text,
        'Prelude\nLeft one\nBetween\nRight two\nSaved custom Tail\n',
      );
      expect(
        tester
            .widget<GitIconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is GitIconButton && w.tooltip == 'Next conflict region',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RTL enlarged panes retain physical side roles and separate local buttons',
    (tester) async {
      final client = _MixedClient();
      await _mount(tester, client, direction: TextDirection.rtl, scale: 1.6);
      await _mapped(tester);
      final path = find.text('/fixture/repo · prose.md');
      expect(path, findsOneWidget);
      expect(Directionality.of(tester.element(path)), TextDirection.ltr);
      final panes = find.byType(GitTextPane);
      expect(
        tester.getRect(panes.at(0)).right,
        lessThan(tester.getRect(panes.at(1)).left),
      );
      expect(
        tester.getRect(panes.at(1)).right,
        lessThan(tester.getRect(panes.at(2)).left),
      );
      for (final (index, accept, ignore) in [
        (0, 'Accept left region', 'Ignore left suggestion'),
        (2, 'Accept right region', 'Ignore right suggestion'),
      ]) {
        final pane = panes.at(index), bounds = tester.getRect(pane);
        final acceptButton = find
            .descendant(of: pane, matching: find.byTooltip(accept))
            .first;
        final ignoreButton = find
            .descendant(of: pane, matching: find.byTooltip(ignore))
            .first;
        final acceptRect = tester.getRect(acceptButton),
            ignoreRect = tester.getRect(ignoreButton);
        expect(acceptRect.overlaps(ignoreRect), isFalse);
        expect(acceptRect.left, greaterThanOrEqualTo(bounds.left));
        expect(ignoreRect.right, lessThanOrEqualTo(bounds.right));
        final action = _pane(
          tester,
          index,
        ).regionActions.firstWhere((a) => a.label == accept);
        final editable = tester
            .state<EditableTextState>(
              find.descendant(of: pane, matching: find.byType(EditableText)),
            )
            .renderEditable;
        expect(editable.textDirection, TextDirection.ltr);
        final field = find.descendant(
          of: pane,
          matching: find.byType(TextField),
        );
        expect(acceptRect.right, lessThanOrEqualTo(tester.getRect(field).left));
        expect(ignoreRect.right, lessThanOrEqualTo(tester.getRect(field).left));
        final caret = editable.localToGlobal(
          editable
              .getLocalRectForCaret(TextPosition(offset: action.start))
              .topLeft,
        );
        expect(
          (acceptRect.center.dy - caret.dy).abs(),
          lessThan(editable.preferredLineHeight * 1.5),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'extra ambiguous copied markers remain manual while other owned regions stay actionable',
    (tester) async {
      final client = _MixedClient();
      await _mount(tester, client);
      await _mapped(tester);
      final result = _pane(tester, 1).controller!;
      final stale = _pane(tester, 1).regionActions.first.onInvoke!;
      result.value = TextEditingValue(
        text: '${client.block('Left one', 'Right one')}${result.text}',
        selection: const TextSelection.collapsed(offset: 0),
      );
      final value = result.value;
      stale();
      expect(result.value, value);
      await _mapped(tester);
      final actions = _pane(
        tester,
        1,
      ).regionActions.where((a) => a.label == 'Accept left region').toList();
      expect(actions, hasLength(1));
      expect(
        result.text.substring(actions.single.start, actions.single.end),
        contains('Left two'),
      );
      expect(
        find.text('Result regions with conflict markers: 3'),
        findsOneWidget,
      );
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failOlder in [false, true]) {
    testWidgets(
      'draft revision rejects out-of-order maps olderFailure=$failOlder',
      (tester) async {
        final client = _MixedClient();
        final pending = <(String, String, String, Completer<List<TextDiff>>)>[];
        await _mount(
          tester,
          client,
          computeDiffs: (a, b, c) {
            final done = Completer<List<TextDiff>>();
            pending.add((a, b, c, done));
            return done.future;
          },
        );
        await _until(tester, () => pending.isNotEmpty);
        void complete(int index) {
          final (a, b, c, done) = pending[index];
          done.complete([computeTextDiff(a, c), computeTextDiff(b, c)]);
        }

        complete(0);
        await _mapped(tester);
        final stale = _pane(tester, 1).regionActions.first.onInvoke!;
        final staleMap = tester
            .widget<GitRevisionPanes>(find.byType(GitRevisionPanes))
            .mapOffset!;
        final controller = _pane(tester, 1).controller!;
        final original = controller.value;
        controller.value = TextEditingValue(
          text: 'manual prefix\n${controller.text}',
          selection: const TextSelection(baseOffset: 0, extentOffset: 6),
          composing: const TextRange(start: 0, end: 6),
        );
        final first = controller.value;
        stale();
        expect(controller.value, first);
        expect(staleMap(0, 1, 0), isNull);
        await tester.pump(const Duration(milliseconds: 79));
        expect(pending, hasLength(1));
        expect(_pane(tester, 1).regionActions, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(pending, hasLength(2));
        controller.value = first.copyWith(
          text: 'newer ${first.text}',
          selection: const TextSelection.collapsed(offset: 3),
          composing: const TextRange(start: 0, end: 3),
        );
        final latest = controller.value;
        await tester.pump(const Duration(milliseconds: 80));
        expect(pending, hasLength(3));
        if (failOlder) {
          pending[1].$4.completeError(
            const GitException(GitErrorCode.outputLimit),
          );
          await tester.pump();
          expect(find.text('Updating conflict regions'), findsOneWidget);
          expect(find.byType(GitFailurePanel), findsNothing);
          expect(_pane(tester, 1).regionActions, isEmpty);
        }
        complete(2);
        await _mapped(tester);
        expect(controller.value, latest);
        expect(
          staleMap(0, 1, 0),
          isNull,
          reason: 'An old mounted callback cannot borrow newly published maps',
        );
        final currentAction = _pane(tester, 1).regionActions.first.onInvoke!;
        if (!failOlder) complete(1);
        await tester.pump();
        expect(controller.value, latest);
        expect(_pane(tester, 1).regionActions.first.onInvoke, isNotNull);
        controller.value = original;
        controller.value = latest; // old bytes cannot revive either callback
        currentAction();
        stale();
        expect(controller.value, latest);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 80));
        expect(pending, hasLength(3));
        expect(tester.takeException(), isNull);
        expect(client.mutations, isEmpty);
      },
    );
  }
  testWidgets(
    'closing while conflict calculation is pending retires its completion',
    (tester) async {
      final client = _MixedClient();
      final pending = Completer<List<TextDiff>>();
      late List<TextDiff> differences;
      var started = false;
      await _mount(
        tester,
        client,
        computeDiffs: (a, b, c) {
          started = true;
          differences = [computeTextDiff(a, c), computeTextDiff(b, c)];
          return pending.future;
        },
      );
      await _until(tester, () => started);
      await tester.pumpWidget(const SizedBox());
      pending.complete(differences);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(client.mutations, isEmpty);
    },
  );

  testWidgets(
    'current comparison failure remains distinct and manual result stays editable',
    (tester) async {
      final client = _MixedClient();
      final pending = Completer<List<TextDiff>>();
      var started = false;
      await _mount(
        tester,
        client,
        computeDiffs: (a, b, c) {
          started = true;
          return pending.future;
        },
      );
      await _until(tester, () => started);
      final value = _pane(tester, 1).controller!.value;
      pending.completeError(const GitException(GitErrorCode.outputLimit));
      await _until(
        tester,
        () => find.byType(GitFailurePanel).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<GitFailurePanel>(find.byType(GitFailurePanel)).error.code,
        GitErrorCode.outputLimit,
      );
      expect(_pane(tester, 1).controller!.value, value);
      expect(_pane(tester, 1).readOnly, isFalse);
      expect(_pane(tester, 1).regionActions, isEmpty);
      expect(
        find.text('Result regions with conflict markers: 0'),
        findsNothing,
      );
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual result composition and undo survive highlighting and region acceptance',
    (tester) async {
      final client = _MixedClient();
      await _mount(tester, client);
      await _mapped(tester);
      final field = find.widgetWithText(TextField, 'Editable conflict result');
      final controller = _pane(tester, 1).controller!;
      final before = controller.text;
      controller.value = TextEditingValue(
        text: '日本語 prefix\n$before',
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 0, end: 3),
      );
      final draft = controller.value;
      await _mapped(tester);
      expect(controller.value, draft);
      _pane(tester, 1).regionActions.first.onInvoke!();
      await _mapped(tester);
      expect(controller.value.composing, const TextRange(start: 0, end: 3));
      expect(controller.selection, draft.selection);
      expect(controller.text, startsWith('日本語 prefix\nPrelude\nLeft one\n'));
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(field, 'Manual complete result\n');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.text, isNot('Manual complete result\n'));
      expect(controller.text, contains('Saved custom Tail'));
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'identical repeated conflict blocks keep exact second-region ownership after prefix and undo',
    (tester) async {
      final client = _RepeatedClient();
      await _mount(tester, client);
      Future<void> mappedTwice() async {
        await tester.pump();
        await _until(
          tester,
          () =>
              _pane(tester, 1).regionActions
                  .where(
                    (a) =>
                        a.label == 'Accept left region' && a.onInvoke != null,
                  )
                  .length ==
              2,
        );
      }

      await mappedTwice();
      final controller = _pane(tester, 1).controller!;
      controller.value = TextEditingValue(
        text: 'manual prefix\n${controller.text}',
        selection: const TextSelection.collapsed(offset: 3),
      );
      await mappedTwice();
      final before = controller.value;
      final second = controller.text.lastIndexOf('<<<<<<< HEAD');
      await tester.tap(find.byTooltip('Next conflict region'));
      await tester.pump();
      await tester.tap(find.byTooltip('Next conflict region'));
      await tester.pump();
      expect(controller.selection.start, second);
      final oldSecond = _pane(tester, 1).regionActions
          .where((a) => a.label == 'Accept left region')
          .last
          .onInvoke!;
      expect(
        _pane(tester, 1).regionActions
            .where((a) => a.label == 'Accept left region')
            .last
            .start,
        second,
      );
      await tester.tap(find.text('Accept left region'));
      await _mapped(tester);
      final expected =
          'manual prefix\nPrelude\n${client.block('Left repeat', 'Right repeat')}Between distinct chapters\nLeft repeat\nSaved custom Tail\n';
      expect(controller.text, expected);
      controller.value = before;
      oldSecond();
      expect(controller.value, before);
      await mappedTwice();
      _pane(tester, 1).regionActions
          .where((a) => a.label == 'Accept left region')
          .last
          .onInvoke!();
      await _mapped(tester);
      expect(controller.text, expected);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conflict keyboard navigation and transfers stay inside Git focus',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _MixedClient(),
          author = TextEditingController(text: 'Unsaved authoring document');
      final authorFocus = FocusNode();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(
                  controller: author,
                  focusNode: authorFocus,
                  decoration: const InputDecoration(labelText: 'Authoring'),
                ),
                Expanded(
                  child: GitConflictView(
                    session: session,
                    path: client.source.path,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await _until(
        tester,
        () => find.byType(GitTextPane).evaluate().length == 3,
      );
      await _mapped(tester);
      final result = _pane(tester, 1).controller!;
      final original = result.value;
      authorFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      expect(result.value, original);
      expect(author.text, 'Unsaved authoring document');
      await tester.tap(
        find.widgetWithText(TextField, 'Editable conflict result'),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      expect(result.selection.start, result.text.indexOf('<<<<<<< HEAD'));
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      expect(result.selection.start, result.text.lastIndexOf('<<<<<<< HEAD'));
      Future<void> command(
        LogicalKeyboardKey key, {
        bool shift = false,
        bool transfer = false,
      }) async {
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        if (transfer) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        }
        await tester.sendKeyEvent(key);
        if (transfer) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
      }

      final before = result.value;
      await command(LogicalKeyboardKey.keyK, transfer: true);
      expect(result.value, before);
      await command(LogicalKeyboardKey.f7, shift: true);
      expect(result.selection.start, result.text.indexOf('<<<<<<< HEAD'));
      await command(LogicalKeyboardKey.arrowRight, transfer: true);
      await _mapped(tester);
      expect(result.text, startsWith('Prelude\nLeft one\nBetween\n'));
      expect(result.text, contains('Left two'));
      await command(LogicalKeyboardKey.f7);
      await command(LogicalKeyboardKey.arrowLeft, transfer: true);
      await _until(
        tester,
        () => find
            .text('Result regions with conflict markers: 0')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        result.text,
        'Prelude\nLeft one\nBetween\nRight two\nSaved custom Tail\n',
      );
      expect(author.text, 'Unsaved authoring document');
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      author.dispose();
      authorFocus.dispose();
    },
  );

  testWidgets(
    'unsupported encoding never becomes an editable empty conflict result',
    (tester) async {
      final client = _InvalidEncodingClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitConflictView(session: session, path: client.source.path),
          ),
        ),
      );
      await _until(
        tester,
        () => find.text('Use entire left content…').evaluate().isNotEmpty,
      );
      expect(find.byType(GitTextPane), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is TextField && !w.readOnly),
        findsNothing,
      );
      expect(find.text('Save result draft'), findsNothing);
      expect(
        find.text('Text comparison is unavailable for these contents.'),
        findsOneWidget,
      );
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'late result input after submitted Apply remains protected in its actual route',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _DelayedMixedClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  session.host.present<void>(
                    context,
                    'Conflict',
                    SizedBox(
                      width: 1450,
                      height: 900,
                      child: GitConflictView(
                        session: session,
                        path: client.source.path,
                      ),
                    ),
                    expanded: true,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await _until(
        tester,
        () => find.byType(GitTextPane).evaluate().length == 3,
      );
      await _mapped(tester);
      final controller = _pane(tester, 1).controller!;
      controller.value = const TextEditingValue(
        text: 'Submitted B\n',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.pump();
      await tester.tap(find.text('Apply result and stage resolution'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply and stage'));
      await tester.pump();
      await _until(tester, () => client.mutations.isNotEmpty);
      expect(
        utf8.decode((client.mutations.single as ResolveConflict).bytes!),
        'Submitted B\n',
      );
      controller.value = const TextEditingValue(
        text: 'Newer C\n',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      final newer = controller.value;
      client.mutationCompletion.complete(
        GitOutcome(
          phase: GitOperationPhase.completed,
          snapshot: await client.status(repo),
        ),
      );
      await _until(
        tester,
        () => find
            .text(
              'The submitted result was saved. Your newer result draft is still unsaved.',
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byType(GitConflictView), findsOneWidget);
      expect(controller.value, newer);
      expect(client.mutations, hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(GitConflictView), findsOneWidget);
      expect(controller.value, newer);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'saving updates source tokens without replacing a newer result or its selection',
    (tester) async {
      final client = SlowConflictClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitConflictView(session: session, path: client.source.path),
          ),
        ),
      );
      await _until(
        tester,
        () => find.byType(GitTextPane).evaluate().length == 3,
      );
      final controller = _pane(tester, 1).controller!;
      controller.value = const TextEditingValue(
        text: 'Saved B\n',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.pump();
      await tester.tap(find.text('Save result draft'));
      await tester.pump();
      await _until(tester, () => client.readingSavedContent.isCompleted);
      controller.value = const TextEditingValue(
        text: 'Newer unsaved C\n',
        selection: TextSelection(baseOffset: 2, extentOffset: 9),
        composing: TextRange(start: 2, end: 9),
      );
      final newer = controller.value;
      client.savedContentBarrier!.complete();
      await _until(
        tester,
        () => find
            .text(
              'The submitted result was saved. Your newer result draft is still unsaved.',
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(controller.value, newer);
      expect(client.mutations, hasLength(1));
      expect(
        utf8.decode((client.mutations.single as ResolveConflict).bytes!),
        'Saved B\n',
      );
      expect((client.mutations.single as ResolveConflict).stageResult, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
