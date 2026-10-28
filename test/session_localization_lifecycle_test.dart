import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

final class DelayedDrafts implements GitDraftStore {
  final pending = Completer<String?>();
  @override
  Future<String?> read(String key) => pending.future;
  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  test(
    'an active draft-load failure is localized without losing a newer draft',
    () async {
      final base = host(), drafts = DelayedDrafts();
      final requested = <String>[];
      final configured = GitHost(
        present: base.present,
        openDocument: base.openDocument,
        prepareMutation: base.prepareMutation,
        chooseDirectory: base.chooseDirectory,
        notify: base.notify,
        drafts: drafts,
        localize: (message, values) {
          requested.add(message);
          return 'Speicher: ${values['arg0']}';
        },
      );
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: configured,
      );
      addTearDown(session.dispose);
      final started = session.start();
      session.setDraft('My newer message · 東京');
      await Future<void>.delayed(Duration.zero);
      drafts.pending.completeError(StateError('Draft storage unavailable'));
      await started;
      expect(session.draft, 'My newer message · 東京');
      expect(requested, [GitMessages.commitDraftStorageArg0]);
      expect(session.draftFailure?.diagnostic, startsWith('Speicher:'));
    },
  );
  test(
    'a late draft-load failure never localizes through a disposed host',
    () async {
      final base = host(), drafts = DelayedDrafts();
      var alive = true, calls = 0;
      final configured = GitHost(
        present: base.present,
        openDocument: base.openDocument,
        prepareMutation: base.prepareMutation,
        chooseDirectory: base.chooseDirectory,
        notify: base.notify,
        drafts: drafts,
        localize: (message, values) {
          calls++;
          if (!alive) throw StateError('The host view has been disposed');
          return message;
        },
      );
      final session = GitSession(
        client: FixtureClient(),
        repository: repo,
        host: configured,
      );
      final started = session.start();
      session.dispose();
      alive = false;
      final checked = expectLater(started, completes);
      drafts.pending.completeError(StateError('Draft storage unavailable'));
      await checked;
      expect(calls, 0);
    },
  );
}
