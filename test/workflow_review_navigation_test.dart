import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

GitComparison comparison() => GitComparison(
  RepoPath.text('chapter/notes.md'),
  const ContentVersion.index(),
  const ContentVersion.working(),
);

Widget selector(
  GitSession session, {
  bool nested = false,
  ValueChanged<VoidCallback>? capture,
}) => SizedBox(
  width: 400,
  height: 200,
  child: Builder(
    builder: (context) {
      void open() => gitOpenComparison(context, session, comparison());
      capture?.call(open);
      return Column(
        children: [
          const Text('Read-only selector'),
          TextButton(
            onPressed: open,
            child: const Text('Open captured comparison'),
          ),
          if (nested)
            TextButton(
              onPressed: () => unawaited(
                session.host.present<void>(
                  context,
                  'Nested selector',
                  selector(session),
                  reviewSelection: true,
                ),
              ),
              child: const Text('Nested selector'),
            ),
          TextButton(
            onPressed: () => unawaited(
              session.host.present<void>(
                context,
                'Newer confirmation',
                const SizedBox(
                  width: 300,
                  height: 100,
                  child: Text('Replacement confirmation'),
                ),
              ),
            ),
            child: const Text('Newer confirmation'),
          ),
        ],
      );
    },
  ),
);

Future<(GitSession, FixtureClient)> mount(
  WidgetTester tester, {
  bool nested = false,
  ValueChanged<VoidCallback>? capture,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FixtureClient();
  final session = GitSession(client: client, repository: repo, host: host());
  await session.start();
  await tester.pumpWidget(
    GitTestApp(
      home: Scaffold(
        body: GitHostScope(
          host: session.host,
          child: Builder(
            builder: (context) => Column(
              children: [
                const Text('Host document draft'),
                TextButton(
                  onPressed: () => unawaited(
                    session.host.present<void>(
                      context,
                      'Selector',
                      selector(session, nested: nested, capture: capture),
                      reviewSelection: true,
                    ),
                  ),
                  child: const Text('Open selector'),
                ),
                TextButton(
                  onPressed: () => unawaited(
                    session.host.present<void>(
                      context,
                      'Operation plan',
                      SizedBox(
                        width: 500,
                        height: 300,
                        child: Builder(
                          builder: (planContext) => Column(
                            children: [
                              const Text('Retained operation plan'),
                              TextButton(
                                onPressed: () => unawaited(
                                  session.host.present<void>(
                                    planContext,
                                    'Selector',
                                    selector(session),
                                    reviewSelection: true,
                                  ),
                                ),
                                child: const Text('Inspect plan file'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    gitCompleteSurface(planContext),
                                child: const Text('Cancel plan'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open plan'),
                ),
                Expanded(
                  child: GitWorkspace(
                    session: session,
                    sidebarHeader: const SizedBox.shrink(),
                    mayCloseReview: () async => true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  return (session, client);
}

Future<void> settleReview(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  } while (find.byType(GitLoading).evaluate().isNotEmpty &&
      DateTime.now().isBefore(deadline));
  expect(find.byType(GitLoading), findsNothing);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'nested read-only selectors close into the canonical independent content tab',
    (tester) async {
      final (session, client) = await mount(tester, nested: true);
      await tester.tap(find.text('Open selector'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nested selector'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open captured comparison').last);
      await settleReview(tester);
      expect(find.text('Read-only selector'), findsNothing);
      expect(find.text('Host document draft'), findsOneWidget);
      expect(find.byType(GitReviewTabStrip), findsOneWidget);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(session.feature.tabs.entries, hasLength(1));
      expect(
        session.feature.tabs.active!.comparison.toJson(),
        comparison().toJson(),
      );
      expect(client.mutations, isEmpty);
    },
  );

  testWidgets(
    'a queued activation cannot dismiss a newer confirmation or create a hidden review',
    (tester) async {
      late VoidCallback queued;
      final (session, client) = await mount(
        tester,
        capture: (value) => queued = value,
      );
      await tester.tap(find.text('Open selector'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Newer confirmation').last);
      await tester.pumpAndSettle();
      queued();
      await tester.pumpAndSettle();
      expect(find.text('Replacement confirmation'), findsOneWidget);
      expect(session.feature.tabs.entries, isEmpty);
      Navigator.of(tester.element(find.text('Replacement confirmation'))).pop();
      await tester.pumpAndSettle();
      queued();
      await settleReview(tester);
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(client.mutations, isEmpty);
    },
  );

  testWidgets(
    'a selector above an operation plan preserves the plan and captured review independently',
    (tester) async {
      final (session, client) = await mount(tester);
      await tester.tap(find.text('Open plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect plan file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open captured comparison'));
      await settleReview(tester);
      expect(find.text('Read-only selector'), findsNothing);
      expect(find.text('Retained operation plan'), findsOneWidget);
      final captured = session.feature.tabs.active!;
      await tester.tap(find.text('Cancel plan'));
      await tester.pumpAndSettle();
      expect(find.text('Retained operation plan'), findsNothing);
      expect(session.feature.tabs.active, same(captured));
      expect(find.byType(GitDiffView), findsOneWidget);
      expect(client.mutations, isEmpty);
    },
  );
}
