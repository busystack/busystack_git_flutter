import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _DelayedStore implements GitDraftStore {
  final values = <String, String>{};
  final writes = <({String key, String value, Completer<void> done})>[];
  Completer<String?>? pendingRead;
  bool delayReads = false;
  final reads = <Completer<String?>>[];
  @override
  Future<String?> read(String key) {
    if (delayReads) {
      final read = Completer<String?>();
      reads.add(read);
      return read.future;
    }
    return pendingRead?.future ?? Future.value(values[key]);
  }

  @override
  Future<void> write(String key, String value) async {
    final done = Completer<void>();
    writes.add((key: key, value: value, done: done));
    await done.future;
    values[key] = value;
  }
}

GitSession _session(_DelayedStore store) {
  final base = host();
  return GitSession(
    client: FixtureClient(),
    repository: repo,
    host: GitHost(
      present: base.present,
      openDocument: base.openDocument,
      prepareMutation: base.prepareMutation,
      chooseDirectory: base.chooseDirectory,
      notify: base.notify,
      drafts: store,
    ),
  );
}

void main() {
  test(
    'sessions sharing one host store share slot ownership and durable order',
    () async {
      final store = _DelayedStore();
      final first = _session(store), second = _session(store);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      first.setDraft('older A');
      final submitted = first.setMessageDraft('amend', 'submitted B');
      await Future<void>.delayed(Duration.zero);
      final submittedInFirstTab = first.setMessageDraft('amend', 'older C');
      second.setMessageDraft('amend', 'newest D in another tab');
      expect(first.clearMessageDraft(submittedInFirstTab), isFalse);
      expect(first.clearMessageDraft(submitted), isFalse);
      expect(first.messageDraft('amend').text, 'newest D in another tab');
      expect(second.messageDraft('amend').text, 'newest D in another tab');
      await Future<void>.delayed(Duration.zero);
      expect(store.writes.where((write) => write.key == 'amend'), hasLength(1));
      final messages = <String>[];
      for (var i = 0; i < 3; i++) {
        final write = store.writes.lastWhere((write) => write.key == 'amend');
        messages.add(write.value);
        write.done.complete();
        await Future<void>.delayed(Duration.zero);
      }
      expect(messages, ['submitted B', 'older C', 'newest D in another tab']);
      store.writes
          .firstWhere((write) => write.key == repo.presentationKey)
          .done
          .complete();
      await first.flushMessageDrafts();
      expect(store.values['amend'], 'newest D in another tab');
      expect(store.values[repo.presentationKey], 'older A');
    },
  );

  test('out-of-order reads cannot publish the obsolete slot value', () async {
    final store = _DelayedStore()..delayReads = true;
    final session = _session(store);
    addTearDown(session.dispose);
    final older = session.readMessageDraft('amend');
    final newer = session.readMessageDraft('amend');
    await Future<void>.delayed(Duration.zero);
    expect(store.reads, hasLength(2));
    store.reads.last.complete('newest read');
    expect((await newer).text, 'newest read');
    store.reads.first.complete('obsolete read');
    expect((await older).text, 'newest read');
    expect(session.messageDraft('amend').text, 'newest read');
  });

  test(
    'failed older persistence does not block a newer draft or report its failure',
    () async {
      final store = _DelayedStore();
      final session = _session(store);
      addTearDown(session.dispose);
      session.setDraft('older');
      session.setDraft('newer');
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(1));
      store.writes.first.done.completeError(StateError('older failed'));
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(2));
      expect(session.draftFailure, isNull);
      store.writes.last.done.complete();
      await session.flushMessageDrafts();
      expect(store.values[repo.presentationKey], 'newer');
      expect(session.draftFailure, isNull);
    },
  );

  test(
    'per-slot persistence orders edits and conditional clear before newer edits',
    () async {
      final store = _DelayedStore(), session = _session(_DelayedStore());
      session.dispose();
      final target = _session(store);
      addTearDown(target.dispose);
      const amendKey = 'reviewed-head-amend';
      target.setDraft('normal A');
      final submitted = target.setMessageDraft(amendKey, 'submitted B');
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(2)); // Different slots are independent.
      target.setMessageDraft(amendKey, 'newer C');
      expect(target.clearMessageDraft(submitted), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(2)); // C cannot race ahead of B.
      store.writes.firstWhere((w) => w.key == amendKey).done.complete();
      await Future<void>.delayed(Duration.zero);
      expect(store.writes.where((w) => w.key == amendKey).map((w) => w.value), [
        'submitted B',
        'newer C',
      ]);
      for (final write in store.writes) {
        if (!write.done.isCompleted) write.done.complete();
      }
      await target.flushMessageDrafts();
      expect(store.values[amendKey], 'newer C');
      expect(store.values[repo.presentationKey], 'normal A');

      final current = target.messageDraft(amendKey);
      expect(target.clearMessageDraft(current), isTrue);
      target.setMessageDraft(amendKey, 'after clear D');
      await Future<void>.delayed(Duration.zero);
      expect(store.writes.last.value, '');
      store.writes.last.done.complete();
      await Future<void>.delayed(Duration.zero);
      expect(store.writes.last.value, 'after clear D');
      store.writes.last.done.complete();
      await target.flushMessageDrafts();
      expect(store.values[amendKey], 'after clear D');
    },
  );

  test('a delayed slot read cannot replace a newer edit', () async {
    final store = _DelayedStore()..pendingRead = Completer<String?>();
    final target = _session(store);
    addTearDown(target.dispose);
    final read = target.readMessageDraft('amend');
    await Future<void>.delayed(Duration.zero);
    target.setMessageDraft('amend', 'typed while loading');
    store.pendingRead!.complete('obsolete stored value');
    expect((await read).text, 'typed while loading');
    await Future<void>.delayed(Duration.zero);
    store.writes.single.done.complete();
    await target.flushMessageDrafts();
    expect(store.values['amend'], 'typed while loading');
  });
}
