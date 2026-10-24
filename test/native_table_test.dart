import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:busystack_git_flutter/src/native_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

const channelName = 'busystack_git_flutter/accessibility';
const channel = MethodChannel(channelName);
const codec = StandardMethodCodec();

final class ReloadingHistoryClient extends FixtureClient {
  Completer<HistoryPage>? nextPage;
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) =>
      nextPage?.future ??
      super.history(
        repository,
        filter: filter,
        offset: offset,
        limit: limit,
        anchor: anchor,
        cancellation: cancellation,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<Object?> request(WidgetTester tester, Map<String, Object> args) async {
    final result = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channelName,
      codec.encodeMethodCall(MethodCall('request', args)),
      (ByteData? data) => result.complete(codec.decodeEnvelope(data!)),
    );
    await tester.pump();
    return result.future;
  }

  testWidgets(
    'native row pages stay bounded and actions stay with their view',
    (tester) async {
      final scroll = ScrollController(), focus = FocusNode();
      final received = <GitNativeTableRequest>[];
      Widget view(String revision, {bool active = true, bool ticking = true}) =>
          MaterialApp(
            home: Scaffold(
              body: TickerMode(
                enabled: ticking,
                child: GitNativeTable(
                  name: 'Git commits',
                  revision: revision,
                  active: active,
                  rowCount: 100000,
                  rowAt: (i) =>
                      GitNativeRow(id: '$revision:$i', cells: ['Commit $i']),
                  columns: const ['Subject'],
                  widths: const [800],
                  rowHeight: 30,
                  scroll: scroll,
                  focus: focus,
                  selected: const [3],
                  focusedRow: 3,
                  onRequest: received.add,
                  builder: (ready) => Focus(
                    focusNode: focus,
                    child: ListView.builder(
                      controller: scroll,
                      itemExtent: 30,
                      itemCount: 100000,
                      itemBuilder: (_, i) => Text('Commit $i'),
                    ),
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(view('repository A'));
      await tester.pumpAndSettle();
      final initial =
          calls.lastWhere((c) => c.method == 'update').arguments as Map;
      expect(initial['rowCount'], 100000);
      expect((initial['rows'] as List).length, lessThan(30));
      final identity = {
        'id': initial['id'] as String,
        'generation': initial['generation'] as int,
      };
      expect(
        await request(tester, {
          ...identity,
          'action': 'rows',
          'row': 90000,
          'column': -1,
          'count': 128,
          'rowId': '',
        }),
        true,
      );
      final page = calls.lastWhere((c) => c.method == 'rows').arguments as Map;
      expect((page['rows'] as List).length, 128);
      expect((page['rows'] as List).first['id'], 'repository A:90000');
      expect(
        await request(tester, {
          ...identity,
          'action': 'select',
          'row': 3,
          'column': 0,
          'count': 0,
          'rowId': 'repository A:3',
        }),
        true,
      );
      expect(received.single.row, 3);
      expect(
        await request(tester, {
          ...identity,
          'action': 'select',
          'row': 3,
          'column': 0,
          'count': 0,
          'rowId': 'repository B:3',
        }),
        false,
      );
      await tester.pumpWidget(view('repository B'));
      await tester.pumpAndSettle();
      expect(
        await request(tester, {
          ...identity,
          'action': 'select',
          'row': 3,
          'column': 0,
          'count': 0,
          'rowId': 'repository A:3',
        }),
        false,
      );
      expect(received.length, 1);
      await tester.pumpWidget(view('repository B', ticking: false));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'remove');
      await tester.pumpWidget(view('repository B'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'update');
      await tester.pumpWidget(view('repository B', active: false));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'remove');
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      focus.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('a modal hides the native table and restores it on return', (
    tester,
  ) async {
    final scroll = ScrollController(), focus = FocusNode();
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return GitNativeTable(
                name: 'Changes',
                revision: 1,
                tree: true,
                headers: false,
                rowCount: 2,
                rowAt: (i) => GitNativeRow(id: '$i', cells: ['Path $i']),
                columns: const ['Changes'],
                widths: const [800],
                rowHeight: 30,
                scroll: scroll,
                focus: focus,
                selected: const [],
                focusedRow: -1,
                onRequest: (_) {},
                builder: (_) => Focus(
                  focusNode: focus,
                  child: ListView(
                    controller: scroll,
                    children: const [Text('Paths')],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.last.method, 'update');
    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (context) => AlertDialog(
          content: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.last.method, 'remove');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'update');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls.last.method, 'remove');
    scroll.dispose();
    focus.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'failed native handoff keeps Flutter semantics and offers retry',
    (tester) async {
      final scroll = ScrollController(), focus = FocusNode();
      var attempts = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'update' && attempts++ == 0) {
          throw PlatformException(code: 'hostUnavailable');
        }
        return true;
      });
      var ready = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitNativeTable(
              name: 'Changes',
              revision: 1,
              rowCount: 1,
              rowAt: (_) => const GitNativeRow(id: 'path', cells: ['Notes']),
              columns: const ['Changes'],
              widths: const [800],
              rowHeight: 30,
              scroll: scroll,
              focus: focus,
              selected: const [],
              focusedRow: -1,
              onRequest: (_) {},
              builder: (nativeReady) {
                ready = nativeReady;
                return ListView(
                  controller: scroll,
                  children: const [Text('Notes')],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ready, false);
      expect(
        find.textContaining('Native Git table accessibility is unavailable'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(ready, true);
      expect(attempts, greaterThanOrEqualTo(2));
      expect(
        find.textContaining('Native Git table accessibility is unavailable'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      focus.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'native Log row selection retains the initially selected commit',
    (tester) async {
      final client = FixtureClient();
      client.historyCommits = [
        for (final id in ['a', 'b'])
          GitCommit(
            oid: GitOid(id * 40),
            parents: const [],
            subject: 'Commit $id',
            author: 'Fixture',
            email: 'fixture@example.invalid',
            date: DateTime.utc(2026),
            message: 'Commit $id',
          ),
      ];
      final session = GitSession(
        client: client,
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
      final frame =
          calls.lastWhere((c) => c.method == 'update').arguments as Map;
      expect(frame['selected'], [0]);
      expect(
        await request(tester, {
          'id': frame['id'] as String,
          'generation': frame['generation'] as int,
          'action': 'addSelection',
          'row': 1,
          'column': 0,
          'rowId': client.historyCommits[1].oid.value,
          'count': 0,
        }),
        true,
      );
      await tester.pumpAndSettle();
      expect(
        (calls.lastWhere((c) => c.method == 'update').arguments
            as Map)['selected'],
        [0, 1],
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('a refreshed native Log binds actions to the newly loaded rows', (
    tester,
  ) async {
    final identities = <int, Map<int, String>>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'update') {
            final frame = call.arguments as Map;
            final bound = identities.putIfAbsent(
              frame['generation'] as int,
              () => {},
            );
            for (final row in (frame['rows'] as List).cast<Map>()) {
              final index = row['index'] as int, id = row['id'] as String;
              if (bound[index] != null && bound[index] != id) {
                throw PlatformException(
                  code: 'invalid',
                  message:
                      'Row identity changed within its reviewed generation',
                );
              }
              bound[index] = id;
            }
          }
          return true;
        });
    GitCommit commit(String id) => GitCommit(
      oid: GitOid(id * 40),
      parents: const [],
      subject: 'Commit $id',
      author: 'Fixture',
      email: 'fixture@example.invalid',
      date: DateTime.utc(2026),
    );
    final client = ReloadingHistoryClient()
      ..historyCommits = [commit('a'), commit('b')];
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GitLogView(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    final original =
        calls.lastWhere((c) => c.method == 'update').arguments as Map;
    client.nextPage = Completer<HistoryPage>();
    await tester.tap(find.byTooltip('Refresh Log'));
    await tester.pump();
    await tester.pump();
    final pending =
        calls.lastWhere((c) => c.method == 'update').arguments as Map;
    expect(pending['busy'], isTrue);
    expect((pending['rows'] as List).first['id'], GitOid('a' * 40).value);
    client.nextPage!.complete(
      HistoryPage(
        [commit('c'), commit('a')],
        nextOffset: 2,
        hasMore: false,
        anchor: 'new-history',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Native Git table accessibility is unavailable'),
      findsNothing,
    );
    final loaded =
        calls.lastWhere((c) => c.method == 'update').arguments as Map;
    expect(loaded['selected'], [1]);
    expect(
      await request(tester, {
        'id': original['id'] as String,
        'generation': original['generation'] as int,
        'action': 'select',
        'row': 0,
        'column': 0,
        'rowId': GitOid('a' * 40).value,
      }),
      false,
    );
    expect(
      await request(tester, {
        'id': loaded['id'] as String,
        'generation': loaded['generation'] as int,
        'action': 'select',
        'row': 1,
        'column': 0,
        'rowId': GitOid('a' * 40).value,
      }),
      true,
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'native Commit cells preserve tree parents and explicit staging',
    (tester) async {
      final client = FixtureClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      final reviews = <GitComparison>[];
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitChangeTree(session: session, onReview: reviews.add),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frame =
          calls.lastWhere((c) => c.method == 'update').arguments as Map;
      final rows = (frame['rows'] as List).cast<Map>();
      final unstaged = rows.firstWhere(
        (r) => (r['description'] as String).contains('Unstaged'),
      );
      final directory = rows.firstWhere(
        (r) => r['index'] == unstaged['parent'],
      );
      expect(directory['depth'], 1);
      expect(
        rows.firstWhere((r) => r['index'] == directory['parent'])['depth'],
        0,
      );
      final identity = {
        'id': frame['id'] as String,
        'generation': frame['generation'] as int,
        'row': unstaged['index'] as int,
        'column': 0,
        'rowId': unstaged['id'] as String,
        'count': 0,
      };
      expect(await request(tester, {...identity, 'action': 'select'}), true);
      await tester.pumpAndSettle();
      expect(reviews.single.right.kind, ContentKind.workingTree);
      expect(client.mutations, isEmpty);
      expect(await request(tester, {...identity, 'action': 'stage'}), true);
      await tester.pumpAndSettle();
      final stage = client.mutations.single as StagePaths;
      expect(stage.paths, [RepoPath.text('chapter/notes.md')]);
      expect(stage.unstage, false);
      expect(stage.expectedIndex, 'index');
      expect(stage.contentTokens.keys, [RepoPath.text('chapter/notes.md').key]);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
