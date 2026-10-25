import 'package:flutter/services.dart';

/// Let Flutter observe every trigger release before a native menu grabs keys.
final class GitContextMenuKeys {
  VoidCallback? _open;
  bool _triggerReleased = false, _awaitingShift = false;

  bool handle(KeyEvent event, VoidCallback? open) {
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final trigger =
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        (key == LogicalKeyboardKey.contextMenu && !keyboard.isShiftPressed ||
            key == LogicalKeyboardKey.f10 && keyboard.isShiftPressed);
    if (event is KeyDownEvent) {
      clear();
      if (!trigger || open == null) return false;
      _open = open;
      _awaitingShift = key == LogicalKeyboardKey.f10;
      return true;
    }
    if (_open == null) return false;
    if (event is KeyRepeatEvent) return true;
    if (event is! KeyUpEvent) return false;
    if (key == LogicalKeyboardKey.f10 ||
        key == LogicalKeyboardKey.contextMenu) {
      _triggerReleased = true;
    }
    // The aggregate mask can clear before the concrete Shift-up reaches the
    // Flutter view. Waiting only for F10-up still races a native GTK grab.
    if ((key == LogicalKeyboardKey.shiftLeft ||
            key == LogicalKeyboardKey.shiftRight) &&
        !keyboard.isShiftPressed) {
      _awaitingShift = false;
    }
    if (_triggerReleased && !_awaitingShift) {
      final action = _open!;
      clear();
      action();
    }
    return true;
  }

  void clear() {
    _open = null;
    _triggerReleased = false;
    _awaitingShift = false;
  }
}
