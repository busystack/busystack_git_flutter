import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

GitOid _oid(int n) => GitOid(n.toRadixString(16).padLeft(40, '0'));
GitCommit _commit(int n, List<GitOid> parents) => GitCommit(
  oid: _oid(n),
  parents: parents,
  subject: 'Commit $n',
  author: 'Fixture',
  email: 'fixture@example.invalid',
  date: DateTime.utc(2026),
  message: 'Commit $n',
);

Future<ByteData> _pixels(WidgetTester tester, Finder finder) async {
  final painter = tester.widget<CustomPaint>(finder).painter!;
  final size = tester.getSize(finder);
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return data!;
  }))!;
}

final class _PagedGraphClient extends FixtureClient {
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) async => HistoryPage(
    offset == 0
        ? [
            _commit(1, [for (var i = 2; i < 15; i++) _oid(i)]),
          ]
        : [for (var i = 2; i < 15; i++) _commit(i, [])],
    nextOffset: offset == 0 ? 1 : 14,
    hasMore: offset == 0,
    anchor: 'graph-page',
  );
}

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('rendered graph has 13 distinct lanes at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient()
        ..historyCommits = [
          _commit(1, [for (var i = 2; i < 15; i++) _oid(i)]),
          for (var i = 2; i < 15; i++) _commit(i, []),
        ];
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: GitLogView(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byKey(ValueKey('git-graph-${_oid(1).value}'));
      final second = find.byKey(ValueKey('git-graph-${_oid(2).value}'));
      expect(tester.getRect(first).left, tester.getRect(second).left);
      expect(tester.getSize(first).width, tester.getSize(second).width);
      final pixels = await _pixels(tester, first);
      final width = tester.getSize(first).width.ceil();
      final height = tester.getSize(first).height.ceil();
      final occupied = <int>[];
      for (var x = 0; x < width; x++) {
        if (pixels.getUint8(((height - 1) * width + x) * 4 + 3) > 0)
          occupied.add(x);
      }
      final clusters = <List<int>>[];
      for (final x in occupied) {
        if (clusters.isEmpty || x > clusters.last.last + 1) clusters.add([]);
        clusters.last.add(x);
      }
      expect(clusters, hasLength(13));
      for (var lane = 0; lane < 13; lane++) {
        final center =
            clusters[lane].reduce((a, b) => a + b) / clusters[lane].length;
        expect(center, closeTo(10 + lane * 14, 2));
      }
      await tester.tap(find.text('Commit 2'));
      await tester.pumpAndSettle();
      expect(tester.getRect(first).left, tester.getRect(second).left);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }

  testWidgets('rendered page boundary resolves without shifting lane columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = GitSession(
      client: _PagedGraphClient(),
      repository: repo,
      host: host(),
    );
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GitLogView(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(ValueKey('git-graph-${_oid(1).value}'));
    final bounds = tester.getRect(first);
    final unloaded = await _pixels(tester, first);
    await tester.tap(find.text('Load more commits'));
    await tester.pumpAndSettle();
    expect(tester.getRect(first), bounds);
    expect(
      tester.getRect(find.byKey(ValueKey('git-graph-${_oid(2).value}'))).left,
      bounds.left,
    );
    final loaded = await _pixels(tester, first);
    expect(
      loaded.buffer.asUint8List(),
      isNot(orderedEquals(unloaded.buffer.asUint8List())),
      reason:
          'Unloaded-parent markers must disappear when the actual parent page arrives.',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('many-lane graph pans inside stable column at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FixtureClient()
      ..historyCommits = [
        _commit(1, [for (var i = 2; i < 34; i++) _oid(i)]),
        _commit(2, []),
      ];
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GitLogView(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    final graph = find.byKey(ValueKey('git-graph-${_oid(1).value}'));
    final before = tester.getRect(graph);
    final subject = tester.getRect(find.text('Commit 1'));
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('git-graph-horizontal')),
        )
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(graph), before);
    expect(tester.getRect(find.text('Commit 1')), subject);
    expect(before.right, lessThan(subject.right));
    final pixels = await _pixels(tester, graph);
    final width = before.width.ceil(), height = before.height.ceil();
    final target = (10 + 31 * 14 - scroll.offset).round();
    expect(target, inInclusiveRange(0, width - 1));
    expect(
      [
        for (var x = target - 2; x <= target + 2; x++)
          if (x >= 0 && x < width)
            pixels.getUint8(((height - 1) * width + x) * 4 + 3),
      ].any((alpha) => alpha > 0),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
