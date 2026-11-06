// Git workflow feedback belongs to the same native surface in both hosts.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'linux_native.dart';

final _notificationQueues = Expando<_GitNotificationQueue>();

/// Shows window-local Git feedback without changing document or keyboard focus.
/// Hosts forward already localized messages; no host supplies a toast design.
void showGitNotification(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 5),
}) {
  if (!context.mounted || message.trim().isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  // A completed operation can outlive its window. Feedback never changes its
  // result or creates a substitute application surface after dismissal.
  if (overlay == null || !overlay.mounted) return;
  var queue = _notificationQueues[overlay];
  if (queue == null || queue.disposed) {
    queue = _GitNotificationQueue();
    _notificationQueues[overlay] = queue;
    final controller = queue;
    overlay.insert(
      OverlayEntry(
        builder: (_) => _GitNotificationLayer(
          queue: controller,
          onDispose: () {
            if (identical(_notificationQueues[overlay], controller)) {
              _notificationQueues[overlay] = null;
            }
          },
        ),
      ),
    );
  }
  queue.add(context, message.trim(), duration);
}

final class _GitNotification {
  const _GitNotification(this.id, this.owner, this.message, this.duration);
  final int id;
  final BuildContext owner;
  final String message;
  final Duration duration;
}

final class _GitNotificationQueue extends ChangeNotifier {
  final _pending = ListQueue<_GitNotification>();
  _GitNotification? active;
  Timer? _timer;
  int _nextId = 0;
  bool disposed = false;

  void add(BuildContext owner, String message, Duration duration) {
    if (disposed) return;
    final current = active;
    if (current != null &&
        current.owner == owner &&
        current.message == message) {
      _startTimer(duration);
      return;
    }
    _pending.add(_GitNotification(_nextId++, owner, message, duration));
    if (active == null) _advance();
  }

  void _startTimer(Duration duration) {
    _timer?.cancel();
    final id = active?.id;
    if (duration > Duration.zero) _timer = Timer(duration, () => dismiss(id));
  }

  void dismiss([int? expectedId]) {
    if (disposed || (expectedId != null && active?.id != expectedId)) return;
    _timer?.cancel();
    active = null;
    _advance();
  }

  void _advance() {
    while (_pending.isNotEmpty) {
      final candidate = _pending.removeFirst();
      if (!candidate.owner.mounted) continue;
      active = candidate;
      _startTimer(candidate.duration);
      break;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    _timer?.cancel();
    _pending.clear();
    active = null;
    super.dispose();
  }
}

final class _GitNotificationLayer extends StatefulWidget {
  const _GitNotificationLayer({required this.queue, required this.onDispose});
  final _GitNotificationQueue queue;
  final VoidCallback onDispose;
  @override
  State<_GitNotificationLayer> createState() => _GitNotificationLayerState();
}

final class _GitNotificationLayerState extends State<_GitNotificationLayer> {
  @override
  void initState() {
    super.initState();
    widget.queue.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.queue.removeListener(_changed);
    widget.queue.dispose();
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.queue.active;
    return Stack(
      children: [
        Positioned(
          left: GitSpacing.lg,
          right: GitSpacing.lg,
          bottom: GitSpacing.lg,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1,
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: active == null
                    ? const SizedBox.shrink()
                    : NativeGitNotificationSurface(
                        key: ValueKey(active.id),
                        message: active.message,
                        onDismiss: () => widget.queue.dismiss(active.id),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
