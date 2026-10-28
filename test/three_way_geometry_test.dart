import 'dart:async';
import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _ThreeClient extends FixtureClient {
  late final head = [
    for (var line = 0; line < 180; line++) 'common $line prose\n',
  ].join();
  late final index = head.replaceFirst(
    'common 20',
    '${'staged long Markdown paragraph 界 ' * 22}\ncommon 20',
  );
  late final working = index.replaceFirst(
    'common 60',
    '${'unstaged paragraph ' * 35}\ncommon 60',
  );
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repo,
    token: 'review',
    indexToken: 'index',
    head: GitOid('a' * 40),
    changes: [
      GitChange(path: RepoPath.text('note.md'), index: 'M', worktree: 'M'),
    ],
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
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode(switch (version.kind) {
      ContentKind.commit => head,
      ContentKind.indexVersion => index,
      _ => working,
    }),
  );
}

RenderEditable editable(WidgetTester tester, Finder field) {
  RenderEditable? result;
  void visit(RenderObject node) {
    if (node is RenderEditable)
      result = node;
    else if (result == null)
      node.visitChildren(visit);
  }

  visit(tester.renderObject(field));
  return result!;
}

Future<(GitSession, List<TextField>)> mount(
  WidgetTester tester,
  double scale,
  TextDirection direction, {
  Future<TextDiff> Function(String, String)? computeDiff,
}) async {
  tester.view.physicalSize = const Size(2400, 1200);
  tester.view.devicePixelRatio = 1.25;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = GitSession(
    client: _ThreeClient(),
    repository: repo,
    host: host(),
  );
  await session.start();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: GitIndexEditor(
          session: session,
          path: RepoPath.text('note.md'),
          computeDiff: computeDiff,
        ),
      ),
    ),
  );
  for (var step = 0; step < 200; step++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (find
        .byTooltip('Copy HEAD region into index draft')
        .evaluate()
        .isNotEmpty)
      break;
  }
  await tester.pumpAndSettle();
  final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
  expect(fields, hasLength(3));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return (session, fields);
}

void main() {
  testWidgets(
    'optional independent scrolling resumes correspondence from the last scrolled pane',
    (tester) async {
      final (_, fields) = await mount(tester, 1, TextDirection.ltr);
      final chip = find.widgetWithText(FilterChip, 'Synchronize scrolling');
      await tester.tap(chip);
      await tester.pump();
      final work = editable(tester, find.byType(TextField).at(2)),
          text = fields[2].controller!.text,
          anchor = text.indexOf('common 100'),
          before = [
            fields[0].scrollController!.offset,
            fields[1].scrollController!.offset,
          ];
      fields[2].scrollController!.jumpTo(
        fields[2].scrollController!.offset +
            work.getLocalRectForCaret(TextPosition(offset: anchor)).top -
            40,
      );
      await tester.pumpAndSettle();
      expect(fields[0].scrollController!.offset, before[0]);
      expect(fields[1].scrollController!.offset, before[1]);
      final sourceScroll = fields[2].scrollController!.offset;
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(fields[2].scrollController!.offset, sourceScroll);
      final offset = work
              .getPositionForPoint(work.localToGlobal(Offset.zero))
              .offset,
          y = work
              .getLocalRectForCaret(
                TextPosition(
                  offset: work
                      .getPositionForPoint(work.localToGlobal(Offset.zero))
                      .offset,
                ),
              )
              .top;
      for (var pane = 0; pane < 2; pane++) {
        final target = editable(tester, find.byType(TextField).at(pane)),
            targetText = fields[pane].controller!.text;
        expect(
          target
              .getLocalRectForCaret(
                TextPosition(
                  offset: offset + targetText.indexOf('common 100') - anchor,
                ),
              )
              .top,
          closeTo(y, 1),
        );
      }
    },
  );

  testWidgets(
    'new correspondence resumes from the last user pane without moving its draft or viewport',
    (tester) async {
      var delay = false;
      final pending = <(String, String, Completer<TextDiff>)>[];
      final (_, fields) = await mount(
        tester,
        1,
        TextDirection.ltr,
        computeDiff: (a, b) async {
          if (!delay) return computeTextDiff(a, b);
          final completion = Completer<TextDiff>();
          pending.add((a, b, completion));
          return completion.future;
        },
      );
      final oldMap = tester
          .widget<GitRevisionPanes>(find.byType(GitRevisionPanes))
          .mapOffset!;
      delay = true;
      fields[1].controller!.value = TextEditingValue(
        text: 'manual header\n${fields[1].controller!.text}',
        selection: const TextSelection.collapsed(offset: 6),
        composing: const TextRange(start: 0, end: 6),
      );
      expect(
        oldMap(1, 0, 0),
        isNull,
        reason:
            'The old mounted callback must reject the new draft immediately.',
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(pending, hasLength(2));
      final work = editable(tester, find.byType(TextField).at(2));
      final workText = fields[2].controller!.text,
          anchor = workText.indexOf('common 100');
      final previous = [
        fields[0].scrollController!.offset,
        fields[1].scrollController!.offset,
      ];
      fields[2].scrollController!.jumpTo(
        fields[2].scrollController!.offset +
            work.getLocalRectForCaret(TextPosition(offset: anchor)).top -
            40,
      );
      await tester.pumpAndSettle();
      final sourceScroll = fields[2].scrollController!.offset,
          values = [for (final field in fields) field.controller!.value];
      expect(fields[0].scrollController!.offset, previous[0]);
      expect(fields[1].scrollController!.offset, previous[1]);
      for (final request in pending.reversed)
        request.$3.complete(computeTextDiff(request.$1, request.$2));
      await tester.pumpAndSettle();
      expect(
        oldMap(1, 0, 0),
        isNull,
        reason: 'Publishing a new map must never revive an old callback.',
      );
      expect(fields[2].scrollController!.offset, sourceScroll);
      final offset = work
              .getPositionForPoint(work.localToGlobal(Offset.zero))
              .offset,
          y = work
              .getLocalRectForCaret(
                TextPosition(
                  offset: work
                      .getPositionForPoint(work.localToGlobal(Offset.zero))
                      .offset,
                ),
              )
              .top;
      for (var pane = 0; pane < 2; pane++) {
        final target = editable(tester, find.byType(TextField).at(pane)),
            text = fields[pane].controller!.text;
        final expected = offset + text.indexOf('common 100') - anchor;
        expect(
          target.getLocalRectForCaret(TextPosition(offset: expected)).top,
          closeTo(y, 1),
        );
        expect(fields[pane].controller!.value, values[pane]);
      }
    },
  );

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets(
      'adjacent local commands have separate rendered hit bounds at scale=$scale',
      (tester) async {
        tester.view.physicalSize = const Size(800, 650);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController(text: 'a\nb\nc\nd\n');
        var commands = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              textTheme: const TextTheme(
                bodyMedium: TextStyle(fontSize: 14, height: 1),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: GitTextPane(
                label: 'Source',
                controller: controller,
                readOnly: true,
                regionActions: [
                  for (var line = 0; line < 3; line++)
                    GitTextPaneAction(
                      start: line * 2,
                      end: line * 2 + 1,
                      label: 'Region $line',
                      glyph: GitGlyph.next,
                      onInvoke: () => commands++,
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controls = [
          for (var line = 0; line < 3; line++) find.byTooltip('Region $line'),
        ];
        for (var line = 1; line < 3; line++) {
          expect(
            tester.getRect(controls[line - 1]).bottom,
            lessThanOrEqualTo(tester.getRect(controls[line]).top + .1),
          );
        }
        for (final control in controls) {
          final button = find.ancestor(
            of: control,
            matching: find.byType(GitIconButton),
          );
          final icon = find.descendant(
            of: button,
            matching: find.byType(GitIcon),
          );
          final iconBounds = tester.getRect(icon),
              buttonBounds = tester.getRect(control);
          expect(iconBounds.height, greaterThan(0));
          expect(iconBounds.top, greaterThanOrEqualTo(buttonBounds.top));
          expect(iconBounds.bottom, lessThanOrEqualTo(buttonBounds.bottom));
          await tester.tap(control);
        }
        expect(commands, 3);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'narrow role switching retains the full editing value and undo history',
    (tester) async {
      final (_, fields) = await mount(tester, 1, TextDirection.ltr);
      final draft = fields[1].controller!;
      draft.value = const TextEditingValue(
        text: 'manual narrow draft\n',
        selection: TextSelection(baseOffset: 2, extentOffset: 7),
        composing: TextRange(start: 0, end: 6),
      );
      final value = draft.value;
      tester.view.physicalSize = const Size(700, 1100);
      await tester.pump();
      expect(find.byType(GitTextPane), findsOneWidget);
      expect(tester.getSize(find.byType(GitTextPane)).width, greaterThan(500));
      await tester.tap(find.text('HEAD'));
      await tester.pump();
      await tester.tap(find.text(GitMessages.workingTree));
      await tester.pump();
      await tester.tap(find.text('Index'));
      await tester.pump();
      final result = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Editable index content'),
      );
      expect(result.controller, same(draft));
      expect(draft.value, value);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Undo'))
            .onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      expect(draft.value, value);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'three real panes map source anchors through unequal wrapped insertions $direction scale=$scale',
        (tester) async {
          final (_, fields) = await mount(tester, scale, direction);
          final head = editable(tester, find.byType(TextField).at(0));
          expect(
            tester.getCenter(find.byType(TextField).at(0)).dx,
            lessThan(tester.getCenter(find.byType(TextField).at(1)).dx),
          );
          expect(
            tester.getCenter(find.byType(TextField).at(1)).dx,
            lessThan(tester.getCenter(find.byType(TextField).at(2)).dx),
          );
          final source = fields[0].controller!.text,
              index = fields[1].controller!.text,
              working = fields[2].controller!.text;
          final anchor = source.indexOf('common 80'),
              values = [for (final field in fields) field.controller!.value];
          final caret = head.getLocalRectForCaret(TextPosition(offset: anchor));
          fields[0].scrollController!.jumpTo(
            fields[0].scrollController!.offset + caret.top - 40,
          );
          await tester.pumpAndSettle();
          final x = direction == TextDirection.rtl ? head.size.width : 0.0;
          final offset = head
              .getPositionForPoint(head.localToGlobal(Offset(x, 0)))
              .offset;
          final y = head.getLocalRectForCaret(TextPosition(offset: offset)).top;
          final expected = [
            offset,
            offset + index.indexOf('common 80') - anchor,
            offset + working.indexOf('common 80') - anchor,
          ];
          for (var pane = 1; pane < 3; pane++) {
            final target = editable(tester, find.byType(TextField).at(pane));
            expect(
              target
                  .getLocalRectForCaret(TextPosition(offset: expected[pane]))
                  .top,
              closeTo(y, 1.5),
              reason:
                  'Pane $pane expectedOffset=${expected[pane]} actualMap=${tester.widget<GitRevisionPanes>(find.byType(GitRevisionPanes)).mapOffset!(0, pane, offset)} offsets=${fields.map((f) => f.scrollController!.offset).toList()} widths=${[for (var i = 0; i < 3; i++) editable(tester, find.byType(TextField).at(i)).size.width]}',
            );
            expect(fields[pane].controller!.value, values[pane]);
          }
          // Reverse direction through Index and Working must also retain anchors.
          fields[2].scrollController!.jumpTo(
            fields[2].scrollController!.offset + 70,
          );
          await tester.pumpAndSettle();
          final workField = editable(tester, find.byType(TextField).at(2));
          final workX = direction == TextDirection.rtl
              ? workField.size.width
              : 0.0;
          final workOffset = workField
              .getPositionForPoint(workField.localToGlobal(Offset(workX, 0)))
              .offset;
          final sourceOffset =
              workOffset - (working.indexOf('common 80') - anchor);
          expect(
            head.getLocalRectForCaret(TextPosition(offset: sourceOffset)).top,
            closeTo(
              workField
                  .getLocalRectForCaret(TextPosition(offset: workOffset))
                  .top,
              1.5,
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'background region refresh preserves the draft viewport and active composition',
    (tester) async {
      final (_, fields) = await mount(tester, 1, TextDirection.ltr);
      final field = fields[1],
          render = editable(tester, find.byType(TextField).at(1));
      final offset = field.controller!.text.indexOf('common 80');
      field.scrollController!.jumpTo(
        field.scrollController!.offset +
            render.getLocalRectForCaret(TextPosition(offset: offset)).top -
            40,
      );
      await tester.pumpAndSettle();
      final scroll = field.scrollController!.offset;
      final text = field.controller!.text;
      field.controller!.value = TextEditingValue(
        text: text.replaceRange(offset, offset, 'IME '),
        selection: TextSelection.collapsed(offset: offset + 4),
        composing: TextRange(start: offset, end: offset + 3),
      );
      final draft = field.controller!.value;
      await tester.pump(const Duration(milliseconds: 120));
      for (var step = 0; step < 200; step++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
        if (find
            .byTooltip('Copy HEAD region into index draft')
            .evaluate()
            .isNotEmpty)
          break;
      }
      await tester.pumpAndSettle();
      expect(field.controller!.value, draft);
      expect(field.scrollController!.offset, closeTo(scroll, 1));
    },
  );
}
