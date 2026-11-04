import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

GitCommit commit(String id, String subject) => GitCommit(
  oid: GitOid(id * 40),
  parents: const [],
  subject: subject,
  author: 'Fixture',
  email: 'fixture@example.invalid',
  date: DateTime.utc(2026),
  message: 'Full message: $subject',
);

final class NavigationClient extends FixtureClient {
  final head = commit('a', 'Current branch tip');
  final older = commit('b', 'Retained ancestor');
  final distant = commit('c', 'Outside the loaded history');
  Completer<HistoryPage>? pendingTarget;
  HistoryPage page(List<GitCommit> commits) => HistoryPage(
    commits,
    nextOffset: commits.length,
    hasMore: false,
    anchor: 'refs',
  );
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) async {
    historyFilters.add(filter);
    if (filter.reference == distant.oid.value && pendingTarget != null) {
      return pendingTarget!.future;
    }
    final result =
        filter.reference == distant.oid.value ||
            filter.reference == 'outside-branch'
        ? [distant, older]
        : [head, older];
    return page(
      (filter.author.isEmpty ? result : [older]).take(limit).toList(),
    );
  }
}

void main() {
  testWidgets(
    'filter composition and focus survive responsive toolbar reparenting',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = GitSession(
        client: NavigationClient(),
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await session.start();
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(body: GitLogView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byKey(const ValueKey('git-history-filter-0')),
        matching: find.byType(EditableText),
      );
      await tester.tap(input);
      const value = TextEditingValue(
        text: '入力 composing',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 2),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      final editor = tester.state<EditableTextState>(input);
      final focus = FocusManager.instance.primaryFocus;
      for (final width in [480.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(tester.state<EditableTextState>(input), same(editor));
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(editor.widget.controller.value, value);
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final reference in [false, true]) {
    testWidgets(
      'Go to an unloaded ${reference ? 'reference' : 'commit'} selects its tip',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = NavigationClient();
        final session = GitSession(
          client: client,
          repository: repo,
          host: host(),
        );
        await session.start();
        await tester.pumpWidget(
          GitTestApp(
            home: Scaffold(body: GitLogView(session: session)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retained ancestor'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('git-history-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Go to commit/reference…'));
        await tester.pumpAndSettle();
        final input = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(
          input,
          reference ? 'outside-branch' : client.distant.oid.value,
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text(client.distant.oid.value), findsOneWidget);
        expect(find.text(client.older.oid.value), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text(client.older.oid.value), findsOneWidget);
        expect(client.mutations, isEmpty);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets(
    'Back to HEAD selects the tip even when an ancestor remains loaded',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = NavigationClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(body: GitLogView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retained ancestor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('git-history-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to HEAD'));
      await tester.pumpAndSettle();
      expect(find.text(client.head.oid.value), findsOneWidget);
      expect(find.text(client.older.oid.value), findsNothing);
      expect(client.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'a filtered revision never substitutes an ancestor for the requested tip',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = NavigationClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(body: GitLogView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Author'),
        'Only older',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('git-history-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to commit/reference…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        'outside-branch',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('outside the current filters'),
        findsOneWidget,
      );
      expect(find.text(client.distant.oid.value), findsNothing);
      expect(find.text(client.older.oid.value), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Only older'), findsOneWidget);
      await tester.tap(find.text('Reveal revision without filters'));
      await tester.pumpAndSettle();
      expect(find.text(client.distant.oid.value), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Only older'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('git-history-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore history filters'));
      await tester.pumpAndSettle();
      expect(find.text(client.distant.oid.value), findsNothing);
      expect(find.text(client.older.oid.value), findsOneWidget);
      expect(client.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'late navigation cannot replace a later choice from loaded history',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = NavigationClient()
        ..pendingTarget = Completer<HistoryPage>();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        GitTestApp(
          home: Scaffold(body: GitLogView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('git-history-actions')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Go to commit/reference…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        client.distant.oid.value,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('git-history-actions')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Go to commit/reference…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        client.older.oid.value,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      client.pendingTarget!.complete(
        client.page([client.distant, client.older]),
      );
      await tester.pumpAndSettle();
      expect(find.text(client.older.oid.value), findsOneWidget);
      expect(find.text(client.distant.oid.value), findsNothing);
      expect(client.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
