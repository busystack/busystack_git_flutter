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
