import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

typedef _Binding = ({
  GitSession session,
  bool active,
  RepoPath? path,
  bool shown,
});

final class _Client extends FixtureClient {
  _Client(String id) {
    historyCommits = [
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
  }
}

Future<(_Client, _Client, ValueNotifier<_Binding>, Completer<String?>)> _mount(
  WidgetTester tester, {
  String? menuChoice,
  bool compact = false,
  bool realBranchDialog = false,
  Completer<String?>? pendingMenu,
  List<String>? dispatched,
  List<Completer<String?>>? dialogAnswers,
  bool withReference = false,
  bool translated = false,
  Size? size,
}) async {
  tester.view.physicalSize =
      size ?? (compact ? const Size(600, 300) : const Size(1440, 900));
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final answer = Completer<String?>();
  final presenter = GitHost(
    translate: translated
        ? (_, fallback) => switch (fallback) {
            GitMessages.local => 'Localized local',
            GitMessages.remote => 'Localized remote',
            GitMessages.tags => 'Localized tags',
            _ => fallback,
          }
        : null,
    present: <T>(context, title, child, {bool expanded = false}) async {
      if (realBranchDialog && title == GitMessages.filterBranchesAndTags) {
        return await showDialog<T>(
          context: context,
          builder: (_) => Dialog(child: child),
        );
      }
      return await (dialogAnswers != null && dialogAnswers.isNotEmpty
              ? dialogAnswers.removeAt(0).future
              : answer.future)
          as T?;
    },
    presentMenu: (_, entries, {position}) async =>
        pendingMenu == null ? menuChoice : await pendingMenu.future,
    openDocument: (_, _, {snapshot}) async {},
    prepareMutation: (_, _) async => true,
    chooseDirectory: (_) async => null,
    notify: (_) {},
    drafts: MemoryGitDraftStore(),
  );
  final first = _Client('a'), second = _Client('b');
  if (withReference)
    first.historyReferences = [
      GitReference(
        name: 'refs/heads/main',
        oid: GitOid('a' * 40),
        current: true,
      ),
    ];
  final a = GitSession(client: first, repository: repo, host: presenter);
  final b = GitSession(
    client: second,
    repository: const RepositoryId(
      root: '/fixture/other',
      gitDir: '/fixture/other/.git',
      commonDir: '/fixture/other/.git',
      objectFormat: 'sha1',
    ),
    host: presenter,
  );
  await a.start();
  await b.start();
  final binding = ValueNotifier<_Binding>((
    session: a,
    active: true,
    path: null,
    shown: true,
  ));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<_Binding>(
          valueListenable: binding,
          builder: (_, value, _) => value.shown
              ? GitLogView(
                  session: value.session,
                  active: value.active,
                  path: value.path,
                  onCommitAction: dispatched == null
                      ? null
                      : (commit, action) => dispatched.add(action),
                )
              : const Text('Owning Log removed'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    if (!answer.isCompleted) answer.complete(null);
    binding.dispose();
    a.dispose();
    b.dispose();
  });
  // Keep the second session available through the test binding transition.
  _otherSessions[binding] = b;
  addTearDown(() => _otherSessions.remove(binding));
  return (first, second, binding, answer);
}

final _otherSessions = <ValueNotifier<_Binding>, GitSession>{};

Future<void> _transition(
  WidgetTester tester,
  ValueNotifier<_Binding> binding,
  String kind,
) async {
  final old = binding.value;
  if (kind == 'repository') {
    binding.value = (
      session: _otherSessions[binding]!,
      active: true,
      path: null,
      shown: true,
    );
  } else if (kind == 'path') {
    binding.value = (
      session: old.session,
      active: true,
      path: RepoPath.text('new-history-path.md'),
      shown: true,
    );
  } else {
    binding.value = (
      session: old.session,
      active: false,
      path: old.path,
      shown: true,
    );
    await tester.pumpAndSettle();
    binding.value = old;
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final transition in ['repository', 'activeABA', 'path']) {
    testWidgets(
      'compact Author dialog cannot complete into $transition replacement',
      (tester) async {
        final (first, second, binding, answer) = await _mount(
          tester,
          menuChoice: 'author',
          compact: true,
        );
        final before = tester.state(
          find.byType(GitLogView, skipOffstage: false),
        );
        await tester.tap(find.byTooltip('Filter Log'));
        await tester.pumpAndSettle();
        await _transition(tester, binding, transition);
        expect(
          identical(
            before,
            tester.state(find.byType(GitLogView, skipOffstage: false)),
          ),
          isTrue,
        );
        final client = transition == 'repository' ? second : first;
        final reads = client.historyFilters.length;
        answer.complete('Belongs only to the original dialog');
        await tester.pumpAndSettle();
        expect(
          client.historyFilters.length,
          reads,
          reason: 'A retired filter response must not issue new history reads',
        );
        expect(
          client.historyFilters.any(
            (f) => f.author == 'Belongs only to the original dialog',
          ),
          isFalse,
        );
        expect(first.mutations, isEmpty);
        expect(second.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Go to dialog cannot revive after active ABA', (tester) async {
    final (first, _, binding, answer) = await _mount(tester);
    await tester.tap(find.text('Go to commit/reference…'));
    await tester.pumpAndSettle();
    await _transition(tester, binding, 'activeABA');
    final reads = first.historyFilters.length;
    answer.complete('retired-reference');
    await tester.pumpAndSettle();
    expect(first.historyFilters.length, reads);
    expect(
      first.historyFilters.any((f) => f.reference == 'retired-reference'),
      isFalse,
    );
    expect(first.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final transition in ['repository', 'activeABA']) {
    testWidgets(
      'actual DateRangePicker cannot complete into $transition replacement',
      (tester) async {
        final (first, second, binding, _) = await _mount(tester);
        final before = tester.state(
          find.byType(GitLogView, skipOffstage: false),
        );
        await tester.tap(find.text(GitMessages.date));
        await tester.pumpAndSettle();
        expect(find.byType(DateRangePickerDialog), findsOneWidget);
        await _transition(tester, binding, transition);
        expect(
          identical(
            before,
            tester.state(find.byType(GitLogView, skipOffstage: false)),
          ),
          isTrue,
        );
        final client = transition == 'repository' ? second : first;
        final reads = client.historyFilters.length;
        Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop(
          DateTimeRange(
            start: DateTime.utc(2026, 1, 1),
            end: DateTime.utc(2026, 1, 2),
          ),
        );
        await tester.pumpAndSettle();
        expect(client.historyFilters.length, reads);
        expect(
          client.historyFilters.any((f) => f.since != null || f.until != null),
          isFalse,
        );
        expect(first.mutations, isEmpty);
        expect(second.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'actual DateRangePicker completion after owning Log disposal is harmless',
    (tester) async {
      final (first, _, binding, _) = await _mount(tester);
      await tester.tap(find.text(GitMessages.date));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      binding.value = (
        session: binding.value.session,
        active: true,
        path: null,
        shown: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(GitLogView), findsNothing);
      final reads = first.historyFilters.length;
      Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop(
        DateTimeRange(
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 1, 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(first.historyFilters.length, reads);
      expect(tester.takeException(), isNull);
    },
  );
  for (final transition in ['repository', 'activeABA', 'dispose']) {
    testWidgets('actual compact branch popup cannot select after $transition', (
      tester,
    ) async {
      final (first, second, binding, _) = await _mount(
        tester,
        compact: true,
        realBranchDialog: true,
      );
      final before = tester.state(find.byType(GitLogView, skipOffstage: false));
      await tester.tap(find.byTooltip(GitMessages.filterBranchesAndTags));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      if (transition == 'dispose') {
        binding.value = (
          session: binding.value.session,
          active: true,
          path: null,
          shown: false,
        );
        await tester.pumpAndSettle();
        expect(find.byType(GitLogView, skipOffstage: false), findsNothing);
      } else {
        await _transition(tester, binding, transition);
        expect(
          identical(
            before,
            tester.state(find.byType(GitLogView, skipOffstage: false)),
          ),
          isTrue,
        );
      }
      final client = transition == 'repository' ? second : first;
      final reads = client.historyFilters.length;
      await tester.tap(find.text(GitMessages.allReferences));
      await tester.pumpAndSettle();
      expect(client.historyFilters.length, reads);
      expect(first.mutations, isEmpty);
      expect(second.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Go to completion during actual owning route reverse animation is retired',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final answer = Completer<String?>();
      final client = FixtureClient()
        ..historyCommits = [
          GitCommit(
            oid: GitOid('a' * 40),
            parents: const [],
            subject: 'Current commit',
            author: 'Fixture',
            email: 'fixture@example.invalid',
            date: DateTime.utc(2026),
            message: 'Current commit',
          ),
        ];
      final presenter = GitHost(
        present: <T>(context, title, child, {bool expanded = false}) async =>
            await answer.future as T?,
        openDocument: (_, _, {snapshot}) async {},
        prepareMutation: (_, _) async => true,
        chooseDirectory: (_) async => null,
        notify: (_) {},
        drafts: MemoryGitDraftStore(),
      );
      final session = GitSession(
        client: client,
        repository: repo,
        host: presenter,
      );
      await session.start();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Owning parent remains')),
        ),
      );
      unawaited(
        navigator.currentState!.push<void>(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: const Duration(seconds: 1),
            pageBuilder: (_, _, _) =>
                Scaffold(body: GitLogView(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(GitLogView));
      final state = tester.state(find.byType(GitLogView));
      final route = ModalRoute.of(element)!;
      await tester.tap(find.text('Go to commit/reference…'));
      await tester.pump();
      final reads = client.historyFilters.length;
      navigator.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        state.mounted,
        isTrue,
        reason: 'Exercise closing, not disposed, owner',
      );
      expect(route.isActive, isFalse);
      answer.complete('retired-route-reference');
      await tester.pump(const Duration(milliseconds: 1));
      expect(client.historyFilters.length, reads);
      expect(
        client.historyFilters.any(
          (f) => f.reference == 'retired-route-reference',
        ),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Owning parent remains'), findsOneWidget);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  for (final goTo in [false, true]) {
    testWidgets(
      'valid ${goTo ? 'Go to' : 'Author'} dialog survives same-origin refresh',
      (tester) async {
        final (first, _, _, answer) = await _mount(
          tester,
          compact: !goTo,
          menuChoice: 'author',
        );
        if (goTo)
          await tester.tap(find.text(GitMessages.goToCommitReference));
        else
          await tester.tap(find.byTooltip(GitMessages.filterLog));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(GitMessages.refreshLog));
        await tester.pumpAndSettle();
        final reads = first.historyFilters.length;
        answer.complete(goTo ? 'valid-reference' : 'valid-author');
        await tester.pumpAndSettle();
        expect(first.historyFilters.length, greaterThan(reads));
        expect(
          first.historyFilters.any(
            (f) => goTo
                ? f.reference == 'valid-reference'
                : f.author == 'valid-author',
          ),
          isTrue,
        );
        expect(first.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('newer filter dialog wins while the old response is pending', (
    tester,
  ) async {
    final old = Completer<String?>(), newer = Completer<String?>();
    final queue = [old, newer];
    addTearDown(() {
      if (!old.isCompleted) old.complete(null);
      if (!newer.isCompleted) newer.complete(null);
    });
    final (first, _, _, _) = await _mount(
      tester,
      compact: true,
      menuChoice: 'author',
      dialogAnswers: queue,
    );
    await tester.tap(find.byTooltip(GitMessages.filterLog));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(GitMessages.filterLog));
    await tester.pumpAndSettle();
    expect(queue, isEmpty);
    newer.complete('newer author');
    await tester.pumpAndSettle();
    final reads = first.historyFilters.length;
    old.complete('retired author');
    await tester.pumpAndSettle();
    expect(first.historyFilters.length, reads);
    expect(first.historyFilters.last.author, 'newer author');
    expect(
      first.historyFilters.any((f) => f.author == 'retired author'),
      isFalse,
    );
    expect(first.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid actual date selection still applies its inclusive range', (
    tester,
  ) async {
    final (first, _, _, _) = await _mount(tester);
    await tester.tap(find.text(GitMessages.date));
    await tester.pumpAndSettle();
    final range = DateTimeRange(
      start: DateTime.utc(2026, 1, 1),
      end: DateTime.utc(2026, 1, 2),
    );
    Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop(range);
    await tester.pumpAndSettle();
    expect(first.historyFilters.last.since, range.start);
    expect(
      first.historyFilters.last.until,
      range.end.add(const Duration(days: 1)),
    );
    expect(first.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'valid compact branch popup owns search and applies chosen reference',
    (tester) async {
      final (first, _, _, _) = await _mount(
        tester,
        compact: true,
        realBranchDialog: true,
        withReference: true,
      );
      await tester.tap(find.byTooltip(GitMessages.filterBranchesAndTags));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        'mai',
      );
      await tester.pumpAndSettle();
      final target = find.descendant(
        of: find.byType(Dialog),
        matching: find.text('main'),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(first.historyFilters.last.reference, 'refs/heads/main');
      expect(first.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending commit menu cannot revive after active ABA', (
    tester,
  ) async {
    final menu = Completer<String?>(), dispatched = <String>[];
    addTearDown(() {
      if (!menu.isCompleted) menu.complete(null);
    });
    final (first, _, binding, _) = await _mount(
      tester,
      pendingMenu: menu,
      dispatched: dispatched,
    );
    await tester.tap(find.text(GitMessages.commitActions));
    await tester.pumpAndSettle();
    await _transition(tester, binding, 'activeABA');
    menu.complete(GitMessages.createBranch2);
    await tester.pumpAndSettle();
    expect(dispatched, isEmpty);
    expect(first.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final transition in ['repository', 'activeABA']) {
    testWidgets(
      'pending compact Filter menu cannot open a dialog after $transition',
      (tester) async {
        final menu = Completer<String?>();
        addTearDown(() {
          if (!menu.isCompleted) menu.complete(null);
        });
        final (first, second, binding, answer) = await _mount(
          tester,
          compact: true,
          pendingMenu: menu,
        );
        final before = tester.state(find.byType(GitLogView));
        await tester.tap(find.byTooltip(GitMessages.filterLog));
        await tester.pumpAndSettle();
        await _transition(tester, binding, transition);
        expect(
          identical(before, tester.state(find.byType(GitLogView))),
          isTrue,
        );
        final client = transition == 'repository' ? second : first;
        final reads = client.historyFilters.length;
        menu.complete('author');
        await tester.pumpAndSettle();
        answer.complete('foreign dialog result');
        await tester.pumpAndSettle();
        expect(client.historyFilters.length, reads);
        expect(
          client.historyFilters.any((f) => f.author == 'foreign dialog result'),
          isFalse,
        );
        expect(first.mutations, isEmpty);
        expect(second.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'retained branch selection cannot pop the parent while popup closes',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client('a');
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      addTearDown(session.dispose);
      await session.start();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Parent route')),
        ),
      );
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(body: GitLogView(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(GitMessages.filterBranchesAndTags));
      await tester.pumpAndSettle();
      final popup = tester.element(find.byType(Dialog));
      final popupRoute = ModalRoute.of(popup)!;
      final selection = tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, GitMessages.allReferences),
          )
          .onTap!;
      final reads = client.historyFilters.length;
      navigator.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 1));
      expect(popup.mounted, isTrue);
      expect(popupRoute.isActive, isFalse);
      selection();
      await tester.pumpAndSettle();
      expect(find.byType(GitLogView), findsOneWidget);
      expect(find.text('Parent route'), findsNothing);
      expect(client.historyFilters.length, reads);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final popup in [false, true]) {
    testWidgets(
      'branch group headers use host translations in ${popup ? 'popup' : 'inline'} pane',
      (tester) async {
        await _mount(
          tester,
          realBranchDialog: popup,
          translated: true,
          size: Size(popup ? 600 : 1440, 900),
        );
        if (popup) {
          await tester.tap(find.byTooltip(GitMessages.filterBranchesAndTags));
          await tester.pumpAndSettle();
        }
        expect(find.text('Localized local'), findsOneWidget);
        expect(find.text('Localized remote'), findsOneWidget);
        expect(find.text('Localized tags'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
