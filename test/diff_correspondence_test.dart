import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _CorrespondenceClient extends FixtureClient {
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    final before = version.kind == ContentKind.indexVersion;
    final text = [
      for (var line = 0; line < 180; line++) ...[
        if (before && line == 30)
          for (var extra = 0; extra < 15; extra++)
            'deleted $extra ${'old wrapped paragraph ' * 8}',
        if (!before && line == 100)
          for (var extra = 0; extra < 10; extra++)
            'inserted $extra ${'new wrapped paragraph ' * 4}',
        'shared anchor $line ${'Markdown prose ' * (line % 4 + 1)}',
      ],
    ].join('\n');
    return GitContent(
      path: path,
      version: version,
      availability: ContentAvailability.present,
      token: version.label,
      mode: '100644',
      bytes: utf8.encode(text),
    );
  }
}

void main() {
  testWidgets(
    'aligned rendered rows retain correspondence across one-sided changes and relayout',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = GitSession(
        client: _CorrespondenceClient(),
        repository: repo,
        host: host(),
      );
      await session.start();
      session.setViewState('diffCollapse', false);
      var scale = 1.0;
      final comparison = GitComparison(
        RepoPath.text('paragraphs.md'),
        const ContentVersion.index(),
        const ContentVersion.working(),
      );
      late StateSetter relayout;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              relayout = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: GitDiffView(session: session, comparison: comparison),
                ),
              );
            },
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      void verifyPairs() {
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
            .where((text) => text.startsWith('shared anchor '))
            .toSet();
        expect(texts, isNotEmpty);
        for (final text in texts) {
          final pairs = find.text(text);
          expect(pairs, findsNWidgets(2));
          expect(
            tester.getTopLeft(pairs.at(0)).dy,
            closeTo(tester.getTopLeft(pairs.at(1)).dy, .1),
          );
        }
      }

      Future<void> reveal(String anchor) async {
        final target = find.textContaining(anchor);
        for (var step = 0; step < 50 && target.evaluate().isEmpty; step++) {
          await tester.drag(find.byType(ListView), const Offset(0, -250));
          await tester.pumpAndSettle();
        }
        expect(target, findsNWidgets(2));
        await tester.ensureVisible(target.at(0));
        await tester.pumpAndSettle();
      }

      verifyPairs();
      await tester.tap(find.byTooltip('Next difference'));
      await tester.pumpAndSettle();
      await reveal('shared anchor 30 ');
      await tester.pumpAndSettle();
      verifyPairs();
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      verifyPairs();
      await tester.tap(find.byTooltip('Next difference'));
      await tester.pumpAndSettle();
      await reveal('shared anchor 100 ');
      await tester.pumpAndSettle();
      verifyPairs();
      tester.view.physicalSize = const Size(720, 850);
      relayout(() => scale = 1.6);
      await tester.pumpAndSettle();
      await reveal('shared anchor 100 ');
      verifyPairs();
      expect(
        tester.widgetList<Text>(find.byType(Text)).length,
        lessThan(180),
        reason: 'Correspondence must retain bounded row rendering.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
