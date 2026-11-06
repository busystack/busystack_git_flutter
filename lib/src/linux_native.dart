// BusyStack-owned native Git rendering, derived from the approved BusyMark
// primitives. Both hosts use these exact controls; no upstream source is copied
// or modified. Native services, localization and modal lifetime stay host-owned.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';
import 'package:intl/intl.dart' as intl;
import '../busystack_git_flutter.dart' as git;

abstract final class GitSpacing {
  static const double xxs = 2,
      xs = 4,
      sm = 8,
      md = 12,
      mdPlus = 14,
      lg = 16,
      xl = 24,
      headerInset = 6;
}

abstract final class GitStroke {
  static const double hairline = 1;
}

abstract final class GitRadius {
  static const double md = 8, headerButton = kYaruButtonRadius;
}

abstract final class GitSizes {
  static const double sidebarWidth = 300,
      iconButton = kYaruTitleBarItemHeight,
      sidebarTreeRowHeight = iconButton - 2,
      sidebarRowHeight = 36,
      sidebarTreeDepthBase = 4,
      sidebarTreeDepthIndent = 14,
      sidebarTreeControl = 18,
      sidebarTreeArrow = 14,
      iconSm = 16,
      toolbarHeight = kYaruTitleBarHeight,
      dialogWide = 560;
}

abstract final class GitTypography {
  static const monoFontFamily = 'Ubuntu Mono';
  static const monoFontFamilyFallback = <String>[
    'Noto Sans Arabic',
    'Noto Sans Mono',
    'DejaVu Sans Mono',
    'DejaVu Sans',
  ];
}

/// Approved BusyMark GTK/Yaru neutral roles, owned once for the Git feature.
/// Host editor/browser palette overrides are not Git design inputs. System
/// accent and the platform accessibility contrast setting remain authoritative.
abstract final class GitPalette {
  static ColorScheme resolve(
    ThemeData official,
    Color accent,
    bool highContrast,
  ) {
    final base = official.colorScheme;
    if (highContrast) {
      return base.copyWith(
        primary: accent,
        secondary: accent,
        onPrimary: contrastColor(accent),
      );
    }
    final dark = official.brightness == Brightness.dark;
    final foreground = dark ? const Color(0xfff7f7f7) : const Color(0xff3d3d3d);
    final muted = dark ? const Color(0xffb5b5b5) : const Color(0xff666666);
    final view = dark ? const Color(0xff272727) : const Color(0xffffffff);
    final window = dark ? const Color(0xff2c2c2c) : const Color(0xfffafafa);
    final panel = dark ? const Color(0xff323232) : const Color(0xfff0f0f0);
    final sidebar = dark ? const Color(0xff393939) : const Color(0xffebebeb);
    return base.copyWith(
      primary: accent,
      secondary: accent,
      onPrimary: contrastColor(accent),
      surface: view,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainerLowest: view,
      surfaceContainerLow: window,
      surfaceContainer: panel,
      surfaceContainerHigh: panel,
      surfaceContainerHighest: sidebar,
      outline: const Color(0xff000000).withValues(alpha: dark ? .75 : .18),
      outlineVariant: (dark ? const Color(0xffffffff) : const Color(0xff000000))
          .withValues(alpha: .10),
    );
  }
}

// Resolve official pinned Yaru typography/control geometry once, independent
// of unrelated editor/browser style overrides. This is not a second app theme:
// it supplies native control roles and preserves the system accent while it
// uses the same accessibility text scale, focus and high-contrast settings.
final _gitYaruMetrics = <(Brightness, Color, bool), ThemeData>{};
ThemeData _gitNativeTheme(BuildContext context) {
  final app = Theme.of(context);
  final highContrast = MediaQuery.highContrastOf(context);
  final base = _gitYaruMetrics.putIfAbsent(
    (app.brightness, app.colorScheme.primary, highContrast),
    () => highContrast
        ? app.brightness == Brightness.dark
              ? yaruHighContrastDark
              : yaruHighContrastLight
        : app.brightness == Brightness.dark
        ? createYaruDarkTheme(primaryColor: app.colorScheme.primary)
        : createYaruLightTheme(primaryColor: app.colorScheme.primary),
  );
  final scheme = GitPalette.resolve(
    base,
    app.colorScheme.primary,
    highContrast,
  );
  final foreground = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;
  final disabled = foreground.withValues(alpha: .38);
  final transparent = foreground.withValues(alpha: 0);
  final disabledBackground = foreground.withValues(
    alpha: app.brightness == Brightness.dark ? .06 : .04,
  );
  ButtonStyle? action(ButtonStyle? style, Color color, Color background) =>
      style?.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? disabled : color,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? disabled : color,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? disabledBackground
              : background,
        ),
      );
  final text = base.textTheme.apply(
    bodyColor: foreground,
    displayColor: foreground,
  );
  return base.copyWith(
    colorScheme: scheme,
    dividerColor: scheme.outlineVariant,
    textSelectionTheme: base.textSelectionTheme.copyWith(
      cursorColor: app.colorScheme.primary,
      selectionColor: app.colorScheme.primary.withValues(alpha: .32),
      selectionHandleColor: app.colorScheme.primary,
    ),
    textTheme: text.copyWith(
      titleSmall: text.titleSmall?.copyWith(color: muted),
      bodySmall: text.bodySmall?.copyWith(color: muted),
      labelMedium: text.labelMedium?.copyWith(color: muted),
      labelSmall: text.labelSmall?.copyWith(color: muted),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: action(base.outlinedButtonTheme.style, foreground, transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: action(
        base.filledButtonTheme.style,
        foreground,
        foreground.withValues(alpha: .10),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: action(
        base.elevatedButtonTheme.style,
        contrastColor(app.colorScheme.primary),
        app.colorScheme.primary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: action(base.textButtonTheme.style, foreground, transparent),
    ),
  );
}

final class NativeGitSurface {
  NativeGitSurface.of(BuildContext context) : theme = _gitNativeTheme(context);
  final ThemeData theme;
  Color get foreground => theme.colorScheme.onSurface;
  Color get mutedForeground => theme.colorScheme.onSurfaceVariant;
  Color get disabledForeground => foreground.withValues(alpha: .38);
  Color get divider => theme.dividerColor;
  Color get panel => theme.colorScheme.surfaceContainerHigh;
  Color get sidebar => theme.colorScheme.surfaceContainerHighest;
  Color get controlActive => foreground.withValues(alpha: .18);
  Color get controlHover => foreground.withValues(alpha: .06);
}

enum NativeGitActionRole { inline, standard, suggested }

const gitLinuxIcons = <git.GitGlyph, IconData>{
  git.GitGlyph.back: YaruIcons.go_previous,
  git.GitGlyph.branch: YaruIcons.share,
  git.GitGlyph.history: YaruIcons.history,
  git.GitGlyph.selectCommit: YaruIcons.share,
  git.GitGlyph.repository: YaruIcons.folder,
  git.GitGlyph.refresh: YaruIcons.refresh,
  git.GitGlyph.copy: YaruIcons.copy,
  git.GitGlyph.options: YaruIcons.settings,
  git.GitGlyph.moreHorizontal: YaruIcons.view_more_horizontal,
  git.GitGlyph.more: YaruIcons.view_more,
  git.GitGlyph.actions: YaruIcons.menu,
  git.GitGlyph.expand: YaruIcons.pan_down,
  git.GitGlyph.previous: YaruIcons.pan_start,
  git.GitGlyph.next: YaruIcons.pan_end,
  git.GitGlyph.up: YaruIcons.pan_up,
  git.GitGlyph.down: YaruIcons.pan_down,
  git.GitGlyph.search: YaruIcons.search,
  git.GitGlyph.add: YaruIcons.plus,
  git.GitGlyph.remove: YaruIcons.minus,
  git.GitGlyph.check: YaruIcons.checkmark,
  git.GitGlyph.tag: YaruIcons.tag,
  git.GitGlyph.error: YaruIcons.error,
  git.GitGlyph.warning: YaruIcons.warning,
  git.GitGlyph.close: YaruIcons.window_close,
};

class NativeGitActionButton extends StatefulWidget {
  const NativeGitActionButton({
    super.key,
    required this.role,
    required this.child,
    required this.onPressed,
    this.compact = false,
  });

  final NativeGitActionRole role;
  final Widget child;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  State<NativeGitActionButton> createState() => NativeGitActionButtonState();
}

class NativeGitActionButtonState extends State<NativeGitActionButton> {
  final _focusNode = FocusNode(debugLabel: 'Git action');
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  Set<WidgetState> get _states => {
    if (widget.onPressed == null) WidgetState.disabled,
    if (_hovered) WidgetState.hovered,
    if (_pressed) WidgetState.pressed,
    if (_focused) WidgetState.focused,
  };

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _activate() {
    if (widget.onPressed != null) widget.onPressed!();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NativeGitSurface.of(context);
    final theme = _gitNativeTheme(context);
    final style = switch (widget.role) {
      // Match BusyMarkPushButton.flat: native neutral foreground, never the
      // accent/link foreground from the application's text-button theme.
      NativeGitActionRole.inline => theme.textButtonTheme.style?.copyWith(
        foregroundColor: theme.outlinedButtonTheme.style?.foregroundColor,
        iconColor: theme.outlinedButtonTheme.style?.iconColor,
      ),
      NativeGitActionRole.standard => theme.filledButtonTheme.style,
      NativeGitActionRole.suggested => theme.elevatedButtonTheme.style,
    };
    final states = _states;
    final enabled = widget.onPressed != null;
    final foreground = enabled
        ? style?.foregroundColor?.resolve(states) ?? colors.foreground
        : colors.disabledForeground;
    final baseBackground = style?.backgroundColor?.resolve(states);
    final fallbackOverlay = !enabled
        ? null
        : _pressed
        ? colors.controlActive
        : _hovered || _focused
        ? colors.controlHover
        : null;
    final overlay = style?.overlayColor?.resolve(states) ?? fallbackOverlay;
    final background = Color.alphaBlend(
      overlay ??
          _gitNativeTheme(context).colorScheme.surface.withValues(alpha: 0),
      baseBackground ??
          _gitNativeTheme(context).colorScheme.surface.withValues(alpha: 0),
    );
    final resolvedShape =
        style?.shape?.resolve(states) ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kYaruButtonRadius),
        );
    final side = style?.side?.resolve(states);
    final shape = side != null
        ? resolvedShape.copyWith(side: side)
        : resolvedShape;
    final radius = resolvedShape is RoundedRectangleBorder
        ? resolvedShape.borderRadius
        : BorderRadius.circular(kYaruButtonRadius);
    final padding = widget.compact
        ? const EdgeInsets.symmetric(
            horizontal: GitSpacing.md,
            vertical: GitSpacing.xs,
          )
        : const EdgeInsets.symmetric(
            horizontal: GitSpacing.lg,
            vertical: GitSpacing.sm,
          );
    final minimum =
        style?.minimumSize?.resolve(states) ??
        const Size(kYaruButtonHeight, kYaruButtonHeight);
    final maximum =
        style?.maximumSize?.resolve(states) ??
        const Size(double.infinity, double.infinity);
    final fixed = style?.fixedSize?.resolve(states);
    final constraints = fixed == null
        ? BoxConstraints(
            minWidth: minimum.width,
            minHeight: widget.compact
                ? kYaruTitleBarItemHeight
                : minimum.height,
            maxWidth: maximum.width,
            maxHeight: maximum.height,
          )
        : BoxConstraints.tight(fixed);
    final textStyle = theme.textTheme.bodyMedium!.merge(
      style?.textStyle?.resolve(states),
    );
    final content = DefaultTextStyle(
      style: textStyle.copyWith(color: foreground),
      child: IconTheme.merge(
        data: IconThemeData(
          color: style?.iconColor?.resolve(states) ?? foreground,
          size: style?.iconSize?.resolve(states),
        ),
        child: Padding(padding: padding, child: widget.child),
      ),
    );
    final painted = DecoratedBox(
      decoration: ShapeDecoration(color: background, shape: shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: ConstrainedBox(
          constraints: constraints,
          child: Center(widthFactor: 1, heightFactor: 1, child: content),
        ),
      ),
    );
    final action = Semantics(
      button: true,
      enabled: enabled,
      onTap: enabled ? _activate : null,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        child: MouseRegion(
          onEnter: (_) {
            if (enabled && !_hovered) setState(() => _hovered = true);
          },
          onExit: (_) {
            if (_hovered || _pressed) {
              setState(() {
                _hovered = false;
                _pressed = false;
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _activate : null,
            onTapDown: enabled
                ? (_) {
                    _focusNode.requestFocus();
                    _setPressed(true);
                  }
                : null,
            onTapUp: enabled ? (_) => _setPressed(false) : null,
            onTapCancel: enabled ? () => _setPressed(false) : null,
            child: painted,
          ),
        ),
      ),
    );
    return YaruTheme.maybeOf(context)?.focusBorders != false
        ? YaruFocusBorder.primary(borderRadius: radius, child: action)
        : action;
  }
}

class NativeGitTextEntry extends StatefulWidget {
  const NativeGitTextEntry({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.expands = false,
    this.minLines,
    this.maxLines = 1,
    this.scrollController,
    this.undoController,
    this.textStyle,
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.leading,
    this.trailing,
    this.dense = false,
    this.contentPadding,
    this.textAlignVertical,
    this.alignLabelWithHint = false,
    this.contextMenuBuilder,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool expands;
  final int? minLines;
  final int? maxLines;
  final ScrollController? scrollController;
  final UndoHistoryController? undoController;
  final TextStyle? textStyle;
  final TextDirection? textDirection;
  final TextAlign textAlign;
  final Widget? leading, trailing;
  final bool dense, alignLabelWithHint;
  final EdgeInsetsGeometry? contentPadding;
  final TextAlignVertical? textAlignVertical;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<NativeGitTextEntry> createState() => _NativeGitTextEntryState();
}

class _NativeGitTextEntryState extends State<NativeGitTextEntry>
    implements TextSelectionGestureDetectorBuilderDelegate {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocusNode;
  @override
  final editableTextKey = GlobalKey<EditableTextState>();
  @override
  bool get forcePressEnabled => false;
  @override
  bool get selectionEnabled => widget.enabled;
  late final _gestures = TextSelectionGestureDetectorBuilder(delegate: this);

  TextEditingController get _controller =>
      widget.controller ?? (_ownedController ??= TextEditingController());
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(NativeGitTextEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onTextChanged);
      widget.controller?.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onTextChanged);
    _ownedController?.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    widget.onSubmitted?.call(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NativeGitSurface.of(context);
    final enabled = widget.enabled;
    final selectionTheme = _gitNativeTheme(context).textSelectionTheme;
    final style =
        (widget.textStyle ?? _gitNativeTheme(context).textTheme.bodyMedium)!
            .copyWith(
              color: enabled
                  ? (widget.textStyle?.color ?? colors.foreground)
                  : colors.disabledForeground,
            );
    final editable = EditableText(
      key: editableTextKey,
      controller: _controller,
      focusNode: _focusNode,
      readOnly: widget.readOnly || !enabled,
      autofocus: enabled && widget.autofocus,
      obscureText: widget.obscureText,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      style: style,
      cursorColor:
          selectionTheme.cursorColor ??
          _gitNativeTheme(context).colorScheme.primary,
      rendererIgnoresPointer: true,
      selectionControls: desktopTextSelectionHandleControls,
      backgroundCursorColor: colors.mutedForeground,
      selectionColor:
          selectionTheme.selectionColor ??
          _gitNativeTheme(context).colorScheme.primary.withValues(alpha: .25),
      expands: widget.expands,
      minLines: widget.expands ? null : widget.minLines,
      maxLines: widget.expands ? null : widget.maxLines,
      scrollController: widget.scrollController,
      undoController: widget.undoController,
      textDirection: widget.textDirection,
      textAlign: widget.textAlign,
      contextMenuBuilder: widget.contextMenuBuilder,
      onChanged: enabled
          ? (value) {
              setState(() {});
              widget.onChanged?.call(value);
            }
          : null,
      onSubmitted: enabled ? widget.onSubmitted : null,
    );
    // Native search entries use an inline placeholder. The semantic label
    // persists while typing, without a second permanent toolbar line.
    final label = widget.label.trim();
    final hint = widget.hintText ?? (widget.dense ? label : null);
    final editor = Stack(
      alignment: AlignmentDirectional(
        -1,
        widget.textAlignVertical?.y ?? (widget.alignLabelWithHint ? -1 : 0),
      ),
      children: [
        if (hint != null && hint.isNotEmpty && _controller.text.isEmpty)
          IgnorePointer(
            child: ExcludeSemantics(
              // The persistent field label names the editor. The placeholder
              // is visual guidance, not a second accessible field name.
              child: Text(
                hint,
                maxLines: widget.maxLines == 1 ? 1 : null,
                overflow: widget.maxLines == 1 ? TextOverflow.ellipsis : null,
                style: style.copyWith(color: colors.mutedForeground),
              ),
            ),
          ),
        editable,
      ],
    );
    final content = Column(
      mainAxisSize: widget.expands ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.dense && label.isNotEmpty) ...[
          ExcludeSemantics(
            child: Text(
              label,
              style: _gitNativeTheme(context).textTheme.bodySmall?.copyWith(
                color: enabled
                    ? colors.mutedForeground
                    : colors.disabledForeground,
              ),
            ),
          ),
          const SizedBox(height: GitSpacing.xs),
        ],
        if (widget.expands) Expanded(child: editor) else editor,
      ],
    );
    final inputTheme = _gitNativeTheme(context).inputDecorationTheme;
    final radius = BorderRadius.circular(
      widget.dense ? kYaruButtonRadius : kYaruContainerRadius,
    );
    final surface = ListenableBuilder(
      listenable: _focusNode,
      builder: (context, _) => YaruBorderContainer(
        color: widget.dense
            ? _gitNativeTheme(context).colorScheme.surface
            : NativeGitSurface.of(context).panel,
        border: Border.fromBorderSide(
          (_focusNode.hasFocus
                      ? inputTheme.focusedBorder
                      : widget.dense && enabled
                      ? inputTheme.enabledBorder
                      : widget.dense
                      ? inputTheme.disabledBorder
                      : null)
                  ?.borderSide ??
              BorderSide(color: colors.divider),
        ),
        borderRadius: radius,
        constraints: BoxConstraints(
          minHeight: widget.dense ? kYaruTitleBarItemHeight : 0,
        ),
        padding:
            widget.contentPadding ??
            const EdgeInsets.symmetric(
              horizontal: GitSpacing.sm,
              vertical: GitSpacing.xs,
            ),
        child: Row(
          crossAxisAlignment: widget.expands
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: GitSpacing.sm),
            ],
            Expanded(child: content),
            if (widget.trailing != null) ...[
              const SizedBox(width: GitSpacing.xs),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
    final interactive = Semantics(
      label: label.isEmpty ? null : label,
      enabled: enabled,
      child: IgnorePointer(
        ignoring: !enabled,
        child: ExcludeFocus(
          excluding: !enabled,
          child: _gestures.buildGestureDetector(
            behavior: HitTestBehavior.translucent,
            child: surface,
          ),
        ),
      ),
    );
    if (!enabled || widget.onSubmitted == null) return interactive;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
      },
      child: interactive,
    );
  }
}

class NativeGitRowSurface extends StatefulWidget {
  const NativeGitRowSurface({
    super.key,
    required this.child,
    required this.enabled,
    required this.clickable,
    this.selected = false,
    this.focusNode,
    this.onKeyEvent,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.onHoverChanged,
    this.onFocusChange,
  });

  final Widget child;
  final bool enabled;
  final bool clickable;
  final bool selected;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<NativeGitRowSurface> createState() => NativeGitRowSurfaceState();
}

class NativeGitRowSurfaceState extends State<NativeGitRowSurface> {
  FocusNode? _ownedFocusNode;
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'Git sidebar row'));

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final result = widget.onKeyEvent?.call(node, event);
    if (result != null && result != KeyEventResult.ignored) return result;
    if (widget.enabled &&
        widget.clickable &&
        event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _hover(bool hovered) {
    if (_hovered != hovered || !hovered && _pressed) {
      setState(() {
        _hovered = hovered;
        if (!hovered) _pressed = false;
      });
    }
    widget.onHoverChanged?.call(hovered);
  }

  void _focus(bool focused) {
    if (_focused != focused) setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NativeGitSurface.of(context);
    final background = widget.selected
        ? NativeGitSurface.of(context).controlActive
        : widget.enabled && widget.clickable && _pressed
        ? colors.controlActive
        : widget.enabled && widget.clickable && (_hovered || _focused)
        ? NativeGitSurface.of(context).controlHover
        : _gitNativeTheme(context).colorScheme.surface.withValues(alpha: 0);
    final radius = BorderRadius.circular(GitRadius.md);
    final row = DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: GitSizes.sidebarTreeRowHeight,
          ),
          child: widget.child,
        ),
      ),
    );
    final surface = MouseRegion(
      cursor: widget.enabled && widget.clickable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GitStroke.hairline),
        child: Focus(
          focusNode: _focusNode,
          canRequestFocus: widget.enabled && widget.clickable,
          onKeyEvent: _handleKeyEvent,
          onFocusChange: _focus,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled && widget.onTap != null
                ? () {
                    if (widget.clickable) _focusNode.requestFocus();
                    widget.onTap?.call();
                  }
                : null,
            onDoubleTap: widget.enabled ? widget.onDoubleTap : null,
            onSecondaryTapUp: widget.enabled && widget.onSecondaryTapUp != null
                ? (details) {
                    if (widget.clickable) _focusNode.requestFocus();
                    widget.onSecondaryTapUp!(details);
                  }
                : null,
            onTapDown: widget.enabled && widget.clickable
                ? (_) {
                    if (!_pressed) setState(() => _pressed = true);
                  }
                : null,
            onTapUp: widget.enabled && widget.clickable
                ? (_) {
                    if (_pressed) setState(() => _pressed = false);
                  }
                : null,
            onTapCancel: widget.enabled && widget.clickable
                ? () {
                    if (_pressed) setState(() => _pressed = false);
                  }
                : null,
            child: row,
          ),
        ),
      ),
    );
    return YaruTheme.maybeOf(context)?.focusBorders != false && widget.clickable
        ? YaruFocusBorder.primary(
            borderRadius: radius,
            borderStrokeAlign: BorderSide.strokeAlignInside,
            child: surface,
          )
        : surface;
  }
}

base class YaruGitPresentation implements git.GitPresentation {
  const YaruGitPresentation();
  @override
  git.GitEntryActionPlacement get entryActionPlacement =>
      git.GitEntryActionPlacement.contextMenu;
  @override
  ThemeData theme(BuildContext context) => _gitNativeTheme(context);
  @override
  TextStyle? codeStyle(BuildContext context) =>
      _gitNativeTheme(context).textTheme.bodyMedium?.copyWith(
        fontFamily: GitTypography.monoFontFamily,
        fontFamilyFallback: GitTypography.monoFontFamilyFallback,
      );
  @override
  git.GitColors colors(BuildContext context) {
    final native = YaruColors.of(context);
    return git.GitColors(
      accent: _gitNativeTheme(context).colorScheme.primary,
      selection: NativeGitSurface.of(context).controlActive,
      border: NativeGitSurface.of(context).divider,
      subtleBorder: NativeGitSurface.of(context).divider,
      surface: NativeGitSurface.of(context).panel,
      mutedText: _gitNativeTheme(context).colorScheme.onSurfaceVariant,
      added: native.success,
      removed: native.error,
      staged: native.success,
      unstaged: native.warning,
      conflict: native.error,
      addedBackground: native.success.withValues(alpha: .20),
      removedBackground: native.error.withValues(alpha: .20),
      stagedBackground: native.success.withValues(alpha: .16),
      unstagedBackground: native.warning.withValues(alpha: .16),
      conflictBackground: native.error.withValues(alpha: .24),
      searchBackground: _gitNativeTheme(
        context,
      ).colorScheme.primary.withValues(alpha: .18),
    );
  }

  @override
  String formatCommitDate(
    BuildContext context,
    DateTime date, {
    bool full = false,
  }) {
    final local = date.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${full ? labels.formatFullDate(local) : labels.formatMediumDate(local)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  @override
  Future<(DateTime, DateTime)?> dateRange(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) => git.GitHostScope.of(context)!.present<(DateTime, DateTime)>(
    context,
    git
        .gitString(context, git.GitMessages.dateFilter)
        .replaceFirst(RegExp(r'(?:…|\.{3})$'), ''),
    _GitDateRange(start: start, end: end),
  );
  @override
  String repositoryActionsLabel(BuildContext context) =>
      git.gitString(context, git.GitMessages.actions);
  @override
  git.GitToolbarMetrics toolbarMetrics(BuildContext context) =>
      const git.GitToolbarMetrics(
        iconExtent: GitSizes.iconButton,
        gap: GitSpacing.xs,
        textInsets: GitSpacing.md * 2,
        modeAdornment: GitSpacing.sm + GitSizes.iconSm,
      );
  @override
  double buttonWidth(
    BuildContext context,
    String label,
    git.GitActionStyle variant,
  ) {
    final theme = _gitNativeTheme(context);
    final style = switch (variant) {
      git.GitActionStyle.suggested => theme.elevatedButtonTheme.style,
      git.GitActionStyle.standard => theme.filledButtonTheme.style,
      _ => theme.textButtonTheme.style,
    };
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: style?.textStyle?.resolve({}) ?? theme.textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width + GitSpacing.lg * 2;
    painter.dispose();
    return math.max(width, style?.minimumSize?.resolve({})?.width ?? 0);
  }

  @override
  Widget button(BuildContext context, git.GitButton control) =>
      NativeGitActionButton(
        compact: control.compact,
        role: switch (control.variant) {
          git.GitActionStyle.inline ||
          git.GitActionStyle.toolbar ||
          git.GitActionStyle.diffInline => NativeGitActionRole.inline,
          git.GitActionStyle.standard => NativeGitActionRole.standard,
          git.GitActionStyle.suggested => NativeGitActionRole.suggested,
        },
        onPressed: control.onPressed,
        child: control.child,
      );
  @override
  Widget iconAction(BuildContext context, git.GitIconButton control) {
    final glyph = switch (control.icon) {
      git.GitIcon(:final glyph) => gitLinuxIcons[glyph]!,
      Icon(:final icon) when icon != null => icon,
      _ => throw StateError('Git icon actions require a native host glyph.'),
    };
    return GestureDetector(
      // Disabled trailing actions still own their pointer target. Letting the
      // row behind them win would open a comparison instead of doing nothing.
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: control.onPressed == null ? () {} : null,
      child: NativeGitIconAction(
        focusBorderRadius: GitRadius.headerButton,
        tooltip: git.gitString(context, control.tooltip),
        icon: glyph,
        onPressed: control.onPressed,
      ),
    );
  }

  @override
  Widget field(BuildContext context, git.GitTextField control) {
    final decoration = control.decoration;
    return NativeGitTextEntry(
      label: decoration?.labelText ?? '',
      hintText: decoration?.hintText,
      dense: decoration?.isDense ?? false,
      leading: decoration?.prefixIcon,
      contentPadding: decoration?.contentPadding,
      alignLabelWithHint: decoration?.alignLabelWithHint ?? false,
      textAlignVertical: control.textAlignVertical,
      contextMenuBuilder: (menuContext, editable) => git.GitTextContextMenu(
        host: git.GitHostScope.of(context)!,
        items: editable.contextMenuButtonItems,
        position: editable.contextMenuAnchors.primaryAnchor,
        close: editable.hideToolbar,
      ),
      controller: control.controller,
      focusNode: control.focusNode,
      enabled: control.enabled ?? true,
      readOnly: control.readOnly,
      autofocus: control.autofocus,
      obscureText: control.obscureText,
      autocorrect: control.autocorrect,
      enableSuggestions: control.enableSuggestions,
      expands: control.expands,
      minLines: control.minLines,
      maxLines: control.maxLines,
      scrollController: control.scrollController,
      undoController: control.undoController,
      textStyle: control.style,
      textDirection: control.textDirection,
      textAlign: control.textAlign,
      trailing: decoration?.suffixIcon,
      onChanged: control.onChanged,
      onSubmitted: control.onSubmitted,
    );
  }

  @override
  Widget checkbox(BuildContext context, git.GitCheckbox control) =>
      NativeGitCheckbox(
        label: control.label,
        value: control.value,
        tristate: control.value == null,
        onChanged: control.onChanged,
      );
  @override
  Widget choice<T>(BuildContext context, git.GitChoice<T> control) {
    final selected = control.value ?? control.initialValue;
    final label = control.items
        .where((item) => item.value == selected)
        .map((item) => item.child)
        .firstOrNull;
    return NativeGitActionButton(
      role: NativeGitActionRole.standard,
      onPressed: control.onChanged == null
          ? null
          : () async {
              final result = await git.GitHostScope.of(context)!
                  .menu(context, control.decoration?.labelText ?? '', [
                    for (var i = 0; i < control.items.length; i++)
                      git.GitMenuEntry(
                        '$i',
                        git.gitControlLabel(context, control.items[i].child),
                        radio: true,
                        checked: control.items[i].value == selected,
                        localize: false,
                      ),
                  ]);
              if (context.mounted && result != null) {
                control.onChanged?.call(control.items[int.parse(result)].value);
              }
            },
      child: Row(
        mainAxisSize: control.isExpanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Flexible(child: label ?? Text(control.decoration?.labelText ?? '')),
          const git.GitIcon(git.GitGlyph.down),
        ],
      ),
    );
  }

  @override
  Widget choiceBar<T>(BuildContext context, git.GitChoiceBar<T> control) =>
      Wrap(
        spacing: GitSpacing.sm,
        children: [
          for (final segment in control.segments)
            MergeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  YaruRadio<T>(
                    value: segment.value,
                    groupValue: control.selected.firstOrNull,
                    onChanged: control.onSelectionChanged == null
                        ? null
                        : (value) => control.onSelectionChanged!({value as T}),
                  ),
                  GestureDetector(
                    onTap: control.onSelectionChanged == null
                        ? null
                        : () => control.onSelectionChanged!({segment.value}),
                    child: segment.label,
                  ),
                ],
              ),
            ),
        ],
      );
  @override
  Widget row(BuildContext context, git.GitActionRow control) => Semantics(
    selected: control.selected,
    button: control.onTap != null,
    enabled: control.enabled,
    child: Row(
      children: [
        Expanded(
          child: NativeGitRowSurface(
            enabled: control.enabled,
            clickable:
                control.onTap != null || control.onSecondaryTapUp != null,
            selected: control.selected,
            onTap: control.onTap,
            onSecondaryTapUp: control.onSecondaryTapUp,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: control.dense
                    ? GitSizes.sidebarTreeRowHeight
                    : GitSizes.sidebarRowHeight,
              ),
              child: Padding(
                padding:
                    control.contentPadding ??
                    EdgeInsets.symmetric(
                      horizontal: GitSpacing.sm,
                      vertical: control.dense ? GitSpacing.xxs : GitSpacing.sm,
                    ),
                child: Row(
                  children: [
                    if (control.leading != null) ...[
                      control.leading!,
                      const SizedBox(width: GitSpacing.sm),
                    ],
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: control.enabled
                              ? NativeGitSurface.of(context).foreground
                              : NativeGitSurface.of(context).disabledForeground,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (control.title != null) control.title!,
                            if (control.subtitle != null)
                              DefaultTextStyle.merge(
                                style: _gitNativeTheme(
                                  context,
                                ).textTheme.bodySmall,
                                child: control.subtitle!,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (control.trailing != null) control.trailing!,
      ],
    ),
  );

  @override
  double changeRowTextInset(BuildContext context, int depth) =>
      GitSpacing.sm +
      GitSizes.sidebarTreeDepthBase +
      depth * GitSizes.sidebarTreeDepthIndent +
      GitSizes.sidebarTreeControl +
      GitSpacing.xs +
      GitSizes.sidebarTreeControl +
      GitSpacing.sm +
      GitSizes.sidebarTreeControl +
      GitSpacing.xs;
  @override
  Widget changeRow(BuildContext context, git.GitChangeRow control) {
    if (control.trailing != null) {
      throw StateError('Git entries require contextual actions.');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GitSpacing.sm),
      child: NativeGitTreeRow(
        title: control.title,
        depth: control.depth,
        selected: control.selected,
        expanded: control.expanded,
        group: control.group,
        onToggle: control.onToggle,
        onTap: control.onTap,
        onDoubleTap: control.onDoubleTap,
        onSecondaryTapUp: control.onSecondaryTapUp,
        tooltip: control.tooltip,
        leading: Icon(
          control.expanded != null
              ? (control.expanded! ? YaruIcons.folder_open : YaruIcons.folder)
              : _fileIcon(control.title),
          size: GitSizes.iconSm,
        ),
        status: control.status,
        reserveStatus: true,
      ),
    );
  }

  IconData _fileIcon(String title) {
    final name = title.toLowerCase();
    if (name.endsWith('.md') || name.endsWith('.txt'))
      return YaruIcons.text_editor;
    if (RegExp(r'\.(png|jpe?g|gif|webp|svg)$').hasMatch(name))
      return YaruIcons.image;
    if (RegExp(r'\.(dart|c|cc|cpp|h|py|js|ts|json|yaml|yml)$').hasMatch(name))
      return YaruIcons.code;
    return YaruIcons.document;
  }

  @override
  EdgeInsetsGeometry logContentInsets(BuildContext context) =>
      const EdgeInsetsDirectional.fromSTEB(
        GitSpacing.mdPlus,
        GitSpacing.sm,
        GitSpacing.sm,
        GitSpacing.sm,
      );
  @override
  Widget logHeader(BuildContext context, git.GitLogHeader control) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(
      GitSpacing.mdPlus,
      0,
      GitSpacing.sm,
      GitSpacing.sm,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: GitSizes.iconButton),
      child: Row(
        children: [
          Expanded(child: control.subject),
          const SizedBox(width: GitSpacing.sm),
          control.choose,
          const SizedBox(width: GitSpacing.sm),
          control.actions,
        ],
      ),
    ),
  );

  @override
  Widget historyLayout(BuildContext context, git.GitHistoryLayout control) =>
      _GitHistoryLayout(control: control);

  @override
  Widget referenceRow(BuildContext context, git.GitReferenceRow control) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NativeGitTreeRow(
            title: control.title,
            depth: control.depth,
            leading: control.leading,
            selected: control.selected,
            expanded: control.expanded,
            onToggle: control.onToggle,
            onTap: control.onTap,
            onSecondaryTapUp: control.onSecondaryTapUp,
            tooltip: control.title,
          ),
          if (control.expanded ?? false) ...control.children,
        ],
      );

  @override
  Widget expander(BuildContext context, git.GitExpander control) {
    return _GitExpander(control: control);
  }

  @override
  Widget progress(BuildContext context, git.GitLoading control) => Semantics(
    label: control.semanticsLabel,
    liveRegion: true,
    child: control.circular
        ? YaruCircularProgressIndicator(strokeWidth: control.strokeWidth)
        : YaruLinearProgressIndicator(strokeWidth: control.strokeWidth),
  );
  @override
  Widget tooltip(BuildContext context, git.GitTooltip control) =>
      NativeGitTooltip.wrap(
        context,
        message: control.message,
        child: control.child,
      );
  @override
  Widget scrollbar(BuildContext context, git.GitScrollbar control) {
    final colors = NativeGitSurface.of(context);
    return RawScrollbar(
      controller: control.controller,
      thumbVisibility: control.thumbVisibility,
      thumbColor: colors.mutedForeground.withValues(alpha: .65),
      radius: const Radius.circular(kYaruButtonRadius),
      thickness: GitSpacing.xs,
      child: control.child,
    );
  }

  @override
  Widget separator(BuildContext context, git.GitSeparator control) {
    final color = NativeGitSurface.of(context).divider;
    return SizedBox(
      width: control.vertical ? control.width : null,
      height: control.vertical ? null : control.height,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(color: color),
          child: SizedBox(
            width: control.vertical ? GitStroke.hairline : double.infinity,
            height: control.vertical ? double.infinity : GitStroke.hairline,
          ),
        ),
      ),
    );
  }

  @override
  Widget activation(BuildContext context, git.GitActivation control) {
    return NativeGitRowSurface(
      enabled: control.onTap != null,
      clickable: control.onTap != null,
      focusNode: control.focusNode,
      onTap: control.onTap,
      onDoubleTap: control.onDoubleTap,
      onSecondaryTapUp: control.onSecondaryTapUp,
      child: control.child,
    );
  }

  @override
  Widget notice(BuildContext context, git.GitNotice control) {
    final colors = NativeGitSurface.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel,
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(GitSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (control.leading != null) ...[
                    control.leading!,
                    const SizedBox(width: GitSpacing.sm),
                  ],
                  Expanded(child: control.content),
                ],
              ),
              Wrap(spacing: GitSpacing.sm, children: control.actions),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget selectable(BuildContext context, git.GitSelectableText control) =>
      SelectableRegion(
        selectionControls: emptyTextSelectionControls,
        contextMenuBuilder: (menuContext, editable) => git.GitTextContextMenu(
          host: git.GitHostScope.of(context)!,
          items: editable.contextMenuButtonItems,
          position: editable.contextMenuAnchors.primaryAnchor,
          close: editable.hideToolbar,
        ),
        child: Semantics(
          label: control.data,
          child: Text(control.data, style: control.style),
        ),
      );
  @override
  Widget selectionArea(BuildContext context, Widget child) => SelectableRegion(
    selectionControls: emptyTextSelectionControls,
    contextMenuBuilder: (menuContext, region) => git.GitTextContextMenu(
      host: git.GitHostScope.of(context)!,
      items: region.contextMenuButtonItems,
      position: region.contextMenuAnchors.primaryAnchor,
      close: region.hideToolbar,
    ),
    child: child,
  );
  @override
  String editingActionLabel(BuildContext context, ContextMenuButtonType type) {
    final labels = MaterialLocalizations.of(context);
    return switch (type) {
      ContextMenuButtonType.cut => labels.cutButtonLabel,
      ContextMenuButtonType.copy => labels.copyButtonLabel,
      ContextMenuButtonType.paste => labels.pasteButtonLabel,
      ContextMenuButtonType.selectAll => labels.selectAllButtonLabel,
      _ => labels.moreButtonTooltip,
    };
  }
}

class _GitDateRange extends StatefulWidget {
  const _GitDateRange({this.start, this.end});
  final DateTime? start, end;
  @override
  State<_GitDateRange> createState() => _GitDateRangeState();
}

class _GitDateRangeState extends State<_GitDateRange> {
  final _startEntry = TextEditingController(),
      _endEntry = TextEditingController();
  bool _initialized = false, _submitted = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final labels = MaterialLocalizations.of(context);
    _startEntry.text = widget.start == null
        ? ''
        : labels.formatCompactDate(widget.start!);
    _endEntry.text = widget.end == null
        ? ''
        : labels.formatCompactDate(widget.end!);
  }

  @override
  void dispose() {
    _startEntry.dispose();
    _endEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MaterialLocalizations.of(context);
    // CLDR date patterns can contain invisible direction marks. Keep them in
    // formatted values, but do not require users to type formatting controls.
    // The field order and separators still come from this locale's formatter.
    final directionMarks = RegExp('[\u061c\u200e\u200f\u2066-\u2069]');
    final localeFormat = intl.DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    );
    final pattern = localeFormat.pattern!.replaceAll(directionMarks, '');
    final parser = intl.DateFormat(pattern, localeFormat.locale)
      ..useNativeDigits = false;
    final zero = localeFormat.localeZeroCodeUnit;
    DateTime? parse(String input) {
      if (input.isEmpty) return null;
      try {
        final text = input
            .replaceAll(directionMarks, '')
            .runes
            .map(
              (digit) => digit >= zero && digit < zero + 10
                  ? 0x30 + digit - zero
                  : digit,
            );
        return parser.parseStrict(String.fromCharCodes(text));
      } on FormatException {
        return null;
      }
    }

    final hint = pattern.replaceAllMapped(
      RegExp(r'd+|M+|y+'),
      (match) => switch (match[0]![0]) {
        'd' => 'dd',
        'M' => 'mm',
        _ => 'yyyy',
      },
    );
    final start = parse(_startEntry.text);
    final end = parse(_endEntry.text);
    final last = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 1)),
    );
    bool acceptable(DateTime? value) =>
        value != null &&
        !value.isBefore(DateTime(1970)) &&
        !value.isAfter(last);
    final valid =
        acceptable(start) && acceptable(end) && !end!.isBefore(start!);
    final invalidRange = start != null && end != null && end.isBefore(start);
    void save() {
      if (!valid || _submitted || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _submitted = true;
      git.gitCompleteSurface(context, (start, end));
    }

    Widget field(
      String key,
      String label,
      TextEditingController entry,
      DateTime? value,
    ) => Column(
      key: ValueKey(key),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: GitSpacing.xs),
        Semantics(
          label: label,
          child: NativeGitTextEntry(
            controller: entry,
            label: '',
            hintText: hint,
            dense: true,
            contextMenuBuilder: (menuContext, editable) =>
                git.GitTextContextMenu(
                  host: git.GitHostScope.of(context)!,
                  items: editable.contextMenuButtonItems,
                  position: editable.contextMenuAnchors.primaryAnchor,
                  close: editable.hideToolbar,
                ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => save(),
            trailing: entry.text.isEmpty
                ? const SizedBox.square(dimension: GitSizes.iconButton)
                : NativeGitIconAction(
                    key: ValueKey('$key-clear'),
                    focusBorderRadius: GitRadius.headerButton,
                    tooltip: labels.deleteButtonTooltip,
                    icon: YaruIcons.edit_clear,
                    onPressed: () => setState(entry.clear),
                  ),
          ),
        ),
        if (entry.text.isNotEmpty && !acceptable(value)) ...[
          const SizedBox(height: GitSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              value == null
                  ? labels.invalidDateFormatLabel
                  : labels.dateOutOfRangeLabel,
              style: TextStyle(color: YaruColors.of(context).error),
            ),
          ),
        ],
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field('git-date-start', labels.dateRangeStartLabel, _startEntry, start),
        const SizedBox(height: GitSpacing.lg),
        field('git-date-end', labels.dateRangeEndLabel, _endEntry, end),
        if (invalidRange) ...[
          const SizedBox(height: GitSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              labels.invalidDateRangeLabel,
              style: TextStyle(color: YaruColors.of(context).error),
            ),
          ),
        ],
        const SizedBox(height: GitSpacing.lg),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: GitSpacing.sm,
          overflowSpacing: GitSpacing.sm,
          children: [
            NativeGitActionButton(
              compact: true,
              role: NativeGitActionRole.standard,
              onPressed: () => git.gitCompleteSurface(context),
              child: Text(labels.cancelButtonLabel),
            ),
            NativeGitActionButton(
              compact: true,
              role: NativeGitActionRole.suggested,
              onPressed: valid ? save : null,
              child: Text(labels.saveButtonLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class NativeGitIconAction extends StatelessWidget {
  const NativeGitIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.focusBorderRadius = kYaruButtonRadius,
    this.selected = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double focusBorderRadius;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final button = YaruIconButton(
      hasFocusBorder: false,
      isSelected: selected,
      tooltip: tooltip.trim().isEmpty ? null : tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: GitSizes.iconSm),
      iconSize: GitSizes.iconButton,
      padding: EdgeInsets.zero,
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => NativeGitSurface.of(context).foreground.withValues(
            alpha: states.contains(WidgetState.disabled) ? .38 : 1,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          final pressed = states.contains(WidgetState.pressed);
          final hovered = states.contains(WidgetState.hovered);
          final alpha = states.contains(WidgetState.disabled)
              ? 0.0
              : selected && pressed
              ? .19
              : selected && hovered
              ? .13
              : pressed
              ? .16
              : selected
              ? .10
              : hovered
              ? .07
              : 0.0;
          return NativeGitSurface.of(
            context,
          ).foreground.withValues(alpha: alpha);
        }),
        overlayColor: WidgetStatePropertyAll(
          _gitNativeTheme(context).colorScheme.surface.withValues(alpha: 0),
        ),
        fixedSize: const WidgetStatePropertyAll(
          Size.square(GitSizes.iconButton),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(focusBorderRadius),
          ),
        ),
      ),
    );
    return Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      child: YaruTheme.maybeOf(context)?.focusBorders != false
          ? YaruFocusBorder.primary(
              borderRadius: BorderRadius.circular(focusBorderRadius),
              child: button,
            )
          : button,
    );
  }
}

class NativeGitCheckbox extends StatelessWidget {
  const NativeGitCheckbox({
    super.key,
    this.label,
    required this.value,
    required this.tristate,
    required this.onChanged,
  });
  final String? label;
  final bool? value;
  final bool tristate;
  final ValueChanged<bool?>? onChanged;
  @override
  Widget build(BuildContext context) {
    final theme = _gitNativeTheme(context);
    final titleStyle = theme.textTheme.bodyMedium!.copyWith(
      inherit: false,
      color: onChanged == null
          ? NativeGitSurface.of(context).disabledForeground
          : theme.colorScheme.onSurface,
    );
    return YaruToggleButtonTheme(
      data:
          theme.extension<YaruToggleButtonThemeData>() ??
          const YaruToggleButtonThemeData(),
      child: YaruCheckboxTheme(
        data:
            theme.extension<YaruCheckboxThemeData>() ??
            const YaruCheckboxThemeData(),
        child: label == null
            ? YaruCheckbox(
                value: value,
                tristate: tristate,
                onChanged: onChanged,
              )
            : YaruCheckButton(
                value: value,
                tristate: tristate,
                onChanged: onChanged,
                contentPadding: EdgeInsets.zero,
                title: Text(label!, style: titleStyle),
              ),
      ),
    );
  }
}

/// Empty tooltip requests have no overlay or hover timer.
abstract final class NativeGitTooltip {
  static Widget wrap(
    BuildContext context, {
    required String message,
    required Widget child,
  }) => message.trim().isEmpty
      ? child
      : _NativeGitTooltip(message: message, child: child);
}

class _NativeGitTooltip extends StatefulWidget {
  const _NativeGitTooltip({required this.message, required this.child});
  final String message;
  final Widget child;
  @override
  State<_NativeGitTooltip> createState() => _NativeGitTooltipState();
}

class _NativeGitTooltipState extends State<_NativeGitTooltip> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  Timer? _timer;
  void _hide() {
    _timer?.cancel();
    if (_controller.isShowing) _controller.hide();
  }

  @override
  void didUpdateWidget(_NativeGitTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message) _hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    tooltip: widget.message,
    child: MouseRegion(
      onEnter: (_) {
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 500), () {
          if (mounted && widget.message.trim().isNotEmpty) _controller.show();
        });
      },
      onExit: (_) => _hide(),
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) => IgnorePointer(
          child: CompositedTransformFollower(
            showWhenUnlinked: false,
            link: _link,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 4),
            child: Align(
              alignment: Alignment.topCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _gitNativeTheme(context).colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(kYaruButtonRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    widget.message,
                    style: _gitNativeTheme(context).textTheme.bodySmall
                        ?.copyWith(
                          color: _gitNativeTheme(
                            context,
                          ).colorScheme.onInverseSurface,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(link: _link, child: widget.child),
      ),
    ),
  );
}

class NativeGitTreeRow extends StatelessWidget {
  const NativeGitTreeRow({
    super.key,
    required this.title,
    required this.depth,
    this.leading,
    this.status,
    this.reserveStatus = false,
    this.expanded,
    this.group = false,
    this.selected = false,
    this.onToggle,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.tooltip,
  });
  final String title;
  final int depth;
  final Widget? leading;
  final String? status, tooltip;
  final bool? expanded;
  final bool selected, group, reserveStatus;
  final VoidCallback? onToggle, onTap, onDoubleTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final row = Semantics(
      selected: selected,
      expanded: expanded,
      child: NativeGitRowSurface(
        enabled: true,
        clickable: onTap != null || onToggle != null,
        selected: selected,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapUp: onSecondaryTapUp,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent || expanded == null)
            return KeyEventResult.ignored;
          final open = rtl
              ? LogicalKeyboardKey.arrowLeft
              : LogicalKeyboardKey.arrowRight;
          final close = rtl
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft;
          if (event.logicalKey == open && !expanded! ||
              event.logicalKey == close && expanded!) {
            onToggle?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          children: [
            SizedBox(
              width:
                  GitSizes.sidebarTreeDepthBase +
                  depth * GitSizes.sidebarTreeDepthIndent,
            ),
            SizedBox.square(
              dimension: GitSizes.sidebarTreeControl,
              child: expanded == null
                  ? null
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: AnimatedRotation(
                        turns: expanded! ? (rtl ? -.25 : .25) : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 120),
                        child: Icon(
                          rtl ? YaruIcons.pan_start : YaruIcons.pan_end,
                          size: GitSizes.sidebarTreeArrow,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: GitSpacing.xs),
            SizedBox.square(
              dimension: GitSizes.sidebarTreeControl,
              child: Center(child: leading),
            ),
            const SizedBox(width: GitSpacing.sm),
            if (reserveStatus || status != null) ...[
              SizedBox.square(
                dimension: GitSizes.sidebarTreeControl,
                child: Center(
                  child: Text(
                    status ?? '',
                    style: _gitNativeTheme(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(width: GitSpacing.xs),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: group
                    ? _gitNativeTheme(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: GitSpacing.xs),
          ],
        ),
      ),
    );
    return NativeGitTooltip.wrap(context, message: tooltip ?? '', child: row);
  }
}

class _GitExpander extends StatefulWidget {
  const _GitExpander({required this.control});
  final git.GitExpander control;
  @override
  State<_GitExpander> createState() => _GitExpanderState();
}

class _GitExpanderState extends State<_GitExpander> {
  late bool _expanded = widget.control.initiallyExpanded;
  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.control.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        expanded: _expanded,
        child: NativeGitRowSurface(
          enabled: true,
          clickable: true,
          onTap: _toggle,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final rtl = Directionality.of(context) == TextDirection.rtl;
            final open = rtl
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight;
            final close = rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft;
            if (event.logicalKey == open && !_expanded ||
                event.logicalKey == close && _expanded) {
              _toggle();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            children: [
              const SizedBox(width: GitSizes.sidebarTreeDepthBase),
              SizedBox.square(
                dimension: GitSizes.sidebarTreeControl,
                child: Icon(
                  _expanded
                      ? YaruIcons.pan_down
                      : Directionality.of(context) == TextDirection.rtl
                      ? YaruIcons.pan_start
                      : YaruIcons.pan_end,
                  size: GitSizes.sidebarTreeArrow,
                ),
              ),
              const SizedBox(width: GitSpacing.xs),
              Expanded(child: widget.control.title),
            ],
          ),
        ),
      ),
      if (_expanded) ...widget.control.children,
    ],
  );
}

/// Git owns its internal modal grid. Hosts only present/dismiss this surface.
class _GitHistoryLayout extends StatelessWidget {
  const _GitHistoryLayout({required this.control});
  final git.GitHistoryLayout control;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final sidebarWidth = (bounds.maxWidth * control.sidebarFraction)
          .clamp(220.0, math.max(220.0, bounds.maxWidth * .4))
          .toDouble();
      final wide =
          bounds.maxWidth >=
          sidebarWidth + math.max(560, control.minimumHistoryWidth);
      // A narrow reference overlay is an explicit choice. Resizing while
      // editing a history filter must not cover it or discard IME focus.
      final visible = wide
          ? control.sidebarVisible
          : control.compactSidebarVisible;
      final title = git.gitString(context, git.GitMessages.gitLog);
      final titleStyle = _gitNativeTheme(context).textTheme.titleMedium;
      final titleMeasure = TextPainter(
        text: TextSpan(text: title, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final titleStart = (bounds.maxWidth - titleMeasure.width) / 2;
      final toggleStart = visible
          ? sidebarWidth + GitSpacing.headerInset
          : GitSpacing.headerInset;
      final needsSecondHeaderRow =
          toggleStart < titleStart + titleMeasure.width + GitSpacing.sm &&
          toggleStart + GitSizes.iconButton + GitSpacing.sm > titleStart;
      titleMeasure.dispose();
      final headerHeight =
          GitSizes.toolbarHeight * (needsSecondHeaderRow ? 2 : 1);
      final footer = control.footer == null
          ? null
          : Padding(
              key: const ValueKey('git-history-footer'),
              padding: const EdgeInsets.all(GitSpacing.lg),
              child: control.footer!,
            );
      final header = SizedBox(
        key: const ValueKey('git-history-header'),
        height: headerHeight,
        child: Stack(
          children: [
            SizedBox(
              height: GitSizes.toolbarHeight,
              child: Center(
                child: Text(
                  title,
                  key: const ValueKey('git-history-title'),
                  style: titleStyle,
                ),
              ),
            ),
            PositionedDirectional(
              start: toggleStart,
              top:
                  (needsSecondHeaderRow ? GitSizes.toolbarHeight : 0) +
                  (GitSizes.toolbarHeight - GitSizes.iconButton) / 2,
              child: Semantics(
                toggled: visible,
                child: NativeGitIconAction(
                  key: const ValueKey('git-history-sidebar-toggle'),
                  tooltip: git.gitString(context, git.GitMessages.branches),
                  icon: YaruIcons.sidebar,
                  selected: visible,
                  onPressed: wide
                      ? control.onToggle
                      : control.onToggleCompact ?? control.onToggle,
                ),
              ),
            ),
            PositionedDirectional(
              end: GitSpacing.headerInset,
              top: (GitSizes.toolbarHeight - kYaruWindowControlSize) / 2,
              child: YaruWindowControl(
                type: YaruWindowControlType.close,
                semanticLabel: MaterialLocalizations.of(
                  context,
                ).closeButtonTooltip,
                onTap: () => _nativeGitClose(context),
              ),
            ),
          ],
        ),
      );
      final sidebar = DecoratedBox(
        key: const ValueKey('git-history-reference-sidebar'),
        decoration: BoxDecoration(
          color: NativeGitSurface.of(context).sidebar,
          border: BorderDirectional(
            end: BorderSide(color: NativeGitSurface.of(context).divider),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('git-history-sidebar-header'),
              height: headerHeight,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(GitSpacing.sm),
                child: control.sidebar,
              ),
            ),
          ],
        ),
      );
      return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: [
                      SizedBox(width: wide && visible ? sidebarWidth : 0),
                      Expanded(
                        child: ExcludeFocus(
                          excluding: !wide && visible,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: headerHeight),
                              control.toolbar,
                              Expanded(child: control.main),
                              if (wide && footer != null) footer,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: sidebarWidth,
                  child: Offstage(
                    offstage: !visible,
                    child: ExcludeFocus(excluding: !visible, child: sidebar),
                  ),
                ),
                if (wide && visible)
                  PositionedDirectional(
                    start: sidebarWidth - 2,
                    top: headerHeight,
                    bottom: 0,
                    width: 4,
                    child: Semantics(
                      slider: true,
                      label: git.gitString(
                        context,
                        git.GitMessages.resizeGitPanes,
                      ),
                      onIncrease: () => control.onResize(
                        (sidebarWidth + 24) / bounds.maxWidth,
                      ),
                      onDecrease: () => control.onResize(
                        (sidebarWidth - 24) / bounds.maxWidth,
                      ),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (details) => control.onResize(
                            (sidebarWidth +
                                    details.delta.dx *
                                        (Directionality.of(context) ==
                                                TextDirection.rtl
                                            ? -1
                                            : 1)) /
                                bounds.maxWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(top: 0, left: 0, right: 0, child: header),
              ],
            ),
          ),
          if (!wide && footer != null) footer,
        ],
      );
    },
  );
}

class GitNativeDialog extends StatelessWidget {
  const GitNativeDialog({
    super.key,
    required this.title,
    required this.child,
    this.expanded = false,
  });
  final String title;
  final Widget child;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ownsHeader = git.GitDialogBody.ownsHeader(child);
    final content = DefaultTextStyle(
      style: _gitNativeTheme(context).textTheme.bodyMedium!,
      child: child,
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: expanded ? size.width * .94 : GitSizes.dialogWide,
              maxHeight: size.height * .86,
            ),
            child: YaruBorderContainer(
              color: NativeGitSurface.of(context).panel,
              borderRadius: BorderRadius.circular(kYaruWindowRadius),
              child: SizedBox(
                width: expanded ? size.width * .94 : GitSizes.dialogWide,
                height: expanded ? size.height * .86 : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!ownsHeader)
                      SizedBox(
                        height: GitSizes.toolbarHeight,
                        child: Stack(
                          children: [
                            Center(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _gitNativeTheme(
                                  context,
                                ).textTheme.titleMedium,
                              ),
                            ),
                            PositionedDirectional(
                              end: GitSpacing.headerInset,
                              top: 6,
                              child: YaruWindowControl(
                                type: YaruWindowControlType.close,
                                semanticLabel: MaterialLocalizations.of(
                                  context,
                                ).closeButtonTooltip,
                                onTap: () => _nativeGitClose(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (expanded)
                      Expanded(child: content)
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(GitSpacing.lg),
                          child: content,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _nativeGitClose(BuildContext context) async {
  if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
    await Navigator.of(context).maybePop();
  }
}
