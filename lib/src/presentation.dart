import 'package:busystack_git/busystack_git.dart'
    show GitException, GitErrorCode;
import 'messages.dart';
import 'package:flutter/material.dart' show ThemeData, TextAlignVertical;
import 'package:flutter/widgets.dart';
import 'host.dart';

/// Required native control boundary, implemented by each application's existing
/// design system. There is deliberately no default or Material implementation.
abstract interface class GitPresentation {
  /// Native entry actions are contextual in BusyMark; BusyFiles retains its
  /// established trailing controls. Feature controls never guess or fall back.
  GitEntryActionPlacement get entryActionPlacement;
  ThemeData theme(BuildContext context);
  TextStyle? codeStyle(BuildContext context);
  String formatCommitDate(
    BuildContext context,
    DateTime date, {
    bool full = false,
  });
  GitColors colors(BuildContext context);
  Future<(DateTime, DateTime)?> dateRange(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  });
  Widget button(BuildContext context, GitButton control);
  Widget iconAction(BuildContext context, GitIconButton control);
  Widget field(BuildContext context, GitTextField control);
  Widget checkbox(BuildContext context, GitCheckbox control);
  Widget choice<T>(BuildContext context, GitChoice<T> control);
  Widget choiceBar<T>(BuildContext context, GitChoiceBar<T> control);
  Widget row(BuildContext context, GitActionRow control);
  Widget expander(BuildContext context, GitExpander control);
  Widget progress(BuildContext context, GitLoading control);
  Widget tooltip(BuildContext context, GitTooltip control);
  Widget separator(BuildContext context, GitSeparator control);
  Widget scrollbar(BuildContext context, GitScrollbar control);
  Widget activation(BuildContext context, GitActivation control);
  Widget changeRow(BuildContext context, GitChangeRow control);
  double changeRowTextInset(BuildContext context, int depth);
  Widget notice(BuildContext context, GitNotice control);
  Widget selectable(BuildContext context, GitSelectableText control);
  Widget selectionArea(BuildContext context, Widget child);
  String editingActionLabel(BuildContext context, ContextMenuButtonType type);
}

GitPresentation gitPresentation(BuildContext context) {
  final host = GitHostScope.of(context);
  if (host == null)
    throw StateError('Git requires the host native presentation scope.');
  return host.presentation;
}

abstract final class GitTheme {
  static ThemeData of(BuildContext context) =>
      gitPresentation(context).theme(context);
}

enum GitEntryActionPlacement { contextMenu, trailing }

enum GitActionStyle { standard, suggested, inline }

final class GitButton extends StatelessWidget {
  const GitButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = GitActionStyle.inline,
    this.compact = false,
  });
  GitButton.icon({
    super.key,
    required this.onPressed,
    required Widget icon,
    required Widget label,
    this.variant = GitActionStyle.inline,
    this.compact = false,
  }) : child = Row(
         mainAxisSize: MainAxisSize.min,
         children: [
           icon,
           const SizedBox(width: 8),
           Flexible(child: label),
         ],
       );
  const GitButton.primary({
    super.key,
    required this.onPressed,
    required this.child,
    this.compact = false,
  }) : variant = GitActionStyle.suggested;
  const GitButton.standard({
    super.key,
    required this.onPressed,
    required this.child,
    this.compact = false,
  }) : variant = GitActionStyle.standard;
  final VoidCallback? onPressed;
  final Widget child;
  final GitActionStyle variant;

  /// Desktop toolbar/dialog action insets; unrelated footer actions keep their geometry.
  final bool compact;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).button(context, this);
}

/// Text/controller ownership stays with the Git editor; the host supplies its
/// native input surface without replacing selection, composing range or undo.
final class GitFieldDecoration {
  const GitFieldDecoration({
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.contentPadding,
    this.isDense = false,
    this.alignLabelWithHint = false,
  });
  final String? labelText, hintText;
  final Widget? prefixIcon, suffixIcon;
  final EdgeInsetsGeometry? contentPadding;
  final bool isDense, alignLabelWithHint;
}

final class GitTextField extends StatelessWidget {
  const GitTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.scrollController,
    this.undoController,
    this.style,
    this.autofocus = false,
    this.readOnly = false,
    this.expands = false,
    this.enabled,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.textAlignVertical,
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final GitFieldDecoration? decoration;
  final ScrollController? scrollController;
  final UndoHistoryController? undoController;
  final TextStyle? style;
  final bool autofocus;
  final bool readOnly;
  final bool expands;
  final bool? enabled;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final TextAlignVertical? textAlignVertical;
  final TextDirection? textDirection;
  final TextAlign textAlign;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).field(context, this);
}

final class GitCheckbox extends StatelessWidget {
  const GitCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  /// A desktop check choice whose native label shares the activation target.
  final String? label;
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).checkbox(context, this);
}

final class GitActionRow extends StatelessWidget {
  const GitActionRow({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.dense = false,
    this.contentPadding,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    this.onSecondaryTapUp,
  });
  final Widget? title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final bool dense;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).row(context, this);
}

/// Semantic tree request. The host owns row geometry, native disclosure and
/// action treatment; the shared tree keeps reviewed selection and transactions.
final class GitChangeRow extends StatelessWidget {
  const GitChangeRow({
    super.key,
    required this.title,
    required this.depth,
    required this.onTap,
    required this.onPointerDown,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.onToggle,
    this.expanded,
    this.selected = false,
    this.group = false,
    this.status,
    this.tooltip,
    this.trailing,
  });
  final String title;
  final int depth;
  final bool selected, group;
  final bool? expanded;
  final String? status, tooltip;
  final Widget? trailing;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap, onToggle;
  final GestureTapUpCallback? onSecondaryTapUp;
  final PointerDownEventListener onPointerDown;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: onPointerDown,
    child: gitPresentation(context).changeRow(context, this),
  );
}

final class GitExpander extends StatelessWidget {
  const GitExpander({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });
  final Widget title;
  final List<Widget> children;
  final bool initiallyExpanded;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).expander(context, this);
}

final class GitLoading extends StatelessWidget {
  const GitLoading({
    super.key,
    this.semanticsLabel,
    this.strokeWidth,
    this.circular = false,
  });
  final String? semanticsLabel;
  final double? strokeWidth;
  final bool circular;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).progress(context, this);
  const GitLoading.spinner({super.key, this.semanticsLabel, this.strokeWidth})
    : circular = true;
}

final class GitTooltip extends StatelessWidget {
  const GitTooltip({super.key, required this.message, required this.child});
  final String message;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).tooltip(context, this);
}

final class GitSeparator extends StatelessWidget {
  const GitSeparator({
    super.key,
    this.height,
    this.width,
    this.vertical = false,
  });
  final double? height;
  final double? width;
  final bool vertical;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).separator(context, this);
  const GitSeparator.vertical({super.key, this.width})
    : vertical = true,
      height = null;
}

final class GitActivation extends StatelessWidget {
  const GitActivation({
    super.key,
    required this.child,
    this.focusNode,
    this.onPointerDown,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
  });
  final Widget child;
  final FocusNode? focusNode;
  final PointerDownEventListener? onPointerDown;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: onPointerDown,
    child: gitPresentation(context).activation(context, this),
  );
}

final class GitNotice extends StatelessWidget {
  const GitNotice({
    super.key,
    required this.content,
    required this.actions,
    this.leading,
  });
  final Widget content;
  final List<Widget> actions;
  final Widget? leading;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).notice(context, this);
}

final class GitChoiceItem<T> {
  const GitChoiceItem({required this.value, required this.child});
  final T value;
  final Widget child;
}

final class GitChoice<T> extends StatelessWidget {
  const GitChoice({
    super.key,
    this.value,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.decoration,
    this.underline,
  });
  final T? value, initialValue;
  final List<GitChoiceItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final GitFieldDecoration? decoration;
  final Widget? underline;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).choice(context, this);
}

/// Native check control and native row share one meaning, including keyboard
/// activation. A trailing control consumes its own activation event.
final class GitCheckRow extends StatelessWidget {
  const GitCheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.dense = false,
    this.contentPadding,
  });
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? title, subtitle;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext context) => GitActionRow(
    title: title,
    subtitle: subtitle,
    dense: dense,
    contentPadding: contentPadding,
    enabled: onChanged != null,
    onTap: onChanged == null ? null : () => onChanged!(!(value ?? false)),
    leading: GitCheckbox(value: value, onChanged: onChanged),
  );
}

final class GitSegment<T> {
  const GitSegment({required this.value, required this.label, this.icon});
  final T value;
  final Widget label;
  final Widget? icon;
}

final class GitChoiceBar<T> extends StatelessWidget {
  const GitChoiceBar({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
  });
  final List<GitSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).choiceBar(context, this);
}

final class GitFilterChoice extends StatelessWidget {
  const GitFilterChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  @override
  Widget build(BuildContext context) => GitCheckRow(
    title: label,
    value: selected,
    dense: true,
    onChanged: onSelected == null ? null : (value) => onSelected!(value!),
  );
}

final class GitFilterLabel extends StatelessWidget {
  const GitFilterLabel({
    super.key,
    required this.label,
    required this.onDeleted,
  });
  final Widget label;
  final VoidCallback? onDeleted;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: label),
      GitIconButton(
        tooltip: GitMessages.removeFilter,
        onPressed: onDeleted,
        icon: const GitIcon(GitGlyph.close),
      ),
    ],
  );
}

/// Choice labels are already translated by their owning feature. Repository
/// data stays literal. Only these two neutral label forms are accepted.
String gitControlLabel(BuildContext context, Widget label) => switch (label) {
  Text(:final data) when data != null => data,
  GitLabel(:final message, :final values) => gitString(
    context,
    message,
    values: values,
  ),
  _ => throw StateError('A native Git choice requires a text label.'),
};

/// Git meanings are mapped by the host to its native semantic colors. Feature
/// views cannot choose a palette or reinterpret a Material accent as a status.
final class GitColors {
  const GitColors({
    required this.accent,
    required this.selection,
    required this.border,
    required this.subtleBorder,
    required this.surface,
    required this.mutedText,
    required this.added,
    required this.removed,
    required this.staged,
    required this.unstaged,
    required this.conflict,
    required this.addedBackground,
    required this.removedBackground,
    required this.stagedBackground,
    required this.unstagedBackground,
    required this.conflictBackground,
    required this.searchBackground,
  });
  final Color accent, selection, border, subtleBorder, surface, mutedText;
  final Color added, removed, staged, unstaged, conflict;
  final Color addedBackground,
      removedBackground,
      stagedBackground,
      unstagedBackground,
      conflictBackground,
      searchBackground;

  /// Hosts supply word-level backgrounds, already treated for readable text.
  /// Line emphasis reduces that treatment without discarding host opacity.
  Color get addedLineBackground =>
      addedBackground.withValues(alpha: addedBackground.a * .4);
  Color get removedLineBackground =>
      removedBackground.withValues(alpha: removedBackground.a * .4);
  Color get transparent => surface.withValues(alpha: 0);
  static GitColors of(BuildContext context) =>
      gitPresentation(context).colors(context);
}

final class GitSelectionArea extends StatelessWidget {
  const GitSelectionArea({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).selectionArea(context, child);
}

/// A native text menu retains Flutter's public text action callbacks. It owns
/// only completion/lifetime; it never paints a substitute toolbar.
final class GitTextContextMenu extends StatefulWidget {
  const GitTextContextMenu({
    super.key,
    required this.host,
    required this.items,
    required this.position,
    required this.close,
  });
  final GitHost host;
  final List<ContextMenuButtonItem> items;
  final Offset position;
  final VoidCallback close;
  @override
  State<GitTextContextMenu> createState() => _GitTextContextMenuState();
}

final class _GitTextContextMenuState extends State<GitTextContextMenu> {
  bool _finished = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted || _finished) return;
    try {
      final selected = await widget.host.menu(context, '', [
        for (var i = 0; i < widget.items.length; i++)
          GitMenuEntry(
            '$i',
            widget.items[i].label ??
                widget.host.presentation.editingActionLabel(
                  context,
                  widget.items[i].type,
                ),
            enabled: widget.items[i].onPressed != null,
            localize: false,
          ),
      ], position: widget.position);
      if (!mounted || _finished) return;
      _finished = true;
      if (selected != null) widget.items[int.parse(selected)].onPressed?.call();
    } on GitException catch (error) {
      if (error.code != GitErrorCode.unavailable) rethrow;
    } finally {
      if (mounted) {
        _finished = true;
        widget.close();
      }
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Scroll interaction and chrome are supplied by the same native host as panes.
final class GitScrollbar extends StatelessWidget {
  const GitScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
  });
  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).scrollbar(context, this);
}
