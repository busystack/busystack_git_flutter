import 'dart:async';
import 'package:flutter/material.dart';
import 'host.dart';

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
    for (final guard in _guards.reversed.toList()) {
      if (_guards.contains(guard) && !await guard()) return false;
    }
    return true;
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
    required this.confirmDiscard,
    required this.child,
  });
  final GitHost host;
  final bool canDismiss;
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
    if (widget.canDismiss) return Future.value(true);
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
