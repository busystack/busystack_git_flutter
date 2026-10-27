import 'messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Keeps an immediate undo reversible, including an IME commit or cancellation.
/// Uses Flutter's public overridable text actions and editing entry point.
final class GitTextUndo extends StatefulWidget {
  const GitTextUndo({
    super.key,
    required this.controller,
    required this.child,
    this.history,
    this.enabled = true,
  });
  final TextEditingController controller;
  final UndoHistoryController? history;
  final bool enabled;
  final Widget child;

  @override
  State<GitTextUndo> createState() => _GitTextUndoState();
}

final class _GitTextUndoState extends State<GitTextUndo> {
  final _child = GlobalKey();
  final _undo = <TextEditingValue>[], _redo = <TextEditingValue>[];
  late TextEditingValue _current;
  TextEditingValue? _beforeComposition;
  bool _applying = false, _notificationQueued = false;
  bool get _composing =>
      widget.controller.value.composing.isValid &&
      !widget.controller.value.composing.isCollapsed;
  bool get _canUndo => _undo.isNotEmpty || _beforeComposition != null;
  bool get _canRedo => !_composing && _redo.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _current = widget.controller.value;
    widget.controller.addListener(_changed);
    _bind();
  }

  void _bind() {
    widget.history?.onUndo.addListener(_undoEdit);
    widget.history?.onRedo.addListener(_redoEdit);
    _notify();
  }

  @override
  void didUpdateWidget(covariant GitTextUndo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _undo.clear();
      _redo.clear();
      _beforeComposition = null;
      _current = widget.controller.value;
      widget.controller.addListener(_changed);
    }
    if (oldWidget.history != widget.history) {
      oldWidget.history?.onUndo.removeListener(_undoEdit);
      oldWidget.history?.onRedo.removeListener(_redoEdit);
      _bind();
    }
    _notify();
  }

  void _changed() {
    if (_applying) return;
    final next = widget.controller.value;
    if (_composing) {
      _beforeComposition ??= _current;
    } else {
      final previous = _beforeComposition ?? _current;
      if (next.text != previous.text) {
        _undo.add(previous.copyWith(composing: TextRange.empty));
        _redo.clear();
      }
      _beforeComposition = null;
    }
    _current = next;
    _trim();
    _notify();
  }

  void _trim() {
    // Content reads are already bounded. Bound retained draft versions too;
    // always keep the nearest available undo/redo rather than retaining a file
    // version for every keystroke indefinitely.
    int bytes() => [
      ..._undo,
      ..._redo,
    ].fold(0, (size, value) => size + value.text.length * 2);
    while (_undo.length + _redo.length > 100 ||
        (_undo.length + _redo.length > 1 && bytes() > 32 * 1024 * 1024)) {
      if (_undo.length > 1 || _redo.isEmpty) {
        _undo.removeAt(0);
      } else {
        _redo.removeAt(0);
      }
    }
  }

  void _notify() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_notificationQueued) {
        _notificationQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _notificationQueued = false;
          if (mounted) _notify();
        });
      }
      return;
    }
    widget.history?.value = UndoHistoryValue(
      canUndo: _canUndo,
      canRedo: _canRedo,
    );
  }

  void _apply(TextEditingValue value) {
    EditableTextState? editable;
    void visit(Element element) {
      if (element is StatefulElement &&
          element.state is EditableTextState &&
          identical(
            (element.widget as EditableText).controller,
            widget.controller,
          )) {
        editable = element.state as EditableTextState;
      } else {
        element.visitChildren(visit);
      }
    }

    _child.currentContext?.visitChildElements(visit);
    if (editable == null) {
      throw StateError(GitMessages.aGitTextHistoryMustOwnItsEditableField);
    }
    _applying = true;
    try {
      editable!.userUpdateTextEditingValue(
        value.copyWith(composing: TextRange.empty),
        SelectionChangedCause.keyboard,
      );
      _current = widget.controller.value;
    } finally {
      _applying = false;
    }
    _notify();
  }

  void _undoEdit() {
    if (!widget.enabled || !_canUndo) return;
    final composition = _beforeComposition;
    if (composition != null) {
      _beforeComposition = null;
      _apply(composition);
      return;
    }
    _redo.add(widget.controller.value.copyWith(composing: TextRange.empty));
    _apply(_undo.removeLast());
    _trim();
  }

  void _redoEdit() {
    if (!widget.enabled || !_canRedo) return;
    _undo.add(widget.controller.value.copyWith(composing: TextRange.empty));
    _apply(_redo.removeLast());
    _trim();
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      UndoTextIntent: _GitHistoryAction<UndoTextIntent>(
        enabled: () => widget.enabled && _canUndo,
        run: _undoEdit,
      ),
      RedoTextIntent: _GitHistoryAction<RedoTextIntent>(
        enabled: () => widget.enabled && _canRedo,
        run: _redoEdit,
      ),
    },
    child: KeyedSubtree(key: _child, child: widget.child),
  );

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.history?.onUndo.removeListener(_undoEdit);
    widget.history?.onRedo.removeListener(_redoEdit);
    super.dispose();
  }
}

final class _GitHistoryAction<T extends Intent> extends Action<T> {
  _GitHistoryAction({required this.enabled, required this.run});
  final bool Function() enabled;
  final VoidCallback run;
  @override
  bool isEnabled(T intent) => enabled();
  @override
  Object? invoke(T intent) {
    run();
    return null;
  }
}
