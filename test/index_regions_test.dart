import 'dart:async';
import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _IndexClient extends FixtureClient {
  String statusToken = 'review';
  String indexText = 'one\nstaged\nend\n';
  String workingText = 'one\nstaged\nend\nunstaged\n';
  GitOid head = GitOid('a' * 40);
  String? branch;
  RepositoryOperation operation = const RepositoryOperation(
    GitOperationKind.none,
  );
  Completer<void>? contentGate;
  int contentReads = 0;
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    contentReads++;
    final gate = contentGate;
    if (gate != null) await gate.future;
    final text = switch (version.kind) {
      ContentKind.commit => 'one\nold\nend\n',
      ContentKind.indexVersion => indexText,
      ContentKind.normalizedWorking => workingText,
      _ => '',
    };
    return GitContent(
      path: path,
      version: version,
      availability: ContentAvailability.present,
      token: '${version.kind.name}:$text',
      mode: '100644',
      bytes: utf8.encode(text),
    );
  }

  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    token: statusToken,
    indexToken: 'index',
    head: head,
    branch: branch,
    changes: [
      GitChange(path: RepoPath.text('note.md'), index: 'M', worktree: 'M'),
    ],
    operation: operation,
    observedAt: DateTime.utc(2026),
  );
}

Future<(GitSession, TextEditingController)> _mountIndex(
  WidgetTester tester, {
  Future<TextDiff> Function(String, String)? computeDiff,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(
    client: _IndexClient(),
    repository: repo,
    host: host(),
  );
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GitHostScope(
          host: session.host,
          child: GitIndexEditor(
            session: session,
            path: RepoPath.text('note.md'),
            computeDiff: computeDiff ?? (a, b) async => computeTextDiff(a, b),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final field = tester.widget<TextField>(
    find.widgetWithText(TextField, 'Editable index content'),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return (session, field.controller!);
}

VoidCallback _unstageCallback(WidgetTester tester) => tester
    .widget<TextButton>(find.widgetWithText(TextButton, 'Unstage this hunk'))
    .onPressed!;

RenderEditable _fieldRender(WidgetTester tester, int index) {
  RenderEditable? field;
  void visit(RenderObject node) {
    if (node is RenderEditable)
      field = node;
    else if (field == null)
      node.visitChildren(visit);
  }

  visit(tester.renderObject(find.byType(TextField).at(index)));
  return field!;
}

VoidCallback _localAction(WidgetTester tester, String label) => tester
    .widget<GitIconButton>(
      find.ancestor(
        of: find.byTooltip(label),
        matching: find.byType(GitIconButton),
      ),
    )
    .onPressed!;

void main() {
  testWidgets(
    'local source controls are beside the real region and rapid old actions cannot repeat',
    (tester) async {
      final (_, draft) = await _mountIndex(tester);
      await tester.pump();
      final button = find.byTooltip('Copy HEAD region into index draft');
      final rect = tester.getRect(button),
          field = tester.getRect(find.byType(TextField).at(0));
      final source = _fieldRender(tester, 0);
      final caret = source.getLocalRectForCaret(const TextPosition(offset: 4));
      expect(rect.right, lessThanOrEqualTo(field.left));
      expect(rect.top, closeTo(source.localToGlobal(caret.topLeft).dy, 1));
      final old = _localAction(tester, 'Copy HEAD region into index draft');
      await tester.tap(button);
      old(); // Deliberately before a frame or the region debounce.
      expect(draft.text, 'one\nold\nend\n');
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      old();
      expect(draft.text, 'one\nold\nend\n');
    },
  );

  testWidgets(
    'local working transfer edits only the draft and cannot append twice',
    (tester) async {
      final (session, draft) = await _mountIndex(tester);
      await tester.pump();
      final old = _localAction(tester, 'Copy working region into index draft');
      await tester.tap(find.byTooltip('Copy working region into index draft'));
      old();
      expect(draft.text, 'one\nstaged\nend\nunstaged\n');
      expect((session.client as _IndexClient).mutations, isEmpty);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
    },
  );

  testWidgets(
    'Git keyboard transfer preserves unrelated selection and composing offsets',
    (tester) async {
      final (_, draft) = await _mountIndex(tester);
      draft.value = const TextEditingValue(
        text: 'one\nstaged\nend\ncomposing\n',
        selection: TextSelection.collapsed(offset: 20),
        composing: TextRange(start: 15, end: 24),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      final input = find.widgetWithText(TextField, 'Editable index content');
      await tester.showKeyboard(input);
      // Native focus acquisition can commit composition; set the exact queued
      // editing value after focus to verify the region command's own behavior.
      draft.value = const TextEditingValue(
        text: 'one\nstaged\nend\ncomposing\n',
        selection: TextSelection.collapsed(offset: 20),
        composing: TextRange(start: 15, end: 24),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(draft.text, 'one\nold\nend\ncomposing\n');
      expect(draft.selection, const TextSelection.collapsed(offset: 17));
      expect(draft.value.composing, const TextRange(start: 12, end: 21));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
    },
  );

  testWidgets('successful Apply of B keeps newer queued draft C recoverable', (
    tester,
  ) async {
    final (session, draft) = await _mountIndex(tester);
    final client = session.client as _IndexClient;
    client.pending = Completer<GitOutcome>();
    draft.text = 'submitted B\n';
    await tester.pump();
    final apply = tester
        .widget<FilledButton>(
          find.widgetWithText(
            FilledButton,
            'Write edited result to this index entry',
          ),
        )
        .onPressed!;
    apply();
    draft.value = const TextEditingValue(
      text: 'queued C\n',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );
    final newer = draft.value;
    await tester.pump();
    expect(
      (client.mutations.single as WriteIndex).bytes,
      utf8.encode('submitted B\n'),
    );
    client.indexText = 'submitted B\n';
    client.statusToken = 'after-B';
    client.pending!.complete(
      GitOutcome(
        phase: GitOperationPhase.completed,
        snapshot: await client.status(repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GitIndexEditor), findsOneWidget);
    expect(draft.value, newer);
    expect(
      find.textContaining('The submitted draft was written to the index.'),
      findsOneWidget,
    );
    expect(client.mutations, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(
              FilledButton,
              'Write edited result to this index entry',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Undo'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Review saved index and keep draft'));
    await tester.pumpAndSettle();
    expect(draft.value, newer);
    // Finish the retained input-method transaction before testing normal
    // undo/redo; canceling an active composition is a distinct native action.
    draft.value = draft.value.copyWith(composing: TextRange.empty);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await tester.pump();
    expect(draft.text, 'submitted B\n');
    await tester.tap(find.widgetWithText(TextButton, 'Redo'));
    await tester.pump();
    expect(draft.text, 'queued C\n');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
  });

  for (final external in [
    'none',
    'index',
    'head',
    'branch',
    'operation',
    'working',
    'typing',
    'switch',
  ]) {
    testWidgets(
      'explicit saved-index review preserves draft with $external changes',
      (tester) async {
        final (session, draft) = await _mountIndex(tester);
        final client = session.client as _IndexClient;
        client.pending = Completer<GitOutcome>();
        draft.text = 'submitted B\n';
        await tester.pump();
        await tester.tap(find.text('Write edited result to this index entry'));
        draft.value = const TextEditingValue(
          text: 'queued C\n',
          selection: TextSelection(baseOffset: 2, extentOffset: 7),
          composing: TextRange(start: 0, end: 6),
        );
        final kept = draft.value;
        client.indexText = 'submitted B\n';
        client.statusToken = 'after-B';
        client.pending!.complete(
          GitOutcome(
            phase: GitOperationPhase.completed,
            snapshot: await client.status(repo),
          ),
        );
        await tester.pumpAndSettle();
        final review = tester
            .widget<TextButton>(
              find.widgetWithText(
                TextButton,
                'Review saved index and keep draft',
              ),
            )
            .onPressed!;
        switch (external) {
          case 'index':
            client.indexText = 'external E\n';
          case 'head':
            client.head = GitOid('b' * 40);
          case 'branch':
            client.branch = 'other';
          case 'operation':
            client.operation = const RepositoryOperation(
              GitOperationKind.merge,
            );
          case 'working':
            client.workingText = 'changed working\n';
        }
        if (external == 'typing' || external == 'switch')
          client.contentGate = Completer<void>();
        review();
        await tester.pump();
        if (external == 'typing') {
          draft.value = const TextEditingValue(
            text: 'newer D during read\n',
            selection: TextSelection.collapsed(offset: 9),
            composing: TextRange(start: 0, end: 5),
          );
        } else if (external == 'switch') {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: GitHostScope(
                  host: session.host,
                  child: GitIndexEditor(
                    session: session,
                    path: RepoPath.text('other.md'),
                    computeDiff: (a, b) async => computeTextDiff(a, b),
                  ),
                ),
              ),
            ),
          );
        }
        client.contentGate?.complete();
        await tester.pumpAndSettle();
        final expected = external == 'typing'
            ? const TextEditingValue(
                text: 'newer D during read\n',
                selection: TextSelection.collapsed(offset: 9),
                composing: TextRange(start: 0, end: 5),
              )
            : kept;
        expect(draft.value, expected);
        expect(client.mutations, hasLength(1));
        final apply = tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Write edited result to this index entry',
              ),
            )
            .onPressed;
        if (external == 'none' || external == 'typing') {
          expect(apply, isNotNull);
          expect(find.text('Review saved index and keep draft'), findsNothing);
          // A callback captured before consumption cannot rebind another review.
          final reads = client.contentReads;
          review();
          await tester.pump();
          expect(client.contentReads, reads);
          expect(draft.value, expected);
          client.pending = null;
          apply!();
          await tester.pump();
          await tester.pump();
          expect(session.running, isFalse);
          expect(session.outcome?.completed, isTrue);
          expect(client.mutations, hasLength(2));
          expect(
            (client.mutations.last as WriteIndex).bytes,
            utf8.encode(expected.text),
          );
        } else {
          expect(apply, isNull);
        }
        await tester.pump(const Duration(milliseconds: 120));
      },
    );
  }

  testWidgets('discard consent cannot discard a newer queued draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = GitSession(
      client: _IndexClient(),
      repository: repo,
      host: host(),
    );
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => session.host.present<void>(
                context,
                'Index',
                GitIndexEditor(
                  session: session,
                  path: RepoPath.text('note.md'),
                  computeDiff: (a, b) async => computeTextDiff(a, b),
                ),
                expanded: true,
              ),
              child: const Text('Open index'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open index'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(
          find.widgetWithText(TextField, 'Editable index content'),
        )
        .controller!;
    controller.text = 'draft before confirmation\n';
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    controller.value = const TextEditingValue(
      text: 'queued newer draft\n',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 0, end: 6),
    );
    final newer = controller.value;
    await tester.tap(find.text('Discard index draft'));
    await tester.pumpAndSettle();
    expect(find.byType(GitIndexEditor), findsOneWidget);
    expect(controller.value, newer);
    expect((session.client as _IndexClient).mutations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'a dirty draft remains bound to its loaded path after widget replacement',
    (tester) async {
      final (session, draft) = await _mountIndex(tester);
      final oldAction = _unstageCallback(tester);
      draft.value = const TextEditingValue(
        text: 'manual draft\n',
        selection: TextSelection(baseOffset: 2, extentOffset: 7),
      );
      final value = draft.value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitHostScope(
              host: session.host,
              child: GitIndexEditor(
                session: session,
                path: RepoPath.text('different.md'),
                computeDiff: (a, b) async => computeTextDiff(a, b),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      oldAction();
      expect(draft.value, value);
      expect(find.textContaining('/fixture/repo · note.md'), findsOneWidget);
      expect(find.textContaining('/fixture/repo · different.md'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Write edited result to this index entry',
              ),
            )
            .onPressed,
        isNull,
      );
      expect((session.client as _IndexClient).mutations, isEmpty);
    },
  );

  testWidgets('old Unstage callbacks cannot apply twice before debounce', (
    tester,
  ) async {
    final (_, draft) = await _mountIndex(tester);
    final unstage = _unstageCallback(tester);
    unstage();
    expect(draft.text, 'one\nold\nend\n');
    unstage(); // Deliberately no pump or elapsed debounce.
    expect(draft.text, 'one\nold\nend\n');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    unstage(); // Nor may the old callback revive after a new calculation.
    expect(draft.text, 'one\nold\nend\n');
  });

  testWidgets('typing and undo redo invalidate even identical old text', (
    tester,
  ) async {
    final (_, draft) = await _mountIndex(tester);
    final unstage = _unstageCallback(tester), before = draft.value;
    draft.value = const TextEditingValue(
      text: 'typed\none\nstaged\nend\n',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    final typed = draft.value;
    unstage();
    expect(draft.value, typed);
    // The controller value notifications are exactly those generated by undo/
    // redo; returning to identical text must still invalidate the old identity.
    draft.value = before;
    unstage();
    expect(draft.value, before);
    draft.value = typed;
    unstage();
    expect(draft.value, typed);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
  });

  testWidgets('actual Undo and Redo reject captured region callbacks', (
    tester,
  ) async {
    final (_, draft) = await _mountIndex(tester);
    final oldAction = _unstageCallback(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Editable index content'),
      'typed\none\nstaged\nend\n',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    final undone = draft.value;
    expect(undone.text, 'one\nstaged\nend\n');
    oldAction();
    expect(draft.value, undone);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Redo'));
    final redone = draft.value;
    expect(redone.text, 'typed\none\nstaged\nend\n');
    oldAction();
    expect(draft.value, redone);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
  });

  testWidgets('obsolete calculations cannot publish or clear newer loading', (
    tester,
  ) async {
    final pending = <(String, String, Completer<TextDiff>)>[];
    final (_, draft) = await _mountIndex(
      tester,
      computeDiff: (a, b) {
        final completion = Completer<TextDiff>();
        pending.add((a, b, completion));
        return completion.future;
      },
    );
    expect(pending, hasLength(2));
    draft.text = 'first\n';
    await tester.pump(const Duration(milliseconds: 120));
    expect(pending, hasLength(4));
    draft.text = 'newest\n';
    await tester.pump(const Duration(milliseconds: 120));
    expect(pending, hasLength(6));
    for (final request in pending.take(4).toList().reversed) {
      request.$3.complete(computeTextDiff(request.$1, request.$2));
    }
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Unstage this hunk'),
          )
          .onPressed,
      isNull,
    );
    expect(draft.text, 'newest\n');
    for (final request in pending.skip(4)) {
      request.$3.complete(computeTextDiff(request.$1, request.$2));
    }
    await tester.pump();
    expect(draft.text, 'newest\n');
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Unstage this hunk'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('closing during calculation ignores all late completions', (
    tester,
  ) async {
    final pending = <(String, String, Completer<TextDiff>)>[];
    await _mountIndex(
      tester,
      computeDiff: (a, b) {
        final completion = Completer<TextDiff>();
        pending.add((a, b, completion));
        return completion.future;
      },
    );
    await tester.pumpWidget(const SizedBox());
    for (final request in pending) {
      request.$3.complete(computeTextDiff(request.$1, request.$2));
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('index regions distinguish staged and unstaged transfer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _IndexClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHostScope(
            host: session.host,
            child: GitIndexEditor(
              session: session,
              path: RepoPath.text('note.md'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Staged (1)'), findsOneWidget);
    expect(find.text('Unstaged (1)'), findsOneWidget);
    final index = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Editable index content'),
    );
    expect(index.controller!.text, 'one\nstaged\nend\n');
    final span = (index.controller! as GitHighlightedTextController)
        .buildTextSpan(
          context: tester.element(find.byType(GitIndexEditor)),
          withComposing: false,
        );
    expect(
      span.children!.whereType<TextSpan>().any(
        (part) =>
            part.text!.contains('staged') &&
            part.style?.backgroundColor != null,
      ),
      isTrue,
    );
    await tester.tap(find.text('Unstage this hunk'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await tester.pumpAndSettle();
    expect(index.controller!.text, 'one\nold\nend\n');
    expect(
      client.mutations,
      isEmpty,
      reason: 'Region transfer edits only the draft.',
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('closing a dirty index draft requires a deliberate decision', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _IndexClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => session.host.present<void>(
                context,
                'Index',
                GitIndexEditor(
                  session: session,
                  path: RepoPath.text('note.md'),
                ),
                expanded: true,
              ),
              child: const Text('Open index'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open index'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'Editable index content');
    await tester.enterText(input, 'manual draft\n');
    await tester.pump();
    expect(find.text('Dirty'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Closing the index editor discards only its draft'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'Editable index content'),
      findsOneWidget,
    );
    expect(client.mutations, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard index draft'));
    await tester.pumpAndSettle();
    expect(find.byType(GitIndexEditor), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('external repository change leaves the index draft reviewable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _IndexClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHostScope(
            host: session.host,
            child: GitIndexEditor(
              session: session,
              path: RepoPath.text('note.md'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'Editable index content');
    await tester.enterText(input, 'manual draft\n');
    await tester.pump();
    client.statusToken = 'external-change';
    await session.refresh();
    await tester.pump();
    expect(
      find.textContaining('The reviewed index or working content changed'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(input).controller!.text, 'manual draft\n');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(
              FilledButton,
              'Write edited result to this index entry',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(client.mutations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
