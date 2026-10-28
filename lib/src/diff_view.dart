import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'host.dart';
import 'session.dart';
import 'text_pane.dart';
import 'text_encoding.dart';
import 'text_undo.dart';
import 'text_correspondence.dart';
import 'diff_document_selection.dart';
import 'dismissal.dart';
import 'workflow_ui.dart' show gitConfirm;
export 'text_pane.dart';
export 'text_correspondence.dart';

Future<TextDiff> _backgroundDiff(String left, String right) =>
    Isolate.run(() => computeTextDiff(left, right));

// Search indexes bounded content off the UI isolate. The extra sentinel match
// reports truncation explicitly without retaining unbounded match metadata.
Future<List<(int, int, int)>> _backgroundSearch(
  List<String> lines,
  String query,
) => Isolate.run(() {
  final matches = <(int, int, int)>[];
  final literal = RegExp(
    RegExp.escape(query),
    caseSensitive: false,
    unicode: true,
  );
  for (var line = 0; line < lines.length; line++) {
    for (final match in literal.allMatches(lines[line])) {
      matches.add((line, match.start, match.end));
      if (matches.length > 10000) return matches;
    }
  }
  return matches;
});

// Callers rebuild immutable comparison descriptors when surrounding panes or
// labels change. Only actual endpoint changes retire the loaded review.
bool _sameComparison(GitComparison a, GitComparison b) {
  bool version(ContentVersion x, ContentVersion y) =>
      x.kind == y.kind && x.revision == y.revision && x.stage == y.stage;
  return a.path == b.path &&
      (a.leftPath ?? a.path) == (b.leftPath ?? b.path) &&
      version(a.left, b.left) &&
      version(a.right, b.right);
}

final class GitDiffView extends StatefulWidget {
  const GitDiffView({
    super.key,
    required this.session,
    required this.comparison,
    this.preview = false,
    this.onPreviousFile,
    this.onNextFile,
    @visibleForTesting this.searchMatches,
  });
  final Future<List<(int, int, int)>> Function(List<String>, String)?
  searchMatches;
  final GitSession session;
  final GitComparison comparison;
  final bool preview;
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
  final _scrollStorageKey = GlobalKey(debugLabel: 'Git diff vertical scroll');
  final _leftHorizontalStorageKey = GlobalKey(
    debugLabel: 'Git diff left scroll',
  );
  final _rightHorizontalStorageKey = GlobalKey(
    debugLabel: 'Git diff right scroll',
  );
  final _lineFocus = <int, FocusNode>{};
  final _searchMatches = <(int, int, int)>[];
  final _searchMatchesByLine = <int, List<(int, int)>>{};
  int _activeSearchMatch = -1, _searchQueryGeneration = 0;
  bool _searchLoading = false, _matchesLimited = false;
  GitException? _searchFailure;
  Timer? _searchTimer;
  int? _selectionAnchor;
  final _rowKeys = <int, GlobalKey>{};
  final _textKeys = <(int, bool), GlobalKey>{};
  final _scroll = ScrollController(),
      _horizontalScroll = ScrollController(),
      _rightHorizontalScroll = ScrollController(),
      _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchVisible = false;
  var _generation = 0,
      _difference = -1,
      _revealGeneration = 0,
      _searchNavigationGeneration = 0;
  @override
  void initState() {
    super.initState();
    _unified = widget.session.option('diffUnified', false);
    _wrap = widget.session.option('diffWrap', true);
    _words = widget.session.option('diffWords', true);
    _collapse = widget.session.option('diffCollapse', true);
    _ignoreWhitespace = widget.session.option('diffIgnoreWhitespace', false);
    widget.session.addListener(_repositoryChanged);
    _search.addListener(_searchChanged);
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
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_repositoryChanged);
      widget.session.addListener(_repositoryChanged);
    }
    if (!_sameComparison(oldWidget.comparison, widget.comparison) ||
        oldWidget.session != widget.session)
      unawaited(_load());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchQueryGeneration++;
    _searchFocus.dispose();
    for (final focus in _lineFocus.values) {
      focus.dispose();
    }
    _search.removeListener(_searchChanged);
    _generation++;
    _readCancellation?.cancel();
    widget.session.removeListener(_repositoryChanged);
    _scroll.dispose();
    _horizontalScroll.dispose();
    _rightHorizontalScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refreshStatus = false}) async {
    final generation = ++_generation;
    _searchTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _displayLimit = null;
      _selected.clear();
      _selectionAnchor = null;
      _rowKeys.clear();
      _textKeys.clear();
      _difference = -1;
      _searchMatches.clear();
      _searchMatchesByLine.clear();
      _activeSearchMatch = -1;
      _searchLoading = false;
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
      if (_search.text.isNotEmpty) _searchChanged();
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
    _revealGeneration++;
    setState(() {
      update();
      _rowKeys.clear();
      _difference = -1;
    });
    widget.session.setViewState(key, value);
  }

  void _searchChanged() {
    if (!mounted) return;
    final request = ++_searchQueryGeneration;
    _searchTimer?.cancel();
    _revealGeneration++;
    final query = _search.text;
    setState(() {
      _searchMatches.clear();
      _searchMatchesByLine.clear();
      _activeSearchMatch = -1;
      _matchesLimited = false;
      _searchFailure = null;
      _searchLoading = query.isNotEmpty && _diff != null;
      _rowKeys.clear();
    });
    if (_searchLoading) {
      _searchTimer = Timer(
        const Duration(milliseconds: 100),
        () =>
            unawaited(_findSearchMatches(request, _generation, query, _diff!)),
      );
    }
  }

  Future<void> _findSearchMatches(
    int request,
    int generation,
    String query,
    TextDiff diff,
  ) async {
    bool current() =>
        mounted &&
        request == _searchQueryGeneration &&
        generation == _generation &&
        identical(diff, _diff) &&
        query == _search.text;
    try {
      final search = widget.searchMatches ?? _backgroundSearch;
      final matches = await search(
        diff.edits.map((line) => line.text).toList(),
        query,
      );
      if (!current()) return;
      setState(() {
        _searchMatches.addAll(matches.take(10000));
        for (final match in _searchMatches) {
          _searchMatchesByLine.putIfAbsent(match.$1, () => []).add((
            match.$2,
            match.$3,
          ));
        }
        _matchesLimited = matches.length > 10000;
        _activeSearchMatch = _searchMatches.isEmpty ? -1 : 0;
        _searchLoading = false;
      });
      if (_activeSearchMatch >= 0) _revealSearchMatch();
    } on Object catch (error) {
      if (!current()) return;
      setState(() {
        _searchLoading = false;
        _searchFailure = error is GitException
            ? error
            : GitException(
                GitErrorCode.commandFailed,
                diagnostic: sanitizeGitDiagnostic('$error'),
              );
      });
    }
  }

  void _stepSearch(int delta) {
    if (_searchMatches.isEmpty) return;
    setState(
      () => _activeSearchMatch =
          (_activeSearchMatch + delta) % _searchMatches.length,
    );
    _revealSearchMatch();
  }

  void _revealSearchMatch() {
    final match = _searchMatches[_activeSearchMatch], line = match.$1;
    final generation = _generation, request = ++_searchNavigationGeneration;
    final rows = _alignedRows();
    final row = rows.indexWhere((pair) => pair.$1 == line || pair.$2 == line);
    if (row < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool current() =>
          mounted &&
          generation == _generation &&
          request == _searchNavigationGeneration;
      if (!current()) return;
      await _scrollToRenderedRow(row, generation);
      if (!current()) return;
      final edit = _diff!.edits[line];
      final sides = _unified
          ? [false]
          : [if (edit.oldLine != null) false, if (edit.newLine != null) true];
      for (final right in sides) {
        final render = _textKeys[(line, right)]?.currentContext
            ?.findRenderObject();
        RenderParagraph? paragraph;
        void visit(RenderObject node) {
          if (node is RenderParagraph) {
            paragraph = node;
          } else if (paragraph == null) {
            node.visitChildren(visit);
          }
        }

        if (render != null) visit(render);
        final target = paragraph;
        if (target == null || !target.attached) continue;
        final boxes = target.getBoxesForSelection(
          TextSelection(baseOffset: match.$2, extentOffset: match.$3),
        );
        if (boxes.isEmpty) continue;
        final box = boxes.first.toRect();
        if (!_wrap) {
          final horizontal = right ? _rightHorizontalScroll : _horizontalScroll;
          if (horizontal.hasClients) {
            final available = math.max(
              1.0,
              horizontal.position.viewportDimension - (_unified ? 128 : 96),
            );
            horizontal.jumpTo(
              (box.left - available / 2).clamp(
                0.0,
                horizontal.position.maxScrollExtent,
              ),
            );
          }
        }
        // Reveal the match inside a wrapped paragraph, rather than assuming
        // the logical line's top is the match's rendered vertical location.
        final viewport = RenderAbstractViewport.maybeOf(target);
        if (viewport != null && _scroll.hasClients) {
          final offset = viewport
              .getOffsetToReveal(target, .18, rect: box, axis: Axis.vertical)
              .offset;
          await _scroll.animateTo(
            offset.clamp(0.0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
          );
          if (!current()) return;
        }
      }
    });
  }

  bool get _canOpenSource =>
      !_stale &&
      _right?.availability == ContentAvailability.present &&
      {
        ContentKind.workingTree,
        ContentKind.normalizedWorking,
      }.contains(_right?.version.kind);

  bool _canInvokeReview(int generation) =>
      mounted && !_loading && generation == _generation;

  void _openSource(int expectedGeneration) {
    if (!_canInvokeReview(expectedGeneration) || !_canOpenSource) return;
    final session = widget.session, path = widget.comparison.path;
    unawaited(
      session.host
          .openDocument(session.repository, path)
          .catchError((Object error) => session.reportFailure(error)),
    );
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
    final generation = _generation;
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
        if (_canOpenSource)
          const SingleActivator(LogicalKeyboardKey.f4): () =>
              _openSource(generation),
        const SingleActivator(LogicalKeyboardKey.f7): () => _jump(1),
        const SingleActivator(LogicalKeyboardKey.f7, shift: true): () =>
            _jump(-1),
        const SingleActivator(LogicalKeyboardKey.f3): () => _stepSearch(1),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
            _stepSearch(-1),
        if (widget.onPreviousFile != null)
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              widget.onPreviousFile!,
        if (widget.onNextFile != null)
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
              widget.onNextFile!,
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
          if (!widget.preview)
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
                          tooltip: gitString(
                            context,
                            GitMessages.comparisonMode,
                          ),
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
                          GitMenuEntry(
                            'wrap',
                            GitMessages.wrap,
                            checked: _wrap,
                          ),
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
                              _display(
                                'diffWrap',
                                !_wrap,
                                () => _wrap = !_wrap,
                              );
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
                        tooltip: gitString(
                          context,
                          GitMessages.searchComparison,
                        ),
                        onPressed: _openSearch,
                        icon: const GitIcon(GitGlyph.search),
                      ),
                      if (_canOpenSource)
                        TextButton(
                          key: const ValueKey('git-diff-open-source'),
                          onPressed: () => _openSource(generation),
                          child: const GitLabel(GitMessages.openCurrentFile),
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
                            tooltip: gitString(
                              context,
                              GitMessages.closeSearch,
                            ),
                            onPressed: () => setState(() {
                              _search.clear();
                              _searchVisible = false;
                            }),
                            icon: const GitIcon(GitGlyph.close),
                          ),
                        ),
                        onSubmitted: (_) => _stepSearch(
                          HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
                        ),
                      ),
                    ),
                  if (_searchVisible)
                    Row(
                      children: [
                        GitIconButton(
                          tooltip: gitString(
                            context,
                            GitMessages.previousSearchMatch,
                          ),
                          onPressed: _searchMatches.isEmpty
                              ? null
                              : () => _stepSearch(-1),
                          icon: const GitIcon(GitGlyph.up),
                        ),
                        GitIconButton(
                          tooltip: gitString(
                            context,
                            GitMessages.nextSearchMatch,
                          ),
                          onPressed: _searchMatches.isEmpty
                              ? null
                              : () => _stepSearch(1),
                          icon: const GitIcon(GitGlyph.down),
                        ),
                        if (_searchLoading)
                          const SizedBox(
                            key: ValueKey('git-diff-search-loading'),
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          GitLabel(
                            GitMessages.searchMatchPosition,
                            values: {
                              'current': _activeSearchMatch + 1,
                              'count': _searchMatches.length,
                            },
                          ),
                      ],
                    ),
                  if (_searchVisible && _matchesLimited)
                    GitLabel(
                      GitMessages.searchResultsLimited,
                      values: {'count': _searchMatches.length},
                    ),
                  if (_searchVisible && _searchFailure != null)
                    GitFailurePanel(
                      error: _searchFailure!,
                      onRefresh: _searchChanged,
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
                              unawaited(_applySelection(generation));
                            case 'index':
                              unawaited(_indexEditor(generation));
                            case 'file':
                              unawaited(_wholeFile(generation));
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
                              : () => unawaited(_applySelection(generation)),
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
                          onPressed: () => unawaited(_indexEditor(generation)),
                          child: const GitLabel(
                            GitMessages.editHEADIndexWorkingTree,
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_wholeFile(generation)),
                          child: Text(
                            _unstage
                                ? gitString(
                                    context,
                                    GitMessages.unstageWholeFile,
                                  )
                                : gitString(
                                    context,
                                    GitMessages.stageWholeFile,
                                  ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          Row(
            textDirection: TextDirection.ltr,
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
          if (!widget.preview && (_diff != null || !_stagingComparison))
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

  Widget _label(GitContent content) {
    final label = gitString(
      context,
      GitMessages.arg0Arg1Arg2BytesArg3,
      values: {
        'arg0': gitVersionLabel(context, content.version),
        'arg1': '\u2066${content.path.display}\u2069 · ${content.mode}',
        'arg2': content.size,
        'arg3': content.bytes.isNotEmpty && content.bytes.last != 10
            ? gitString(context, GitMessages.noFinalNewline)
            : '',
      },
    );
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _nonText() {
    final generation = _generation;
    return Center(
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
                  : () => unawaited(_wholeFile(generation)),
              child: Text(
                _unstage
                    ? gitString(context, GitMessages.unstageWholeFile)
                    : gitString(context, GitMessages.stageWholeFile),
              ),
            ),
        ],
      ),
    );
  }

  List<int> _visible() {
    final edits = _diff!.edits, visible = <int>[];
    final ignored = _ignoreWhitespace ? _ignoredWhitespace() : <int>{};
    for (var i = 0; i < edits.length; i++) {
      if (ignored.contains(i)) continue;
      if (!_collapse ||
          _search.text.isNotEmpty ||
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
    final settings =
        '$_collapse:$_unified:$_ignoreWhitespace:${_search.text.isNotEmpty}';
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
    final generation = _generation;
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
        label: changed && _canStage
            ? gitString(
                context,
                GitMessages.arg0ChangedLine,
                values: {
                  'arg0': _unstage
                      ? gitString(context, GitMessages.unstage)
                      : gitString(context, GitMessages.stage),
                },
              )
            : gitString(
                context,
                changed ? GitMessages.changedLine : GitMessages.context,
              ),
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
              horizontal: right ? _rightHorizontalScroll : _horizontalScroll,
              editIndex: index,
              copyLine: index == null
                  ? null
                  : _unified
                  ? index
                  : (right ? edit!.newLine! : edit!.oldLine!) - 1,
            ),
          ),
        ),
      );
    }

    final list = ListView.builder(
      key: _scrollStorageKey,
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
        final hunk = changed ? _hunk(first) : <int>{};
        return Column(
          key: _rowKeys.putIfAbsent(row, GlobalKey.new),
          children: [
            if (gap)
              SelectionContainer.disabled(
                child: TextButton(
                  onPressed: () => setState(() => _collapse = false),
                  child: const GitLabel(GitMessages.expandUnchangedContext),
                ),
              ),
            if (_canStage &&
                changed &&
                (first == 0 || edits[first - 1].kind == TextEditKind.equal))
              Align(
                alignment: Alignment.centerLeft,
                child: SelectionContainer.disabled(
                  child: TextButton(
                    onPressed: () =>
                        unawaited(_applySelection(generation, hunk)),
                    child: Text(
                      _unstage
                          ? gitString(context, GitMessages.unstageThisHunk)
                          : gitString(context, GitMessages.stageThisHunk),
                    ),
                  ),
                ),
              ),
            if (_unified)
              cell(left, _counterpartIndex(left!), false)
            else
              IntrinsicHeight(
                child: Row(
                  textDirection: TextDirection.ltr,
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
    if (_wrap)
      return GitDiffDocumentSelection(
        diff: _diff!,
        unified: _unified,
        child: list,
      );
    // The vertical list remains bounded and row-aligned. Each fixed pane has
    // one document scrollbar; its offset is used by every visible content row.
    // Neither the divider nor the opposite viewport is part of that surface.
    double contentWidth(bool right) {
      final style = Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      var width = 0.0;
      for (final edit in edits) {
        if (!_unified && (right ? edit.newLine : edit.oldLine) == null)
          continue;
        painter.text = TextSpan(text: edit.text.trimRight(), style: style);
        painter.layout();
        width = math.max(width, painter.width);
      }
      painter.dispose();
      return width + (_unified ? 128 : 96);
    }

    Widget scrollbar(ScrollController controller, double width, Key key) =>
        LayoutBuilder(
          builder: (context, bounds) => SizedBox(
            key: key,
            height: 18,
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: identical(controller, _rightHorizontalScroll)
                    ? _rightHorizontalStorageKey
                    : _leftHorizontalStorageKey,
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(width, bounds.maxWidth),
                  height: 1,
                ),
              ),
            ),
          ),
        );
    return Column(
      children: [
        Expanded(
          child: GitDiffDocumentSelection(
            diff: _diff!,
            unified: _unified,
            child: list,
          ),
        ),
        if (_unified)
          scrollbar(
            _horizontalScroll,
            contentWidth(false),
            const ValueKey('git-diff-unified-horizontal'),
          )
        else
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(
                child: scrollbar(
                  _horizontalScroll,
                  contentWidth(false),
                  const ValueKey('git-diff-left-horizontal'),
                ),
              ),
              const VerticalDivider(width: 6),
              Expanded(
                child: scrollbar(
                  _rightHorizontalScroll,
                  contentWidth(true),
                  const ValueKey('git-diff-right-horizontal'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _selectChangedLine(int index, int generation) {
    if (!_canInvokeReview(generation) || !_canStage) return;
    _lineFocus[index]?.requestFocus();
    final edits = _diff!.edits;
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed &&
          _selectionAnchor != null) {
        final first = math.min(_selectionAnchor!, index);
        final last = math.max(_selectionAnchor!, index);
        _selected.clear();
        for (var i = first; i <= last; i++) {
          if (edits[i].kind != TextEditKind.equal) _selected.add(i);
        }
      } else {
        if (!_selected.add(index)) _selected.remove(index);
        _selectionAnchor = index;
      }
    });
  }

  Future<void> _moveChangedLine(
    int current,
    int delta, {
    required bool extend,
    required int expectedGeneration,
  }) async {
    if (!_canInvokeReview(expectedGeneration) || !_canStage) return;
    final generation = _generation;
    final changed = _diff?.changedIndices ?? <int>[];
    final position = changed.indexOf(current);
    if (position < 0) return;
    final next = changed[(position + delta).clamp(0, changed.length - 1)];
    setState(() {
      if (extend) {
        _selectionAnchor ??= current;
        _selected.clear();
        final low = math.min(_selectionAnchor!, next),
            high = math.max(_selectionAnchor!, next);
        _selected.addAll(changed.where((line) => line >= low && line <= high));
      } else {
        _selectionAnchor = next;
      }
    });
    final rows = _alignedRows();
    final row = rows.indexWhere((pair) => pair.$1 == next || pair.$2 == next);
    if (row >= 0) await _scrollToRenderedRow(row, _generation);
    if (mounted && generation == _generation) _lineFocus[next]?.requestFocus();
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
    String? counterpart, {
    required ScrollController horizontal,
    required int? editIndex,
    required int? copyLine,
  }) {
    final generation = _generation;
    final shown = text.endsWith('\r\n')
        ? text.substring(0, text.length - 2)
        : text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final content = GitDiffCopyText(
      line: copyLine,
      right: !_unified && identical(horizontal, _rightHorizontalScroll),
      child: Text.rich(
        key: editIndex == null
            ? null
            : _textKeys.putIfAbsent((
                editIndex,
                identical(horizontal, _rightHorizontalScroll),
              ), GlobalKey.new),
        TextSpan(children: _wordSpans(shown, counterpart, kind, editIndex)),
        style: style,
        softWrap: _wrap,
        textDirection: TextDirection.ltr,
      ),
    );
    Widget gutter = Row(
      textDirection: TextDirection.ltr,
      mainAxisSize: MainAxisSize.min,
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
      ],
    );
    if (editIndex != null && kind != TextEditKind.equal && _canStage) {
      final index = editIndex;
      gutter = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => unawaited(
            _moveChangedLine(
              index,
              1,
              extend: false,
              expectedGeneration: generation,
            ),
          ),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => unawaited(
            _moveChangedLine(
              index,
              -1,
              extend: false,
              expectedGeneration: generation,
            ),
          ),
          const SingleActivator(
            LogicalKeyboardKey.arrowDown,
            shift: true,
          ): () => unawaited(
            _moveChangedLine(
              index,
              1,
              extend: true,
              expectedGeneration: generation,
            ),
          ),
          const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
              unawaited(
                _moveChangedLine(
                  index,
                  -1,
                  extend: true,
                  expectedGeneration: generation,
                ),
              ),
        },
        child: Tooltip(
          message: gitString(
            context,
            GitMessages.arg0ChangedLine,
            values: {
              'arg0': gitString(
                context,
                _unstage ? GitMessages.unstage : GitMessages.stage,
              ),
            },
          ),
          child: InkWell(
            key: ValueKey('git-diff-stage-line-$index'),
            focusNode: _lineFocus.putIfAbsent(index, FocusNode.new),
            onTap: () => _selectChangedLine(index, generation),
            child: gutter,
          ),
        ),
      );
    }
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(child: gutter),
        Expanded(
          child: _wrap
              ? content
              : Listener(
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent || !horizontal.hasClients)
                      return;
                    final delta = event.scrollDelta.dx != 0
                        ? event.scrollDelta.dx
                        : HardwareKeyboard.instance.isShiftPressed
                        ? event.scrollDelta.dy
                        : 0.0;
                    if (delta == 0) return;
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (_) {
                        horizontal.jumpTo(
                          (horizontal.offset + delta).clamp(
                            0.0,
                            horizontal.position.maxScrollExtent,
                          ),
                        );
                      },
                    );
                  },
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: horizontal,
                      builder: (context, _) => Transform.translate(
                        offset: Offset(
                          horizontal.hasClients ? -horizontal.offset : 0,
                          0,
                        ),
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxWidth: double.infinity,
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  List<InlineSpan> _wordSpans(
    String value,
    String? counterpart,
    TextEditKind kind,
    int? editIndex,
  ) {
    if (!_words ||
        counterpart == null ||
        kind == TextEditKind.equal ||
        _search.text.isNotEmpty ||
        value.length > 16000)
      return _highlight(value, null, editIndex);
    final words = RegExp(
      r'\s+|[^\s]+',
    ).allMatches(value).map((m) => m.group(0)!).toList();
    final other = RegExp(
      r'\s+|[^\s]+',
    ).allMatches(counterpart.trimRight()).map((m) => m.group(0)!).toList();
    if (words.length + other.length > 4000)
      return _highlight(value, null, editIndex);
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

  List<InlineSpan> _highlight(String value, TextStyle? style, int? editIndex) {
    final matches = _searchMatchesByLine[editIndex];
    if (_search.text.isEmpty || matches == null || matches.isEmpty)
      return [TextSpan(text: value)];
    final active =
        _activeSearchMatch >= 0 &&
            _searchMatches[_activeSearchMatch].$1 == editIndex
        ? _searchMatches[_activeSearchMatch]
        : null;
    var first = 0;
    if (active != null) {
      var low = 0, high = matches.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (matches[middle].$1 < active.$2) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      first = math.max(0, low - 128);
    }
    // A single Markdown paragraph may contain thousands of matches. Paint a
    // bounded neighborhood around the current match; navigation still indexes
    // every retained match, using original UTF-16 positions from the worker.
    final last = math.min(matches.length, first + 256), spans = <InlineSpan>[];
    var offset = 0;
    for (var index = first; index < last; index++) {
      final (start, end) = matches[index];
      if (start < offset || end > value.length) continue;
      if (start > offset)
        spans.add(TextSpan(text: value.substring(offset, start)));
      final current = active != null && active.$2 == start && active.$3 == end;
      spans.add(
        TextSpan(
          text: value.substring(start, end),
          style: TextStyle(
            backgroundColor: current
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.tertiaryContainer,
            decoration: current ? TextDecoration.underline : null,
            fontWeight: current ? FontWeight.bold : null,
          ),
        ),
      );
      offset = end;
    }
    if (offset < value.length)
      spans.add(TextSpan(text: value.substring(offset)));
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
    final request = ++_revealGeneration;
    double lower = 0, upper = double.infinity;
    for (var attempt = 0; attempt < 40; attempt++) {
      if (!mounted ||
          generation != _generation ||
          request != _revealGeneration ||
          !_scroll.hasClients)
        return;
      final target = _rowKeys[row]?.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          alignment: .18,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
        // Geometry can change during a theme/font/splitter relayout. Confirm
        // against the rendered row on the next frame, rather than retaining an
        // estimated line height as the final destination.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            generation != _generation ||
            request != _revealGeneration)
          return;
        final settled = _rowKeys[row]?.currentContext;
        if (settled != null)
          await Scrollable.ensureVisible(settled, alignment: .18);
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
      if (row < first.key) {
        upper = math.min(upper, _scroll.offset);
      } else if (row > last.key) {
        lower = math.max(lower, _scroll.offset);
      }
      final maximum = _scroll.position.maxScrollExtent;
      var desired =
          (_scroll.offset + (row - nearest.key) * math.max(1, measured)).clamp(
            0.0,
            maximum,
          );
      final high = math.min(upper, maximum);
      // Estimates accelerate normal navigation. Bracketed bisection prevents
      // oscillation across strongly asymmetric wrapping or newly measured rows.
      if (desired <= lower ||
          desired >= high ||
          (desired - _scroll.offset).abs() < 1) {
        desired = upper.isFinite
            ? (lower + high) / 2
            : math.min(
                maximum,
                math.max(
                  desired,
                  _scroll.offset + _scroll.position.viewportDimension,
                ),
              );
      }
      if ((desired - _scroll.offset).abs() < .1) return;
      _scroll.jumpTo(desired);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _wholeFile(int expectedGeneration) async {
    if (!_canInvokeReview(expectedGeneration) ||
        !_stagingComparison ||
        widget.session.running ||
        _stale ||
        !widget.session.canWriteMetadata)
      return;
    final snapshot = _review ?? widget.session.snapshot;
    if (snapshot == null) return;
    final generation = _generation;
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
    if (mounted && generation == _generation) await _load();
  }

  Future<void> _applySelection(int expectedGeneration, [Set<int>? hunk]) async {
    if (!_canInvokeReview(expectedGeneration)) return;
    final selection = hunk ?? _selected;
    if (!_canStage || selection.isEmpty) return;
    final path = widget.comparison.path, session = widget.session;
    final generation = _generation;
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
    if (mounted && generation == _generation) {
      if (result?.error case final error?)
        setState(() => _error = error);
      else
        await _load();
    }
  }

  Future<void> _indexEditor(int expectedGeneration) async {
    if (!_canInvokeReview(expectedGeneration)) return;
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
    if (_canInvokeReview(expectedGeneration)) await _load();
  }
}

final class GitIndexEditor extends StatefulWidget {
  const GitIndexEditor({
    super.key,
    required this.session,
    required this.path,
    @visibleForTesting this.computeDiff,
  });

  /// Override background scheduling to exercise obsolete completions in tests.
  final Future<TextDiff> Function(String, String)? computeDiff;
  final GitSession session;
  final RepoPath path;
  @override
  State<GitIndexEditor> createState() => _GitIndexEditorState();
}

final class _GitIndexEditorState extends State<GitIndexEditor> {
  GitSnapshot? _snapshot;
  RepoPath? _reviewPath;
  GitContent? _head, _index, _working;
  GitException? _failure;
  final _headText = GitHighlightedTextController();
  final _result = GitHighlightedTextController();
  final _workingText = GitHighlightedTextController();
  final _undo = UndoHistoryController();
  final _regions = <_IndexRegion>[];
  final _paneGeometry = List.generate(3, (_) => GitTextPaneGeometry());
  GitTextCorrespondence? _headMap, _workingMap;
  final _revealOffsets = List<int?>.filled(3, null);
  Timer? _regionTimer;
  int _loadGeneration = 0, _regionGeneration = 0, _activeRegion = 0;
  int _anchorRevision = 0, _draftRevision = 0, _correspondenceRevision = 0;
  _IndexRegionReview? _regionReview;
  _AppliedIndexReview? _appliedReview;
  bool _reviewingSavedIndex = false;
  String? _lastResultText;
  String _draftBaseline = '';
  bool _saving = false, _dirty = false, _regionsLoading = false;
  bool _stale = false,
      _allowClose = false,
      _navigationStarted = false,
      _appliedNewerDraft = false;
  @override
  void initState() {
    super.initState();
    _result.addListener(_resultChanged);
    widget.session.addListener(_repositoryChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant GitIndexEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session && oldWidget.path == widget.path)
      return;
    oldWidget.session.removeListener(_repositoryChanged);
    widget.session.addListener(_repositoryChanged);
    _loadGeneration++;
    _invalidateRegions();
    if (_dirty) {
      // Hosts guard identity changes before disposing a draft. If a caller does
      // replace the binding, retain the text and refuse every write/transfer.
      _stale = true;
    } else {
      unawaited(_load());
    }
  }

  void _repositoryChanged() {
    final current = widget.session.snapshot;
    if (mounted &&
        _snapshot != null &&
        current != null &&
        current.token != _snapshot!.token &&
        !_stale) {
      _invalidateRegions();
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
    if (_snapshot == null || _result.text == _lastResultText) return;
    _lastResultText = _result.text;
    _draftRevision++;
    // Controller notifications are synchronous. Invalidate offsets before even
    // an already-mounted button callback can observe the new draft.
    _invalidateRegions();
    setState(() => _dirty = _result.text != _draftBaseline);
    _regionTimer = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(_computeRegions()),
    );
  }

  void _invalidateRegions() {
    _regionTimer?.cancel();
    _regionGeneration++;
    _regionReview = null;
    _headMap = _workingMap = null;
    _revealOffsets.fillRange(0, 3, null);
    _regions.clear();
    _regionsLoading = true;
    _headText.setHighlights(const []);
    _result.setHighlights(const []);
    _workingText.setHighlights(const []);
  }

  bool _isCurrentRegionReview(_IndexRegionReview review) =>
      mounted &&
      identical(review.session, widget.session) &&
      review.path == widget.path &&
      review.load == _loadGeneration &&
      review.generation == _regionGeneration &&
      review.draftRevision == _draftRevision &&
      review.snapshot == _snapshot?.token &&
      review.head == _head?.token &&
      review.index == _index?.token &&
      review.working == _working?.token &&
      review.text == _result.text &&
      !_stale;

  Future<void> _computeRegions() async {
    final generation = ++_regionGeneration;
    final head = _head?.text ?? '',
        index = _result.text,
        working = _working?.text ?? '';
    final review = _IndexRegionReview(
      widget.session,
      widget.path,
      _loadGeneration,
      generation,
      _draftRevision,
      _snapshot?.token,
      _head?.token,
      _index?.token,
      _working?.token,
      index,
    );
    setState(() => _regionsLoading = true);
    try {
      final testCompute = widget.computeDiff;
      Future<GitTextCorrespondence> compute(String left, String right) async {
        if (testCompute == null)
          return GitTextCorrespondence.compute(left, right);
        return GitTextCorrespondence(
          await testCompute(left, right),
          left,
          right,
        );
      }

      final maps = await Future.wait([
        compute(head, index),
        compute(index, working),
      ]);
      final diffs = [maps[0].diff, maps[1].diff];
      if (!_isCurrentRegionReview(review)) return;
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
      final headMap = maps[0], workingMap = maps[1];
      setState(() {
        _regionReview = review;
        _headMap = headMap;
        _workingMap = workingMap;
        _correspondenceRevision++;
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

  int? _mapPaneOffset(
    _IndexRegionReview? review,
    int source,
    int target,
    int offset,
  ) {
    if (review == null ||
        !identical(review, _regionReview) ||
        !_isCurrentRegionReview(review) ||
        _headMap == null ||
        _workingMap == null)
      return null;
    final index = switch (source) {
      0 => _headMap!.forward(offset),
      2 => _workingMap!.reverse(offset),
      _ => offset,
    };
    return switch (target) {
      0 => _headMap!.reverse(index),
      2 => _workingMap!.forward(index),
      _ => index,
    };
  }

  List<GitTextPaneAction> _sourceActions(GitHighlightKind kind) {
    final review = _regionReview;
    if (review == null ||
        _saving ||
        _regionsLoading ||
        !_isCurrentRegionReview(review))
      return const [];
    return [
      for (final region in _regions.where((region) => region.kind == kind))
        GitTextPaneAction(
          start: region.sourceStart,
          end: region.sourceEnd,
          label: kind == GitHighlightKind.staged
              ? GitMessages.copyHeadRegionIntoIndexDraft
              : GitMessages.copyWorkingRegionIntoIndexDraft,
          glyph: kind == GitHighlightKind.staged
              ? GitGlyph.next
              : GitGlyph.previous,
          onInvoke: _regionAction(region),
        ),
    ];
  }

  VoidCallback? _activeTransfer(GitHighlightKind kind) {
    if (_regions.isEmpty || _regions[_activeRegion].kind != kind) return null;
    return _regionAction(_regions[_activeRegion]);
  }

  void _navigateRegion(int direction) {
    if (_regions.isEmpty) return;
    setState(() {
      _activeRegion = !_navigationStarted
          ? (direction > 0 ? 0 : _regions.length - 1)
          : (_activeRegion + direction) % _regions.length;
      _navigationStarted = true;
      final region = _regions[_activeRegion];
      _revealOffsets[0] = region.kind == GitHighlightKind.staged
          ? region.sourceStart
          : _headMap?.reverse(region.indexStart);
      _revealOffsets[1] = region.indexStart;
      _revealOffsets[2] = region.kind == GitHighlightKind.unstaged
          ? region.sourceStart
          : _workingMap?.forward(region.indexStart);
      _anchorRevision++;
    });
  }

  void _transferRegion(_IndexRegionReview review, _IndexRegion region) {
    if (_saving ||
        _regionsLoading ||
        !identical(review, _regionReview) ||
        !_isCurrentRegionReview(review) ||
        !_regions.contains(region))
      return;
    _navigationStarted = true;
    _activeRegion = _regions.indexOf(region);
    _result.value = _result.value.replaced(
      TextRange(start: region.indexStart, end: region.indexEnd),
      region.replacement,
    );
    _anchorRevision++;
  }

  VoidCallback? _regionAction(_IndexRegion region) {
    final review = _regionReview;
    return review == null ? null : () => _transferRegion(review, region);
  }

  Future<void> _reviewSavedIndex(_AppliedIndexReview applied) async {
    if (_saving || _reviewingSavedIndex || !_ownsAppliedReview(applied)) return;
    setState(() => _reviewingSavedIndex = true);
    try {
      await _load(applied: applied);
    } finally {
      if (mounted) setState(() => _reviewingSavedIndex = false);
    }
  }

  bool _ownsAppliedReview(_AppliedIndexReview applied) =>
      identical(applied, _appliedReview) &&
      identical(applied.session, widget.session) &&
      applied.path == widget.path &&
      applied.snapshot.repository.key == widget.session.repository.key;

  Future<void> _load({_AppliedIndexReview? applied}) async {
    final generation = ++_loadGeneration;
    _invalidateRegions();
    _draftRevision++;
    final session = widget.session, path = widget.path;
    try {
      final snapshot = await session.readStatus();
      if (!mounted || generation != _loadGeneration) return;
      if (applied != null &&
          (!_ownsAppliedReview(applied) ||
              !applied.matchesSnapshot(snapshot))) {
        throw const GitException(
          GitErrorCode.staleReview,
          diagnostic: GitMessages.indexSourcesChangedSinceApply,
        );
      }
      final headPath =
          applied?.head.path ??
          snapshot.changes
              .where((e) => e.path == path && e.index == 'R')
              .firstOrNull
              ?.originalPath ??
          path;
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
          path,
          const ContentVersion.index(),
        ),
        session.client.content(
          session.repository,
          path,
          const ContentVersion(ContentKind.normalizedWorking),
        ),
      ]);
      final after = await session.readStatus();
      if (!mounted || generation != _loadGeneration) return;
      if (after.token != snapshot.token ||
          !identical(session, widget.session) ||
          path != widget.path) {
        throw const GitException(GitErrorCode.staleReview);
      }
      if (applied != null &&
          (!_ownsAppliedReview(applied) ||
              !applied.matchesSnapshot(after) ||
              !applied.matchesContent(values))) {
        throw const GitException(
          GitErrorCode.staleReview,
          diagnostic: GitMessages.indexSourcesChangedSinceApply,
        );
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
        _reviewPath = path;
        _head = values[0];
        _index = values[1];
        _working = values[2];
        _headText.text = _head!.text ?? '';
        _workingText.text = _working!.text ?? '';
        _draftBaseline = _index!.text ?? '';
        // Only an explicit reload replaces text. Reviewing our own completed
        // Apply keeps the current editing value, Undo history and composition,
        // including text entered while these source reads were outstanding.
        _regionTimer?.cancel();
        if (applied == null) {
          _lastResultText = _draftBaseline;
          _result.text = _draftBaseline;
        } else {
          _lastResultText = _result.text;
        }
        _dirty = _result.text != _draftBaseline;
        _stale = false;
        _failure = null;
        _navigationStarted = false;
        _appliedNewerDraft = false;
        _appliedReview = null;
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
    final _regionReviewForBuild = _regionReview;
    return GitDraftGuard(
      host: widget.session.host,
      canDismiss: _allowClose || (!_dirty && !_saving),
      confirmDiscard: () => _saving ? Future.value(false) : _confirmClose(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f7): () =>
              _navigateRegion(1),
          const SingleActivator(LogicalKeyboardKey.f7, shift: true): () =>
              _navigateRegion(-1),
          if (_activeTransfer(GitHighlightKind.staged) case final transfer?)
            const SingleActivator(
              LogicalKeyboardKey.arrowRight,
              control: true,
              alt: true,
            ): transfer,
          if (_activeTransfer(GitHighlightKind.unstaged) case final transfer?)
            const SingleActivator(
              LogicalKeyboardKey.arrowLeft,
              control: true,
              alt: true,
            ): transfer,
        },
        child: Column(
          children: [
            Text(
              '${_snapshot!.repository.root} · ${_reviewPath!.display}',
              maxLines: 2,
            ),
            if (_saving)
              LinearProgressIndicator(
                semanticsLabel: gitString(
                  context,
                  GitMessages.writingReviewedIndexResult,
                ),
              ),
            if (_appliedNewerDraft)
              const GitLabel(GitMessages.indexAppliedNewerDraftPreserved),
            if (_appliedReview case final applied?)
              TextButton(
                onPressed:
                    _saving ||
                        _reviewingSavedIndex ||
                        !_ownsAppliedReview(applied)
                    ? null
                    : () => unawaited(_reviewSavedIndex(applied)),
                child: const GitLabel(GitMessages.reviewSavedIndexAndKeepDraft),
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
                  onPressed: _regions.isEmpty
                      ? null
                      : () => _navigateRegion(-1),
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
                          _regions[_activeRegion].kind !=
                              GitHighlightKind.staged
                      ? null
                      : _regionAction(_regions[_activeRegion]),
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
                      : _regionAction(_regions[_activeRegion]),
                  child: const GitLabel(GitMessages.stageThisHunk),
                ),
              ],
            ),
            Expanded(
              child: GitRevisionPanes(
                geometry: _paneGeometry,
                mapOffset: (source, target, offset) => _mapPaneOffset(
                  _regionReviewForBuild,
                  source,
                  target,
                  offset,
                ),
                correspondenceRevision: _correspondenceRevision,
                labels: const [
                  GitMessages.head,
                  GitMessages.index,
                  GitMessages.workingTree,
                ],
                anchorRevision: _anchorRevision,
                panes: [
                  (scroll) => GitTextPane(
                    geometry: _paneGeometry[0],
                    regionActions: _sourceActions(GitHighlightKind.staged),
                    minimumActionColumns: 1,
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
                    revealOffset: _revealOffsets[0],
                  ),
                  (scroll) => GitTextPane(
                    geometry: _paneGeometry[1],
                    label: gitString(
                      context,
                      GitMessages.indexEditableUTF8Blob,
                    ),
                    controller: _result,
                    readOnly: _saving,
                    undoController: _undo,
                    scrollController: scroll,
                    revealRevision: _anchorRevision,
                    revealOffset: _revealOffsets[1],
                  ),
                  (scroll) => GitTextPane(
                    geometry: _paneGeometry[2],
                    regionActions: _sourceActions(GitHighlightKind.unstaged),
                    minimumActionColumns: 1,
                    label: gitVersionLabel(context, _working!.version),
                    controller: _workingText,
                    readOnly: true,
                    semanticLabel: GitMessages.readOnlyRevisionContent,
                    scrollController: scroll,
                    revealRevision: _anchorRevision,
                    revealOffset: _revealOffsets[2],
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
                    onPressed: _saving || _reviewingSavedIndex
                        ? null
                        : () async {
                            if (_saving || _reviewingSavedIndex) return;
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
      ),
    );
  }

  Future<bool> _confirmClose() async {
    final revision = _draftRevision, snapshot = _snapshot;
    final approved = await gitConfirm(
      context,
      widget.session,
      GitMessages.discardUnsavedIndexDraft,
      GitMessages.closingTheIndexEditorDiscardsOnlyItsDraft,
      action: GitMessages.discardIndexDraft,
    );
    // A queued input-method update or programmatic edit is a newer draft; the
    // previous confirmation does not authorize discarding it.
    return mounted &&
        approved &&
        revision == _draftRevision &&
        identical(snapshot, _snapshot);
  }

  Future<void> _apply() async {
    if (_saving || _reviewingSavedIndex || _stale || !_dirty) return;
    final text = _result.text, session = widget.session, path = widget.path;
    final draftRevision = _draftRevision;
    final snapshot = _snapshot!,
        index = _index!,
        working = _working!,
        head = _head!;
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
    if (_result.text != text ||
        _draftRevision != draftRevision ||
        _stale ||
        !identical(session, widget.session) ||
        path != widget.path ||
        !identical(snapshot, _snapshot)) {
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
    final request = WriteIndex(
      path,
      Uint8List.fromList(utf8.encode(text)),
      expectedHead: snapshot.head,
      expectedIndex: snapshot.indexToken,
      expectedContent: index.token,
      expectedWorktree: working.sourceToken.isEmpty
          ? working.token
          : working.sourceToken,
      mode: _index!.mode == '000000'
          ? (_working!.mode == '000000' ? '100644' : _working!.mode)
          : _index!.mode,
    );
    final result = await session.mutate(request);
    if (!mounted) return;
    if (result?.completed == true &&
        (draftRevision != _draftRevision ||
            _result.text != text ||
            !identical(session, widget.session) ||
            path != widget.path ||
            !identical(snapshot, _snapshot))) {
      setState(() {
        _draftBaseline = text;
        _appliedNewerDraft = true;
        _appliedReview = _AppliedIndexReview(
          session,
          path,
          snapshot,
          head,
          working,
          text,
          request.mode,
        );
        _dirty = _result.text != text;
        _saving = false;
        _stale = true;
        _failure = const GitException(
          GitErrorCode.staleReview,
          diagnostic: GitMessages.indexAppliedNewerDraftPreserved,
        );
      });
    } else if (result?.completed == true) {
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

/// The sole continuation which can preserve a draft across source reload is a
/// known successful write by this editor. It never authorizes external changes.
final class _AppliedIndexReview {
  const _AppliedIndexReview(
    this.session,
    this.path,
    this.snapshot,
    this.head,
    this.working,
    this.submitted,
    this.mode,
  );
  final GitSession session;
  final RepoPath path;
  final GitSnapshot snapshot;
  final GitContent head, working;
  final String submitted, mode;

  bool matchesSnapshot(GitSnapshot current) {
    Object operation(RepositoryOperation value) => (
      value.kind,
      value.head,
      value.other,
      value.message,
      value.editStop,
      value.unmerged,
    );
    return current.repository.key == snapshot.repository.key &&
        current.head == snapshot.head &&
        current.branch == snapshot.branch &&
        operation(current.operation) == operation(snapshot.operation) &&
        current.capabilities.writeMetadata ==
            snapshot.capabilities.writeMetadata &&
        current.capabilities.replaceWorkingFiles ==
            snapshot.capabilities.replaceWorkingFiles;
  }

  bool matchesContent(List<GitContent> content) {
    bool same(GitContent a, GitContent b) =>
        a.path == b.path &&
        a.availability == b.availability &&
        a.token == b.token &&
        a.sourceToken == b.sourceToken &&
        a.mode == b.mode;
    return same(head, content[0]) &&
        same(working, content[2]) &&
        content[1].path == path &&
        content[1].availability == ContentAvailability.present &&
        content[1].mode == mode &&
        content[1].text == submitted;
  }
}

/// A calculated offset belongs to one immutable source review and draft.
final class _IndexRegionReview {
  const _IndexRegionReview(
    this.session,
    this.path,
    this.load,
    this.generation,
    this.draftRevision,
    this.snapshot,
    this.head,
    this.index,
    this.working,
    this.text,
  );
  final GitSession session;
  final RepoPath path;
  final int load, generation, draftRevision;
  final String? snapshot, head, index, working;
  final String text;
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
    this.geometry,
    this.mapOffset,
    this.correspondenceRevision = 0,
  });
  final int correspondenceRevision;
  final List<GitTextPaneGeometry>? geometry;
  final int? Function(int source, int target, int offset)? mapOffset;
  final int anchorRevision;
  final List<String> labels;
  final List<Widget Function(ScrollController)> panes;
  @override
  State<GitRevisionPanes> createState() => _RevisionPanesState();
}

final class _RevisionPanesState extends State<GitRevisionPanes> {
  final _scrolls = List.generate(3, (_) => ScrollController());
  final _paneKeys = List.generate(3, (_) => GlobalKey());
  int _selected = 1, _syncRequest = 0;
  int? _lastSource;
  ({int offset, double y})? _lastAnchor;
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
    if (widget.correspondenceRevision != oldWidget.correspondenceRevision &&
        _lastSource != null) {
      final source = _lastSource!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _synchronize(source);
      });
    }
    if (widget.anchorRevision != oldWidget.anchorRevision) {
      _anchoring = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduleMicrotask(() => _anchoring = false);
      });
    }
  }

  void _synchronize(int source) {
    if (_anchoring ||
        _moving ||
        !_scrolls[source].hasClients ||
        widget.geometry == null)
      return;
    _lastSource = source;
    _lastAnchor = widget.geometry![source].anchor();
    if (!_sync || widget.mapOffset == null || _lastAnchor == null) return;
    final request = ++_syncRequest;
    void align() {
      if (!mounted ||
          request != _syncRequest ||
          !_sync ||
          _anchoring ||
          widget.geometry == null ||
          widget.mapOffset == null)
        return;
      // Re-read the same user's pane after layout so edits before its viewport
      // do not reuse an old numeric offset. This pane itself is never moved.
      final anchor = widget.geometry![source].anchor();
      if (anchor == null) return;
      _lastAnchor = anchor;
      _moving = true;
      try {
        for (var target = 0; target < 3; target++) {
          if (target == source) continue;
          final offset = widget.mapOffset!(source, target, anchor.offset);
          if (offset != null) widget.geometry![target].align(offset, anchor.y);
        }
      } finally {
        _moving = false;
      }
    }

    // The source's scroll can be reported before other text fields have
    // completed their resized/wrapped layout. Measure after layout, then
    // reconcile once more after the target scroll positions have settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      align();
      if (mounted && request == _syncRequest) {
        WidgetsBinding.instance.addPostFrameCallback((_) => align());
      }
    });
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
      final direction = Directionality.of(context);
      final panes = [
        for (var i = 0; i < 3; i++)
          KeyedSubtree(
            key: _paneKeys[i],
            child: Directionality(
              textDirection: direction,
              child: widget.panes[i](_scrolls[i]),
            ),
          ),
      ];
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
                selected:
                    _sync &&
                    widget.geometry != null &&
                    widget.mapOffset != null,
                onSelected: widget.geometry == null || widget.mapOffset == null
                    ? null
                    : (value) {
                        setState(() => _sync = value);
                        if (value && _lastSource != null) {
                          _synchronize(_lastSource!);
                        }
                      },
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
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: GitSplitter(
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
          ),
        ],
      );
    },
  );
}
