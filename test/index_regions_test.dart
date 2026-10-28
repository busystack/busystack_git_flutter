import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _IndexClient extends FixtureClient {
  String statusToken = 'review';
  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    final text = switch (version.kind) {
      ContentKind.commit => 'one\nold\nend\n',
      ContentKind.indexVersion => 'one\nstaged\nend\n',
      ContentKind.normalizedWorking => 'one\nstaged\nend\nunstaged\n',
      _ => '',
    };
    return GitContent(
      path: path,
      version: version,
      availability: ContentAvailability.present,
      token: version.kind.name,
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
    head: GitOid('a' * 40),
    changes: [
      GitChange(path: RepoPath.text('note.md'), index: 'M', worktree: 'M'),
    ],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
}

void main() {
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
