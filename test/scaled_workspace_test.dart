import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

Future<void> scaled(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'enlarged Commit keeps its multiline draft and actions visible together',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: host(),
      );
      await session.start();
      session.setDraft('retained prose\nsecond line');
      await scaled(
        tester,
        GitCommitView(
          session: session,
          onReview: (_) {},
          onLog: () {},
          onBranches: () {},
          onPush: () {},
          onMore: (_) {},
        ),
        const Size(400, 600),
      );
      final surface = tester.getRect(find.byType(GitCommitView));
      final message = tester.getRect(find.byType(TextField));
      expect(message.top, greaterThanOrEqualTo(surface.top));
      expect(message.bottom, lessThanOrEqualTo(surface.bottom));
      expect(message.height, greaterThanOrEqualTo(70));
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'narrow enlarged workspace opens full review and returns to the retained draft',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      session.setDraft('retained prose');
      await scaled(
        tester,
        GitWorkspace(session: session),
        const Size(900, 550),
      );
      tester
          .widget<GitCommitView>(find.byType(GitCommitView))
          .onReview(
            GitComparison(
              RepoPath.text('chapter/notes.md'),
              const ContentVersion.index(),
              const ContentVersion.working(),
            ),
          );
      await tester.pump();
      expect(find.text('Back to Commit'), findsOneWidget);
      expect(find.byType(GitCommitView).hitTestable(), findsNothing);
      expect(tester.getSize(find.byType(GitDiffView)).width, greaterThan(850));
      await tester.tap(find.text('Back to Commit'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(session.draft, 'retained prose');
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('enlarged diff controls leave a usable content viewport', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = GitSession(
      client: FixtureClient(),
      repository: repo,
      host: host(),
    );
    await session.start();
    await scaled(
      tester,
      GitDiffView(
        session: session,
        comparison: GitComparison(
          RepoPath.text('chapter/notes.md'),
          const ContentVersion.index(),
          const ContentVersion.working(),
        ),
      ),
      const Size(700, 500),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    final content = find.descendant(
      of: find.byType(GitDiffView),
      matching: find.byType(ListView),
    );
    expect(content, findsOneWidget);
    expect(tester.getSize(content).height, greaterThan(150));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets(
    'compact diff menus retain explicit staging and display actions',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await session.start();
      await scaled(
        tester,
        GitDiffView(
          session: session,
          comparison: GitComparison(
            RepoPath.text('chapter/notes.md'),
            const ContentVersion.index(),
            const ContentVersion.working(),
          ),
        ),
        const Size(700, 500),
      );
      await tester.tap(find.byTooltip('Diff display options'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ignore whitespace'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Ignore whitespace'));
      await tester.pumpAndSettle();
      expect(session.option('diffIgnoreWhitespace', false), isTrue);
      expect(client.mutations, isEmpty);
      await tester.tap(find.text('Staging actions…'));
      await tester.pumpAndSettle();
      final lines = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Stage selected changed lines'),
          matching: find.byType(ListTile),
        ),
      );
      expect(lines.enabled, isFalse);
      await tester.tap(find.text('Stage whole file'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(client.mutations.single, isA<StagePaths>());
      expect(
        (client.mutations.single as StagePaths).paths.single,
        RepoPath.text('chapter/notes.md'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
