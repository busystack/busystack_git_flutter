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
  final _scroll = ScrollController(), _search = TextEditingController();
  var _generation = 0, _difference = 0;
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
    _generation++;
    _readCancellation?.cancel();
    widget.session.removeListener(_repositoryChanged);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _displayLimit = null;
      _selected.clear();
    });
    _readCancellation?.cancel();
    final cancellation = _readCancellation = GitCancellation();
    try {
      final session = widget.session, comparison = widget.comparison;
      final before = await session.readStatus(cancellation: cancellation);
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
      final after = await session.readStatus(cancellation: cancellation);
      if (before.token != after.token)
        throw const GitException(GitErrorCode.staleReview);
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
        _stale = false;
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

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: widget.session.host,
    child: Builder(builder: _build),
  );
  Widget _build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return GitFailurePanel(
        error: _error!,
        onRefresh: () => unawaited(_load()),
      );
    final comparison = widget.comparison, host = widget.session.host;
    return Column(
      children: [
        if (_stale)
          MaterialBanner(
            content: const GitLabel(
              'The reviewed index or working content changed. Refresh this comparison before staging.',
            ),
            actions: [
              TextButton(
                onPressed: () => unawaited(_load()),
                child: const GitLabel('Refresh comparison'),
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
                    tooltip: 'Refresh comparison',
                    onPressed: () => unawaited(_load()),
                    icon: const Icon(Icons.refresh),
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
                      tooltip: 'Previous changed file',
                      onPressed: widget.onPreviousFile,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    GitIconButton(
                      tooltip: 'Next changed file',
                      onPressed: widget.onNextFile,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                  GitIconButton(
                    tooltip: 'Previous difference',
                    onPressed: () => _jump(-1),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  ),
                  GitIconButton(
                    tooltip: 'Next difference',
                    onPressed: () => _jump(1),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: GitLabel('Side by side'),
                      ),
                      ButtonSegment(value: true, label: GitLabel('Unified')),
                    ],
                    selected: {_unified},
                    onSelectionChanged: (s) => _display(
                      'diffUnified',
                      s.single,
                      () => _unified = s.single,
                    ),
                  ),
                  FilterChip(
                    label: const GitLabel('Wrap'),
                    selected: _wrap,
                    onSelected: (v) => _display('diffWrap', v, () => _wrap = v),
                  ),
                  FilterChip(
                    label: const GitLabel('Words'),
                    selected: _words,
                    onSelected: (v) =>
                        _display('diffWords', v, () => _words = v),
                  ),
                  FilterChip(
                    label: const GitLabel('Collapse context'),
                    selected: _collapse,
                    onSelected: (v) =>
                        _display('diffCollapse', v, () => _collapse = v),
                  ),
                  FilterChip(
                    label: const GitLabel('Ignore whitespace'),
                    selected: _ignoreWhitespace,
                    onSelected: (v) => _display(
                      'diffIgnoreWhitespace',
                      v,
                      () => _ignoreWhitespace = v,
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        labelText: gitString(context, 'Search'),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_canStage)
                Wrap(
                  spacing: host.spacing,
                  children: [
                    FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => unawaited(_applySelection()),
                      child: Text(
                        _unstage
                            ? 'Unstage selected changed lines'
                            : 'Stage selected changed lines',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => unawaited(_indexEditor()),
                      child: const GitLabel(
                        'Edit HEAD | Index | Working Tree…',
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_wholeFile()),
                      child: Text(
                        _unstage ? 'Unstage whole file' : 'Stage whole file',
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
              '${_ignoredWhitespace().length} whitespace-only changed lines hidden · Show exact changes',
            ),
          ),
        const Divider(height: 1),
        Expanded(child: _diff == null ? _nonText() : _reviewRows(context)),
        if (_diff != null)
          Padding(
            padding: EdgeInsets.all(host.spacing),
            child: Text(
              '${_selected.length} changed lines selected · Display settings never alter the staged bytes.',
            ),
          ),
      ],
    );
  }

  Widget _label(GitContent content) => Padding(
    padding: const EdgeInsets.all(6),
    child: Text(
      '${content.version.label} · ${content.mode} · ${content.size} bytes${content.bytes.isNotEmpty && content.bytes.last != 10 ? ' · no final newline' : ''}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
  Widget _nonText() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${_left!.availability.name} → ${_right!.availability.name}'),
        Text(
          _displayLimit == null
              ? 'Text comparison is unavailable for these contents.'
              : 'This comparison exceeds the bounded text review limit. The contents have not been declared identical.',
        ),
        if (_stagingComparison)
          TextButton(
            onPressed:
                widget.session.running ||
                    _stale ||
                    !widget.session.canWriteMetadata
                ? null
                : () => unawaited(_wholeFile()),
            child: Text(_unstage ? 'Unstage whole file' : 'Stage whole file'),
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
        child: GitLabel('The compared contents are identical.'),
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
            ? '${_unstage ? 'Unstage' : 'Stage'} changed line'
            : 'Context',
        child: InkWell(
          canRequestFocus: changed && _canStage,
          onTap: !changed || !_canStage
              ? null
              : () => setState(() {
                  if (!_selected.add(index!)) _selected.remove(index);
                }),
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

    return SelectionArea(
      child: ListView.builder(
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
          final changed = indices.any(
            (i) => edits[i].kind != TextEditKind.equal,
          );
          return Column(
            children: [
              if (gap)
                TextButton(
                  onPressed: () => setState(() => _collapse = false),
                  child: const GitLabel('Expand unchanged context'),
                ),
              if (_canStage &&
                  changed &&
                  (first == 0 || edits[first - 1].kind == TextEditKind.equal))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => unawaited(_applySelection(_hunk(first))),
                    child: Text(
                      _unstage ? 'Unstage this hunk' : 'Stage this hunk',
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
      ),
    );
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
        Expanded(
          child: _wrap
              ? content
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: content,
                ),
        ),
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
    final changes = _diff?.changedIndices ?? [];
    if (changes.isEmpty || !_scroll.hasClients) return;
    _difference = (_difference + direction) % changes.length;
    final row = _alignedRows().indexWhere(
      (r) => r.$1 == changes[_difference] || r.$2 == changes[_difference],
    );
    _scroll.animateTo(
      (row * widget.session.host.rowHeight(context)).clamp(
        0,
        _scroll.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
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
      'Edit staged content · ${widget.comparison.path.display}',
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
  final _result = TextEditingController();
  final _undo = UndoHistoryController();
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _result.dispose();
    _undo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      if (!mounted) return;
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
        _result.text = _index!.text ?? '';
      });
    } on Object catch (error) {
      if (mounted)
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
    return Column(
      children: [
        if (_saving)
          LinearProgressIndicator(
            semanticsLabel: gitString(context, 'Writing reviewed index result'),
          ),
        if (_failure != null)
          Flexible(
            child: SingleChildScrollView(
              child: GitFailurePanel(error: _failure!),
            ),
          ),
        Expanded(
          child: GitRevisionPanes(
            labels: const ['HEAD', 'Index', 'Working Tree'],
            panes: [
              (scroll) => GitTextPane(
                label: 'HEAD · ${_snapshot!.head?.abbreviated ?? 'unborn'}',
                text: _head!.text ?? '',
                scrollController: scroll,
              ),
              (scroll) => GitTextPane(
                label: 'Index · editable UTF-8 blob',
                controller: _result,
                readOnly: _saving,
                undoController: _undo,
                scrollController: scroll,
              ),
              (scroll) => GitTextPane(
                label: _working!.version.label,
                text: _working!.text ?? '',
                scrollController: scroll,
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.all(widget.session.host.spacing),
          child: Wrap(
            spacing: widget.session.host.spacing,
            children: [
              TextButton(
                onPressed: _saving ? null : _undo.undo,
                child: const GitLabel('Undo'),
              ),
              TextButton(
                onPressed: _saving ? null : _undo.redo,
                child: const GitLabel('Redo'),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_result.text != (_index!.text ?? '') &&
                            await widget.session.host.present<bool>(
                                  context,
                                  'Reload index review?',
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const GitLabel(
                                        'Reload the current HEAD, index and working versions. This replaces the unsaved index editor draft.',
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const GitLabel(
                                          'Replace draft and reload',
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
                child: const GitLabel('Reload versions…'),
              ),
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_apply()),
                child: const GitLabel(
                  'Write edited result to this index entry',
                ),
              ),
              const GitLabel(
                'Working files remain on disk. Review the edited index before applying.',
              ),
              ListenableBuilder(
                listenable: _result,
                builder: (context, _) =>
                    GitLabel(gitTextFormatLabel(_result.text)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    final text = _result.text;
    final formatChange = gitTextFormatChange(_index!.text ?? '', text);
    if (formatChange != null &&
        !await gitConfirm(
          context,
          widget.session,
          'Review index text format changes',
          'Update only the reviewed index entry for ${widget.path.display}.\n\n$formatChange',
          action: 'Write reviewed index result',
        ))
      return;
    if (!mounted) return;
    if (_result.text != text) {
      setState(
        () => _failure = const GitException(
          GitErrorCode.staleReview,
          diagnostic:
              'The edited result changed during format review. Review it again.',
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
    if (result?.completed == true)
      Navigator.of(context).pop();
    else
      setState(() {
        _failure = result?.error;
        _saving = false;
      });
  }
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
                      ButtonSegment(value: i, label: Text(widget.labels[i])),
                  ],
                  selected: {_selected},
                  onSelectionChanged: (value) =>
                      setState(() => _selected = value.single),
                ),
              FilterChip(
                label: const GitLabel('Synchronize scrolling'),
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
