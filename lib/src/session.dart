import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/foundation.dart';
import 'host.dart';

/// One instance per attached worktree surface. Outstanding callbacks retain this
/// identity; changing a host tab never retargets an operation.
final class GitSession extends ChangeNotifier {
  GitSession({
    required this.client,
    required this.repository,
    required this.host,
  });
  final GitClient client;
  final RepositoryId repository;
  final GitHost host;
  GitSnapshot? snapshot;
  GitException? failure;
  GitException? _operationFailure;
  GitException? draftFailure;
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
  String draft = '';
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

  Map<String, Object> viewState = {};
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

  void setViewState(String name, Object value) {
    viewState = {...viewState, name: value};
    final write = host.writeViewState;
    if (write != null)
      unawaited(
        write(repository.presentationKey, viewState).catchError((Object error) {
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
        }),
      );
  }

  var _draftGeneration = 0;
  int get draftRevision => _draftGeneration;
  bool get canWriteMetadata => snapshot?.capabilities.writeMetadata == true;
  Future<void> start() async {
    final draftGeneration = _draftGeneration;
    String? saved;
    try {
      saved = await host.drafts.read(repository.presentationKey);
    } on Object catch (error) {
      if (_disposed) return;
      draftFailure = GitException(
        GitErrorCode.commandFailed,
        diagnostic: host.message(
          GitMessages.commitDraftStorageArg0,
          values: {'arg0': sanitizeGitDiagnostic('$error')},
        ),
      );
    }
    if (_disposed) return;
    if (saved != null && draftGeneration == _draftGeneration) draft = saved;
    try {
      final values = await host.readViewState?.call(repository.presentationKey);
      if (values != null && !_disposed) viewState = {...values, ...viewState};
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

  void setDraft(String value) {
    draft = value;
    final generation = ++_draftGeneration;
    unawaited(
      host.drafts
          .write(repository.presentationKey, value)
          .then(
            (_) {
              if (!_disposed &&
                  generation == _draftGeneration &&
                  draftFailure != null) {
                draftFailure = null;
                notifyListeners();
              }
            },
            onError: (Object error) {
              if (!_disposed && generation == _draftGeneration) {
                draftFailure = GitException(
                  GitErrorCode.commandFailed,
                  diagnostic: host.message(
                    GitMessages.commitDraftWasRetainedInMemoryButCouldNotBe,
                    values: {'arg0': sanitizeGitDiagnostic('$error')},
                  ),
                );
                notifyListeners();
              }
            },
          ),
    );
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
    _generation++;
    _readCancellation?.cancel();
    // Closing a surface does not cancel a mutation or abort the sequencer.
    unawaited(_watch?.cancel());
    super.dispose();
  }
}
