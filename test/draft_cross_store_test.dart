import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'support/presentation_fixture.dart';

final _messageKey = repo.presentationKey;
final _amendKey = '${repo.presentationKey}:amend:${'a' * 40}';

class _Disk {
  final values = <String, GitStoredDraft>{};
  int revision = 0;
}

class _Store implements GitVersionedDraftStore {
  _Store(this.disk);
  final _Disk disk;
  String? delayKey;
  Completer<void>? entered, release;
  final writes = <String>[];

  void delayNext(String key) {
    delayKey = key;
    entered = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<GitStoredDraft> readVersioned(String key) async =>
      disk.values[key] ??
      const GitStoredDraft(text: null, version: GitStoredDraft.absentVersion);

  @override
  Future<GitDraftWriteResult> compareAndWrite(
    String key, {
    required String expectedVersion,
    required String? text,
  }) async {
    if (delayKey == key) {
      delayKey = null;
      entered!.complete();
      await release!.future;
    }
    final current =
        disk.values[key] ??
        const GitStoredDraft(text: null, version: GitStoredDraft.absentVersion);
    if (current.version != expectedVersion) {
      return GitDraftWriteResult(written: false, current: current);
    }
    writes.add(text ?? '');
    final saved = GitStoredDraft(text: text, version: 'v${++disk.revision}');
    disk.values[key] = saved;
    return GitDraftWriteResult(written: true, current: saved);
  }

  @override
  Future<String?> read(String key) async => (await readVersioned(key)).text;
  @override
  Future<void> write(String key, String value) => throw StateError(
    'Versioned sessions must never use unconditional writes',
  );
}

GitSession _session(
  GitDraftStore store, {
  FixtureClient? client,
  GitDismissalRegistry? dismissal,
  RepositoryId repository = repo,
  Future<Map<String, Object>?> Function(String)? readViewState,
  String Function(String, Map<String, Object?>)? localize,
}) {
  final base = host();
  return GitSession(
    client: client ?? FixtureClient(),
    repository: repository,
    host: GitHost(
      present: base.present,
      openDocument: base.openDocument,
      prepareMutation: base.prepareMutation,
      chooseDirectory: base.chooseDirectory,
      notify: base.notify,
      drafts: store,
      registerDismissalGuard: dismissal?.register,
      readViewState: readViewState,
      localize: localize,
    ),
  );
}

class _CommitClient extends FixtureClient {
  _CommitClient() {
    historyCommits = [
      GitCommit(
        oid: head,
        parents: const [],
        subject: 'old',
        author: 'Fixture',
        email: 'fixture@example.invalid',
        date: DateTime.utc(2026),
        message: 'original message',
      ),
    ];
  }
  var head = GitOid('a' * 40);
  GitSnapshot current() => GitSnapshot(
    repository: repo,
    token: 'review',
    indexToken: 'index',
    head: head,
    branch: 'main',
    changes: [
      GitChange(path: RepoPath.text('note.md'), index: 'M', worktree: '.'),
    ],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => current();
}

Widget _commit(GitSession session) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 600,
      child: GitCommitView(
        session: session,
        onReview: (_) {},
        onLog: () {},
        onBranches: () {},
        onPush: () {},
        onMore: (_) {},
      ),
    ),
  ),
);

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test(
    'recovered saved amend owners survive an empty cached view-state list',
    () async {
      final session = _session(
        _Store(_Disk()),
        readViewState: (_) async => {
          'commitAmendDraftTargets': ['a' * 40],
          'workspaceSplit': .25,
        },
      );
      addTearDown(session.dispose);
      session.viewState = {
        'commitAmendDraftTargets': <String>[],
        'workspaceSplit': .4,
      };
      await session.start();
      expect(session.viewState['commitAmendDraftTargets'], ['a' * 40]);
      expect(session.viewState['workspaceSplit'], .4);
      expect(session.viewState['commitAmendDraftTarget'], isNull);
    },
  );

  testWidgets(
    'long localized recovery stays readable in a narrow enlarged Commit',
    (tester) async {
      _desktop(tester);
      final disk = _Disk();
      final first = _session(
        _Store(disk),
        localize: (message, _) => switch (message) {
          GitMessages.commitDraftChangedInAnotherWindow =>
            'Diese Nachricht wurde in einem anderen Fenster geändert. Prüfen Sie die gespeicherte Nachricht, bevor Sie sie ersetzen.',
          GitMessages.reviewSavedMessage => 'Gespeicherte Nachricht prüfen',
          _ => message,
        },
      );
      final second = _session(_Store(disk));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.start();
      second.setDraft('saved C');
      await second.flushMessageDrafts();
      first.setDraft('local B');
      await first.flushMessageDrafts();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 650,
              child: GitCommitView(
                session: first,
                onReview: (_) {},
                onLog: () {},
                onBranches: () {},
                onPush: () {},
                onMore: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final input = find.widgetWithText(TextField, 'Commit message');
      await tester.ensureVisible(input);
      await tester.pumpAndSettle();
      expect(tester.getRect(input).height, greaterThan(32));
      expect(first.draft, 'local B');
      expect(disk.values[_messageKey]!.text, 'saved C');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('host dismissal reads dirty state before a widget rebuild', (
    tester,
  ) async {
    final registry = GitDismissalRegistry();
    final session = _session(MemoryGitDraftStore(), dismissal: registry);
    addTearDown(session.dispose);
    var dirty = false, requests = 0;
    final decision = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: GitDraftGuard(
          host: session.host,
          canDismiss: true,
          isDismissible: () => !dirty,
          confirmDiscard: () {
            requests++;
            return decision.future;
          },
          child: const SizedBox(),
        ),
      ),
    );
    dirty = true; // Deliberately no pump/rebuild before the host request.
    final closing = registry.mayDismiss();
    expect(requests, 1);
    expect(registry.mayDismiss(), same(closing));
    decision.complete(false);
    expect(await closing, isFalse);
    expect(dirty, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'draft failures and review candidates stay in their owning worktree',
    () async {
      final disk = _Disk();
      final store = _Store(disk);
      final first = _session(store), otherWriter = _session(_Store(disk));
      const elsewhere = RepositoryId(
        root: '/fixture/other',
        gitDir: '/fixture/other/.git',
        commonDir: '/fixture/other/.git',
        objectFormat: 'sha1',
      );
      final otherRepo = _session(store, repository: elsewhere);
      addTearDown(first.dispose);
      addTearDown(otherWriter.dispose);
      addTearDown(otherRepo.dispose);
      otherWriter.setDraft('saved C');
      await otherWriter.flushMessageDrafts();
      first.setDraft('local B');
      await first.flushMessageDrafts();
      expect(first.draftFailure, isNotNull);
      expect(otherRepo.draftFailure, isNull);
      expect(otherRepo.hasUnpersistedMessageDrafts, isFalse);
      expect(
        otherRepo.reviewableMessageDraft(elsewhere.presentationKey),
        isNull,
      );
      expect(otherRepo.messageDraftRevisions, isEmpty);
    },
  );

  testWidgets(
    'amend completion keeps another window C under the old reviewed HEAD',
    (tester) async {
      _desktop(tester);
      final disk = _Disk(),
          client = _CommitClient()..pending = Completer<GitOutcome>();
      final first = _session(_Store(disk), client: client);
      final second = _session(_Store(disk));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.start();
      first.setDraft('normal A');
      await first.flushMessageDrafts();
      await tester.pumpWidget(_commit(first));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final input = find.widgetWithText(TextField, 'Commit message');
      await tester.enterText(input, 'submitted B');
      await first.flushMessageDrafts();
      final operation = first.commitAction!(false);
      await tester.pump();
      await second.readMessageDraft(_amendKey);
      second.setMessageDraft(_amendKey, 'other window C');
      await second.flushMessageDrafts();
      client.head = GitOid('b' * 40);
      client.pending!.complete(
        GitOutcome(
          phase: GitOperationPhase.completed,
          createdCommit: client.head,
          snapshot: client.current(),
        ),
      );
      await operation;
      await tester.pumpAndSettle();
      expect((client.mutations.single as CommitIndex).message, 'submitted B');
      expect(first.draft, 'normal A');
      expect(find.text('other window C'), findsOneWidget);
      expect(first.canCommit!(), isFalse);
      expect(first.viewState['commitAmendDraftTarget'], 'a' * 40);
      expect(first.viewState['commitAmendDraftTargets'], contains('a' * 40));
      expect(disk.values[_amendKey]!.text, 'other window C');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'saved-message review completes its own dialog and explicitly loads C',
    (tester) async {
      _desktop(tester);
      final disk = _Disk();
      final first = _session(_Store(disk)), second = _session(_Store(disk));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.start();
      second.setDraft('saved C');
      await second.flushMessageDrafts();
      await tester.pumpWidget(_commit(first));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Commit message'),
        'local B',
      );
      await first.flushMessageDrafts();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review saved message'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('saved C'), findsOneWidget);
      final revision = disk.revision;
      await tester.tap(find.text('Use saved message'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(GitCommitView), findsOneWidget);
      expect(first.draft, 'saved C');
      expect(first.hasUnpersistedMessageDrafts, isFalse);
      expect(disk.revision, revision);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'one persistent workspace guard protects failed messages while Log is shown',
    (tester) async {
      _desktop(tester);
      final disk = _Disk(), registry = GitDismissalRegistry();
      final first = _session(_Store(disk), dismissal: registry);
      final second = _session(_Store(disk));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.start();
      second.setDraft('saved C');
      await second.flushMessageDrafts();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitWorkspace(session: first)),
        ),
      );
      await tester.pumpAndSettle();
      first.setDraft('local B');
      await first.flushMessageDrafts();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log').first);
      await tester.pumpAndSettle();
      final closing = registry.mayDismiss();
      expect(registry.mayDismiss(), same(closing));
      await tester.pumpAndSettle();
      expect(find.text('Discard messages'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await closing, isFalse);
      expect(first.draft, 'local B');
      expect(disk.values[_messageKey]!.text, 'saved C');
      final discard = registry.mayDismiss();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard messages'));
      await tester.pumpAndSettle();
      expect(await discard, isTrue);
      expect(disk.values[_messageKey]!.text, 'saved C');
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'consuming B preserves other-store C and the independent normal A',
    () async {
      final disk = _Disk();
      final first = _session(_Store(disk)), second = _session(_Store(disk));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      first.setDraft('normal A');
      final submitted = first.setMessageDraft(_amendKey, 'submitted B');
      await first.flushMessageDrafts();
      await second.readMessageDraft(_amendKey);
      second.setMessageDraft(_amendKey, 'other window C');
      await second.flushMessageDrafts();
      expect(await first.clearMessageDraft(submitted), isFalse);
      expect(disk.values[repo.presentationKey]!.text, 'normal A');
      expect(disk.values[_amendKey]!.text, 'other window C');
      expect(first.messageDraft(_amendKey).text, 'other window C');
      expect(first.draftFailure, isNotNull);
      expect(first.hasUnpersistedMessageDrafts, isFalse);
    },
  );

  test(
    'late older write fails closed; explicit review can retain local text',
    () async {
      final disk = _Disk();
      final firstStore = _Store(disk)..delayNext(_messageKey);
      final first = _session(firstStore), second = _session(_Store(disk));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      first.setMessageDraft(_messageKey, 'older B');
      await firstStore.entered!.future;
      second.setMessageDraft(_messageKey, 'newer C');
      await second.flushMessageDrafts();
      firstStore.release!.complete();
      await first.flushMessageDrafts();
      expect(disk.values[_messageKey]!.text, 'newer C');
      expect(first.messageDraft(_messageKey).text, 'older B');
      expect(first.hasUnpersistedMessageDrafts, isTrue);
      expect(first.draftFailure, isNotNull);
      expect(firstStore.writes, isEmpty);
      final review = (await first.reviewMessageDraft(_messageKey))!;
      expect(review.local.text, 'older B');
      expect(review.saved.text, 'newer C');
      expect(await first.resolveMessageDraft(review, useSaved: false), isTrue);
      expect(disk.values[_messageKey]!.text, 'older B');
      expect(first.hasUnpersistedMessageDrafts, isFalse);
      expect(first.draftFailure, isNull);
    },
  );

  test(
    'changed saved review cannot renew consent; explicit reload has no write',
    () async {
      final disk = _Disk();
      final first = _session(_Store(disk)), second = _session(_Store(disk));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      second.setMessageDraft(_messageKey, 'saved C');
      await second.flushMessageDrafts();
      first.setMessageDraft(_messageKey, 'local B');
      await first.flushMessageDrafts();
      final staleReview = (await first.reviewMessageDraft(_messageKey))!;
      second.setMessageDraft(_messageKey, 'saved D');
      await second.flushMessageDrafts();
      expect(
        await first.resolveMessageDraft(staleReview, useSaved: false),
        isFalse,
      );
      expect(disk.values[_messageKey]!.text, 'saved D');
      expect(first.messageDraft(_messageKey).text, 'local B');
      final freshReview = (await first.reviewMessageDraft(_messageKey))!;
      final revision = disk.revision;
      expect(
        await first.resolveMessageDraft(freshReview, useSaved: true),
        isTrue,
      );
      expect(first.messageDraft(_messageKey).text, 'saved D');
      expect(disk.revision, revision);
      expect(first.hasUnpersistedMessageDrafts, isFalse);
    },
  );

  test('new local typing invalidates both saved-review choices', () async {
    final disk = _Disk();
    final first = _session(_Store(disk)), second = _session(_Store(disk));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    second.setMessageDraft(_messageKey, 'saved C');
    await second.flushMessageDrafts();
    first.setMessageDraft(_messageKey, 'local B');
    await first.flushMessageDrafts();
    final review = (await first.reviewMessageDraft(_messageKey))!;
    first.setMessageDraft(_messageKey, 'new local D');
    expect(await first.resolveMessageDraft(review, useSaved: true), isFalse);
    expect(await first.resolveMessageDraft(review, useSaved: false), isFalse);
    await first.flushMessageDrafts();
    expect(first.messageDraft(_messageKey).text, 'new local D');
    expect(disk.values[_messageKey]!.text, 'saved C');
  });

  test(
    'typing during durable clear keeps its own submitted version for next commit',
    () async {
      final store = _Store(_Disk());
      final session = _session(store);
      addTearDown(session.dispose);
      final submitted = session.setMessageDraft(_messageKey, 'submitted B');
      await session.flushMessageDrafts();
      store.delayNext(_messageKey);
      final clearing = session.clearMessageDraft(submitted);
      await store.entered!.future;
      session.setMessageDraft(_messageKey, 'new local C');
      store.release!.complete();
      expect(await clearing, isFalse);
      await session.flushMessageDrafts();
      expect(store.disk.values[_messageKey]!.text, 'new local C');
      expect(session.messageDraft(_messageKey).text, 'new local C');
      expect(
        await session.clearMessageDraft(session.messageDraft(_messageKey)),
        isTrue,
      );
      expect(store.disk.values[_messageKey]!.text, '');
      expect(session.hasUnpersistedMessageDrafts, isFalse);
    },
  );
}
