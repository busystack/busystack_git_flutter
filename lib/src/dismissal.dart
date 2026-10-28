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
    required this.confirmDiscard,
    required this.child,
  });
  final GitHost host;
  final bool canDismiss;

  /// Read current draft state for host requests that arrive before a rebuild.
  final bool Function()? isDismissible;
  final Future<bool> Function() confirmDiscard;
  final Widget child;

  @override
  State<GitDraftGuard> createState() => _GitDraftGuardState();
}

class _GitDraftGuardState extends State<GitDraftGuard> {
  VoidCallback? _unregister;
  Future<bool>? _pending;

  @override
  void initState() {
    super.initState();
    _register();
  }

  void _register() {
    _unregister = widget.host.registerDismissalGuard?.call(_mayDismiss);
  }

  @override
  void didUpdateWidget(GitDraftGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _unregister?.call();
      _register();
    }
  }

  Future<bool> _mayDismiss() {
    if (!mounted) return Future.value(true);
    if (widget.isDismissible?.call() ?? widget.canDismiss) {
      return Future.value(true);
    }
    return _pending ??= widget
        .confirmDiscard()
        .then((approved) {
          return mounted && approved;
        })
        .whenComplete(() => _pending = null);
  }

  Future<void> _requestClose() async {
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    if (await _mayDismiss() && mounted && route?.isCurrent == true) {
      gitCompleteSurface(context);
    }
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: widget.canDismiss,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_requestClose());
    },
    child: widget.child,
  );
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
