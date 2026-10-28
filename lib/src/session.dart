import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/foundation.dart';
import 'host.dart';

/// An immutable version of one message slot. An amend slot belongs to its
/// reviewed HEAD, independently of the normal commit message.
final class GitMessageDraft {
  const GitMessageDraft._(
    this.key,
    this.text,
    this.revision,
    this._owner,
    this._persisted,
  );
  final String key, text;
  final int revision;
  final Object _owner;
  final Future<GitStoredDraft?> _persisted;
}

/// A comparison is immutable consent for one local and one saved message.
final class GitMessageDraftReview {
  const GitMessageDraftReview(this.local, this.saved);
  final GitMessageDraft local;
  final GitStoredDraft saved;
}

final class _MessageDraftSlot {
  String? text;
  int revision = 0, readGeneration = 0, persistedRevision = 0;
  Future<void> pending = Future<void>.value();
  Future<GitStoredDraft?> persisted = Future<GitStoredDraft?>.value();
  GitStoredDraft? stored, conflict;
}

// A host can attach several tabs to the same worktree. Ownership and durable
// write order belong to its existing draft store, rather than one tab's lifetime.
final _draftStores = Expando<_MessageDraftState>('Git message draft ownership');

final class _MessageDraftState extends ChangeNotifier {
  final slots = <String, _MessageDraftSlot>{};
  final errors = <String, GitException>{};
  final views = <String, Map<String, Object>>{};
  final viewWrites = <String, Future<void>>{};
  void changed() => notifyListeners();
}

/// One instance per attached worktree surface. Outstanding callbacks retain this
/// identity; changing a host tab never retargets an operation.
final class GitSession extends ChangeNotifier {
  GitSession({
    required this.client,
    required this.repository,
    required this.host,
  }) {
    _draftState.addListener(_draftsChanged);
  }
  final GitClient client;
  final RepositoryId repository;
  final GitHost host;
  GitSnapshot? snapshot;
  GitException? failure;
  GitException? _operationFailure;
  bool _ownsMessageKey(String key) =>
      key == repository.presentationKey ||
      key.startsWith('${repository.presentationKey}:amend:');
  GitException? get draftFailure => _draftState.errors.entries
      .where((entry) => _ownsMessageKey(entry.key))
      .map((entry) => entry.value)
      .firstOrNull;
  GitProgress? progress;
  GitOutcome? outcome;
  Future<void> Function(bool push)? commitAction;
  bool Function()? canCommit;
  bool loading = true, refreshing = false, running = false, _disposed = false;
  int _generation = 0;
  Future<void>? _refresh;
  bool _refreshQueued = false;
  StreamSubscription<void>? _watch;
  GitCancellation? _readCancellation, _mutationCancellation;
  late final _MessageDraftState _draftState = _draftStores[host.drafts] ??=
      _MessageDraftState();
  Map<String, _MessageDraftSlot> get _messageDrafts => _draftState.slots;
  void _draftsChanged() {
    if (!_disposed) notifyListeners();
  }

  _MessageDraftSlot _messageSlot(String key) =>
      _messageDrafts.putIfAbsent(key, _MessageDraftSlot.new);
  String get draft => _messageSlot(repository.presentationKey).text ?? '';
  bool _authorizedInspection = false;
  Future<GitSnapshot> readStatus({GitCancellation? cancellation}) =>
      client.status(
        repository,
        cancellation: cancellation,
        policy: _authorizedInspection
            ? GitReadPolicy.authorized
            : GitReadPolicy.restricted,
      );
  Future<void> authorizeInspection() async {
    if (_disposed || host.prepareInspection == null) return;
    try {
      if (await host.prepareInspection!(
            repository,
            const GitInspection(GitInspectionKind.workingStatus),
          ) &&
          !_disposed) {
        _authorizedInspection = true;
        await refresh(clearOperationFailure: true);
      }
    } on Object catch (error) {
      reportFailure(error);
    }
  }

  void restrictInspection() {
    _authorizedInspection = false;
  }

  Map<String, Object> get viewState =>
      _draftState.views.putIfAbsent(repository.presentationKey, () => {});
  set viewState(Map<String, Object> value) =>
      _draftState.views[repository.presentationKey] = value;
  double split(String name, double fallback) => switch (viewState[name]) {
    final num value when value.isFinite => value.toDouble().clamp(.05, .95),
    _ => fallback,
  };
  bool option(String name, bool fallback) => switch (viewState[name]) {
    final bool value => value,
    _ => fallback,
  };
  void reportFailure(Object error) {
    if (!_disposed) {
      failure = _operationFailure = _failure(error);
      notifyListeners();
    }
  }

  Future<void> get _viewStateWrite =>
      _draftState.viewWrites[repository.presentationKey] ??
      Future<void>.value();
  set _viewStateWrite(Future<void> value) =>
      _draftState.viewWrites[repository.presentationKey] = value;
  void setViewState(String name, Object value) {
    viewState = {...viewState, name: value};
    final write = host.writeViewState;
    if (write != null) {
      final captured = viewState;
      _viewStateWrite = _viewStateWrite
          .then((_) => write(repository.presentationKey, captured))
          .catchError((Object error) {
            if (!_disposed) {
              failure = GitException(
                GitErrorCode.commandFailed,
                diagnostic: host.message(
                  GitMessages.viewPreferencesCouldNotBeSavedArg0,
                  values: {'arg0': sanitizeGitDiagnostic('$error')},
                ),
              );
              notifyListeners();
            }
          });
    }
  }

  int get draftRevision => _messageSlot(repository.presentationKey).revision;
  bool get canWriteMetadata => snapshot?.capabilities.writeMetadata == true;
  Future<void> start() async {
    try {
      await readMessageDraft(repository.presentationKey);
    } on Object catch (error) {
      if (_disposed) return;
      _draftState.errors[repository.presentationKey] = GitException(
        GitErrorCode.commandFailed,
        diagnostic: host.message(
          GitMessages.commitDraftStorageArg0,
          values: {'arg0': sanitizeGitDiagnostic('$error')},
        ),
      );
    }
    if (_disposed) return;
    try {
      final values = await host.readViewState?.call(repository.presentationKey);
      if (values != null && !_disposed) {
        final retained = <String>{
          if (values['commitAmendDraftTargets'] case final List saved)
            ...saved.whereType<String>(),
          if (viewState['commitAmendDraftTargets'] case final List local)
            for (final target in local.whereType<String>())
              if (_messageDrafts['${repository.presentationKey}:amend:$target']
                      ?.text
                      ?.isNotEmpty ==
                  true)
                target,
        };
        viewState = {
          ...values,
          ...viewState,
          if (retained.isNotEmpty ||
              values.containsKey('commitAmendDraftTargets'))
            'commitAmendDraftTargets': retained.toList(),
        };
      }
    } on Object catch (error) {
      if (!_disposed)
        failure = GitException(
          GitErrorCode.commandFailed,
          diagnostic: host.message(
            GitMessages.viewPreferencesCouldNotBeReadArg0,
            values: {'arg0': sanitizeGitDiagnostic('$error')},
          ),
        );
    }
    await refresh();
    if (_disposed) return;
    _installWatch();
  }

  void _installWatch() {
    _watch ??= client
        .watch(repository)
        .listen(
          (_) => unawaited(refresh()),
          onError: (Object e) {
            if (!_disposed) {
              failure = _failure(e);
              notifyListeners();
            }
          },
          onDone: () {
            _watch = null;
            if (!_disposed) {
              failure = const GitException(GitErrorCode.disconnected);
              notifyListeners();
            }
          },
        );
  }

  /// Reads are generation-bound too: a slow load cannot replace a newer edit.
  /// Durable versions also bind independent windows, not only these local slots.
  Future<GitMessageDraft> readMessageDraft(String key) async {
    final slot = _messageSlot(key);
    if (slot.text != null) return messageDraft(key);
    final revision = slot.revision, generation = ++slot.readGeneration;
    await slot.pending;
    final store = host.drafts;
    final saved = store is GitVersionedDraftStore
        ? await store.readVersioned(key)
        : null;
    final text = saved?.text ?? (saved == null ? await store.read(key) : null);
    if (slot.revision == revision &&
        generation == slot.readGeneration &&
        slot.text == null) {
      slot.text = text ?? '';
      slot.stored = saved;
      slot.persisted = Future.value(saved);
      slot.persistedRevision = revision;
      _draftState.changed();
    }
    return messageDraft(key);
  }

  GitMessageDraft messageDraft(String key) {
    final slot = _messageSlot(key);
    return GitMessageDraft._(
      key,
      slot.text ?? '',
      slot.revision,
      slot,
      slot.persisted,
    );
  }

  bool _matchesDraft(GitMessageDraft value) {
    final current = _messageSlot(value.key);
    return identical(current, value._owner) &&
        current.revision == value.revision &&
        current.text == value.text;
  }

  void _draftSaveFailed(String key, int revision, Object error) {
    final slot = _messageSlot(key);
    if (slot.revision != revision) return;
    _draftState.errors[key] = GitException(
      error is GitDraftConflict
          ? GitErrorCode.staleReview
          : GitErrorCode.commandFailed,
      diagnostic: error is GitDraftConflict
          ? host.message(GitMessages.commitDraftChangedInAnotherWindow)
          : host.message(
              GitMessages.commitDraftWasRetainedInMemoryButCouldNotBe,
              values: {'arg0': sanitizeGitDiagnostic('$error')},
            ),
    );
    _draftState.changed();
  }

  GitMessageDraft setMessageDraft(String key, String value) {
    final slot = _messageSlot(key);
    slot.text = value;
    final revision = ++slot.revision;
    final persisted = Completer<GitStoredDraft?>();
    slot.persisted = persisted.future;
    slot.pending = slot.pending.then((_) async {
      try {
        final store = host.drafts;
        GitStoredDraft? written;
        if (store is GitVersionedDraftStore) {
          final result = await store.compareAndWrite(
            key,
            expectedVersion:
                slot.stored?.version ?? GitStoredDraft.absentVersion,
            text: value,
          );
          if (!result.written) {
            slot.conflict = result.current;
            throw GitDraftConflict(key, result.current);
          }
          slot.stored = written = result.current;
          slot.conflict = null;
        } else {
          await store.write(key, value);
        }
        slot.persistedRevision = revision;
        if (slot.revision == revision) _draftState.errors.remove(key);
        persisted.complete(written);
        _draftState.changed();
      } on Object catch (error) {
        persisted.complete(null);
        _draftSaveFailed(key, revision, error);
      }
    });
    final version = messageDraft(key);
    _draftState.changed();
    return version;
  }

  /// Consume only the submitted local revision AND its exact durable version.
  /// A surviving message from another window stays in its original slot.
  Future<bool> clearMessageDraft(GitMessageDraft submitted) {
    final slot = _messageSlot(submitted.key);
    if (!_matchesDraft(submitted)) return Future.value(false);
    final complete = Completer<bool>();
    slot.pending = slot.pending.then((_) async {
      if (!_matchesDraft(submitted)) {
        complete.complete(false);
        return;
      }
      try {
        final store = host.drafts;
        if (store is GitVersionedDraftStore) {
          final written = await submitted._persisted;
          final result = written == null
              ? GitDraftWriteResult(
                  written: false,
                  current: await store.readVersioned(submitted.key),
                )
              : await store.compareAndWrite(
                  submitted.key,
                  expectedVersion: written.version,
                  text: '',
                );
          if (!result.written) {
            // The submitted message has committed. If local typing has not
            // advanced, expose the surviving saved message without retargeting
            // an amend. A newer local edit remains untouched and recoverable.
            if (_matchesDraft(submitted)) {
              slot.text = result.current.text ?? '';
              slot.stored = result.current;
              slot.persisted = Future.value(result.current);
              slot.persistedRevision = ++slot.revision;
              slot.conflict = null;
              _draftSaveFailed(
                submitted.key,
                slot.revision,
                GitDraftConflict(submitted.key, result.current),
              );
            }
            complete.complete(false);
            return;
          }
          slot.stored = result.current;
          if (_matchesDraft(submitted)) {
            slot.persisted = Future.value(result.current);
          }
        } else {
          await store.write(submitted.key, '');
        }
        if (_matchesDraft(submitted)) {
          slot.text = '';
          slot.persistedRevision = ++slot.revision;
          slot.conflict = null;
          _draftState.errors.remove(submitted.key);
          _draftState.changed();
          complete.complete(true);
        } else {
          complete.complete(false);
        }
      } on Object catch (error) {
        _draftSaveFailed(submitted.key, submitted.revision, error);
        complete.complete(false);
      }
    });
    return complete.future;
  }

  bool get hasUnpersistedMessageDrafts => _messageDrafts.entries.any(
    (entry) =>
        _ownsMessageKey(entry.key) &&
        entry.value.text != null &&
        entry.value.persistedRevision < entry.value.revision,
  );
  Map<String, int> get messageDraftRevisions => {
    for (final entry in _messageDrafts.entries)
      if (_ownsMessageKey(entry.key)) entry.key: entry.value.revision,
  };
  String? reviewableMessageDraft(String preferred) {
    if (host.drafts is! GitVersionedDraftStore) return null;
    if (_ownsMessageKey(preferred) &&
        _draftState.errors.containsKey(preferred)) {
      return preferred;
    }
    return _draftState.errors.keys.where(_ownsMessageKey).firstOrNull;
  }

  Future<GitMessageDraftReview?> reviewMessageDraft(String key) async {
    final store = host.drafts;
    if (store is! GitVersionedDraftStore) return null;
    await _messageSlot(key).pending;
    final local = messageDraft(key);
    final saved = await store.readVersioned(key);
    return _matchesDraft(local) ? GitMessageDraftReview(local, saved) : null;
  }

  /// Both choices are bound to the reviewed local and saved versions. Keeping
  /// this window's message is an explicit conditional replacement, never retry.
  Future<bool> resolveMessageDraft(
    GitMessageDraftReview review, {
    required bool useSaved,
  }) {
    final store = host.drafts;
    if (store is! GitVersionedDraftStore || !_matchesDraft(review.local)) {
      return Future.value(false);
    }
    final slot = _messageSlot(review.local.key);
    final complete = Completer<bool>();
    slot.pending = slot.pending.then((_) async {
      if (!_matchesDraft(review.local)) {
        complete.complete(false);
        return;
      }
      try {
        final result = useSaved
            ? GitDraftWriteResult(
                written: false,
                current: await store.readVersioned(review.local.key),
              )
            : await store.compareAndWrite(
                review.local.key,
                expectedVersion: review.saved.version,
                text: review.local.text,
              );
        if ((useSaved && result.current.version != review.saved.version) ||
            (!useSaved && !result.written)) {
          slot.conflict = result.current;
          _draftSaveFailed(
            review.local.key,
            review.local.revision,
            GitDraftConflict(review.local.key, result.current),
          );
          complete.complete(false);
          return;
        }
        slot.stored = result.current;
        slot.conflict = null;
        if (_matchesDraft(review.local)) {
          if (useSaved) slot.text = result.current.text ?? '';
          slot.persistedRevision = ++slot.revision;
          slot.persisted = Future.value(result.current);
          _draftState.errors.remove(review.local.key);
          _draftState.changed();
        }
        complete.complete(true);
      } on Object catch (error) {
        _draftSaveFailed(review.local.key, review.local.revision, error);
        complete.complete(false);
      }
    });
    return complete.future;
  }

  Future<void> flushMessageDrafts() async {
    while (true) {
      final pending = [for (final slot in _messageDrafts.values) slot.pending];
      await Future.wait(pending);
      final current = [for (final slot in _messageDrafts.values) slot.pending];
      if (listEquals(pending, current)) return;
    }
  }

  void setDraft(String value) {
    setMessageDraft(repository.presentationKey, value);
  }

  Future<void> refresh({bool clearOperationFailure = false}) {
    if (clearOperationFailure) {
      _operationFailure = null;
      failure = null;
    }
    if (running) {
      _refreshQueued = true;
      return Future<void>.value();
    }
    if (_refresh case final current?) return current;
    late Future<void> current;
    current = _load().whenComplete(() {
      if (identical(_refresh, current)) _refresh = null;
    });
    _refresh = current;
    return current;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _readCancellation?.cancel();
    final cancel = _readCancellation = GitCancellation();
    refreshing = true;
    if (!_disposed) notifyListeners();
    try {
      final result = await readStatus(cancellation: cancel);
      if (!_disposed && generation == _generation) {
        snapshot = result;
        failure = _operationFailure;
        _installWatch();
      }
    } on Object catch (error) {
      if (!_disposed && generation == _generation) failure = _failure(error);
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<GitOutcome?> mutate(GitMutation request) async {
    if (running || _disposed) return null;
    if (snapshot != null &&
        (!canWriteMetadata ||
            request.replacesWorkingFiles &&
                !snapshot!.capabilities.replaceWorkingFiles)) {
      reportFailure(
        const GitException(
          GitErrorCode.readOnly,
          diagnostic: GitMessages
              .theReviewedRepositoryIsReadOnlyForThisOperationHistory,
        ),
      );
      return null;
    }
    _generation++;
    _readCancellation?.cancel();
    _refresh = null;
    refreshing = false;
    running = true;
    failure = null;
    _operationFailure = null;
    outcome = null;
    final cancel = _mutationCancellation = GitCancellation();
    notifyListeners();
    try {
      if (!await host.prepareMutation(repository, request) ||
          _disposed ||
          cancel.isCancelled)
        return null;
      final result = await client.mutate(
        repository,
        request,
        cancellation: cancel,
        onProgress: (value) {
          if (!_disposed) {
            progress = value;
            notifyListeners();
          }
        },
      );
      if (!_disposed) {
        snapshot = result.snapshot ?? snapshot;
        outcome = result;
        failure = _operationFailure = result.error;
      }
      try {
        await host.afterMutation?.call(repository, result);
      } on Object catch (error) {
        reportFailure(
          GitException(
            GitErrorCode.commandFailed,
            diagnostic: host.message(
              GitMessages
                  .gitReturnedArg0TheApplicationCouldNotRefreshItsDocuments,
              values: {
                'arg0': host.message(gitEnumMessage(result.phase)),
                'arg1': sanitizeGitDiagnostic('$error'),
              },
            ),
          ),
        );
      }
      return result;
    } on Object catch (error) {
      if (!_disposed) failure = _operationFailure = _failure(error);
      await refresh();
      return null;
    } finally {
      if (!_disposed) {
        running = false;
        progress = null;
        notifyListeners();
        if (_refreshQueued) {
          _refreshQueued = false;
          unawaited(refresh());
        }
      }
    }
  }

  void cancel() => _mutationCancellation?.cancel();
  GitException _failure(Object error) => error is GitException
      ? error
      : GitException(
          GitErrorCode.disconnected,
          diagnostic: sanitizeGitDiagnostic('$error'),
        );
  @override
  void dispose() {
    _disposed = true;
    _draftState.removeListener(_draftsChanged);
    _generation++;
    _readCancellation?.cancel();
    // Closing a surface does not cancel a mutation or abort the sequencer.
    unawaited(_watch?.cancel());
    super.dispose();
  }
}
