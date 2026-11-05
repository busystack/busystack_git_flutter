import 'dart:async';
import 'dart:ui' show SemanticsRole;
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'context_menu_keys.dart';
import 'host.dart';
import 'messages.dart';
import 'presentation.dart';
import 'session.dart';

/// Historical paths keep their immutable review owner; this tree has no staging
/// callbacks. Native row/disclosure/action geometry comes from the host.
final class GitHistoricalChangeTree extends StatefulWidget {
  const GitHistoricalChangeTree({
    super.key,
    required this.session,
    required this.files,
    required this.selected,
    required this.onHighlight,
    required this.onActivate,
    required this.onAction,
  });
  final GitSession session;
  final List<GitChange> files;
  final RepoPath? selected;
  final ValueChanged<GitChange> onHighlight, onActivate;
  final Future<void> Function(GitChange, String) onAction;
  @override
  State<GitHistoricalChangeTree> createState() => _HistoricalTreeState();
}

final class _HistoricalRow {
  const _HistoricalRow(this.key, this.title, this.depth, {this.file});
  final String key, title;
  final int depth;
  final GitChange? file;
}

final class _HistoricalTreeState extends State<GitHistoricalChangeTree> {
  final _focus = FocusNode(debugLabel: 'Historical changed files');
  late final _scroll = ScrollController(
    initialScrollOffset:
        switch (widget.session.viewState['inspectorFileScroll']) {
          final num value when value.isFinite && value >= 0 => value.toDouble(),
          _ => 0,
        },
  )..addListener(_rememberScroll);
  final _menuKeys = GitContextMenuKeys();
  final _collapsed = <String>{};
  List<GitChange>? _rowSource;
  List<_HistoricalRow>? _rowCache;
  int _focused = 0;
  String? _focusedKey;
  static const _entries = [
    GitMenuEntry('review', GitMessages.reviewDifference),
    GitMenuEntry('history', GitMessages.fileHistoryAndBlame),
    GitMenuEntry('snapshot', GitMessages.openSnapshot),
  ];
  @override
  void initState() {
    super.initState();
    _restore();
  }

  void _rememberScroll() {
    if (_scroll.hasClients)
      widget.session.setViewState('inspectorFileScroll', _scroll.offset);
  }

  void _restore() {
    _rowCache = null;
    _focusedKey =
        widget.session.viewState['inspectorFocusedRow'] as String? ??
        (widget.selected == null ? null : 'file:${widget.selected!.key}');
    _collapsed.clear();
    final saved = widget.session.viewState['inspectorCollapsedDirectories'];
    if (saved is List) _collapsed.addAll(saved.whereType<String>());
  }

  @override
  void didUpdateWidget(GitHistoricalChangeTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _restore();
      _focused = 0;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _menuKeys.clear();
    super.dispose();
  }

  List<_HistoricalRow> _rows() {
    if (identical(_rowSource, widget.files) && _rowCache != null)
      return _rowCache!;
    _rowSource = widget.files;
    final rows = <_HistoricalRow>[];
    final seen = <String>{};
    final files = [...widget.files]..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      var directory = '';
      var depth = 0;
      var hidden = false;
      // RepoPath display is losslessly escaped and never used as a Git pathspec.
      for (final part in file.path.parent.split('/')) {
        if (part.isEmpty) continue;
        directory = directory.isEmpty ? part : '$directory/$part';
        if (!hidden && seen.add(directory))
          rows.add(_HistoricalRow(directory, part, depth));
        hidden |= _collapsed.contains(directory);
        depth++;
      }
      if (!hidden)
        rows.add(
          _HistoricalRow(
            'file:${file.path.key}',
            file.path.basename,
            depth,
            file: file,
          ),
        );
    }
    return _rowCache = rows;
  }

  void _highlight(List<_HistoricalRow> rows, int index, {bool reveal = false}) {
    if (index < 0 || index >= rows.length) return;
    setState(() {
      _focused = index;
      _focusedKey = rows[index].key;
    });
    widget.session.setViewState('inspectorFocusedRow', rows[index].key);
    if (rows[index].file case final file?) widget.onHighlight(file);
    if (reveal && _scroll.hasClients) {
      final height = widget.session.host.rowHeight(context);
      final start = index * height;
      final current = _scroll.offset;
      final viewport = _scroll.position.viewportDimension;
      final offset = start < current
          ? start
          : start + height > current + viewport
          ? start + height - viewport
          : current;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  void _toggle(_HistoricalRow row) {
    setState(() {
      _rowCache = null;
      if (!_collapsed.add(row.key)) _collapsed.remove(row.key);
    });
    widget.session.setViewState(
      'inspectorCollapsedDirectories',
      _collapsed.toList(),
    );
  }

  Future<void> _menu(GitChange file, {Offset? position}) async {
    final owner = widget;
    if (position == null) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final bottom =
            ((_focused + 1) * owner.session.host.rowHeight(context) -
                    (_scroll.hasClients ? _scroll.offset : 0))
                .clamp(0.0, box.size.height);
        position = box.localToGlobal(
          Offset(
            Directionality.of(context) == TextDirection.rtl
                ? box.size.width
                : 0,
            bottom,
          ),
        );
      }
    }
    final action = await owner.session.host.menu(
      context,
      file.path.display,
      _entries,
      localizeTitle: false,
      position: position,
    );
    if (mounted &&
        identical(widget.session, owner.session) &&
        identical(widget.files, owner.files) &&
        action != null) {
      await owner.onAction(file, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final saved = rows.indexWhere((row) => row.key == _focusedKey);
    if (saved >= 0) _focused = saved;
    if (_focused >= rows.length) _focused = rows.length - 1;
    return Focus(
      focusNode: _focus,
      onFocusChange: (focused) {
        if (!focused) _menuKeys.clear();
        if (mounted) setState(() {});
      },
      onKeyEvent: (_, event) {
        if (rows.isEmpty) return KeyEventResult.ignored;
        final row = rows[_focused.clamp(0, rows.length - 1)];
        if (_menuKeys.handle(event, () {
          if (row.file case final file?) unawaited(_menu(file));
        }))
          return KeyEventResult.handled;
        if (event is! KeyDownEvent && event is! KeyRepeatEvent)
          return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.home ||
            key == LogicalKeyboardKey.end) {
          final next = key == LogicalKeyboardKey.home
              ? 0
              : key == LogicalKeyboardKey.end
              ? rows.length - 1
              : (_focused + (key == LogicalKeyboardKey.arrowDown ? 1 : -1))
                    .clamp(0, rows.length - 1);
          _focus.requestFocus();
          _highlight(rows, next, reveal: true);
        } else if (key == LogicalKeyboardKey.arrowRight && row.file == null) {
          _focus.requestFocus();
          if (_collapsed.contains(row.key)) _toggle(row);
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          _focus.requestFocus();
          if (row.file == null && !_collapsed.contains(row.key)) {
            _toggle(row);
          } else {
            final parent = rows.lastIndexWhere(
              (r) => r.depth < row.depth,
              _focused - 1,
            );
            if (parent >= 0) _highlight(rows, parent, reveal: true);
          }
        } else if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          if (!_focus.hasPrimaryFocus) return KeyEventResult.ignored;
          if (row.file case final file?) {
            widget.onActivate(file);
          } else {
            _toggle(row);
          }
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: CustomScrollView(
        key: PageStorageKey(
          'git-inspector-files:${widget.session.repository.presentationKey}',
        ),
        controller: _scroll,
        slivers: [
          SliverSemantics(
            role: SemanticsRole.list,
            container: true,
            explicitChildNodes: true,
            label: gitString(context, GitMessages.changedFiles),
            sliver: SliverFixedExtentList(
              itemExtent: widget.session.host.rowHeight(context),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final owner = widget;
                  final row = rows[index];
                  final file = row.file;
                  final path = file == null
                      ? row.key
                      : file.originalPath == null
                      ? file.path.display
                      : '${file.originalPath!.display} → ${file.path.display}';
                  return Semantics(
                    role: SemanticsRole.listItem,
                    container: true,
                    selected: file != null && widget.selected == file.path,
                    expanded: file == null
                        ? !_collapsed.contains(row.key)
                        : null,
                    label: file == null ? row.title : '$path, ${file.index}',
                    child: GitChangeRow(
                      key: ValueKey('git-historical-row:${row.key}'),
                      title: row.title,
                      depth: row.depth,
                      selected: file != null
                          ? widget.selected == file.path
                          : _focus.hasFocus && _focused == index,
                      status: file?.index,
                      tooltip: path,
                      expanded: file == null
                          ? !_collapsed.contains(row.key)
                          : null,
                      onToggle: file == null ? () => _toggle(row) : null,
                      onPointerDown: (_) {},
                      onTap: () {
                        _focus.requestFocus();
                        _highlight(rows, index);
                        if (file == null) {
                          _toggle(row);
                        } else {
                          widget.onActivate(file);
                        }
                      },
                      onSecondaryTapUp: file == null
                          ? null
                          : (details) {
                              _focus.requestFocus();
                              _highlight(rows, index);
                              unawaited(
                                _menu(file, position: details.globalPosition),
                              );
                            },
                      trailing:
                          file == null ||
                              gitPresentation(context).entryActionPlacement ==
                                  GitEntryActionPlacement.contextMenu
                          ? null
                          : Focus(
                              onFocusChange: (focused) {
                                if (focused)
                                  _highlight(rows, index, reveal: true);
                              },
                              child: GitMenuButton(
                                role: GitMenuRole.entryContext,
                                key: ValueKey(
                                  'git-historical-menu:${file.path.key}',
                                ),
                                host: widget.session.host,
                                tooltip: gitString(
                                  context,
                                  GitMessages.actionsForArg0,
                                  values: {'arg0': file.path.display},
                                ),
                                entries: _entries,
                                onSelected: (action) =>
                                    unawaited(owner.onAction(file, action)),
                              ),
                            ),
                    ),
                  );
                },
                childCount: rows.length,
                addSemanticIndexes: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
