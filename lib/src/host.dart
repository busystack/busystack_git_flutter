import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef GitPresentSurface =
    Future<T?> Function<T>(
      BuildContext context,
      String title,
      Widget child, {
      bool expanded,
    });

/// Complete the surface that owns this view, including while another modal is
/// above it. A dismissed route can remain mounted during its closing animation;
/// completing its operation must never pop the newly current parent route.
/// Views embedded in the application's first route stay open.
void gitCompleteSurface<T>(BuildContext context, [T? result]) {
  if (!context.mounted) return;
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive || route.isFirst) return;
  final navigator = route.navigator;
  if (navigator == null) return;
  if (route.isCurrent) {
    navigator.pop<T>(result);
  } else {
    navigator.removeRoute(route, result);
  }
}

final class GitMenuEntry {
  const GitMenuEntry(
    this.id,
    this.label, {
    this.enabled = true,
    this.sectionStart = false,
    this.checked,
    this.radio = false,
    this.localize = true,
    this.separator = false,
  });
  const GitMenuEntry.separator()
    : this('', '', enabled: false, separator: true);
  final String id, label;
  final bool enabled, sectionStart, radio, localize, separator;
  final bool? checked;
}

typedef GitPresentMenu =
    Future<String?> Function(
      BuildContext context,
      List<GitMenuEntry> entries, {
      Offset? position,
    });

abstract interface class GitDraftStore {
  Future<String?> read(String worktreeKey);
  Future<void> write(String worktreeKey, String message);
}

final class MemoryGitDraftStore implements GitDraftStore {
  final _drafts = <String, String>{};
  @override
  Future<String?> read(String worktreeKey) async => _drafts[worktreeKey];
  @override
  Future<void> write(String worktreeKey, String message) async {
    _drafts[worktreeKey] = message;
  }
}

/// Host owns dialogs, native chrome, file opening, trust and unsaved buffers.
/// No nested MaterialApp, independent theme, or application navigator is used.
final class GitHost {
  const GitHost({
    required GitPresentSurface present,
    required this.openDocument,
    required this.prepareMutation,
    required this.chooseDirectory,
    required this.notify,
    required this.drafts,
    this.afterMutation,
    this.openFolder,
    this.prepareInspection,
    this.draftMessage,
    this.translate,
    this.spacing = 8,
    this.minimumRowHeight = 30,
    this.measureText,
    this.icons = const {},
    this.readViewState,
    this.writeViewState,
    this.revokeRepositoryTrust,
    this.presentMenu,
  }) : _present = present;
  final GitPresentSurface _present;
  final GitPresentMenu? presentMenu;
  Future<T?> present<T>(
    BuildContext context,
    String title,
    Widget child, {
    bool expanded = false,
  }) => _present<T>(
    context,
    text('git.$title', title),
    GitHostScope(host: this, child: child),
    expanded: expanded,
  );
  Future<String?> menu(
    BuildContext context,
    String title,
    List<GitMenuEntry> entries, {
    Offset? position,
  }) async {
    final localized = <GitMenuEntry>[];
    var section = false;
    for (final e in entries) {
      if (e.separator) {
        section = true;
        continue;
      }
      localized.add(
        GitMenuEntry(
          e.id,
          e.localize ? text('git.${e.label}', e.label) : e.label,
          enabled: e.enabled,
          sectionStart: section || e.sectionStart,
          checked: e.checked,
          radio: e.radio,
          localize: false,
        ),
      );
      section = false;
    }
    if (presentMenu != null) {
      try {
        return await presentMenu!(context, localized, position: position);
      } on GitException catch (error) {
        if (error.code != GitErrorCode.unavailable) rethrow;
      }
    }
    if (!context.mounted) return null;
    return present<String>(
      context,
      title,
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in localized) ...[
              if (e.sectionStart) const Divider(),
              ListTile(
                dense: true,
                enabled: e.enabled,
                leading: e.checked == null
                    ? null
                    : SizedBox(
                        width: 18,
                        child: e.checked!
                            ? const GitIcon(GitGlyph.check, size: 18)
                            : null,
                      ),
                title: Text(e.label),
                onTap: e.enabled ? () => Navigator.of(context).pop(e.id) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  final Future<void> Function(RepositoryId, RepoPath, {GitContent? snapshot})
  openDocument;
  final Future<bool> Function(RepositoryId, GitMutation) prepareMutation;
  final Future<String?> Function(BuildContext context) chooseDirectory;
  final void Function(String) notify;
  final GitDraftStore drafts;
  final Future<void> Function(RepositoryId, GitOutcome)? afterMutation;
  final Future<void> Function(String localPath)? openFolder;
  final Future<bool> Function(RepositoryId, GitInspection)? prepareInspection;
  final Future<void> Function(RepositoryId)? revokeRepositoryTrust;
  final Future<String?> Function(RepositoryId)? draftMessage;
  final String Function(String key, String fallback)? translate;
  final double spacing, minimumRowHeight;
  final double Function(BuildContext context, TextStyle? style)? measureText;

  /// Override every shared control using semantic [GitGlyph] keys. Applications
  /// supply their existing semantic glyph catalog; no icon font is imposed.
  final Map<GitGlyph, IconData> icons;
  final Future<Map<String, Object>?> Function(String worktreeKey)?
  readViewState;
  final Future<void> Function(String worktreeKey, Map<String, Object> values)?
  writeViewState;
  String text(String key, String fallback) =>
      translate?.call(key, fallback) ?? fallback;
  double rowHeight(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    painter.layout();
    final height = measureText?.call(context, style) ?? painter.height;
    painter.dispose();
    return (height + spacing).clamp(minimumRowHeight, double.infinity);
  }
}

/// Localization and layout ownership stay with the consuming application.
/// Message IDs use the English template, with named values substituted only
/// after host translation. Repository content and filenames never pass here.
final class GitHostScope extends InheritedWidget {
  const GitHostScope({super.key, required this.host, required super.child});
  final GitHost host;
  static GitHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GitHostScope>()?.host;
  @override
  bool updateShouldNotify(GitHostScope oldWidget) => oldWidget.host != host;
}

enum GitGlyph {
  back,
  branch,
  history,
  refresh,
  more,
  expand,
  previous,
  next,
  up,
  down,
  search,
  add,
  remove,
  check,
  tag,
  error,
  warning,
  close;

  IconData get fallback => switch (this) {
    back => Icons.arrow_back,
    branch => Icons.account_tree_outlined,
    history => Icons.history,
    refresh => Icons.refresh,
    more => Icons.more_vert,
    expand => Icons.expand_more,
    previous => Icons.chevron_left,
    next => Icons.chevron_right,
    up => Icons.arrow_upward,
    down => Icons.arrow_downward,
    search => Icons.search,
    add => Icons.add,
    remove => Icons.remove,
    check => Icons.check,
    tag => Icons.label_outline,
    error => Icons.error_outline,
    warning => Icons.warning_amber_outlined,
    close => Icons.close,
  };
}

/// Inherits the active theme and resolves artwork through the host's catalog.
final class GitIcon extends StatelessWidget {
  const GitIcon(this.glyph, {super.key, this.size, this.color});
  final GitGlyph glyph;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Icon(
    GitHostScope.of(context)?.icons[glyph] ?? glyph.fallback,
    size: size,
    color: color,
  );
}

String gitString(
  BuildContext context,
  String message, {
  Map<String, Object?> values = const {},
}) {
  Localizations.maybeLocaleOf(context);
  var translated =
      GitHostScope.of(context)?.text('git.$message', message) ?? message;
  for (final value in values.entries) {
    translated = translated.replaceAll('{${value.key}}', '${value.value}');
  }
  return translated;
}

/// Selectable Git details also need a label on Linux's native accessibility
/// bridge. Keep data verbatim: paths, revisions and destinations are not keys.
final class GitSelectableText extends StatelessWidget {
  const GitSelectableText(this.data, {super.key, this.style});
  final String data;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) =>
      SelectableText(data, semanticsLabel: data, style: style);
}

final class GitLabel extends StatelessWidget {
  const GitLabel(
    this.message, {
    super.key,
    this.values = const {},
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.semanticsLabel,
  });
  final String message;
  final Map<String, Object?> values;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => Text(
    gitString(context, message, values: values),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}

final class GitSplitter extends StatefulWidget {
  const GitSplitter({
    super.key,
    required this.first,
    required this.second,
    this.axis = Axis.horizontal,
    this.initial = .35,
    this.minimum = 120,
    this.minimumSecond,
    this.value,
    this.onChanged,
  });
  final Widget first, second;
  final Axis axis;
  final double initial, minimum;
  final double? minimumSecond;
  final double? value;
  final ValueChanged<double>? onChanged;
  @override
  State<GitSplitter> createState() => _GitSplitterState();
}

final class _GitSplitterState extends State<GitSplitter> {
  double? _fraction;
  bool _focused = false;
  void _update(double value) {
    final next = value.clamp(0.0, 1.0);
    setState(() => _fraction = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final extent = widget.axis == Axis.horizontal
          ? constraints.maxWidth
          : constraints.maxHeight;
      final handleExtent = extent.clamp(0.0, 6.0),
          available = (extent - handleExtent).clamp(0.0, double.infinity);
      final secondMinimum =
          (widget.minimumSecond ?? widget.minimum.clamp(0.0, available / 2))
              .clamp(0.0, available);
      final maximum = available - secondMinimum;
      final minimum = widget.minimum.clamp(0.0, maximum);
      final first = ((_fraction ?? widget.value ?? widget.initial) * available)
          .clamp(minimum, maximum)
          .toDouble();
      final divisor = available > 0 ? available : 1.0;
      final handle = Semantics(
        label: gitString(context, 'Resize Git panes'),
        slider: true,
        value: '${(first / divisor * 100).round()} percent',
        increasedValue:
            '${((first + 24).clamp(minimum, maximum) / divisor * 100).round()} percent',
        decreasedValue:
            '${((first - 24).clamp(minimum, maximum) / divisor * 100).round()} percent',
        onIncrease: available > 0
            ? () => _update((first + 24) / divisor)
            : null,
        onDecrease: available > 0
            ? () => _update((first - 24) / divisor)
            : null,
        child: Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent)
              return KeyEventResult.ignored;
            final forward = widget.axis == Axis.horizontal
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowDown;
            final backward = widget.axis == Axis.horizontal
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowUp;
            if (event.logicalKey != forward && event.logicalKey != backward)
              return KeyEventResult.ignored;
            _update(
              (first + (event.logicalKey == forward ? 24 : -24)) / divisor,
            );
            return KeyEventResult.handled;
          },
          child: MouseRegion(
            cursor: widget.axis == Axis.horizontal
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (event) => _update(
                (first +
                        (widget.axis == Axis.horizontal
                            ? event.delta.dx
                            : event.delta.dy)) /
                    divisor,
              ),
              child: ColoredBox(
                color: _focused
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .5),
                child: SizedBox(
                  width: widget.axis == Axis.horizontal ? handleExtent : null,
                  height: widget.axis == Axis.vertical ? handleExtent : null,
                  child: Center(
                    child: Container(
                      color: Theme.of(context).colorScheme.outline,
                      width: widget.axis == Axis.horizontal ? 2 : 22,
                      height: widget.axis == Axis.vertical ? 2 : 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return Flex(
        direction: widget.axis,
        children: [
          SizedBox(
            width: widget.axis == Axis.horizontal ? first : null,
            height: widget.axis == Axis.vertical ? first : null,
            child: widget.first,
          ),
          handle,
          Expanded(child: widget.second),
        ],
      );
    },
  );
}

final class GitFailurePanel extends StatelessWidget {
  const GitFailurePanel({
    super.key,
    required this.error,
    this.message,
    this.onRefresh,
    this.onAuthorize,
  });
  final GitException error;
  final String? message;
  final VoidCallback? onRefresh;
  final VoidCallback? onAuthorize;
  String _diagnostics(BuildContext context) => [
    if (error.exitCode case final status?)
      gitString(
        context,
        'Exit status: {status}',
        values: {'status': '$status'},
      ),
    if (error.diagnostic.isNotEmpty) error.diagnostic,
  ].join('\n');
  @override
  Widget build(BuildContext context) => MaterialBanner(
    leading: const GitIcon(GitGlyph.error),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GitLabel(
          message ??
              switch (error.code) {
                GitErrorCode.staleReview =>
                  'Repository changed. Refresh and review before trying again.',
                GitErrorCode.locked =>
                  'Another operation holds the repository or index lock. Wait, then refresh.',
                GitErrorCode.trustRequired =>
                  'Repository trust is required for this operation.',
                GitErrorCode.disconnected =>
                  'The Git service disconnected. Reconnect and reconcile the repository.',
                GitErrorCode.unavailable || GitErrorCode.unsupportedVersion =>
                  'The installed Git executable cannot support this operation. Review its runtime requirements below.',
                GitErrorCode.readOnly =>
                  'This repository is read-only for the requested operation. Review and history remain available.',
                GitErrorCode.uncertainOutcome =>
                  'The operation needs reconciliation. Review the resulting repository or remote state before repeating it.',
                GitErrorCode.authentication =>
                  'Git authentication failed. Review the credential helper or unlock the configured keyring.',
                GitErrorCode.unknownHost =>
                  'SSH host verification failed. Review the host identity through your configured SSH tools.',
                GitErrorCode.signing =>
                  'Commit signing failed or was cancelled. Review the signing key, agent and configured signing tool.',
                GitErrorCode.authorIdentity =>
                  'Set a repository author name and email, then return to the preserved message draft.',
                GitErrorCode.rejected =>
                  'Git rejected the reviewed update. Refresh and review the actual destination before trying again.',
                GitErrorCode.dirty =>
                  'Working or staged changes prevent this operation. Review, commit or explicitly stash them.',
                GitErrorCode.missingContent =>
                  'A required Git object is unavailable. Review shallow or partial-repository boundaries and fetch explicitly if needed.',
                _ => 'Git operation failed: ${error.code.name}',
              },
        ),
        if (_diagnostics(context).isNotEmpty)
          ExpansionTile(
            title: const GitLabel('Diagnostics'),
            children: [SelectableText(_diagnostics(context))],
          ),
      ],
    ),
    actions: [
      if (onAuthorize != null)
        TextButton(
          onPressed: onAuthorize,
          child: const GitLabel('Authorize Git inspection…'),
        ),
      if (onRefresh != null)
        TextButton(onPressed: onRefresh, child: const GitLabel('Refresh'))
      else
        TextButton(
          onPressed: () => Clipboard.setData(
            ClipboardData(text: '${error.code.name}\n${_diagnostics(context)}'),
          ),
          child: const GitLabel('Copy diagnostics'),
        ),
    ],
  );
}

/// Explicit action names also reach the Linux AT-SPI bridge, where a tooltip
/// alone may be exposed as a description instead of the control's name.
final class GitIconButton extends StatelessWidget {
  const GitIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: gitString(context, tooltip),
    button: true,
    enabled: onPressed != null,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: IconButton(
        tooltip: gitString(context, tooltip),
        onPressed: onPressed,
        icon: icon,
      ),
    ),
  );
}

/// Specialized Git action menu anchored to its actual desktop control.
final class GitMenuButton extends StatelessWidget {
  const GitMenuButton({
    super.key,
    required this.host,
    required this.entries,
    required this.onSelected,
    this.tooltip = 'Actions',
    this.child,
    this.enabled = true,
    this.disabledReason,
  });
  final GitHost host;
  final List<GitMenuEntry> entries;
  final ValueChanged<String> onSelected;
  final String tooltip;
  final Widget? child;
  final bool enabled;
  final String? disabledReason;
  @override
  Widget build(BuildContext context) {
    Future<void> open() async {
      final box = context.findRenderObject();
      final position = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset(0, box.size.height))
          : null;
      final value = await host.menu(
        context,
        tooltip,
        entries,
        position: position,
      );
      if (context.mounted && value != null) onSelected(value);
    }

    final available = enabled && entries.isNotEmpty;
    final description = !available && disabledReason != null
        ? '$tooltip · ${gitString(context, disabledReason!)}'
        : tooltip;
    return child == null
        ? GitIconButton(
            tooltip: description,
            onPressed: available ? () => open() : null,
            icon: const GitIcon(GitGlyph.more, size: 18),
          )
        : Tooltip(
            message: gitString(context, description),
            child: TextButton(
              onPressed: available ? () => open() : null,
              child: child!,
            ),
          );
  }
}
