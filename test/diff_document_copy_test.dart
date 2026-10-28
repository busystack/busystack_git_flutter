import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _CopyClient extends FixtureClient {
  _CopyClient({this.crlf = false, this.tail = ''});
  final bool crlf;
  final String tail;
  static final contextLine =
      'shared ${'long Markdown 界 paragraph ' * 12}middle';
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
      ((version.kind == ContentKind.indexVersion
                  ? 'LEFT ONE\nshared middle\n\nLEFT THREE\nLEFT FOUR'
                  : 'RIGHT ONE\nshared middle\nRIGHT ONLY\nRIGHT THREE\nRIGHT FOUR') +
              tail)
          .replaceAll('shared middle', contextLine)
          .replaceAll('\n', crlf ? '\r\n' : '\n'),
    ),
  );
}

void main() {
  for (final right in [false, true]) {
    testWidgets(
      'copy full ${right ? 'right' : 'left'} source without building its tail',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tail = '\n${List.generate(1000, (i) => 'tail $i 界').join('\n')}';
        final client = _CopyClient(crlf: true, tail: tail);
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        session.setViewState('diffWrap', false);
        session.setViewState('diffCollapse', false);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GitDiffView(
                session: session,
                comparison: GitComparison(
                  RepoPath.text('prose.md'),
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
        expect(find.text('tail 999 界'), findsNothing);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final first = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(right ? 'RIGHT ONE' : 'LEFT ONE'),
            matching: find.byType(RichText),
          ),
        );
        final origin = first.localToGlobal(const Offset(1, 6));
        final mouse = await tester.startGesture(
          origin,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(origin + const Offset(30, 0));
        await mouse.up();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          copied,
          (right
                  ? 'RIGHT ONE\nshared middle\nRIGHT ONLY\nRIGHT THREE\nRIGHT FOUR$tail'
                  : 'LEFT ONE\nshared middle\n\nLEFT THREE\nLEFT FOUR$tail')
              .replaceAll('shared middle', _CopyClient.contextLine)
              .replaceAll('\n', '\r\n'),
        );
        expect(find.text('tail 999 界'), findsNothing);
        expect(find.textContaining('0 changed lines selected'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
  final cases = [
    for (final wrap in [true, false])
      for (final right in [false, true])
        for (final reverse in [false, true])
          for (final crlf in [false, true])
            (
              wrap: wrap,
              right: right,
              reverse: reverse,
              crlf: crlf,
              rtl: false,
            ),
    (wrap: true, right: true, reverse: false, crlf: true, rtl: true),
  ];
  for (final scenario in cases) {
    final wrap = scenario.wrap, right = scenario.right;
    testWidgets(
      'document copy ${right ? 'right' : 'left'} wrap=$wrap reverse=${scenario.reverse} crlf=${scenario.crlf} rtl=${scenario.rtl}',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = GitSession(
          client: _CopyClient(crlf: scenario.crlf),
          repository: repo,
          host: host(),
        );
        await session.start();
        session.setViewState('diffWrap', wrap);
        session.setViewState('diffCollapse', false);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Directionality(
              textDirection: scenario.rtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child!,
            ),
            home: Scaffold(
              body: GitDiffView(
                session: session,
                comparison: GitComparison(
                  RepoPath.text('prose.md'),
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
        RenderParagraph paragraph(String text) =>
            tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(text),
                matching: find.byType(RichText),
              ),
            );
        final first = paragraph(right ? 'RIGHT ONE' : 'LEFT ONE'),
            last = paragraph(right ? 'RIGHT THREE' : 'LEFT THREE');
        final origin = first.localToGlobal(
          first.getOffsetForCaret(const TextPosition(offset: 0), Rect.zero) +
              Offset(.1, first.size.height / 2),
        );
        final target = last.localToGlobal(
          last.getOffsetForCaret(
                TextPosition(offset: last.text.toPlainText().length),
                Rect.zero,
              ) +
              Offset(1, last.size.height / 2),
        );
        final mouse = await tester.startGesture(
          scenario.reverse ? target : origin,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(scenario.reverse ? origin : target);
        await mouse.up();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          copied,
          (right
                  ? 'RIGHT ONE\nshared middle\nRIGHT ONLY\nRIGHT THREE'
                  : 'LEFT ONE\nshared middle\n\nLEFT THREE')
              .replaceAll('shared middle', _CopyClient.contextLine)
              .replaceAll('\n', scenario.crlf ? '\r\n' : '\n'),
        );
        if (wrap) {
          expect(
            tester.getSize(find.text(_CopyClient.contextLine).first).height,
            greaterThan(first.size.height * 2),
          );
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          copied,
          (right
                  ? 'RIGHT ONE\nshared middle\nRIGHT ONLY\nRIGHT THREE\nRIGHT FOUR'
                  : 'LEFT ONE\nshared middle\n\nLEFT THREE\nLEFT FOUR')
              .replaceAll('shared middle', _CopyClient.contextLine)
              .replaceAll('\n', scenario.crlf ? '\r\n' : '\n'),
        );
        expect(find.textContaining('0 changed lines selected'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
