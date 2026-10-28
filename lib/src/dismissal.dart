import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'host.dart';
import 'session.dart';
import 'messages.dart';
import 'workflow_ui.dart' show gitConfirm;

/// One registry per host window. Guard requests also protect disposal that does
/// not involve a Navigator, such as switching workspaces or closing the window.
final class GitDismissalRegistry {
  final _guards = <Future<bool> Function()>[];
  Future<bool>? _pending;

  VoidCallback register(Future<bool> Function() guard) {
    _guards.add(guard);
    return () => _guards.remove(guard);
  }

  Future<bool> mayDismiss() => _pending ??= _check().whenComplete(() {
    _pending = null;
  });

  Future<bool> _check() async {
    final reviewed = <Future<bool> Function()>{};
    while (true) {
      final pending = _guards.reversed
          .where((guard) => !reviewed.contains(guard))
          .toList();
      if (pending.isEmpty) return true;
      for (final guard in pending) {
        if (!_guards.contains(guard)) continue;
        if (!await guard()) return false;
        reviewed.add(guard);
      }
    }
  }
}

/// A user dismissal request is distinct from successful operation completion.
/// The host must use maybePop for its Close control and consult its registry
/// before disposing a workspace or OS window.
class GitDraftGuard extends StatefulWidget {
  const GitDraftGuard({
    super.key,
    required this.host,
    required this.canDismiss,
    this.isDismissible,
    this.revisionChanges,
    this.revisionIdentity,
    required this.confirmDiscard,
    required this.child,
  });
  final GitHost host;
  final bool canDismiss;

  /// Read current draft state for host requests that arrive before a rebuild.
  final bool Function()? isDismissible;

  /// Text/session changes update the route predicate synchronously, before the
  /// next frame. The current-state callback must observe this same revision.
  final Listenable? revisionChanges;

  /// Immutable draft/source identity reviewed by the discard confirmation.
  /// A map snapshot is compared by its entries; other values use equality.
  final Object? Function()? revisionIdentity;
  final Future<bool> Function() confirmDiscard;
  final Widget child;

  @override
  State<GitDraftGuard> createState() => _GitDraftGuardState();
}

final class _GitDraftPopEntry extends PopEntry<Object?> {
  _GitDraftPopEntry(bool canPop, this.onBlocked)
    : canPopNotifier = ValueNotifier(canPop);
  @override
  final ValueNotifier<bool> canPopNotifier;
  final VoidCallback onBlocked;
  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && !canPopNotifier.value) onBlocked();
  }
}

class _GitDraftGuardState extends State<GitDraftGuard> {
  VoidCallback? _unregister;
  Future<bool>? _pending;
  Future<void>? _closing;
  int _inputRevision = 0;
  ModalRoute<Object?>? _route;
  late final _GitDraftPopEntry _entry;
  bool get _canDismiss => widget.isDismissible?.call() ?? widget.canDismiss;

  @override
  void initState() {
    super.initState();
    _entry = _GitDraftPopEntry(_canDismiss, () => unawaited(_requestClose()));
    widget.revisionChanges?.addListener(_revisionChanged);
    _register();
  }

  void _register() {
    _unregister = widget.host.registerDismissalGuard?.call(_mayDismiss);
  }

  void _synchronizeRoute() => _entry.canPopNotifier.value = _canDismiss;
  void _revisionChanged() {
    _inputRevision++;
    _synchronizeRoute();
  }

  Object? get _identity => widget.revisionIdentity?.call() ?? _inputRevision;
  bool _sameIdentity(Object? before, Object? after) =>
      before is Map && after is Map
      ? mapEquals(before, after)
      : before == after;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<Object?>(context);
    if (_route != route) {
      _route?.unregisterPopEntry(_entry);
      _route = route;
      route?.registerPopEntry(_entry);
    }
  }

  @override
  void didUpdateWidget(GitDraftGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revisionChanges != widget.revisionChanges) {
      oldWidget.revisionChanges?.removeListener(_revisionChanged);
      widget.revisionChanges?.addListener(_revisionChanged);
    }
    if (oldWidget.host != widget.host) {
      _unregister?.call();
      _register();
    }
    _synchronizeRoute();
  }

  Future<bool> _mayDismiss() {
    if (!mounted || _canDismiss) return Future.value(true);
    return _pending ??= widget
        .confirmDiscard()
        .then((approved) {
          return mounted && approved;
        })
        .whenComplete(() => _pending = null);
  }

  Future<void> _requestClose() =>
      _closing ??= _closeRoute().whenComplete(() => _closing = null);

  Future<void> _closeRoute() async {
    final route = _route;
    if (route?.isCurrent != true) return;
    final revision = _identity;
    if (!await _mayDismiss() ||
        !mounted ||
        route != _route ||
        route?.isCurrent != true)
      return;
    if (!_sameIdentity(revision, _identity) && !_canDismiss) return;
    // Authorize only this entry for this request. Other guards retain their
    // veto. A newer input notification revokes this authorization immediately.
    final navigator = Navigator.of(context);
    _entry.canPopNotifier.value = true;
    try {
      if (!mounted ||
          !navigator.mounted ||
          route != _route ||
          route?.isCurrent != true)
        return;
      await navigator.maybePop();
    } finally {
      // maybePop may be handled but vetoed; never assume the route disappeared,
      // retry against its parent, or leave this draft authorized for later.
      if (mounted && route == _route) _synchronizeRoute();
    }
  }

  @override
  void dispose() {
    widget.revisionChanges?.removeListener(_revisionChanged);
    _route?.unregisterPopEntry(_entry);
    _entry.canPopNotifier.dispose();
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A host window keeps this guard alive when Commit is hidden or unmounted.
/// The live owner list also invalidates consent if another worktree attaches.
Future<bool> gitMayDismissMessageDrafts(
  BuildContext context,
  Iterable<GitSession> Function() liveSessions,
) async {
  Map<(GitDraftStore, String), GitSession> owners() => {
    for (final session in liveSessions())
      (session.host.drafts, session.repository.presentationKey): session,
  };
  var current = owners();
  for (final session in current.values) {
    await session.flushMessageDrafts();
  }
  if (!context.mounted) return false;
  current = owners();
  final dirty = current.values.where(
    (session) => session.hasUnpersistedMessageDrafts,
  );
  if (dirty.isEmpty) return true;
  final reviewed = {
    for (final entry in current.entries)
      entry.key: entry.value.messageDraftRevisions,
  };
  final session = dirty.first;
  final approved = await gitConfirm(
    context,
    session,
    GitMessages.discardUnsavedCommitMessages,
    session.host.message(GitMessages.messagesCouldNotBeSavedStayInThisWindow),
    action: GitMessages.discardCommitMessages,
  );
  if (!approved || !context.mounted) return false;
  final latest = owners();
  return latest.length == reviewed.length &&
      latest.entries.every(
        (entry) =>
            mapEquals(reviewed[entry.key], entry.value.messageDraftRevisions),
      );
}
