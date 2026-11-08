// BusyStack-owned native layout and focus primitives used by both applications.
// Flutter's traditional highlight mode includes mouse input. Track modality
// separately without changing focus ownership, traversal, or global strategy.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';

abstract final class NativeFocusStyle {
  static Color color(ColorScheme scheme, {bool highContrast = false}) =>
      scheme.onSurface.withValues(alpha: highContrast ? 1 : .6);

  static InputDecorationThemeData inputs(
    InputDecorationThemeData base,
    ColorScheme scheme, {
    bool highContrast = false,
  }) => base.copyWith(
    focusedBorder: base.focusedBorder?.copyWith(
      borderSide: BorderSide(
        color: color(scheme, highContrast: highContrast),
        width: kYaruFocusBorderWidth,
      ),
    ),
  );
}

class _InputModality extends ChangeNotifier {
  static final instance = _InputModality();
  bool keyboard = true;
  int _users = 0;
  void attach() {
    if (_users++ != 0) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    HardwareKeyboard.instance.addHandler(_key);
  }

  void detach() {
    if (--_users != 0) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    HardwareKeyboard.instance.removeHandler(_key);
    keyboard = true;
  }

  void _set(bool value) {
    if (keyboard == value) return;
    keyboard = value;
    notifyListeners();
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent) _set(false);
  }

  bool _key(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _set(true);
    return false;
  }
}

/// Input focus and visual focus are independent. A mouse-selected row keeps
/// its focus node; the next keyboard event immediately reveals its indicator.
class NativeFocusIndicator extends StatefulWidget {
  const NativeFocusIndicator({
    super.key,
    required this.child,
    this.borderRadius,
    this.borderStrokeAlign = BorderSide.strokeAlignInside,
    this.enabled = true,
  });
  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final double borderStrokeAlign;
  final bool enabled;
  @override
  State<NativeFocusIndicator> createState() => _NativeFocusIndicatorState();
}

class _NativeFocusIndicatorState extends State<NativeFocusIndicator> {
  bool _focused = false;
  final _modality = _InputModality.instance;
  @override
  void initState() {
    super.initState();
    _modality.attach();
    _modality.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _modality.removeListener(_changed);
    _modality.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.enabled && _focused && _modality.keyboard;
    final color = NativeFocusStyle.color(
      Theme.of(context).colorScheme,
      highContrast: MediaQuery.highContrastOf(context),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: YaruFocusBorder.primary(
        focused: true,
        onFocusChange: (_) {},
        borderColor: visible ? color : color.withValues(alpha: 0),
        borderWidth: kYaruFocusBorderWidth,
        borderRadius: widget.borderRadius,
        borderStrokeAlign: widget.borderStrokeAlign,
        child: widget.child,
      ),
    );
  }
}

/// Local History's title/context hierarchy, shared with the Git presenters.
/// Context may be an informational line or a view-specific native selector.
class NativeSidebarHeader extends StatelessWidget {
  const NativeSidebarHeader({
    super.key,
    required this.title,
    this.contextLine,
    this.actions = const [],
    this.leading,
    this.padding = const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
  });
  final String title;
  final Widget? contextLine, leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (contextLine != null) ...[
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: IconTheme.merge(
                      data: IconThemeData(
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: contextLine!,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}
