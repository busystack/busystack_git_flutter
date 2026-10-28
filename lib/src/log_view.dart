import 'messages.dart';
import 'dart:async';
import 'dart:ui' show SemanticsRole;
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'diff_view.dart';
import 'host.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'history_actions.dart';
import 'native_table.dart';
import 'context_menu_keys.dart';

final class GitLogView extends StatefulWidget {
  const GitLogView({
    super.key,
    required this.session,
    this.onCommitAction,
    this.onChooseCommit,
    this.path,
    this.active = true,
  });
  final GitSession session;
  final void Function(GitCommit commit, String action)? onCommitAction;

  /// Reuse the real paged, filterable Log as a read-only revision picker.
  final ValueChanged<GitCommit>? onChooseCommit;
  final RepoPath? path;
  final bool active;
  @override
  State<GitLogView> createState() => _GitLogViewState();
}

final class _GitLogViewState extends State<GitLogView> {
  final _message = TextEditingController(),
      _author = TextEditingController(),
      _path = TextEditingController(),
      _referenceSearch = TextEditingController();
  List<GitCommit> _commits = [];
  List<GitReference> _references = [];
  List<GitChange> _files = [];
  GitCommit? _selected;
  GitChange? _selectedFile;
  bool _expandedDiff = false;
  final _selectedIds = <GitOid>{};
  final _tableScroll = ScrollController();
  final _graphScroll = ScrollController();
  double _graphOffset = 0;
  final _tableFocus = FocusNode(debugLabel: 'Git commits');
  final _contextMenuKeys = GitContextMenuKeys();
  int _selectionAnchor = 0;
  GitOid? _parent;
  String? _reference, _anchor, _navigationReference;
  GitOid? _pendingNavigation;
  DateTime? _since, _until;
  GitException? _failure, _fileFailure;
  bool _filesLoading = false;
  bool _navigationOutsideFilters = false;
  bool _loading = true, _more = true, _branches = true, _details = true;
  int _generation = 0;
  int _historyRevision = 0;
  int _selectionGeneration = 0;
  GitCancellation? _readCancellation;
  Timer? _referenceRefresh;
  bool _checkingReferences = false;
  GitOid? _observedHead;
  @override
  void initState() {
    super.initState();
    _path.text = widget.path?.utf8Path ?? '';
    _observedHead = widget.session.snapshot?.head;
    widget.session.addListener(_repositoryChanged);
    _graphScroll.addListener(_graphScrolled);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GitLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session || oldWidget.path != widget.path) {
      oldWidget.session.removeListener(_repositoryChanged);
      widget.session.addListener(_repositoryChanged);
      _readCancellation?.cancel();
      _referenceRefresh?.cancel();
      _generation++;
      _commits = [];
      _references = [];
      _clearReview();
      _path.text = widget.path?.utf8Path ?? '';
      _observedHead = widget.session.snapshot?.head;
      unawaited(_load());
    } else if (widget.active && !oldWidget.active) {
      _repositoryChanged();
    }
  }

  void _repositoryChanged() {
    if (!widget.active || _loading || widget.session.running) return;
    _referenceRefresh?.cancel();
    _referenceRefresh = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_checkReferences()),
    );
  }

  Future<void> _checkReferences() async {
    if (_checkingReferences || !mounted || !widget.active) return;
    _checkingReferences = true;
    final session = widget.session;
    final generation = _generation;
    try {
      final refs = await session.client.references(session.repository);
      String identity(List<GitReference> values) => values
          .map((r) => '${r.name}:${r.oid.value}:${r.upstream}')
          .join('\n');
      if (mounted &&
          session == widget.session &&
          generation == _generation &&
          (identity(refs) != identity(_references) ||
              _observedHead != widget.session.snapshot?.head)) {
        _observedHead = widget.session.snapshot?.head;
        await _load(preserveNavigation: true);
      }
    } on Object catch (error) {
      if (mounted && session == widget.session && generation == _generation)
        setState(
          () => _failure = error is GitException
              ? error
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$error'),
                ),
        );
    } finally {
      _checkingReferences = false;
    }
  }

  void _graphScrolled() {
    // Responsive pane insertion can briefly reparent the old and new table
    // in one frame. A controller.offset read requires exactly one position.
    if (!mounted || _graphScroll.positions.length != 1) return;
    final offset = _graphScroll.positions.single.pixels;
    if (offset != _graphOffset) setState(() => _graphOffset = offset);
  }

  @override
  void dispose() {
    _generation++;
    _selectionGeneration++;
    _readCancellation?.cancel();
    _referenceRefresh?.cancel();
    widget.session.removeListener(_repositoryChanged);
    _tableScroll.dispose();
    _graphScroll.dispose();
    _contextMenuKeys.clear();
    _tableFocus.dispose();
    for (final c in [_message, _author, _path, _referenceSearch]) {
      c.dispose();
    }
    super.dispose();
  }

  HistoryFilter get _filter => _navigationReference != null
      ? HistoryFilter(reference: _navigationReference)
      : HistoryFilter(
          reference: _reference,
          author: _author.text,
          message: _message.text,
          since: _since,
          until: _until,
          path: _path.text.isEmpty ? null : RepoPath.text(_path.text),
          follow: widget.path != null,
        );
  bool get _hasFilters =>
      _reference != null ||
      _message.text.isNotEmpty ||
      _author.text.isNotEmpty ||
      _path.text.isNotEmpty ||
      _since != null ||
      _until != null;

  // A review is one dependent selection: commit, parent, files and preview.
  // Clear it atomically and retire requests/callbacks that still own its data.
  void _clearReview() {
    _selectionGeneration++;
    _selected = null;
    _parent = null;
    _selectedIds.clear();
    _files = [];
    _selectedFile = null;
    _expandedDiff = false;
    _filesLoading = false;
    _fileFailure = null;
  }

  Future<void> _load({
    bool append = false,
    bool preserveNavigation = false,
    GitOid? reveal,
  }) async {
    if (!append && !preserveNavigation) _navigationReference = null;
    final generation = ++_generation;
    final session = widget.session;
    // Retain the previous, accurately labelled review during loading, but no
    // pending file response may publish into a replacement history request.
    if (!append) _selectionGeneration++;
    setState(() {
      _loading = true;
      _failure = null;
      _navigationOutsideFilters = false;
      if (!preserveNavigation) _pendingNavigation = null;
    });
    _readCancellation?.cancel();
    final cancellation = _readCancellation = GitCancellation();
    try {
      final page = await session.client.history(
        session.repository,
        filter: _filter,
        offset: append ? _commits.length : 0,
        anchor: append ? _anchor : null,
        cancellation: cancellation,
      );
      final refs = append
          ? _references
          : await session.client.references(session.repository);
      if (!mounted || generation != _generation) return;
      setState(() {
        // The read generation changes before loading, while the old rows stay
        // visible. Native actions must advance with the applied row identities.
        _historyRevision++;
        _commits = append ? [..._commits, ...page.commits] : page.commits;
        _references = refs;
        _more = page.hasMore;
        _anchor = page.anchor;
        _loading = false;
        _selectedIds.retainAll(_commits.map((e) => e.oid));
        _selectionAnchor = _selectionAnchor.clamp(
          0,
          _commits.isEmpty ? 0 : _commits.length - 1,
        );
      });
      final retained = _commits
          .where((e) => e.oid == (reveal ?? _selected?.oid))
          .firstOrNull;
      if (reveal != null && retained == null) {
        setState(() {
          _clearReview();
          _navigationOutsideFilters = true;
          _failure = const GitException(
            GitErrorCode.invalidRequest,
            diagnostic: GitMessages
                .theRequestedRevisionIsOutsideTheCurrentFiltersResetFilters,
          );
        });
      } else if (reveal != null) {
        await _reveal(retained!);
      } else if (retained != null || _commits.isNotEmpty) {
        await _select(
          retained ?? _commits.first,
          parent: retained != null && retained.parents.contains(_parent)
              ? _parent
              : null,
        );
      } else {
        setState(() {
          _clearReview();
        });
      }
    } on Object catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _failure = error is GitException
              ? error
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$error'),
                );
          _loading = false;
          _clearReview();
        });
    }
  }

  Future<void> _select(GitCommit commit, {GitOid? parent}) async {
    final generation = ++_selectionGeneration;
    final previousFile = _selectedFile?.path;
    final comparisonParent = parent ?? commit.parents.firstOrNull;
    final retainExpanded =
        _expandedDiff &&
        _selected?.oid == commit.oid &&
        _parent == comparisonParent;
    final session = widget.session;
    setState(() {
      _selected = commit;
      _parent = comparisonParent;
      _files = [];
      _selectedFile = null;
      _expandedDiff = retainExpanded;
      _fileFailure = null;
      _filesLoading = true;
    });
    try {
      final files = await session.client.changedFiles(
        session.repository,
        commit.oid,
        parent: comparisonParent,
      );
      if (mounted && generation == _selectionGeneration)
        setState(() {
          _files = files;
          _selectedFile = previousFile == null
              ? null
              : files.where((file) => file.path == previousFile).firstOrNull;
          _filesLoading = false;
          if (_selectedFile == null) _expandedDiff = false;
        });
    } on Object catch (error) {
      if (mounted && generation == _selectionGeneration)
        setState(() {
          _selectedFile = null;
          _expandedDiff = false;
          _filesLoading = false;
          _fileFailure = error is GitException
              ? error
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$error'),
                );
        });
    }
  }

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: widget.session.host,
    child: Builder(builder: _build),
  );
  double _textWidth(String text, [TextStyle? style]) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style ?? Theme.of(context).textTheme.bodyMedium,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  void _resetFilters() {
    _message.clear();
    _author.clear();
    _path.clear();
    _reference = null;
    _navigationReference = null;
    _pendingNavigation = null;
    _since = _until = null;
    unawaited(_load());
  }

  Future<void> _textFilter(
    TextEditingController controller,
    String title,
  ) async {
    final value = await gitTextInput(
      context,
      widget.session,
      title,
      initial: controller.text,
    );
    if (!mounted || value == null) return;
    controller.text = value;
    await _load();
  }

  Widget _build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final host = widget.session.host;
      final tableMinimum = _textWidth('MMMMMMMMMMMMMMMMMMMMMMMM') + 40;
      final detailMinimum =
          _textWidth('MMMMMMMMMMMMMMMMMMMMMM') + host.spacing * 2;
      final branchMinimum = _textWidth('MMMMMMMMMMMMMMMM');
      final showDetails =
          _details &&
          bounds.maxWidth >=
              (tableMinimum + detailMinimum + 6).clamp(720.0, double.infinity);
      final canShowBranches =
          bounds.maxWidth >=
          (branchMinimum +
                  tableMinimum +
                  (showDetails ? detailMinimum : 0) +
                  12)
              .clamp(1150.0, double.infinity);
      final showBranches = _branches && canShowBranches;
      final compact =
          bounds.maxWidth <
              _textWidth(
                'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM',
              ) &&
          bounds.maxHeight < host.rowHeight(context) * 16;
      final activeFilters = [
        _message.text,
        _author.text,
        _path.text,
        if (_since != null || _until != null) 'date',
      ].where((value) => value.isNotEmpty).length;
      Widget main = _commitTable();
      if (showDetails)
        main = GitSplitter(
          first: main,
          second: _detailPane(),
          initial: .64,
          minimum: tableMinimum,
          minimumSecond: detailMinimum,
          value: widget.session.split('logDetailsSplit', .64),
          onChanged: (v) => widget.session.setViewState('logDetailsSplit', v),
        );
      if (showBranches)
        main = GitSplitter(
          first: _branchPane(),
          second: main,
          initial: .20,
          minimum: branchMinimum,
          minimumSecond: tableMinimum + (showDetails ? detailMinimum : 0),
          value: widget.session.split('logBranchesSplit', .20),
          onChanged: (v) => widget.session.setViewState('logBranchesSplit', v),
        );
      if (_selectedFile != null && !_expandedDiff)
        main = GitSplitter(
          axis: Axis.vertical,
          first: main,
          second: _diffPreview(),
          initial: .67,
          minimum: 220,
          minimumSecond: 200,
          value: widget.session.split('logPreviewSplit', .67),
          onChanged: (v) => widget.session.setViewState('logPreviewSplit', v),
        );
      if (_expandedDiff && _selectedFile != null)
        main = _diffPreview(expanded: true);
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.all(widget.session.host.spacing),
            child: Column(
              children: [
                Wrap(
                  spacing: widget.session.host.spacing,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (compact)
                      GitMenuButton(
                        host: host,
                        tooltip: gitString(context, GitMessages.filterLog),
                        child: GitLabel(
                          activeFilters == 0
                              ? GitMessages.filters
                              : GitMessages.filtersCount,
                          values: {'count': activeFilters},
                        ),
                        entries: const [
                          GitMenuEntry('message', GitMessages.message),
                          GitMenuEntry('author', GitMessages.author),
                          GitMenuEntry('path', GitMessages.path),
                          GitMenuEntry('date', GitMessages.date),
                        ],
                        onSelected: (value) {
                          switch (value) {
                            case 'message':
                              unawaited(
                                _textFilter(
                                  _message,
                                  GitMessages.messageFilter,
                                ),
                              );
                            case 'author':
                              unawaited(
                                _textFilter(_author, GitMessages.authorFilter),
                              );
                            case 'path':
                              unawaited(
                                _textFilter(_path, GitMessages.pathFilter),
                              );
                            case 'date':
                              unawaited(_dates());
                          }
                        },
                      )
                    else ...[
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _message,
                          decoration: InputDecoration(
                            labelText: gitString(context, GitMessages.message2),
                            isDense: true,
                          ),
                          onSubmitted: (_) => unawaited(_load()),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _author,
                          decoration: InputDecoration(
                            labelText: gitString(context, GitMessages.author2),
                            isDense: true,
                          ),
                          onSubmitted: (_) => unawaited(_load()),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _path,
                          decoration: InputDecoration(
                            labelText: gitString(context, GitMessages.path2),
                            isDense: true,
                          ),
                          onSubmitted: (_) => unawaited(_load()),
                        ),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_dates()),
                        child: Text(
                          _since == null && _until == null
                              ? gitString(context, GitMessages.date)
                              : gitString(context, GitMessages.dateFilter),
                        ),
                      ),
                    ],
                    TextButton(
                      onPressed: _resetFilters,
                      child: const GitLabel(GitMessages.resetFilters),
                    ),
                    GitIconButton(
                      tooltip: gitString(context, GitMessages.refreshLog),
                      onPressed: _loading ? null : () => unawaited(_load()),
                      icon: const GitIcon(GitGlyph.refresh),
                    ),
                    if (compact)
                      GitIconButton(
                        tooltip: gitString(
                          context,
                          GitMessages.goToCommitReference,
                        ),
                        onPressed: () => unawaited(_goto()),
                        icon: const GitIcon(GitGlyph.search),
                      )
                    else
                      TextButton(
                        onPressed: () => unawaited(_goto()),
                        child: const GitLabel(GitMessages.goToCommitReference),
                      ),
                    TextButton(
                      onPressed: () =>
                          unawaited(_navigate(GitMessages.head, reload: true)),
                      child: const GitLabel(GitMessages.backToHEAD),
                    ),
                    if (widget.onChooseCommit == null &&
                        _selectedIds.length > 1)
                      TextButton(
                        onPressed: () =>
                            GitWorkflowUi(context, widget.session).present(
                              GitMessages.orderedCherryPick,
                              GitCherryPickView(
                                session: widget.session,
                                commits: _commits
                                    .where((e) => _selectedIds.contains(e.oid))
                                    .toList()
                                    .reversed
                                    .toList(),
                              ),
                              expanded: true,
                            ),
                        child: Text(
                          gitString(
                            context,
                            GitMessages.reviewCherryPickArg0,
                            values: {'arg0': _selectedIds.length},
                          ),
                        ),
                      ),
                    if (_selectedIds.length == 2)
                      TextButton(
                        onPressed: () {
                          final ids = _selectedIds.toList();
                          unawaited(
                            GitHistoryActions(
                              GitWorkflowUi(context, widget.session),
                            ).compare(ids.first, ids.last),
                          );
                        },
                        child: const GitLabel(
                          GitMessages.compareTwoSelectedRevisions,
                        ),
                      ),
                    GitIconButton(
                      tooltip: canShowBranches
                          ? gitString(context, GitMessages.toggleBranchesPane)
                          : gitString(
                              context,
                              GitMessages.filterBranchesAndTags,
                            ),
                      onPressed: canShowBranches
                          ? () => setState(() => _branches = !_branches)
                          : () => unawaited(_showBranchFilter()),
                      icon: const GitIcon(GitGlyph.branch),
                    ),
                    if (!showDetails && _selected != null)
                      TextButton(
                        onPressed: () => widget.session.host.present<void>(
                          context,
                          gitString(
                            context,
                            GitMessages.commitArg0,
                            values: {'arg0': _selected!.oid.abbreviated},
                          ),
                          SizedBox(height: 500, child: _detailPane()),
                          expanded: true,
                        ),
                        child: const GitLabel(GitMessages.commitDetails),
                      ),
                  ],
                ),
                if (compact && activeFilters > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      [
                        if (_message.text.isNotEmpty)
                          '${gitString(context, GitMessages.message2)}: ${_message.text}',
                        if (_author.text.isNotEmpty)
                          '${gitString(context, GitMessages.author2)}: ${_author.text}',
                        if (_path.text.isNotEmpty)
                          '${gitString(context, GitMessages.path2)}: ${_path.text}',
                        if (_since != null || _until != null)
                          gitString(context, GitMessages.dateFilter),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_reference != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      label: Text(
                        gitString(
                          context,
                          GitMessages.referenceArg0,
                          values: {'arg0': _reference},
                        ),
                      ),
                      onDeleted: () {
                        _reference = null;
                        unawaited(_load());
                      },
                    ),
                  ),
                if (_navigationReference != null)
                  TextButton(
                    onPressed: () => unawaited(_load()),
                    child: const GitLabel(GitMessages.restoreHistoryFilters),
                  ),
                if (_navigationReference != null)
                  InputChip(
                    label: Text(
                      gitString(
                        context,
                        GitMessages.referenceArg0,
                        values: {'arg0': _navigationReference},
                      ),
                    ),
                    onDeleted: () => unawaited(_load()),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_failure != null)
            GitFailurePanel(
              error: _failure!,
              message: _navigationOutsideFilters
                  ? gitString(
                      context,
                      GitMessages
                          .theRequestedRevisionIsOutsideTheCurrentFiltersResetFilters,
                    )
                  : null,
              onRefresh: () => unawaited(_load()),
            ),
          if (_navigationOutsideFilters && _pendingNavigation != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () {
                  final target = _pendingNavigation!;
                  _pendingNavigation = null;
                  _navigationReference = target.value;
                  unawaited(_load(preserveNavigation: true, reveal: target));
                },
                child: const GitLabel(GitMessages.revealRevisionWithoutFilters),
              ),
            ),
          Expanded(child: main),
          if (widget.onChooseCommit != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: _loading || _selected == null
                    ? null
                    : () => widget.onChooseCommit!(_selected!),
                child: const GitLabel(GitMessages.selectThisCommit),
              ),
            ),
        ],
      );
    },
  );
  Future<void> _showBranchFilter() => widget.session.host.present<void>(
    context,
    GitMessages.filterBranchesAndTags,
    Builder(
      builder: (dialogContext) => SizedBox(
        width: 420,
        height: (MediaQuery.sizeOf(context).height * .6).clamp(180, 500),
        child: ListenableBuilder(
          listenable: _referenceSearch,
          builder: (_, _) =>
              _branchPane(onChosen: () => Navigator.of(dialogContext).pop()),
        ),
      ),
    ),
    expanded: false,
  );

  Widget _branchPane({VoidCallback? onChosen}) {
    final filter = _referenceSearch.text.toLowerCase();
    return Column(
      children: [
        TextField(
          controller: _referenceSearch,
          decoration: InputDecoration(
            labelText: gitString(context, GitMessages.branchOrTag),
            prefixIcon: GitIcon(GitGlyph.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                dense: true,
                title: const GitLabel(GitMessages.allReferences),
                selected: _reference == null,
                onTap: () {
                  _reference = null;
                  onChosen?.call();
                  unawaited(_load());
                },
              ),
              for (final group in [
                GitMessages.local,
                GitMessages.remote,
                GitMessages.tags,
              ])
                ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(group),
                  children: [
                    for (final ref in _references.where(
                      (ref) =>
                          ref.name.startsWith(
                            group == GitMessages.local
                                ? 'refs/heads/'
                                : group == GitMessages.remote
                                ? 'refs/remotes/'
                                : 'refs/tags/',
                          ) &&
                          ref.shortName.toLowerCase().contains(filter),
                    ))
                      ListTile(
                        dense: true,
                        leading: GitIcon(
                          ref.current
                              ? GitGlyph.check
                              : group == GitMessages.tags
                              ? GitGlyph.tag
                              : GitGlyph.branch,
                          size: 16,
                        ),
                        title: Text(
                          ref.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _reference == ref.name,
                        onTap: () {
                          _reference = ref.name;
                          onChosen?.call();
                          unawaited(_load());
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _referenceLabel(GitReference ref) {
    final kind = ref.name.startsWith('refs/tags/')
        ? GitMessages.tags
        : ref.name.startsWith('refs/remotes/')
        ? GitMessages.remote
        : GitMessages.local;
    return '${gitString(context, kind)}: ${ref.shortName}';
  }

  Widget _commitSubject(GitCommit commit, List<GitReference> references) =>
      Tooltip(
        message: references.map(_referenceLabel).join(' · '),
        child: Text.rich(
          TextSpan(
            children: [
              for (final ref in references) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: GitIcon(
                    ref.current
                        ? GitGlyph.check
                        : ref.name.startsWith('refs/tags/')
                        ? GitGlyph.tag
                        : GitGlyph.branch,
                    size: 13,
                  ),
                ),
                TextSpan(
                  text: ' ${_referenceLabel(ref)}  ',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
              TextSpan(text: commit.subject),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _commitTable() {
    final graph = graphRows(_commits),
        rowHeight = widget.session.host.rowHeight(context);
    // A lane has the same horizontal coordinate in every row. Reserving the
    // widest graph column also keeps native table insets aligned with pixels.
    final graphContentWidth = graph.fold<double>(40, (width, row) {
      final needed = row.width * 14.0 + 14;
      return needed > width ? needed : width;
    });
    if (!_loading && _commits.isEmpty)
      return const Center(
        child: GitLabel(GitMessages.noCommitsMatchTheCurrentFilters),
      );
    return LayoutBuilder(
      builder: (context, bounds) {
        // The graph may have arbitrarily many real lanes. Pan its document
        // column with one shared viewport while subjects stay visible.
        final graphWidth = graphContentWidth.clamp(
          40.0,
          (bounds.maxWidth * .42).clamp(40.0, double.infinity),
        );
        final spacing = widget.session.host.spacing;
        final subjectMinimum = _textWidth('MMMMMMMMMMMMMMMM') + 40;
        final authorWidth = _textWidth('MMMMMMMMMMMM') + spacing * 2;
        final dateWidth =
            _textWidth('2000-12-31', Theme.of(context).textTheme.bodySmall) +
            spacing * 2;
        final idTextWidth = _textWidth(
          'ffffffffffff',
          Theme.of(context).textTheme.bodySmall,
        );
        final idTitleWidth = _textWidth(
          gitString(context, GitMessages.objectID),
        );
        final idWidth =
            (idTextWidth > idTitleWidth ? idTextWidth : idTitleWidth) +
            spacing * 2;
        final showId = bounds.maxWidth >= subjectMinimum + idWidth;
        final showAuthor =
            bounds.maxWidth >= subjectMinimum + idWidth + authorWidth;
        final showDate =
            bounds.maxWidth >=
            subjectMinimum + idWidth + authorWidth + dateWidth;
        final columns = [
          gitString(context, GitMessages.subjectReferences),
          if (showAuthor) gitString(context, GitMessages.author2),
          if (showDate) gitString(context, GitMessages.date2),
          if (showId) gitString(context, GitMessages.objectID),
        ];
        Widget columnCell(Widget child) => Padding(
          padding: EdgeInsetsDirectional.only(start: spacing),
          child: child,
        );
        return GitNativeTable(
          name: gitString(context, GitMessages.gitCommits),
          description: widget.session.repository.root,
          revision: (widget.session.repository.key, _historyRevision),
          active: widget.active,
          busy: _loading,
          rowCount: _commits.length,
          rowHeight: rowHeight,
          columns: columns,
          headerInsets: [
            graphWidth,
            for (var i = 1; i < columns.length; i++) spacing,
          ],
          widths: [
            bounds.maxWidth -
                (showAuthor ? authorWidth : 0) -
                (showDate ? dateWidth : 0) -
                (showId ? idWidth : 0),
            if (showAuthor) authorWidth,
            if (showDate) dateWidth,
            if (showId) idWidth,
          ],
          rowAt: (index) {
            final commit = _commits[index];
            final refs = _references
                .where((r) => r.oid == commit.oid)
                .map(_referenceLabel)
                .join(', ');
            return GitNativeRow(
              id: commit.oid.value,
              textInsets: [
                graphWidth,
                for (var i = 1; i < columns.length; i++) spacing,
              ],
              cells: [
                '${refs.isEmpty ? '' : '[$refs]  '}${commit.subject}',
                if (showAuthor) commit.author,
                if (showDate) commit.date.toLocal().toString().substring(0, 10),
                if (showId) commit.oid.abbreviated,
              ],
              description:
                  '${commit.oid.value}; '
                  '${gitString(context, GitMessages.parents)}: '
                  '${commit.parents.map((p) => p.value).join(', ')}',
            );
          },
          selected: [
            for (var i = 0; i < _commits.length; i++)
              if (_selectedIds.contains(_commits[i].oid) ||
                  _selectedIds.isEmpty && _selected?.oid == _commits[i].oid)
                i,
          ],
          focusedRow: _commits.indexWhere((c) => c.oid == _selected?.oid),
          scroll: _tableScroll,
          focus: _tableFocus,
          onRequest: _nativeRequest,
          builder: (nativeReady) => Focus(
            focusNode: _tableFocus,
            onFocusChange: (focused) {
              if (!focused) _contextMenuKeys.clear();
            },
            onKeyEvent: (_, event) {
              final target = _selected, generation = _selectionGeneration;
              final revision = _historyRevision;
              if (_contextMenuKeys.handle(
                event,
                target == null
                    ? null
                    : () {
                        if (mounted &&
                            widget.active &&
                            _tableFocus.hasFocus &&
                            _historyRevision == revision &&
                            _selectionGeneration == generation &&
                            _selected?.oid == target.oid) {
                          unawaited(_menu(target));
                        }
                      },
              )) {
                return KeyEventResult.handled;
              }
              if (event is! KeyDownEvent || _commits.isEmpty)
                return KeyEventResult.ignored;
              final index = _commits.indexWhere((e) => e.oid == _selected?.oid);
              if ({
                LogicalKeyboardKey.arrowUp,
                LogicalKeyboardKey.arrowDown,
              }.contains(event.logicalKey)) {
                final next =
                    (index +
                            (event.logicalKey == LogicalKeyboardKey.arrowDown
                                ? 1
                                : -1))
                        .clamp(0, _commits.length - 1);
                _choose(next);
                if (_tableScroll.hasClients)
                  _tableScroll.jumpTo(
                    (next * rowHeight).clamp(
                      0,
                      _tableScroll.position.maxScrollExtent,
                    ),
                  );
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: CustomScrollView(
              controller: _tableScroll,
              semanticChildCount: _commits.length,
              slivers: [
                SliverSemantics(
                  excludeSemantics: nativeReady,
                  sliver: SliverSemantics(
                    role: SemanticsRole.table,
                    container: true,
                    explicitChildNodes: true,
                    label: gitString(context, GitMessages.gitCommits),
                    sliver: SliverFixedExtentList(
                      itemExtent: rowHeight,
                      delegate: SliverChildBuilderDelegate(
                        (context, rowIndex) {
                          if (rowIndex == 0)
                            return Semantics(
                              role: SemanticsRole.row,
                              container: true,
                              explicitChildNodes: true,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: graphWidth,
                                    height: rowHeight,
                                    child: Semantics(
                                      role: SemanticsRole.columnHeader,
                                      container: true,
                                      label: gitString(
                                        context,
                                        GitMessages.graphLanes,
                                      ),
                                      child: Scrollbar(
                                        controller: _graphScroll,
                                        thumbVisibility:
                                            graphContentWidth > graphWidth,
                                        child: SingleChildScrollView(
                                          key: const ValueKey(
                                            'git-graph-horizontal',
                                          ),
                                          controller: _graphScroll,
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            width: graphContentWidth,
                                            height: rowHeight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Semantics(
                                      role: SemanticsRole.columnHeader,
                                      child: const GitLabel(
                                        GitMessages.subjectReferences,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  if (showAuthor)
                                    SizedBox(
                                      width: authorWidth,
                                      child: columnCell(
                                        Semantics(
                                          role: SemanticsRole.columnHeader,
                                          child: const GitLabel(
                                            GitMessages.author2,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (showDate)
                                    SizedBox(
                                      width: dateWidth,
                                      child: columnCell(
                                        Semantics(
                                          role: SemanticsRole.columnHeader,
                                          child: const GitLabel(
                                            GitMessages.date2,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (showId)
                                    SizedBox(
                                      width: idWidth,
                                      child: columnCell(
                                        Semantics(
                                          role: SemanticsRole.columnHeader,
                                          child: const GitLabel(
                                            GitMessages.objectID,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          final index = rowIndex - 1,
                              commit = _commits[rowIndex - 1];
                          final refs = _references
                              .where((e) => e.oid == commit.oid)
                              .toList();
                          final selected =
                              _selectedIds.contains(commit.oid) ||
                              _selectedIds.isEmpty &&
                                  _selected?.oid == commit.oid;
                          return Semantics(
                            role: SemanticsRole.row,
                            container: true,
                            explicitChildNodes: true,
                            selected: selected,
                            onTap: () => _choose(index),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              excludeFromSemantics: true,
                              onTap: () => _choose(index),
                              onSecondaryTapUp: (details) => unawaited(
                                _menu(commit, position: details.globalPosition),
                              ),
                              child: ColoredBox(
                                color: selected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    ExcludeSemantics(
                                      child: SizedBox(
                                        width: graphWidth,
                                        height: rowHeight,
                                        child: ClipRect(
                                          child: CustomPaint(
                                            key: ValueKey(
                                              'git-graph-${commit.oid.value}',
                                            ),
                                            painter: _GraphPainter(
                                              graph[index],
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              offset: _graphOffset,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Semantics(
                                        role: SemanticsRole.cell,
                                        container: true,
                                        label: gitString(
                                          context,
                                          GitMessages.arg0Parents,
                                          values: {
                                            'arg0': commit.parents.length,
                                          },
                                        ),
                                        child: _commitSubject(commit, refs),
                                      ),
                                    ),
                                    if (showAuthor)
                                      SizedBox(
                                        width: authorWidth,
                                        child: columnCell(
                                          Semantics(
                                            role: SemanticsRole.cell,
                                            child: Text(
                                              commit.author,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (showDate)
                                      SizedBox(
                                        width: dateWidth,
                                        child: columnCell(
                                          Semantics(
                                            role: SemanticsRole.cell,
                                            child: Text(
                                              commit.date
                                                  .toLocal()
                                                  .toString()
                                                  .substring(0, 10),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (showId)
                                      SizedBox(
                                        width: idWidth,
                                        child: columnCell(
                                          Semantics(
                                            role: SemanticsRole.cell,
                                            child: Text(
                                              commit.oid.abbreviated,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: _commits.length + 1,
                        addSemanticIndexes: false,
                      ),
                    ),
                  ),
                ),
                if (_more)
                  SliverToBoxAdapter(
                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : () => unawaited(_load(append: true)),
                      child: const GitLabel(GitMessages.loadMoreCommits),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _nativeRequest(GitNativeTableRequest request) {
    final index = request.row;
    switch (request.action) {
      case 'clearSelection':
        setState(() {
          _selectedIds.clear();
          _selected = null;
          _files = [];
          _selectionGeneration++;
        });
      case 'selectAll':
        setState(() => _selectedIds.addAll(_commits.map((c) => c.oid)));
      case 'select' || 'focus':
        _choose(index, keyboardModifiers: false);
        _scrollToNativeRow(index);
      case 'scroll':
        _scrollToNativeRow(index);
      case 'context':
        _choose(index, keyboardModifiers: false);
        unawaited(_menu(_commits[index]));
      case 'addSelection':
        setState(() {
          if (_selectedIds.isEmpty && _selected != null) {
            _selectedIds.add(_selected!.oid);
          }
          _selectedIds.add(_commits[index].oid);
        });
      case 'removeSelection':
        setState(() {
          _selectedIds.remove(_commits[index].oid);
          if (_selected?.oid == _commits[index].oid) {
            _selected = null;
            _files = [];
            _selectionGeneration++;
          }
        });
    }
  }

  void _scrollToNativeRow(int index) {
    if (_tableScroll.hasClients) {
      final row = widget.session.host.rowHeight(context);
      final start = (index + 1) * row, end = start + row;
      final position = _tableScroll.position;
      if (start < position.pixels ||
          end > position.pixels + position.viewportDimension) {
        _tableScroll.jumpTo(start.clamp(0, position.maxScrollExtent));
      }
    }
  }

  void _choose(int index, {bool keyboardModifiers = true}) {
    final commit = _commits[index];
    _tableFocus.requestFocus();
    setState(() {
      if (keyboardModifiers && HardwareKeyboard.instance.isShiftPressed) {
        _selectedIds.clear();
        for (
          var i = _selectionAnchor < index ? _selectionAnchor : index;
          i <= (_selectionAnchor > index ? _selectionAnchor : index);
          i++
        ) {
          _selectedIds.add(_commits[i].oid);
        }
      } else if (keyboardModifiers &&
          HardwareKeyboard.instance.isControlPressed) {
        if (!_selectedIds.add(commit.oid)) _selectedIds.remove(commit.oid);
      } else {
        _selectedIds
          ..clear()
          ..add(commit.oid);
        _selectionAnchor = index;
      }
    });
    unawaited(_select(commit));
  }

  Widget _changedFilesPane(GitCommit commit) {
    final generation = _selectionGeneration;
    final parent = _parent;
    bool current() =>
        mounted &&
        _selectionGeneration == generation &&
        _selected?.oid == commit.oid &&
        _parent == parent;
    if (_filesLoading) {
      return Center(
        child: CircularProgressIndicator(
          semanticsLabel: gitString(context, GitMessages.loadingChangedFiles),
        ),
      );
    }
    if (_fileFailure case final error?) {
      return SingleChildScrollView(
        child: GitFailurePanel(
          error: error,
          onRefresh: () {
            if (current()) unawaited(_select(commit, parent: parent));
          },
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Semantics(
          container: true,
          liveRegion: true,
          child: const GitLabel(GitMessages.noChangedFiles),
        ),
      );
    }
    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, i) {
        final file = _files[i];
        return ListTile(
          dense: true,
          leading: Text(file.index),
          title: Text(
            file.path.basename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: file.originalPath != null
              ? Text(
                  '${file.originalPath!.display} → ${file.path.display}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : file.path.parent.isEmpty
              ? null
              : Text(
                  file.path.parent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          selected: _selectedFile?.path == file.path,
          onTap: () {
            if (current()) setState(() => _selectedFile = file);
          },
        );
      },
    );
  }

  Widget _detailPane() {
    final commit = _selected;
    final generation = _selectionGeneration;
    if (commit == null)
      return const Center(child: GitLabel(GitMessages.selectACommit));
    return GitSplitter(
      axis: Axis.vertical,
      initial: .52,
      minimum: 110,
      first: Column(
        children: [
          if (commit.parents.length > 1)
            DropdownButton<GitOid>(
              value: _parent,
              isExpanded: true,
              items: [
                for (var i = 0; i < commit.parents.length; i++)
                  DropdownMenuItem(
                    value: commit.parents[i],
                    child: Text(
                      gitString(
                        context,
                        GitMessages.compareParentArg0Arg1,
                        values: {
                          'arg0': i + 1,
                          'arg1': commit.parents[i].abbreviated,
                        },
                      ),
                    ),
                  ),
              ],
              onChanged: (parent) {
                if (mounted &&
                    generation == _selectionGeneration &&
                    parent != null)
                  unawaited(_select(commit, parent: parent));
              },
            ),
          Padding(
            padding: EdgeInsets.all(widget.session.host.spacing),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                container: true,
                header: true,
                child: const GitLabel(GitMessages.changedFiles),
              ),
            ),
          ),
          Expanded(child: _changedFilesPane(commit)),
        ],
      ),
      second: SingleChildScrollView(
        padding: EdgeInsets.all(widget.session.host.spacing),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commit.message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                gitString(
                  context,
                  GitMessages.authorArg0Arg1Arg2,
                  values: {
                    'arg0': commit.author,
                    'arg1': commit.email,
                    'arg2': commit.date.toLocal(),
                  },
                ),
              ),
              Text(
                gitString(
                  context,
                  GitMessages.committerArg0Arg1Arg2,
                  values: {
                    'arg0': commit.committer,
                    'arg1': commit.committerEmail,
                    'arg2': commit.committerDate?.toLocal(),
                  },
                ),
              ),
              GitSelectableText(commit.oid.value),
              if (commit.boundary)
                const GitLabel(
                  GitMessages.shallowPartialBoundaryAParentObjectIsUnavailable,
                ),
              for (final parent in commit.parents)
                TextButton(
                  onPressed: () {
                    final target = _commits
                        .where((c) => c.oid == parent)
                        .firstOrNull;
                    if (target != null)
                      unawaited(_select(target));
                    else
                      widget.session.host.notify(
                        GitMessages.parentIsOutsideThisPageOrAShallowBoundary,
                      );
                  },
                  child: Text(
                    gitString(
                      context,
                      GitMessages.parentArg0,
                      values: {'arg0': parent.abbreviated},
                    ),
                  ),
                ),
              for (final ref in _references.where((r) => r.oid == commit.oid))
                Text(ref.name),
              if (widget.onChooseCommit == null)
                TextButton(
                  onPressed: () => unawaited(_menu(commit)),
                  child: const GitLabel(GitMessages.commitActions),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diffPreview({bool expanded = false}) {
    final file = _selectedFile!;
    final commit = _selected!;
    final parent = _parent;
    final files = List<GitChange>.unmodifiable(_files);
    final generation = _selectionGeneration;
    final session = widget.session;
    final index = files.indexOf(file);
    bool current() =>
        mounted &&
        widget.session == session &&
        _selectionGeneration == generation &&
        _selected?.oid == commit.oid &&
        _parent == parent &&
        _selectedFile == file;
    void selectFile(int next) {
      if (current()) setState(() => _selectedFile = files[next]);
    }

    return Column(
      children: [
        Row(
          children: [
            if (expanded)
              TextButton.icon(
                onPressed: () {
                  if (current()) setState(() => _expandedDiff = false);
                },
                icon: const GitIcon(GitGlyph.back),
                label: const GitLabel(GitMessages.log),
              )
            else
              GitIconButton(
                tooltip: gitString(context, GitMessages.reviewDifference),
                onPressed: () {
                  if (current()) setState(() => _expandedDiff = true);
                },
                icon: const GitIcon(GitGlyph.expand),
              ),
            Expanded(
              child: Text(
                '${file.originalPath == null ? file.path.display : '${file.originalPath!.display} → ${file.path.display}'} · '
                '${parent?.abbreviated ?? gitString(context, GitMessages.emptyTree)} → '
                '${commit.oid.abbreviated}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Expanded(
          child: GitDiffView(
            key: ValueKey(
              '${session.repository.key}:${commit.oid.value}:${parent?.value}:${file.path.key}:${file.originalPath?.key}',
            ),
            session: widget.session,
            preview: !expanded,
            comparison: GitComparison(
              file.path,
              parent == null
                  ? const ContentVersion.absent()
                  : ContentVersion(ContentKind.commit, revision: parent),
              ContentVersion(ContentKind.commit, revision: commit.oid),
              leftPath: file.originalPath,
            ),
            onPreviousFile: index <= 0 ? null : () => selectFile(index - 1),
            onNextFile: index < 0 || index + 1 >= files.length
                ? null
                : () => selectFile(index + 1),
          ),
        ),
      ],
    );
  }

  Future<void> _menu(GitCommit commit, {Offset? position}) async {
    if (widget.onChooseCommit != null) return;
    final action = await widget.session.host.menu(
      context,
      commit.subject,
      [
        for (final action in [
          GitMessages.createBranch2,
          GitMessages.createTag,
          GitMessages.compareRevisions,
          GitMessages.openSnapshot,
          GitMessages.cherryPickOperation,
          GitMessages.revertCommit,
          GitMessages.interactiveRebaseAfterThisBoundary,
          GitMessages.resetCurrentBranch,
        ])
          GitMenuEntry(
            action,
            action,
            enabled:
                const {
                  GitMessages.compareRevisions,
                  GitMessages.openSnapshot,
                }.contains(action) ||
                !widget.session.running && widget.session.canWriteMetadata,
            sectionStart: const {
              GitMessages.cherryPickOperation,
              GitMessages.revertCommit,
              GitMessages.resetCurrentBranch,
            }.contains(action),
          ),
        const GitMenuEntry(
          'copy',
          GitMessages.copyFullObjectID,
          sectionStart: true,
        ),
      ],
      position: position,
      localizeTitle: false,
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: commit.oid.value));
      return;
    }
    if (action != null && mounted) {
      if (widget.onCommitAction != null) {
        widget.onCommitAction!(commit, action);
      } else {
        await GitWorkflowUi(
          context,
          widget.session,
        ).commitAction(commit, action);
      }
    }
  }

  Future<void> _goto() async {
    final value = await gitTextInput(
      context,
      widget.session,
      GitMessages.goToCommitReference2,
      explanation: GitMessages.enterACommitIDOrReferenceToRevealInLog,
    );
    if (value == null || value.isEmpty || !mounted) return;
    await _navigate(value);
  }

  Future<void> _navigate(String value, {bool reload = false}) async {
    final generation = ++_generation;
    _readCancellation?.cancel();
    final cancellation = _readCancellation = GitCancellation();
    final loaded = _commits.where((e) => e.oid.value == value).firstOrNull;
    if (!reload && loaded != null) {
      setState(() {
        _loading = false;
        _failure = null;
        _navigationOutsideFilters = false;
      });
      await _reveal(loaded);
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
      _navigationOutsideFilters = false;
    });
    try {
      // Resolve names and abbreviated IDs through Git, independently of view
      // filters. A filtered ancestor must never impersonate the requested tip.
      final page = await widget.session.client.history(
        widget.session.repository,
        filter: HistoryFilter(reference: value),
        limit: 1,
        cancellation: cancellation,
      );
      if (!mounted || generation != _generation) return;
      if (page.commits.isEmpty) {
        throw const GitException(
          GitErrorCode.unavailable,
          diagnostic: GitMessages.theRequestedRevisionIsUnavailable,
        );
      }
      final target = page.commits.first;
      final existing = _commits.where((e) => e.oid == target.oid).firstOrNull;
      if (!reload && existing != null) {
        setState(() => _loading = false);
        await _reveal(existing);
      } else if (_hasFilters && _navigationReference == null) {
        // Keep the current filtered table and selection. The user can choose
        // to reveal the resolved object without discarding the filter fields.
        setState(() {
          _loading = false;
          _pendingNavigation = target.oid;
          _navigationOutsideFilters = true;
          _failure = const GitException(
            GitErrorCode.invalidRequest,
            diagnostic: GitMessages
                .theRequestedRevisionIsOutsideTheCurrentFiltersResetFilters,
          );
        });
      } else {
        _navigationReference = target.oid.value;
        await _load(preserveNavigation: true, reveal: target.oid);
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failure = error is GitException
              ? error
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$error'),
                );
        });
      }
    }
  }

  Future<void> _reveal(GitCommit target) async {
    final index = _commits.indexWhere((e) => e.oid == target.oid);
    if (index < 0) return;
    setState(() {
      _selectedIds
        ..clear()
        ..add(target.oid);
      _selectionAnchor = index;
    });
    final details = _select(target);
    final selection = _selectionGeneration;
    await details;
    if (!mounted || selection != _selectionGeneration || !widget.active) return;
    _tableFocus.requestFocus();
    if (_tableScroll.hasClients) {
      _tableScroll.jumpTo(
        (index * widget.session.host.rowHeight(context)).clamp(
          0,
          _tableScroll.position.maxScrollExtent,
        ),
      );
    }
  }

  Future<void> _dates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (range != null) {
      _since = range.start;
      _until = range.end.add(const Duration(days: 1));
      await _load();
    }
  }
}

final class GitGraphRow {
  const GitGraphRow(
    this.lane,
    this.width,
    this.edges, {
    this.unloaded = const {},
    this.boundary = false,
  });
  final int lane, width;
  final List<(int, int, bool)> edges;
  final Set<int> unloaded;
  final bool boundary;
}

/// Lane continuity is computed from actual full parent identities, retaining
/// pending parent lanes across page boundaries.
List<GitGraphRow> graphRows(List<GitCommit> commits) {
  final lanes = <GitOid>[], rows = <GitGraphRow>[];
  final loaded = commits.map((commit) => commit.oid).toSet();
  for (final commit in commits) {
    if (!lanes.contains(commit.oid)) lanes.add(commit.oid);
    final before = List<GitOid>.of(lanes), lane = lanes.indexOf(commit.oid);
    lanes.removeAt(lane);
    for (var i = 0; i < commit.parents.length; i++) {
      final parent = commit.parents[i];
      if (!lanes.contains(parent))
        lanes.insert(
          i == 0 ? lane.clamp(0, lanes.length) : lanes.length,
          parent,
        );
    }
    final edges = <(int, int, bool)>[];
    for (var i = 0; i < before.length; i++) {
      if (i != lane) edges.add((i, lanes.indexOf(before[i]), false));
    }
    for (final parent in commit.parents) {
      edges.add((lane, lanes.indexOf(parent), true));
    }
    rows.add(
      GitGraphRow(
        lane,
        before.length > lanes.length ? before.length : lanes.length,
        edges,
        unloaded: {
          for (final parent in commit.parents)
            if (!loaded.contains(parent)) lanes.indexOf(parent),
        },
        boundary: commit.boundary,
      ),
    );
  }
  return rows;
}

final class _GraphPainter extends CustomPainter {
  const _GraphPainter(this.row, this.color, {this.offset = 0});
  final GitGraphRow row;
  final Color color;
  final double offset;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    double x(int lane) => lane * 14.0 + 10 - offset;
    for (final edge in row.edges) {
      final path = Path()
        ..moveTo(x(edge.$1), edge.$3 ? size.height / 2 : 0)
        ..lineTo(x(edge.$1), size.height / 2)
        ..cubicTo(
          x(edge.$1),
          size.height * .75,
          x(edge.$2),
          size.height * .75,
          x(edge.$2),
          size.height * .9,
        )
        ..lineTo(x(edge.$2), size.height);
      canvas.drawPath(path, paint);
      if (edge.$3 && row.unloaded.contains(edge.$2)) {
        canvas.drawPath(
          Path()
            ..moveTo(x(edge.$2) - 3, size.height - 5)
            ..lineTo(x(edge.$2), size.height - 1)
            ..lineTo(x(edge.$2) + 3, size.height - 5),
          paint,
        );
      }
    }
    canvas.drawLine(
      Offset(x(row.lane), 0),
      Offset(x(row.lane), size.height / 2),
      paint,
    );
    canvas.drawCircle(
      Offset(x(row.lane), size.height / 2),
      3.5,
      paint..style = row.boundary ? PaintingStyle.stroke : PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.row != row ||
      oldDelegate.color != color ||
      oldDelegate.offset != offset;
}
