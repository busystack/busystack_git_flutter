import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'host.dart';
import 'session.dart';
import 'text_pane.dart';
import 'text_encoding.dart';
import 'text_undo.dart';
import 'workflow_ui.dart' show gitConfirm;
export 'text_pane.dart';

Future<TextDiff> _backgroundDiff(String left, String right) =>
    Isolate.run(() => computeTextDiff(left, right));

final class GitDiffView extends StatefulWidget {
  const GitDiffView({
    super.key,
    required this.session,
    required this.comparison,
    this.onPreviousFile,
    this.onNextFile,
  });
  final GitSession session;
  final GitComparison comparison;
  final VoidCallback? onPreviousFile, onNextFile;
  @override
  State<GitDiffView> createState() => _GitDiffViewState();
}

final class _GitDiffViewState extends State<GitDiffView> {
  GitContent? _left, _right;
  GitSnapshot? _review;
  TextDiff? _diff;
  GitException? _error;
  GitException? _displayLimit;
  bool _loading = true,
      _unified = false,
      _wrap = true,
      _words = true,
      _collapse = true,
      _ignoreWhitespace = false;
  bool _stale = false;
  GitCancellation? _readCancellation;
  TextDiff? _rowSource;
  String? _rowSettings;
  List<(int?, int?)>? _rowCache;
  final _selected = <int>{};
  int? _selectionAnchor;
  final _rowKeys = <int, GlobalKey>{};
  final _scroll = ScrollController(),
      _horizontalScroll = ScrollController(),
      _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchVisible = false;
  var _generation = 0, _difference = -1;
  @override
  void initState() {
    super.initState();
    _unified = widget.session.option('diffUnified', false);
    _wrap = widget.session.option('diffWrap', true);
    _words = widget.session.option('diffWords', true);
    _collapse = widget.session.option('diffCollapse', true);
    _ignoreWhitespace = widget.session.option('diffIgnoreWhitespace', false);
    widget.session.addListener(_repositoryChanged);
    unawaited(_load());
  }

  void _repositoryChanged() {
    final comparison = widget.comparison;
    final mutable = [comparison.left, comparison.right].any(
      (v) => {
        ContentKind.indexVersion,
        ContentKind.workingTree,
        ContentKind.normalizedWorking,
        ContentKind.conflictStage,
      }.contains(v.kind),
    );
    if (mounted &&
        mutable &&
        _review != null &&
        widget.session.snapshot?.token != _review!.token) {
      setState(() => _stale = true);
    }
  }

  @override
  void didUpdateWidget(covariant GitDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comparison != widget.comparison) unawaited(_load());
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _generation++;
    _readCancellation?.cancel();
    widget.session.removeListener(_repositoryChanged);
    _scroll.dispose();
    _horizontalScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refreshStatus = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _displayLimit = null;
      _selected.clear();
      _selectionAnchor = null;
      _rowKeys.clear();
      _difference = -1;
    });
    _readCancellation?.cancel();
    final cancellation = _readCancellation = GitCancellation();
    try {
      final session = widget.session, comparison = widget.comparison;
      if (refreshStatus) {
        await session.refresh(clearOperationFailure: true);
        if (session.failure case final failure?) throw failure;
      }
      // A file review uses exact content handles and the observed HEAD/index
      // preconditions. Its mutations revalidate those identities in the engine;
      // opening each file must not rescan every untracked repository path.
      final before =
          session.snapshot ??
          await session.readStatus(cancellation: cancellation);
      final values = await Future.wait([
        session.client.content(
          session.repository,
          comparison.leftPath ?? comparison.path,
          comparison.left,
          cancellation: cancellation,
        ),
        session.client.content(
          session.repository,
          comparison.path,
          comparison.left.kind == ContentKind.indexVersion &&
                  comparison.right.kind == ContentKind.workingTree
              ? const ContentVersion(ContentKind.normalizedWorking)
              : comparison.right,
          cancellation: cancellation,
        ),
      ]);
      final left = values[0], right = values[1];
      final a = left.availability == ContentAvailability.absent
          ? ''
          : left.text;
      final b = right.availability == ContentAvailability.absent
          ? ''
          : right.text;
      TextDiff? diff;
      GitException? displayLimit;
      if (a != null && b != null) {
        try {
          diff = await _backgroundDiff(a, b);
        } on GitException catch (error) {
          if (error.code != GitErrorCode.outputLimit) rethrow;
          displayLimit = error;
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _left = left;
        _right = right;
        _diff = diff;
        _displayLimit = displayLimit;
        _review = before;
        _loading = false;
        _stale =
            session.snapshot != null && session.snapshot!.token != before.token;
      });
    } on GitException catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _error = error;
          _loading = false;
        });
    } on Object catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _error = GitException(
            GitErrorCode.commandFailed,
            diagnostic: sanitizeGitDiagnostic('$error'),
          );
          _loading = false;
        });
    }
  }

  bool get _unstage => widget.comparison.right.kind == ContentKind.indexVersion;
  bool get _stagingComparison =>
      _review != null &&
      (_unstage &&
              (widget.comparison.left.kind == ContentKind.absent &&
                      _review!.head == null ||
                  widget.comparison.left.kind == ContentKind.commit &&
                      widget.comparison.left.revision == _review!.head) ||
          widget.comparison.left.kind == ContentKind.indexVersion &&
              widget.comparison.right.kind == ContentKind.workingTree);
  bool get _canStage =>
      _stagingComparison &&
      _diff != null &&
      !widget.session.running &&
      !_stale &&
      widget.session.canWriteMetadata;
  void _display(String key, bool value, VoidCallback update) {
    setState(update);
    widget.session.setViewState(key, value);
  }

  void _openSearch() {
    setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchVisible) _searchFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: widget.session.host,
    child: Builder(builder: _build),
  );
  Widget _build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => _buildReview(context, bounds),
  );

  Widget _buildReview(BuildContext context, BoxConstraints bounds) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return GitFailurePanel(
        error: _error!,
        onRefresh: () => unawaited(_load(refreshStatus: true)),
      );
    final comparison = widget.comparison, host = widget.session.host;
    final label = TextPainter(
      text: TextSpan(
        text: gitString(context, GitMessages.editHEADIndexWorkingTree),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final compact =
        bounds.maxWidth < label.width * 2 + host.spacing * 8 &&
        bounds.maxHeight < host.rowHeight(context) * 16;
    label.dispose();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
      },
      child: Column(
        children: [
          if (_stale)
            MaterialBanner(
              content: const GitLabel(
                GitMessages
                    .theReviewedIndexOrWorkingContentChangedRefreshThisComparison,
              ),
              actions: [
                TextButton(
                  onPressed: () => unawaited(_load(refreshStatus: true)),
                  child: const GitLabel(GitMessages.refreshComparison),
                ),
              ],
            ),
          Padding(
            padding: EdgeInsets.all(host.spacing),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: SelectableText(comparison.path.display)),
                    GitIconButton(
                      tooltip: gitString(
                        context,
                        GitMessages.refreshComparison,
                      ),
                      onPressed: () => unawaited(_load(refreshStatus: true)),
                      icon: const GitIcon(GitGlyph.refresh),
                    ),
                  ],
                ),
                Wrap(
                  spacing: host.spacing,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.onPreviousFile != null ||
                        widget.onNextFile != null) ...[
                      GitIconButton(
                        tooltip: gitString(
                          context,
                          GitMessages.previousChangedFile,
                        ),
                        onPressed: widget.onPreviousFile,
                        icon: const GitIcon(GitGlyph.previous),
                      ),
                      GitIconButton(
                        tooltip: gitString(
                          context,
                          GitMessages.nextChangedFile,
                        ),
                        onPressed: widget.onNextFile,
                        icon: const GitIcon(GitGlyph.next),
                      ),
                    ],
                    GitIconButton(
                      tooltip: gitString(
                        context,
                        GitMessages.previousDifference,
                      ),
                      onPressed: () => _jump(-1),
                      icon: const GitIcon(GitGlyph.up, size: 18),
                    ),
                    GitIconButton(
                      tooltip: gitString(context, GitMessages.nextDifference),
                      onPressed: () => _jump(1),
                      icon: const GitIcon(GitGlyph.down, size: 18),
                    ),
                    if (compact)
                      GitMenuButton(
                        host: host,
                        tooltip: gitString(context, GitMessages.comparisonMode),
                        entries: [
                          GitMenuEntry(
                            'side',
                            GitMessages.sideBySide,
                            checked: !_unified,
                            radio: true,
                          ),
                          GitMenuEntry(
                            'unified',
                            GitMessages.unified,
                            checked: _unified,
                            radio: true,
                          ),
                        ],
                        onSelected: (value) => _display(
                          'diffUnified',
                          value == 'unified',
                          () => _unified = value == 'unified',
                        ),
                        child: GitLabel(
                          _unified
                              ? GitMessages.unified
                              : GitMessages.sideBySide,
                        ),
                      )
                    else
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: GitLabel(
                              gitString(context, GitMessages.sideBySide),
                            ),
                          ),
                          ButtonSegment(
                            value: true,
                            label: GitLabel(
                              gitString(context, GitMessages.unified),
                            ),
                          ),
                        ],
                        selected: {_unified},
                        onSelectionChanged: (s) => _display(
                          'diffUnified',
                          s.single,
                          () => _unified = s.single,
                        ),
                      ),
                    GitMenuButton(
                      host: host,
                      tooltip: gitString(
                        context,
                        GitMessages.diffDisplayOptions,
                      ),
                      entries: [
                        GitMenuEntry('wrap', GitMessages.wrap, checked: _wrap),
                        GitMenuEntry(
                          'words',
                          GitMessages.words,
                          checked: _words,
                        ),
                        GitMenuEntry(
                          'collapse',
                          GitMessages.collapseContext,
                          checked: _collapse,
                        ),
                        GitMenuEntry(
                          'whitespace',
                          GitMessages.ignoreWhitespace,
                          checked: _ignoreWhitespace,
                        ),
                      ],
                      onSelected: (option) {
                        switch (option) {
                          case 'wrap':
                            _display('diffWrap', !_wrap, () => _wrap = !_wrap);
                          case 'words':
                            _display(
                              'diffWords',
                              !_words,
                              () => _words = !_words,
                            );
                          case 'collapse':
                            _display(
                              'diffCollapse',
                              !_collapse,
                              () => _collapse = !_collapse,
                            );
                          case 'whitespace':
                            _display(
                              'diffIgnoreWhitespace',
                              !_ignoreWhitespace,
                              () => _ignoreWhitespace = !_ignoreWhitespace,
                            );
                        }
                      },
                    ),
                    GitIconButton(
                      tooltip: gitString(context, GitMessages.searchComparison),
                      onPressed: _openSearch,
                      icon: const GitIcon(GitGlyph.search),
                    ),
                  ],
                ),
                if (_searchVisible)
                  GitTextUndo(
                    controller: _search,
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      decoration: InputDecoration(
                        labelText: gitString(context, GitMessages.search),
                        isDense: true,
                        suffixIcon: GitIconButton(
                          tooltip: gitString(context, GitMessages.closeSearch),
                          onPressed: () => setState(() {
                            _search.clear();
                            _searchVisible = false;
                          }),
                          icon: const GitIcon(GitGlyph.close),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                if (_canStage && compact)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GitMenuButton(
                      host: host,
                      tooltip: gitString(context, GitMessages.stagingActions),
                      child: const GitLabel(GitMessages.stagingActions2),
                      entries: [
                        GitMenuEntry(
                          'lines',
                          _unstage
                              ? GitMessages.unstageSelectedChangedLines
                              : GitMessages.stageSelectedChangedLines,
                          enabled: _selected.isNotEmpty,
                        ),
                        const GitMenuEntry(
                          'index',
                          GitMessages.editHEADIndexWorkingTree,
                        ),
                        GitMenuEntry(
                          'file',
                          _unstage
                              ? GitMessages.unstageWholeFile
                              : GitMessages.stageWholeFile,
                        ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'lines':
                            unawaited(_applySelection());
                          case 'index':
                            unawaited(_indexEditor());
                          case 'file':
                            unawaited(_wholeFile());
                        }
                      },
                    ),
                  )
                else if (_canStage)
                  Wrap(
                    spacing: host.spacing,
                    children: [
                      FilledButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => unawaited(_applySelection()),
                        child: Text(
                          _unstage
                              ? gitString(
                                  context,
                                  GitMessages.unstageSelectedChangedLines,
                                )
                              : gitString(
                                  context,
                                  GitMessages.stageSelectedChangedLines,
                                ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => unawaited(_indexEditor()),
                        child: const GitLabel(
                          GitMessages.editHEADIndexWorkingTree,
                        ),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_wholeFile()),
                        child: Text(
                          _unstage
                              ? gitString(context, GitMessages.unstageWholeFile)
                              : gitString(context, GitMessages.stageWholeFile),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(child: _label(_left!)),
              Expanded(child: _label(_right!)),
            ],
          ),
          if (_ignoreWhitespace && _ignoredWhitespace().isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _ignoreWhitespace = false),
              child: Text(
                gitString(
                  context,
                  GitMessages
                      .arg0WhitespaceOnlyChangedLinesHiddenShowExactChanges,
                  values: {'arg0': _ignoredWhitespace().length},
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _diff == null ? _nonText() : _reviewRows(context)),
          if (_diff != null || !_stagingComparison)
            Padding(
              padding: EdgeInsets.all(host.spacing),
              child: Text(
                _stagingComparison
                    ? gitString(
                        context,
                        GitMessages
                            .arg0ChangedLinesSelectedDisplaySettingsNeverAlterTheStaged,
                        values: {'arg0': _selected.length},
                      )
                    : gitString(
                        context,
                        GitMessages
                            .readOnlyComparisonCopyTextOrAdjustDisplaySettings,
                      ),
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(GitContent content) => Padding(
    padding: const EdgeInsets.all(6),
    child: Text(
      gitString(
        context,
        GitMessages.arg0Arg1Arg2BytesArg3,
        values: {
          'arg0': gitVersionLabel(context, content.version),
          'arg1': content.mode,
          'arg2': content.size,
          'arg3': content.bytes.isNotEmpty && content.bytes.last != 10
              ? gitString(context, GitMessages.noFinalNewline)
              : '',
        },
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
  Widget _nonText() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${gitEnumLabel(context, _left!.availability)} → ${gitEnumLabel(context, _right!.availability)}',
        ),
        Text(
          _displayLimit == null
              ? gitString(
                  context,
                  GitMessages.textComparisonIsUnavailableForTheseContents,
                )
              : gitString(
                  context,
                  GitMessages
                      .thisComparisonExceedsTheBoundedTextReviewLimitTheContents,
                ),
        ),
        if (_stagingComparison)
          TextButton(
            onPressed:
                widget.session.running ||
                    _stale ||
                    !widget.session.canWriteMetadata
                ? null
                : () => unawaited(_wholeFile()),
            child: Text(
              _unstage
                  ? gitString(context, GitMessages.unstageWholeFile)
                  : gitString(context, GitMessages.stageWholeFile),
            ),
          ),
      ],
    ),
  );
  List<int> _visible() {
    final edits = _diff!.edits, visible = <int>[];
    final ignored = _ignoreWhitespace ? _ignoredWhitespace() : <int>{};
    for (var i = 0; i < edits.length; i++) {
      if (ignored.contains(i)) continue;
      if (!_collapse ||
          edits[i].kind != TextEditKind.equal ||
          edits
              .skip((i - 3).clamp(0, edits.length))
              .take(7)
              .any((e) => e.kind != TextEditKind.equal))
        visible.add(i);
    }
    return visible;
  }

  Set<int> _ignoredWhitespace() {
    final edits = _diff?.edits ?? [], ignored = <int>{};
    for (var i = 0; i < edits.length;) {
      if (edits[i].kind == TextEditKind.equal) {
        i++;
        continue;
      }
      final start = i;
      final removed = StringBuffer(), added = StringBuffer();
      while (i < edits.length && edits[i].kind != TextEditKind.equal) {
        (edits[i].kind == TextEditKind.remove ? removed : added).write(
          edits[i].text,
        );
        i++;
      }
      if (removed.toString().replaceAll(RegExp(r'\s+'), '') ==
          added.toString().replaceAll(RegExp(r'\s+'), '')) {
        for (var line = start; line < i; line++) {
          ignored.add(line);
        }
      }
    }
    return ignored;
  }

  String? _counterpart(int index) {
    final edits = _diff!.edits;
    if (edits[index].kind == TextEditKind.equal) return null;
    var start = index, end = index;
    while (start > 0 && edits[start - 1].kind != TextEditKind.equal) {
      start--;
    }
    while (end + 1 < edits.length &&
        edits[end + 1].kind != TextEditKind.equal) {
      end++;
    }
    final same = <int>[], other = <int>[];
    for (var i = start; i <= end; i++) {
      (edits[i].kind == edits[index].kind ? same : other).add(i);
    }
    final ordinal = same.indexOf(index);
    return ordinal < other.length ? edits[other[ordinal]].text : '';
  }

  List<(int?, int?)> _alignedRows() {
    final settings = '$_collapse:$_unified:$_ignoreWhitespace';
    if (identical(_rowSource, _diff) &&
        _rowSettings == settings &&
        _rowCache != null)
      return _rowCache!;
    final visible = _visible(), rows = <(int?, int?)>[];
    for (var p = 0; p < visible.length;) {
      final index = visible[p], edit = _diff!.edits[index];
      if (_unified || edit.kind == TextEditKind.equal) {
        rows.add((index, _unified ? null : index));
        p++;
        continue;
      }
      final removed = <int>[], added = <int>[];
      while (p < visible.length &&
          _diff!.edits[visible[p]].kind != TextEditKind.equal) {
        final i = visible[p++];
        (_diff!.edits[i].kind == TextEditKind.remove ? removed : added).add(i);
      }
      for (
        var i = 0;
        i < (removed.length > added.length ? removed.length : added.length);
        i++
      ) {
        rows.add((
          i < removed.length ? removed[i] : null,
          i < added.length ? added[i] : null,
        ));
      }
    }
    _rowSource = _diff;
    _rowSettings = settings;
    return _rowCache = rows;
  }

  Color _lineColor(int? index) {
    if (index == null) return Colors.transparent;
    final colors = Theme.of(context).colorScheme;
    return _selected.contains(index)
        ? colors.secondaryContainer
        : switch (_diff!.edits[index].kind) {
            TextEditKind.add => colors.primaryContainer.withValues(alpha: .3),
            TextEditKind.remove => colors.errorContainer.withValues(alpha: .3),
            _ => Colors.transparent,
          };
  }

  Widget _reviewRows(BuildContext context) {
    final rows = _alignedRows(), edits = _diff!.edits;
    if (_diff!.changedIndices.isEmpty)
      return const Center(
        child: GitLabel(GitMessages.theComparedContentsAreIdentical),
      );
    final host = widget.session.host;
    Widget cell(int? index, int? counterpart, bool right) {
      final edit = index == null ? null : edits[index],
          changed = edit != null && edit.kind != TextEditKind.equal;
      final text = edit?.text ?? '',
          number = edit == null
              ? ''
              : _unified
              ? '${edit.oldLine ?? ''} ${edit.newLine ?? ''}'
              : '${right ? edit.newLine ?? '' : edit.oldLine ?? ''}';
      final kind = edit?.kind ?? TextEditKind.equal;
      return Semantics(
        selected: index != null && _selected.contains(index),
        label: changed
            ? gitString(
                context,
                GitMessages.arg0ChangedLine,
                values: {
                  'arg0': _unstage
                      ? gitString(context, GitMessages.unstage)
                      : gitString(context, GitMessages.stage),
                },
              )
            : gitString(context, GitMessages.context),
        child: InkWell(
          canRequestFocus: changed && _canStage,
          onTap: !changed || !_canStage
              ? null
              : () => _selectChangedLine(index!),
          child: ColoredBox(
            color: _lineColor(index),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: host.rowHeight(context)),
              child: _line(
                text,
                number,
                kind,
                _words && changed
                    ? counterpart == null
                          ? ''
                          : edits[counterpart].text
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    final list = ListView.builder(
      controller: _scroll,
      itemCount: rows.length,
      itemBuilder: (context, row) {
        final (left, right) = rows[row];
        final indices = [if (left != null) left, if (right != null) right]
          ..sort();
        final first = indices.first,
            previous =
                row == 0
                      ? <int>[]
                      : [
                          if (rows[row - 1].$1 != null) rows[row - 1].$1!,
                          if (rows[row - 1].$2 != null) rows[row - 1].$2!,
                        ]
                  ..sort();
        final gap = row == 0 ? first > 0 : first > previous.last + 1;
        final changed = indices.any((i) => edits[i].kind != TextEditKind.equal);
        return Column(
          key: _rowKeys.putIfAbsent(row, GlobalKey.new),
          children: [
            if (gap)
              TextButton(
                onPressed: () => setState(() => _collapse = false),
                child: const GitLabel(GitMessages.expandUnchangedContext),
              ),
            if (_canStage &&
                changed &&
                (first == 0 || edits[first - 1].kind == TextEditKind.equal))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => unawaited(_applySelection(_hunk(first))),
                  child: Text(
                    _unstage
                        ? gitString(context, GitMessages.unstageThisHunk)
                        : gitString(context, GitMessages.stageThisHunk),
                  ),
                ),
              ),
            if (_unified)
              cell(left, _counterpartIndex(left!), false)
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cell(left, right, false)),
                    const VerticalDivider(width: 6),
                    Expanded(child: cell(right, left, true)),
                  ],
                ),
              ),
          ],
        );
      },
    );
    if (_wrap) return SelectionArea(child: list);
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final painter = TextPainter(
      text: TextSpan(text: '界', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final unit = painter.width;
    painter.dispose();
    var oldLength = 0, newLength = 0;
    for (final edit in edits) {
      final length = edit.text.length + 8;
      if (edit.oldLine != null && length > oldLength) oldLength = length;
      if (edit.newLine != null && length > newLength) newLength = length;
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final needed = _unified
            ? (oldLength > newLength ? oldLength : newLength) * unit
            : (oldLength + newLength) * unit;
        final width = needed > bounds.maxWidth ? needed : bounds.maxWidth;
        return Scrollbar(
          controller: _horizontalScroll,
          child: SingleChildScrollView(
            controller: _horizontalScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: bounds.maxHeight,
              child: SelectionArea(child: list),
            ),
          ),
        );
      },
    );
  }

  void _selectChangedLine(int index) {
    final edits = _diff!.edits;
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed &&
          _selectionAnchor != null) {
        final first = math.min(_selectionAnchor!, index);
        final last = math.max(_selectionAnchor!, index);
        for (var i = first; i <= last; i++) {
          if (edits[i].kind != TextEditKind.equal) _selected.add(i);
        }
      } else {
        if (!_selected.add(index)) _selected.remove(index);
        _selectionAnchor = index;
      }
    });
  }

  int? _counterpartIndex(int index) {
    final text = _counterpart(index);
    if (text == null) return null;
    final edits = _diff!.edits;
    for (
      var i = index - 1;
      i >= 0 && edits[i].kind != TextEditKind.equal;
      i--
    ) {
      if (edits[i].kind != edits[index].kind && edits[i].text == text) return i;
    }
    for (
      var i = index + 1;
      i < edits.length && edits[i].kind != TextEditKind.equal;
      i++
    ) {
      if (edits[i].kind != edits[index].kind && edits[i].text == text) return i;
    }
    return null;
  }

  Set<int> _hunk(int index) {
    final edits = _diff!.edits;
    var start = index, end = index, context = 0;
    while (start > 0) {
      start--;
      context = edits[start].kind == TextEditKind.equal ? context + 1 : 0;
      if (context > 6) break;
    }
    context = 0;
    while (end + 1 < edits.length) {
      end++;
      context = edits[end].kind == TextEditKind.equal ? context + 1 : 0;
      if (context > 6) break;
    }
    return {
      for (var i = start; i <= end; i++)
        if (edits[i].kind != TextEditKind.equal) i,
    };
  }

  Widget _line(
    String text,
    String number,
    TextEditKind kind,
    String? counterpart,
  ) {
    final shown = text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final content = Text.rich(
      TextSpan(children: _wordSpans(shown, counterpart, kind)),
      style: style,
      softWrap: _wrap,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _unified ? 82 : 48,
          child: Text(
            number,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          kind == TextEditKind.add
              ? '+'
              : kind == TextEditKind.remove
              ? '−'
              : ' ',
          style: style,
        ),
        const SizedBox(width: 4),
        Expanded(child: content),
      ],
    );
  }

  List<InlineSpan> _wordSpans(
    String value,
    String? counterpart,
    TextEditKind kind,
  ) {
    if (!_words ||
        counterpart == null ||
        kind == TextEditKind.equal ||
        _search.text.isNotEmpty ||
        value.length > 16000)
      return _highlight(value, null);
    final words = RegExp(
      r'\s+|[^\s]+',
    ).allMatches(value).map((m) => m.group(0)!).toList();
    final other = RegExp(
      r'\s+|[^\s]+',
    ).allMatches(counterpart.trimRight()).map((m) => m.group(0)!).toList();
    if (words.length + other.length > 4000) return _highlight(value, null);
    Set<int> changed;
    try {
      changed = computeTokenDiff(words, other, maximumWork: 20000).edits
          .where((e) => e.kind == TextEditKind.remove)
          .map((e) => e.oldLine! - 1)
          .toSet();
    } on GitException {
      changed = Set.from(List.generate(words.length, (i) => i));
    }
    return [
      for (var i = 0; i < words.length; i++)
        TextSpan(
          text: words[i],
          style: changed.contains(i)
              ? TextStyle(
                  backgroundColor: (kind == TextEditKind.add
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.errorContainer),
                )
              : null,
        ),
    ];
  }

  List<InlineSpan> _highlight(String value, TextStyle? style) {
    final search = _search.text;
    if (search.isEmpty) return [TextSpan(text: value)];
    final spans = <InlineSpan>[];
    var start = 0;
    while (start < value.length) {
      final index = value.toLowerCase().indexOf(search.toLowerCase(), start);
      if (index < 0) {
        spans.add(TextSpan(text: value.substring(start)));
        break;
      }
      spans.add(TextSpan(text: value.substring(start, index)));
      spans.add(
        TextSpan(
          text: value.substring(index, index + search.length),
          style: TextStyle(
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
          ),
        ),
      );
      start = index + search.length;
    }
    return spans;
  }

  void _jump(int direction) {
    if (_diff == null || !_scroll.hasClients) return;
    final edits = _diff!.edits, rows = _alignedRows();
    final changes = <int>[];
    var previousChanged = false;
    for (var row = 0; row < rows.length; row++) {
      final changed = [rows[row].$1, rows[row].$2].any(
        (index) => index != null && edits[index].kind != TextEditKind.equal,
      );
      if (changed && !previousChanged) changes.add(row);
      previousChanged = changed;
    }
    if (changes.isEmpty) return;
    _difference = _difference < 0
        ? direction > 0
              ? 0
              : changes.length - 1
        : (_difference + direction) % changes.length;
    unawaited(_scrollToRenderedRow(changes[_difference], _generation));
  }

  Future<void> _scrollToRenderedRow(int row, int generation) async {
    for (var attempt = 0; attempt < 14; attempt++) {
      if (!mounted || generation != _generation || !_scroll.hasClients) return;
      final target = _rowKeys[row]?.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          alignment: .18,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
        return;
      }
      final mountedRows =
          _rowKeys.entries
              .where((entry) => entry.value.currentContext != null)
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      if (mountedRows.isEmpty) return;
      final nearest = mountedRows.reduce(
        (a, b) => (a.key - row).abs() <= (b.key - row).abs() ? a : b,
      );
      final first = mountedRows.first, last = mountedRows.last;
      final firstBox =
          first.value.currentContext!.findRenderObject() as RenderBox;
      final lastBox =
          last.value.currentContext!.findRenderObject() as RenderBox;
      final measured = first.key == last.key
          ? widget.session.host.rowHeight(context)
          : (lastBox.localToGlobal(Offset.zero).dy -
                    firstBox.localToGlobal(Offset.zero).dy) /
                (last.key - first.key);
      final rowHeight = widget.session.host.rowHeight(context);
      final estimate = measured.clamp(rowHeight, rowHeight * 18);
      final desired = (_scroll.offset + (row - nearest.key) * estimate).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if ((desired - _scroll.offset).abs() < 1) return;
      _scroll.jumpTo(desired);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _wholeFile() async {
    if (!_stagingComparison ||
        widget.session.running ||
        _stale ||
        !widget.session.canWriteMetadata)
      return;
    final snapshot = _review ?? widget.session.snapshot;
    if (snapshot == null) return;
    await widget.session.mutate(
      StagePaths(
        [
          widget.comparison.path,
          if (_unstage && widget.comparison.leftPath != null)
            widget.comparison.leftPath!,
        ],
        expectedHead: snapshot.head,
        expectedIndex: snapshot.indexToken,
        unstage: _unstage,
        expectedSnapshot: snapshot.token,
        contentTokens: {
          if (!_unstage && _right != null)
            widget.comparison.path.key: _right!.sourceToken.isEmpty
                ? _right!.token
                : _right!.sourceToken,
        },
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _applySelection([Set<int>? hunk]) async {
    final selection = hunk ?? _selected;
    if (!_canStage || selection.isEmpty) return;
    final path = widget.comparison.path, session = widget.session;
    final index = _unstage ? _right! : _left!;
    final bytes = _diff!.select(selection, exclude: _unstage);
    final result = await session.mutate(
      WriteIndex(
        path,
        bytes,
        expectedHead: _review!.head,
        expectedIndex: _review!.indexToken,
        expectedContent: index.token,
        expectedWorktree: _unstage
            ? null
            : _right!.sourceToken.isEmpty
            ? _right!.token
            : _right!.sourceToken,
        remove:
            (_unstage ? _left!.availability : _right!.availability) ==
                ContentAvailability.absent &&
            _diff!.changedIndices.every(selection.contains),
        mode: index.mode == '000000'
            ? (_right!.mode == '000000' ? '100644' : _right!.mode)
            : index.mode,
      ),
    );
    if (mounted) {
      if (result?.error case final error?)
        setState(() => _error = error);
      else
        await _load();
    }
  }

  Future<void> _indexEditor() async {
    await widget.session.host.present<void>(
      context,
      gitString(
        context,
        GitMessages.editStagedContentArg0,
        values: {'arg0': widget.comparison.path.display},
      ),
      GitIndexEditor(session: widget.session, path: widget.comparison.path),
      expanded: true,
    );
    if (mounted) await _load();
  }
}

final class GitIndexEditor extends StatefulWidget {
  const GitIndexEditor({super.key, required this.session, required this.path});
  final GitSession session;
  final RepoPath path;
  @override
  State<GitIndexEditor> createState() => _GitIndexEditorState();
}

final class _GitIndexEditorState extends State<GitIndexEditor> {
  GitSnapshot? _snapshot;
  GitContent? _head, _index, _working;
  GitException? _failure;
  final _headText = GitHighlightedTextController();
  final _result = GitHighlightedTextController();
  final _workingText = GitHighlightedTextController();
  final _undo = UndoHistoryController();
  final _regions = <_IndexRegion>[];
  Timer? _regionTimer;
  int _loadGeneration = 0, _regionGeneration = 0, _activeRegion = 0;
  int _anchorRevision = 0;
  String? _lastResultText;
  bool _saving = false, _dirty = false, _regionsLoading = false;
  bool _stale = false, _allowClose = false;
  @override
  void initState() {
    super.initState();
    _result.addListener(_resultChanged);
    widget.session.addListener(_repositoryChanged);
    unawaited(_load());
  }

  void _repositoryChanged() {
    final current = widget.session.snapshot;
    if (mounted &&
        _snapshot != null &&
        current != null &&
        current.token != _snapshot!.token &&
        !_stale) {
      setState(() => _stale = true);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _regionGeneration++;
    _regionTimer?.cancel();
    _result.removeListener(_resultChanged);
    widget.session.removeListener(_repositoryChanged);
    _headText.dispose();
    _result.dispose();
    _workingText.dispose();
    _undo.dispose();
    super.dispose();
  }

  void _resultChanged() {
    if (_snapshot == null || _saving || _result.text == _lastResultText) return;
    _lastResultText = _result.text;
    final dirty = _result.text != (_index?.text ?? '');
    if (_dirty != dirty) setState(() => _dirty = dirty);
    _regionTimer?.cancel();
    _regionTimer = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(_computeRegions()),
    );
  }

  Future<void> _computeRegions() async {
    final generation = ++_regionGeneration;
    final head = _head?.text ?? '',
        index = _result.text,
        working = _working?.text ?? '';
    setState(() => _regionsLoading = true);
    try {
      final diffs = await Future.wait([
        _backgroundDiff(head, index),
        _backgroundDiff(index, working),
      ]);
      if (!mounted || generation != _regionGeneration || index != _result.text)
        return;
      final staged = _indexRegions(
        diffs[0],
        head,
        index,
        GitHighlightKind.staged,
      );
      final unstaged = _indexRegions(
        diffs[1],
        index,
        working,
        GitHighlightKind.unstaged,
      );
      setState(() {
        _regions
          ..clear()
          ..addAll(
            [...staged, ...unstaged]
              ..sort((a, b) => a.indexStart.compareTo(b.indexStart)),
          );
        _activeRegion = _activeRegion.clamp(
          0,
          _regions.isEmpty ? 0 : _regions.length - 1,
        );
        _regionsLoading = false;
      });
      _headText.setHighlights([
        for (final region in staged)
          GitTextHighlight(
            region.sourceStart,
            region.sourceEnd,
            GitHighlightKind.staged,
          ),
      ]);
      _result.setHighlights([
        for (final region in _regions)
          GitTextHighlight(region.indexStart, region.indexEnd, region.kind),
      ]);
      _workingText.setHighlights([
        for (final region in unstaged)
          GitTextHighlight(
            region.sourceStart,
            region.sourceEnd,
            GitHighlightKind.unstaged,
          ),
      ]);
    } on Object catch (error) {
      if (mounted && generation == _regionGeneration)
        setState(() {
          _regionsLoading = false;
          _failure = error is GitException
              ? error
              : GitException(
                  GitErrorCode.commandFailed,
                  diagnostic: sanitizeGitDiagnostic('$error'),
                );
        });
    }
  }

  void _navigateRegion(int direction) {
    if (_regions.isEmpty) return;
    setState(() {
      _activeRegion = (_activeRegion + direction) % _regions.length;
      _anchorRevision++;
    });
  }

  void _transferRegion(GitHighlightKind kind) {
    if (_saving || _regionsLoading || _regions.isEmpty) return;
    final region = _regions[_activeRegion];
    if (region.kind != kind) return;
    final next = _result.text.replaceRange(
      region.indexStart,
      region.indexEnd,
      region.replacement,
    );
    _result.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: region.indexStart + region.replacement.length,
      ),
    );
    _anchorRevision++;
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final session = widget.session,
          snapshot = await widget.session.readStatus();
      final headPath =
          snapshot.changes
              .where((e) => e.path == widget.path && e.index == 'R')
              .firstOrNull
              ?.originalPath ??
          widget.path;
      final values = await Future.wait([
        session.client.content(
          session.repository,
          headPath,
          snapshot.head == null
              ? const ContentVersion.absent()
              : ContentVersion(ContentKind.commit, revision: snapshot.head),
        ),
        session.client.content(
          session.repository,
          widget.path,
          const ContentVersion.index(),
        ),
        session.client.content(
          session.repository,
          widget.path,
          const ContentVersion(ContentKind.normalizedWorking),
        ),
      ]);
      final after = await session.readStatus();
      if (!mounted || generation != _loadGeneration) return;
      if (after.token != snapshot.token) {
        throw const GitException(GitErrorCode.staleReview);
      }
      if (values.any(
        (value) =>
            value.availability != ContentAvailability.absent &&
            value.text == null,
      )) {
        throw const GitException(GitErrorCode.unsupportedContent);
      }
      setState(() {
        _snapshot = snapshot;
        _head = values[0];
        _index = values[1];
        _working = values[2];
        _headText.text = _head!.text ?? '';
        _workingText.text = _working!.text ?? '';
        _lastResultText = _index!.text ?? '';
        _result.text = _index!.text ?? '';
        _dirty = false;
        _stale = false;
      });
      unawaited(_computeRegions());
    } on Object catch (error) {
      if (mounted && generation == _loadGeneration)
        setState(
          () => _failure = error is GitException
              ? error
              : GitException(
                  GitErrorCode.commandFailed,
                  diagnostic: sanitizeGitDiagnostic('$error'),
                ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_snapshot == null && _failure != null)
      return GitFailurePanel(
        error: _failure!,
        onRefresh: () => unawaited(_load()),
      );
    if (_snapshot == null)
      return const Center(child: CircularProgressIndicator());
    return PopScope<void>(
      canPop: _allowClose || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving || !_dirty) return;
        unawaited(_confirmClose());
      },
      child: Column(
        children: [
          if (_saving)
            LinearProgressIndicator(
              semanticsLabel: gitString(
                context,
                GitMessages.writingReviewedIndexResult,
              ),
            ),
          if (_stale)
            const GitLabel(
              GitMessages
                  .theReviewedIndexOrWorkingContentChangedRefreshThisComparison,
            ),
          if (_failure != null)
            Flexible(
              child: SingleChildScrollView(
                child: GitFailurePanel(error: _failure!),
              ),
            ),
          Wrap(
            spacing: widget.session.host.spacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GitLabel(
                GitMessages.groupCount,
                values: {
                  'group': gitString(context, GitMessages.staged),
                  'count': _regions
                      .where((r) => r.kind == GitHighlightKind.staged)
                      .length,
                },
              ),
              GitLabel(
                GitMessages.groupCount,
                values: {
                  'group': gitString(context, GitMessages.unstaged),
                  'count': _regions
                      .where((r) => r.kind == GitHighlightKind.unstaged)
                      .length,
                },
              ),
              if (_dirty) const GitLabel(GitMessages.dirty),
              GitIconButton(
                tooltip: gitString(context, GitMessages.previousDifference),
                onPressed: _regions.isEmpty ? null : () => _navigateRegion(-1),
                icon: const GitIcon(GitGlyph.up),
              ),
              GitIconButton(
                tooltip: gitString(context, GitMessages.nextDifference),
                onPressed: _regions.isEmpty ? null : () => _navigateRegion(1),
                icon: const GitIcon(GitGlyph.down),
              ),
              TextButton(
                onPressed:
                    _regions.isEmpty ||
                        _saving ||
                        _regionsLoading ||
                        _regions[_activeRegion].kind != GitHighlightKind.staged
                    ? null
                    : () => _transferRegion(GitHighlightKind.staged),
                child: const GitLabel(GitMessages.unstageThisHunk),
              ),
              TextButton(
                onPressed:
                    _regions.isEmpty ||
                        _saving ||
                        _regionsLoading ||
                        _regions[_activeRegion].kind !=
                            GitHighlightKind.unstaged
                    ? null
                    : () => _transferRegion(GitHighlightKind.unstaged),
                child: const GitLabel(GitMessages.stageThisHunk),
              ),
            ],
          ),
          Expanded(
            child: GitRevisionPanes(
              labels: const [
                GitMessages.head,
                GitMessages.index,
                GitMessages.workingTree,
              ],
              anchorRevision: _anchorRevision,
              panes: [
                (scroll) => GitTextPane(
                  label: gitString(
                    context,
                    GitMessages.headArg0,
                    values: {
                      'arg0':
                          _snapshot!.head?.abbreviated ??
                          gitString(context, GitMessages.unborn),
                    },
                  ),
                  controller: _headText,
                  readOnly: true,
                  semanticLabel: GitMessages.readOnlyRevisionContent,
                  scrollController: scroll,
                  revealRevision: _anchorRevision,
                  revealOffset:
                      _regions.isEmpty ||
                          _regions[_activeRegion].kind !=
                              GitHighlightKind.staged
                      ? null
                      : _regions[_activeRegion].sourceStart,
                ),
                (scroll) => GitTextPane(
                  label: gitString(context, GitMessages.indexEditableUTF8Blob),
                  controller: _result,
                  readOnly: _saving,
                  undoController: _undo,
                  scrollController: scroll,
                  revealRevision: _anchorRevision,
                  revealOffset: _regions.isEmpty
                      ? null
                      : _regions[_activeRegion].indexStart,
                ),
                (scroll) => GitTextPane(
                  label: gitVersionLabel(context, _working!.version),
                  controller: _workingText,
                  readOnly: true,
                  semanticLabel: GitMessages.readOnlyRevisionContent,
                  scrollController: scroll,
                  revealRevision: _anchorRevision,
                  revealOffset:
                      _regions.isEmpty ||
                          _regions[_activeRegion].kind !=
                              GitHighlightKind.unstaged
                      ? null
                      : _regions[_activeRegion].sourceStart,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(widget.session.host.spacing),
            child: Wrap(
              spacing: widget.session.host.spacing,
              children: [
                ListenableBuilder(
                  listenable: _undo,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _saving || !_undo.value.canUndo
                            ? null
                            : _undo.undo,
                        child: const GitLabel(GitMessages.undo),
                      ),
                      TextButton(
                        onPressed: _saving || !_undo.value.canRedo
                            ? null
                            : _undo.redo,
                        child: const GitLabel(GitMessages.redo),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          if (_result.text != (_index!.text ?? '') &&
                              await widget.session.host.present<bool>(
                                    context,
                                    GitMessages.reloadIndexReview,
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const GitLabel(
                                          GitMessages
                                              .reloadTheCurrentHEADIndexAndWorkingVersionsThisReplaces,
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(true),
                                          child: const GitLabel(
                                            GitMessages.replaceDraftAndReload,
                                          ),
                                        ),
                                      ],
                                    ),
                                    expanded: false,
                                  ) !=
                                  true)
                            return;
                          if (mounted) {
                            setState(() => _failure = null);
                            await _load();
                          }
                        },
                  child: const GitLabel(GitMessages.reloadVersions),
                ),
                FilledButton(
                  onPressed: _saving || _stale || !_dirty
                      ? null
                      : () => unawaited(_apply()),
                  child: const GitLabel(
                    GitMessages.writeEditedResultToThisIndexEntry,
                  ),
                ),
                const GitLabel(
                  GitMessages
                      .workingFilesRemainOnDiskReviewTheEditedIndexBefore,
                ),
                ListenableBuilder(
                  listenable: _result,
                  builder: (context, _) => GitLabel(
                    gitTextFormatLabel(_result.text, context: context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose() async {
    if (!await gitConfirm(
      context,
      widget.session,
      GitMessages.discardUnsavedIndexDraft,
      GitMessages.closingTheIndexEditorDiscardsOnlyItsDraft,
      action: GitMessages.discardIndexDraft,
    ))
      return;
    if (!mounted) return;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) gitCompleteSurface(context);
  }

  Future<void> _apply() async {
    if (_stale || !_dirty) return;
    final text = _result.text;
    final formatChange = gitTextFormatChange(
      _index!.text ?? '',
      text,
      context: context,
    );
    if (formatChange != null &&
        !await gitConfirm(
          context,
          widget.session,
          GitMessages.reviewIndexTextFormatChanges,
          gitString(
            context,
            GitMessages.updateOnlyTheReviewedIndexEntryForArg0Arg1,
            values: {'arg0': widget.path.display, 'arg1': formatChange},
          ),
          action: GitMessages.writeReviewedIndexResult,
        ))
      return;
    if (!mounted) return;
    if (_result.text != text) {
      setState(
        () => _failure = const GitException(
          GitErrorCode.staleReview,
          diagnostic:
              GitMessages.theEditedResultChangedDuringFormatReviewReviewItAgain,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final result = await widget.session.mutate(
      WriteIndex(
        widget.path,
        Uint8List.fromList(utf8.encode(text)),
        expectedHead: _snapshot!.head,
        expectedIndex: _snapshot!.indexToken,
        expectedContent: _index!.token,
        expectedWorktree: _working!.sourceToken.isEmpty
            ? _working!.token
            : _working!.sourceToken,
        mode: _index!.mode == '000000'
            ? (_working!.mode == '000000' ? '100644' : _working!.mode)
            : _index!.mode,
      ),
    );
    if (!mounted) return;
    if (result?.completed == true) {
      setState(() => _allowClose = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) gitCompleteSurface(context);
    } else
      setState(() {
        _failure = result?.error;
        _saving = false;
      });
  }
}

final class _IndexRegion {
  const _IndexRegion(
    this.indexStart,
    this.indexEnd,
    this.sourceStart,
    this.sourceEnd,
    this.replacement,
    this.kind,
  );
  final int indexStart, indexEnd, sourceStart, sourceEnd;
  final String replacement;
  final GitHighlightKind kind;
}

List<_IndexRegion> _indexRegions(
  TextDiff diff,
  String oldText,
  String newText,
  GitHighlightKind kind,
) {
  final regions = <_IndexRegion>[];
  var oldOffset = 0, newOffset = 0;
  int? oldStart, newStart;
  void flush() {
    if (oldStart == null || newStart == null) return;
    if (kind == GitHighlightKind.staged) {
      regions.add(
        _IndexRegion(
          newStart!,
          newOffset,
          oldStart!,
          oldOffset,
          oldText.substring(oldStart!, oldOffset),
          kind,
        ),
      );
    } else {
      regions.add(
        _IndexRegion(
          oldStart!,
          oldOffset,
          newStart!,
          newOffset,
          newText.substring(newStart!, newOffset),
          kind,
        ),
      );
    }
    oldStart = newStart = null;
  }

  for (final edit in diff.edits) {
    if (edit.kind == TextEditKind.equal) {
      flush();
      oldOffset += edit.text.length;
      newOffset += edit.text.length;
    } else {
      oldStart ??= oldOffset;
      newStart ??= newOffset;
      if (edit.kind == TextEditKind.remove) oldOffset += edit.text.length;
      if (edit.kind == TextEditKind.add) newOffset += edit.text.length;
    }
  }
  flush();
  return regions;
}

/// Three revision roles remain individually accessible at enlarged text or a
/// narrow host window. The host can expand the same surface for simultaneous
/// review; changing the visible role never recreates an editing controller.
final class GitRevisionPanes extends StatefulWidget {
  const GitRevisionPanes({
    super.key,
    required this.labels,
    required this.panes,
    this.anchorRevision = 0,
  });
  final int anchorRevision;
  final List<String> labels;
  final List<Widget Function(ScrollController)> panes;
  @override
  State<GitRevisionPanes> createState() => _RevisionPanesState();
}

final class _RevisionPanesState extends State<GitRevisionPanes> {
  final _scrolls = List.generate(3, (_) => ScrollController());
  int _selected = 1;
  bool _sync = true, _moving = false, _anchoring = false;
  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      final index = i;
      _scrolls[i].addListener(() => _synchronize(index));
    }
  }

  @override
  void didUpdateWidget(covariant GitRevisionPanes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchorRevision != oldWidget.anchorRevision) {
      _anchoring = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduleMicrotask(() => _anchoring = false);
      });
    }
  }

  void _synchronize(int source) {
    if (!_sync || _anchoring || _moving || !_scrolls[source].hasClients) return;
    _moving = true;
    try {
      for (var i = 0; i < 3; i++) {
        if (i != source && _scrolls[i].hasClients)
          _scrolls[i].jumpTo(
            _scrolls[source].offset.clamp(
              0,
              _scrolls[i].position.maxScrollExtent,
            ),
          );
      }
    } finally {
      _moving = false;
    }
  }

  @override
  void dispose() {
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final font = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;
      final minimum = math.max(
        720.0,
        MediaQuery.textScalerOf(context).scale(font) / 14 * 720,
      );
      final narrow = bounds.maxWidth < minimum;
      final panes = [for (var i = 0; i < 3; i++) widget.panes[i](_scrolls[i])];
      return Column(
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (narrow)
                SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < 3; i++)
                      ButtonSegment(
                        value: i,
                        label: GitLabel(widget.labels[i]),
                      ),
                  ],
                  selected: {_selected},
                  onSelectionChanged: (value) =>
                      setState(() => _selected = value.single),
                ),
              FilterChip(
                label: const GitLabel(GitMessages.synchronizeScrolling),
                selected: _sync,
                onSelected: (value) => setState(() => _sync = value),
              ),
            ],
          ),
          Expanded(
            child: narrow
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Offstage(
                          offstage: i != _selected,
                          child: ExcludeFocus(
                            excluding: i != _selected,
                            child: ExcludeSemantics(
                              excluding: i != _selected,
                              child: panes[i],
                            ),
                          ),
                        ),
                    ],
                  )
                : GitSplitter(
                    initial: .33,
                    minimum: 220,
                    first: panes[0],
                    second: GitSplitter(
                      initial: .5,
                      minimum: 220,
                      first: panes[1],
                      second: panes[2],
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
