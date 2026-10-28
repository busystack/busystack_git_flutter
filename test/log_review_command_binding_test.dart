import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _Client extends FixtureClient {
  _Client(String id) {
    historyCommits = [
      GitCommit(
        oid: GitOid(id * 40),
        parents: const [],
        subject: 'Reviewed commit $id',
        author: 'Fixture',
        email: 'fixture@example.invalid',
        date: DateTime.utc(2026),
        message: 'Reviewed commit $id',
      ),
    ];
  }
}

Future<(ValueNotifier<GitSession>, GitSession, List<String>)> _mount(
  WidgetTester tester, {
  Completer<String?>? menu,
  Completer<String?>? input,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final testHost = GitHost(
    present: <T>(context, title, child, {bool expanded = false}) async =>
        input == null ? null : await input.future as T?,
    presentMenu: (_, entries, {position}) => menu?.future ?? Future.value(),
    openDocument: (_, _, {snapshot}) async {},
    prepareMutation: (_, _) async => true,
    chooseDirectory: (_) async => null,
    notify: (_) {},
    drafts: MemoryGitDraftStore(),
  );
  final first = GitSession(
    client: _Client('a'),
    repository: repo,
    host: testHost,
  );
  final second = GitSession(
    client: _Client('b'),
    repository: const RepositoryId(
      root: '/fixture/other',
      gitDir: '/fixture/other/.git',
      commonDir: '/fixture/other/.git',
      objectFormat: 'sha1',
    ),
    host: testHost,
  );
  await first.start();
  await second.start();
  final selected = ValueNotifier(first);
  final dispatched = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<GitSession>(
          valueListenable: selected,
          builder: (_, session, _) => GitLogView(
            session: session,
            onCommitAction: (commit, action) =>
                dispatched.add('${session.repository.root}:${commit.oid}'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
    first.dispose();
    second.dispose();
  });
  return (selected, second, dispatched);
}

void main() {
  for (final replaceSession in [true, false]) {
    testWidgets(
      'pending commit menu cannot cross ${replaceSession ? 'repository' : 'history'} review',
      (tester) async {
        final menu = Completer<String?>();
        final (selected, second, dispatched) = await _mount(tester, menu: menu);
        await tester.tap(find.text('Commit actions…'));
        await tester.pump();
        if (replaceSession) {
          selected.value = second;
        } else {
          await tester.tap(find.byTooltip('Refresh Log'));
        }
        await tester.pumpAndSettle();
        menu.complete(GitMessages.createBranch2);
        await tester.pumpAndSettle();
        expect(dispatched, isEmpty);
        expect((selected.value.client as FixtureClient).mutations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('pending Go to input cannot navigate a replacement repository', (
    tester,
  ) async {
    final input = Completer<String?>();
    final (selected, second, _) = await _mount(tester, input: input);
    await tester.tap(find.text('Go to commit/reference…'));
    await tester.pump();
    selected.value = second;
    await tester.pumpAndSettle();
    final client = second.client as FixtureClient;
    final reads = client.historyFilters.length;
    input.complete('reviewed-only-in-first-repository');
    await tester.pumpAndSettle();
    expect(client.historyFilters.length, reads);
    expect(
      client.historyFilters.any(
        (f) => f.reference == 'reviewed-only-in-first-repository',
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
