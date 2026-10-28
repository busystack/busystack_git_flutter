import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _WrappedClient extends FixtureClient {
  late final before = [
    for (var i = 0; i < 160; i++)
      i == 20
          ? 'early-old line'
          : i == 140
          ? 'target-old line'
          : 'paragraph $i ${'long prose ' * 16}',
  ].join('\n');
  late final after = [
    for (var i = 0; i < 160; i++)
      i == 20
          ? 'early-new line'
          : i == 140
          ? 'target-new line'
          : 'paragraph $i ${'long prose ' * 16}',
  ].join('\n');

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
    token: version.kind.name,
    mode: '100644',
    bytes: utf8.encode(
      version.kind == ContentKind.indexVersion ? before : after,
    ),
  );
}

void main() {
  for (final collapsed in [false, true]) {
    testWidgets(
      'unbuilt navigation survives scaled relayout collapse=$collapsed',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = _WrappedClient();
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        session.setViewState('diffCollapse', collapsed);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
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
        expect(find.textContaining('target-new line'), findsNothing);
        await tester.tap(find.byTooltip('Next difference'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next difference'));
        // Relayout while the request is seeking a row outside the built viewport.
        tester.view.physicalSize = const Size(720, 850);
        await tester.pumpAndSettle();
        final target = find.textContaining('target-new line');
        expect(target, findsOneWidget);
        final box = tester.getRect(target),
            viewport = tester.getRect(find.byType(ListView));
        expect(box.top, greaterThanOrEqualTo(viewport.top));
        expect(box.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(
          tester.widgetList(find.byType(Text)).length,
          lessThan(160),
          reason: 'Navigation must retain bounded virtual row rendering.',
        );
        await tester.tap(find.byTooltip('Previous difference'));
        await tester.pumpAndSettle();
        expect(find.textContaining('early-new line'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets('difference navigation reveals the rendered wrapped region', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _WrappedClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    session.setViewState('diffCollapse', false);
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
      () async => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('target-new line'), findsNothing);
    await tester.tap(find.byTooltip('Next difference'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next difference'));
    await tester.pumpAndSettle();
    expect(find.textContaining('target-new line'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
