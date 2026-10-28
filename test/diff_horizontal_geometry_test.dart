import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _LongLineClient extends FixtureClient {
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
          ? 'LEFT_START ${'long Markdown paragraph 界 ' * 30} LEFT_END\n'
          : 'RIGHT_START ${'different paragraph ' * 45} RIGHT_END\n',
    ),
  );
}

void main() {
  for (final width in [800.0, 1400.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final wrap in [false, true]) {
        testWidgets('pane geometry width=$width scale=$scale wrap=$wrap', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final session = GitSession(
            client: _LongLineClient(),
            repository: repo,
            host: host(),
          );
          await session.start();
          session.setViewState('diffWrap', wrap);
          session.setViewState('diffCollapse', false);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
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
            () async => Future<void>.delayed(const Duration(milliseconds: 120)),
          );
          await tester.pumpAndSettle();
          final leftText = find.textContaining('LEFT_START'),
              rightText = find.textContaining('RIGHT_START');
          expect(leftText, findsOneWidget);
          expect(rightText, findsOneWidget);
          final leftBar = find.byKey(
            const ValueKey('git-diff-left-horizontal'),
          );
          final rightBar = find.byKey(
            const ValueKey('git-diff-right-horizontal'),
          );
          if (wrap) {
            expect(leftBar, findsNothing);
            final left = tester.getRect(leftText),
                right = tester.getRect(rightText);
            expect(left.left, greaterThanOrEqualTo(0));
            expect(left.right, lessThan(right.left));
            expect(right.right, lessThanOrEqualTo(width));
          } else {
            final leftViewport = tester.getRect(leftBar),
                rightViewport = tester.getRect(rightBar);
            expect(leftViewport.left, greaterThanOrEqualTo(0));
            expect(leftViewport.right, lessThan(rightViewport.left));
            expect(rightViewport.right, lessThanOrEqualTo(width));
            final divider = find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(VerticalDivider),
                )
                .first;
            final dividerBefore = tester.getRect(divider);
            expect(dividerBefore.center.dx, closeTo(width / 2, 2));
            final leftBefore = tester.getTopLeft(leftText),
                rightBefore = tester.getTopLeft(rightText);
            ScrollController controller(Finder bar) => tester
                .widget<SingleChildScrollView>(
                  find.descendant(
                    of: bar,
                    matching: find.byType(SingleChildScrollView),
                  ),
                )
                .controller!;
            final leftScroll = controller(leftBar),
                rightScroll = controller(rightBar);
            leftScroll.jumpTo(leftScroll.position.maxScrollExtent);
            await tester.pump();
            expect(tester.getTopLeft(leftText).dx, lessThan(leftBefore.dx));
            expect(tester.getTopLeft(rightText), rightBefore);
            expect(tester.getRect(divider), dividerBefore);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: leftText, matching: find.byType(RichText)),
            );
            final length = paragraph.text.toPlainText().length;
            final endBox = paragraph
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: length - 8,
                    extentOffset: length - 1,
                  ),
                )
                .last
                .toRect();
            final end = paragraph.localToGlobal(endBox.center);
            expect(
              end.dx,
              inInclusiveRange(leftViewport.left, leftViewport.right),
            );
            rightScroll.jumpTo(rightScroll.position.maxScrollExtent);
            await tester.pump();
            expect(tester.getTopLeft(rightText).dx, lessThan(rightBefore.dx));
            expect(tester.getRect(divider), dividerBefore);
            expect(tester.getRect(leftBar), leftViewport);
            expect(tester.getRect(rightBar), rightViewport);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          session.dispose();
        });
      }
    }
  }
}
