import 'file_status.dart';
import 'package:busystack_git/busystack_git.dart'
    show GitException, GitErrorCode;
import 'messages.dart';
import 'package:flutter/material.dart' show ThemeData, TextAlignVertical;
import 'package:flutter/widgets.dart';
import 'host.dart';
import 'dart:async';
import 'reference_context_menu.dart';

/// Required native control boundary, implemented once by the shared Linux
/// renderer and consumed by both applications. There is deliberately no default or Material implementation.
abstract interface class GitPresentation {
  /// Native entry actions are contextual in both hosts. Feature controls never
  /// guess a host placement or provide a fallback.
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
  GitToolbarMetrics toolbarMetrics(BuildContext context);
  String repositoryActionsLabel(BuildContext context);
  Widget button(BuildContext context, GitButton control);
  double buttonWidth(BuildContext context, String label, GitActionStyle style);
  Widget iconAction(BuildContext context, GitIconButton control);
  Widget field(BuildContext context, GitTextField control);
  Widget checkbox(BuildContext context, GitCheckbox control);
  Widget choice<T>(BuildContext context, GitChoice<T> control);
  Widget choiceBar<T>(BuildContext context, GitChoiceBar<T> control);
  Widget row(BuildContext context, GitActionRow control);
  Widget expander(BuildContext context, GitExpander control);

  /// One shared native content grid for compact history metadata and headings.
  EdgeInsetsGeometry logContentInsets(BuildContext context);
  Widget logHeader(BuildContext context, GitLogHeader control);
  Widget historyLayout(BuildContext context, GitHistoryLayout control);
  Widget referenceRow(BuildContext context, GitReferenceRow control);
  Widget progress(BuildContext context, GitLoading control);
  Widget tooltip(BuildContext context, GitTooltip control);
  Widget separator(BuildContext context, GitSeparator control);
  Widget scrollbar(BuildContext context, GitScrollbar control);
  Widget activation(BuildContext context, GitActivation control);
  Widget changeRow(BuildContext context, GitChangeRow control);
  double changeRowTextInset(
    BuildContext context,
    int depth, {
    GitEntryIdentity identity = GitEntryIdentity.file,
  });
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

/// Native geometry used by shared toolbar measurement and overflow decisions.
final class GitToolbarMetrics {
  const GitToolbarMetrics({
    required this.iconExtent,
    required this.gap,
    required this.textInsets,
    required this.modeAdornment,
  });
  final double iconExtent, gap, textInsets, modeAdornment;
}

enum GitEntryActionPlacement { contextMenu, trailing }

enum GitActionStyle { standard, suggested, inline, toolbar, diffInline }

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
  const GitButton.toolbar({
    super.key,
    required this.onPressed,
    required this.child,
  }) : variant = GitActionStyle.toolbar,
       compact = true;
  const GitButton.diffInline({
    super.key,
    required this.onPressed,
    required this.child,
  }) : variant = GitActionStyle.diffInline,
       compact = true;
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
  Widget build(BuildContext context) {
    if (trailing case final GitMenuButton menu
        when menu.role == GitMenuRole.entryContext &&
            gitPresentation(context).entryActionPlacement ==
                GitEntryActionPlacement.contextMenu) {
      return _GitContextualActionRow(control: this, menu: menu);
    }
    return gitPresentation(context).row(context, this);
  }
}

/// Contextual entry actions share pointer/keyboard ownership and reject replies
/// after the row's captured model has been replaced. No trailing menu is painted.
final class _GitContextualActionRow extends StatefulWidget {
  const _GitContextualActionRow({required this.control, required this.menu});
  final GitActionRow control;
  final GitMenuButton menu;
  @override
  State<_GitContextualActionRow> createState() =>
      _GitContextualActionRowState();
}

class _GitContextualActionRowState extends State<_GitContextualActionRow> {
  bool _opening = false;
  bool get available =>
      widget.control.enabled &&
      widget.menu.enabled &&
      widget.menu.entries.isNotEmpty;
  Future<void> open(Offset position) async {
    if (_opening || !available) return;
    final control = widget.control, menu = widget.menu;
    _opening = true;
    try {
      final action = await menu.host.menu(
        context,
        menu.tooltip,
        menu.entries,
        position: position,
      );
      if (!mounted || !identical(widget.control, control) || !available) return;
      if (action != null &&
          menu.entries.any(
            (e) => !e.separator && e.enabled && e.id == action,
          )) {
        menu.onSelected(action);
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.control;
    return GitReferenceContextMenu(
      open: available ? open : null,
      child: gitPresentation(context).row(
        context,
        GitActionRow(
          title: c.title,
          subtitle: c.subtitle,
          leading: c.leading,
          dense: c.dense,
          contentPadding: c.contentPadding,
          selected: c.selected,
          enabled: c.enabled,
          onTap: c.onTap,
          onSecondaryTapUp:
              c.onSecondaryTapUp ??
              (available
                  ? (event) => unawaited(open(event.globalPosition))
                  : null),
        ),
      ),
    );
  }
}

/// Semantic tree request. The shared native contract owns row geometry,
/// disclosure and actions; the tree keeps reviewed selection and transactions.
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
    this.statusDescription,
    this.identity = GitEntryIdentity.file,
    this.tooltip,
    this.trailing,
  });
  final String title;
  final int depth;
  final bool selected, group;
  final bool? expanded;
  final GitFileStatus? status;
  final String? statusDescription, tooltip;
  final GitEntryIdentity identity;
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
    this.onExpansionChanged,
  });
  final ValueChanged<bool>? onExpansionChanged;
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

/// Explicit history requests: other expanders and workspace layouts keep their
/// existing presentation. Hosts own chrome, insets, surfaces and tree geometry.
final class GitLogHeader extends StatelessWidget {
  const GitLogHeader({
    super.key,
    required this.subject,
    required this.choose,
    required this.actions,
  });
  final Widget subject, choose, actions;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).logHeader(context, this);
}

final class GitHistoryLayout extends StatelessWidget {
  const GitHistoryLayout({
    super.key,
    required this.sidebar,
    required this.main,
    required this.toolbar,
    required this.sidebarVisible,
    required this.onToggle,
    required this.onCompactReferences,
    required this.sidebarFraction,
    required this.onResize,
    required this.minimumHistoryWidth,
    this.compactSidebarVisible = false,
    this.onToggleCompact,
    this.footer,
  });
  final Widget sidebar, main, toolbar;
  final Widget? footer;
  final bool sidebarVisible, compactSidebarVisible;
  final VoidCallback onToggle, onCompactReferences;
  final VoidCallback? onToggleCompact;
  final double sidebarFraction, minimumHistoryWidth;
  final ValueChanged<double> onResize;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).historyLayout(context, this);
}

final class GitReferenceRow extends StatelessWidget {
  const GitReferenceRow({
    super.key,
    required this.title,
    this.depth = 0,
    this.leading,
    this.children = const [],
    this.selected = false,
    this.expanded,
    this.onToggle,
    this.onTap,
    this.onSecondaryTapUp,
  });
  final List<Widget> children;
  final String title;
  final int depth;
  final Widget? leading;
  final bool selected;
  final bool? expanded;
  final VoidCallback? onToggle, onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  @override
  Widget build(BuildContext context) =>
      gitPresentation(context).referenceRow(context, this);
}

/// A host can omit its surrounding titlebar when a history body supplies one.
/// Both hosts omit the surrounding titlebar for this shared history body.
final class GitDialogBody extends StatelessWidget {
  const GitDialogBody({super.key, required this.child});
  final Widget child;
  static bool ownsHeader(Widget? body) =>
      body is GitDialogBody ||
      body is GitHostScope && ownsHeader(body.child) ||
      body is GitReviewSelectionBody && ownsHeader(body.child);
  @override
  Widget build(BuildContext context) => child;
}
