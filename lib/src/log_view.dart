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

final class GitLogView extends StatefulWidget {
  const GitLogView({
    super.key,
    required this.session,
    this.onCommitAction,
    this.path,
    this.active = true,
  });
  final GitSession session;
  final void Function(GitCommit commit, String action)? onCommitAction;
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
  final _selectedIds = <GitOid>{};
  final _tableScroll = ScrollController();
  final _tableFocus = FocusNode(debugLabel: 'Git commits');
  int _selectionAnchor = 0;
  GitOid? _parent;
  String? _reference, _anchor;
  DateTime? _since, _until;
  GitException? _failure;
  bool _loading = true, _more = true, _branches = true, _details = true;
  int _generation = 0;
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
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GitLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _repositoryChanged();
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
    try {
      final refs = await widget.session.client.references(
        widget.session.repository,
      );
      String identity(List<GitReference> values) => values
          .map((r) => '${r.name}:${r.oid.value}:${r.upstream}')
          .join('\n');
      if (mounted &&
          (identity(refs) != identity(_references) ||
              _observedHead != widget.session.snapshot?.head)) {
        _observedHead = widget.session.snapshot?.head;
        await _load();
      }
    } on Object catch (error) {
      if (mounted)
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

  @override
  void dispose() {
    _generation++;
    _selectionGeneration++;
    _readCancellation?.cancel();
    _referenceRefresh?.cancel();
    widget.session.removeListener(_repositoryChanged);
    _tableScroll.dispose();
    _tableFocus.dispose();
    for (final c in [_message, _author, _path, _referenceSearch]) {
      c.dispose();
    }
    super.dispose();
  }

  HistoryFilter get _filter => HistoryFilter(
    reference: _reference,
    author: _author.text,
    message: _message.text,
    since: _since,
    until: _until,
    path: _path.text.isEmpty ? null : RepoPath.text(_path.text),
    follow: widget.path != null,
  );
  Future<void> _load({bool append = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
    });
    _readCancellation?.cancel();
    final cancellation = _readCancellation = GitCancellation();
    try {
      final page = await widget.session.client.history(
        widget.session.repository,
        filter: _filter,
        offset: append ? _commits.length : 0,
        anchor: append ? _anchor : null,
        cancellation: cancellation,
      );
      final refs = append
          ? _references
          : await widget.session.client.references(widget.session.repository);
      if (!mounted || generation != _generation) return;
      setState(() {
        _commits = append ? [..._commits, ...page.commits] : page.commits;
        _references = refs;
        _more = page.hasMore;
        _anchor = page.anchor;
        _loading = false;
      });
      final retained = _commits
          .where((e) => e.oid == _selected?.oid)
          .firstOrNull;
      if (retained != null || _commits.isNotEmpty)
        await _select(retained ?? _commits.first);
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
        });
    }
  }

  Future<void> _select(GitCommit commit, {GitOid? parent}) async {
    final generation = ++_selectionGeneration;
    setState(() {
      _selected = commit;
      _parent = parent ?? commit.parents.firstOrNull;
      _files = [];
    });
    try {
      final files = await widget.session.client.changedFiles(
        widget.session.repository,
        commit.oid,
        parent: _parent,
      );
      if (mounted && generation == _selectionGeneration)
        setState(() => _files = files);
    } on Object catch (error) {
      if (mounted && generation == _selectionGeneration)
        setState(
          () => _failure = error is GitException
              ? error
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$error'),
                ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: widget.session.host,
    child: Builder(builder: _build),
  );
  Widget _build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final showBranches = _branches && bounds.maxWidth >= 1150;
      final showDetails = _details && bounds.maxWidth >= 720;
      Widget main = _commitTable();
      if (showDetails)
        main = GitSplitter(
          first: main,
          second: _detailPane(),
          initial: .64,
          minimum: 220,
          value: widget.session.split('logDetailsSplit', .64),
          onChanged: (v) => widget.session.setViewState('logDetailsSplit', v),
        );
      if (showBranches)
        main = GitSplitter(
          first: _branchPane(),
          second: main,
          initial: .20,
          minimum: 160,
          value: widget.session.split('logBranchesSplit', .20),
          onChanged: (v) => widget.session.setViewState('logBranchesSplit', v),
        );
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
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _message,
                        decoration: InputDecoration(
                          labelText: gitString(context, 'Message'),
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
                          labelText: gitString(context, 'Author'),
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
                          labelText: gitString(context, 'Path'),
                          isDense: true,
                        ),
                        onSubmitted: (_) => unawaited(_load()),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_dates()),
                      child: Text(
                        _since == null && _until == null
                            ? 'Date…'
                            : 'Date filter…',
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _message.clear();
                        _author.clear();
                        _path.clear();
                        _reference = null;
                        _since = _until = null;
                        unawaited(_load());
                      },
                      child: const GitLabel('Reset filters'),
                    ),
                    GitIconButton(
                      tooltip: 'Refresh Log',
                      onPressed: _loading ? null : () => unawaited(_load()),
                      icon: const Icon(Icons.refresh),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_goto()),
                      child: const GitLabel('Go to commit/reference…'),
                    ),
                    TextButton(
                      onPressed: () {
                        _reference = 'HEAD';
                        unawaited(_load());
                      },
                      child: const GitLabel('Back to HEAD'),
                    ),
                    if (_selectedIds.length > 1)
                      TextButton(
                        onPressed: () =>
                            GitWorkflowUi(context, widget.session).present(
                              'Ordered cherry-pick',
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
                          'Review cherry-pick (${_selectedIds.length})…',
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
                          'Compare two selected revisions…',
                        ),
                      ),
                    GitIconButton(
                      tooltip: 'Toggle branches pane',
                      onPressed: () => setState(() => _branches = !_branches),
                      icon: const Icon(Icons.account_tree_outlined),
                    ),
                    if (!showDetails && _selected != null)
                      TextButton(
                        onPressed: () => widget.session.host.present<void>(
                          context,
                          'Commit ${_selected!.oid.abbreviated}',
                          SizedBox(height: 500, child: _detailPane()),
                          expanded: true,
                        ),
                        child: const GitLabel('Commit details…'),
                      ),
                  ],
                ),
                if (_reference != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      label: Text('Reference: $_reference'),
                      onDeleted: () {
                        _reference = null;
                        unawaited(_load());
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_failure != null)
            GitFailurePanel(
              error: _failure!,
              onRefresh: () => unawaited(_load()),
            ),
          Expanded(child: main),
        ],
      );
    },
  );
  Widget _branchPane() {
    final filter = _referenceSearch.text.toLowerCase();
    return Column(
      children: [
        TextField(
          controller: _referenceSearch,
          decoration: InputDecoration(
            labelText: gitString(context, 'Branch or tag'),
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                dense: true,
                title: const GitLabel('All references'),
                selected: _reference == null,
                onTap: () {
                  _reference = null;
                  unawaited(_load());
                },
              ),
              for (final group in ['Local', 'Remote', 'Tags'])
                ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(group),
                  children: [
                    for (final ref in _references.where(
                      (ref) =>
                          ref.name.startsWith(
                            group == 'Local'
                                ? 'refs/heads/'
                                : group == 'Remote'
                                ? 'refs/remotes/'
                                : 'refs/tags/',
                          ) &&
                          ref.shortName.toLowerCase().contains(filter),
                    ))
                      ListTile(
                        dense: true,
                        leading: Icon(
                          ref.current
                              ? Icons.check
                              : group == 'Tags'
                              ? Icons.label_outline
                              : Icons.account_tree_outlined,
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

  Widget _commitTable() {
    final graph = graphRows(_commits),
        rowHeight = widget.session.host.rowHeight(context);
    if (!_loading && _commits.isEmpty)
      return const Center(
        child: GitLabel('No commits match the current filters.'),
      );
    return LayoutBuilder(
      builder: (context, bounds) {
        final showAuthor = bounds.maxWidth >= 650,
            showDate = bounds.maxWidth >= 850;
        final showId = bounds.maxWidth >= 430;
        return Focus(
          focusNode: _tableFocus,
          onKeyEvent: (_, event) {
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
            if ((event.logicalKey == LogicalKeyboardKey.contextMenu ||
                    event.logicalKey == LogicalKeyboardKey.f10 &&
                        HardwareKeyboard.instance.isShiftPressed) &&
                _selected != null) {
              unawaited(_menu(_selected!));
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: CustomScrollView(
            controller: _tableScroll,
            semanticChildCount: _commits.length,
            slivers: [
              SliverSemantics(
                role: SemanticsRole.table,
                container: true,
                explicitChildNodes: true,
                label: gitString(context, 'Git commits'),
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
                              const SizedBox(width: 40),
                              Expanded(
                                child: Semantics(
                                  role: SemanticsRole.columnHeader,
                                  child: const GitLabel('Subject / references'),
                                ),
                              ),
                              if (showAuthor)
                                SizedBox(
                                  width: 120,
                                  child: Semantics(
                                    role: SemanticsRole.columnHeader,
                                    child: const GitLabel('Author'),
                                  ),
                                ),
                              if (showDate)
                                SizedBox(
                                  width: 92,
                                  child: Semantics(
                                    role: SemanticsRole.columnHeader,
                                    child: const GitLabel('Date'),
                                  ),
                                ),
                              if (showId)
                                SizedBox(
                                  width: 96,
                                  child: Semantics(
                                    role: SemanticsRole.columnHeader,
                                    child: const GitLabel('Object ID'),
                                  ),
                                ),
                            ],
                          ),
                        );
                      final index = rowIndex - 1,
                          commit = _commits[rowIndex - 1];
                      final refs = _references
                          .where((e) => e.oid == commit.oid)
                          .map((e) => e.shortName)
                          .join(', ');
                      final selected =
                          _selectedIds.contains(commit.oid) ||
                          _selectedIds.isEmpty && _selected?.oid == commit.oid;
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
                                    width: (graph[index].width * 14.0 + 14)
                                        .clamp(40, 120),
                                    height: rowHeight,
                                    child: CustomPaint(
                                      painter: _GraphPainter(
                                        graph[index],
                                        Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Semantics(
                                    role: SemanticsRole.cell,
                                    container: true,
                                    label: '${commit.parents.length} parents',
                                    child: Text(
                                      '${refs.isEmpty ? '' : '[$refs]  '}${commit.subject}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (showAuthor)
                                  SizedBox(
                                    width: 120,
                                    child: Semantics(
                                      role: SemanticsRole.cell,
                                      child: Text(
                                        commit.author,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                if (showDate)
                                  SizedBox(
                                    width: 92,
                                    child: Semantics(
                                      role: SemanticsRole.cell,
                                      child: Text(
                                        commit.date
                                            .toLocal()
                                            .toString()
                                            .substring(0, 10),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                                if (showId)
                                  SizedBox(
                                    width: 96,
                                    child: Semantics(
                                      role: SemanticsRole.cell,
                                      child: Text(
                                        commit.oid.abbreviated,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
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
              if (_more)
                SliverToBoxAdapter(
                  child: TextButton(
                    onPressed: _loading
                        ? null
                        : () => unawaited(_load(append: true)),
                    child: const GitLabel('Load more commits'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _choose(int index) {
    final commit = _commits[index];
    _tableFocus.requestFocus();
    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _selectedIds.clear();
        for (
          var i = _selectionAnchor < index ? _selectionAnchor : index;
          i <= (_selectionAnchor > index ? _selectionAnchor : index);
          i++
        ) {
          _selectedIds.add(_commits[i].oid);
        }
      } else if (HardwareKeyboard.instance.isControlPressed) {
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

  Widget _detailPane() {
    final commit = _selected;
    if (commit == null) return const Center(child: GitLabel('Select a commit'));
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
                      'Compare parent ${i + 1}: ${commit.parents[i].abbreviated}',
                    ),
                  ),
              ],
              onChanged: (parent) => unawaited(_select(commit, parent: parent)),
            ),
          Expanded(
            child: ListView.builder(
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
                  subtitle: file.path.parent.isEmpty
                      ? null
                      : Text(
                          file.path.parent,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => unawaited(_diff(file)),
                );
              },
            ),
          ),
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
                'Author: ${commit.author} <${commit.email}>\n${commit.date.toLocal()}',
              ),
              Text(
                'Committer: ${commit.committer} <${commit.committerEmail}>\n${commit.committerDate?.toLocal()}',
              ),
              GitSelectableText(commit.oid.value),
              if (commit.boundary)
                const GitLabel(
                  'Shallow/partial boundary: a parent object is unavailable.',
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
                        'Parent is outside this page or a shallow boundary.',
                      );
                  },
                  child: Text('Parent ${parent.abbreviated}'),
                ),
              for (final ref in _references.where((r) => r.oid == commit.oid))
                Text(ref.name),
              TextButton(
                onPressed: () => unawaited(_menu(commit)),
                child: const GitLabel('Commit actions…'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _diff(GitChange file) => widget.session.host.present<void>(
    context,
    '${_parent?.abbreviated ?? 'empty tree'} → ${_selected!.oid.abbreviated}',
    GitDiffView(
      session: widget.session,
      comparison: GitComparison(
        file.path,
        _parent == null
            ? const ContentVersion.absent()
            : ContentVersion(ContentKind.commit, revision: _parent),
        ContentVersion(ContentKind.commit, revision: _selected!.oid),
      ),
    ),
    expanded: true,
  );
  Future<void> _menu(GitCommit commit, {Offset? position}) async {
    final action = await widget.session.host.menu(context, commit.subject, [
      for (final action in [
        'Create branch',
        'Create tag',
        'Compare revisions',
        'Open snapshot',
        'Cherry-pick',
        'Revert commit',
        'Interactive rebase after this boundary',
        'Reset current branch',
      ])
        GitMenuEntry(
          action,
          action,
          enabled:
              const {'Compare revisions', 'Open snapshot'}.contains(action) ||
              !widget.session.running && widget.session.canWriteMetadata,
          sectionStart: const {
            'Cherry-pick',
            'Revert commit',
            'Reset current branch',
          }.contains(action),
        ),
      const GitMenuEntry('copy', 'Copy full object ID', sectionStart: true),
    ], position: position);
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
    final entry = TextEditingController();
    final value = await widget.session.host.present<String>(
      context,
      'Go to commit/reference',
      TextField(
        controller: entry,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      expanded: false,
    );
    entry.dispose();
    if (value == null || !mounted) return;
    final target = _commits
        .where((e) => e.oid.value.startsWith(value))
        .firstOrNull;
    if (target != null) {
      await _select(target);
      return;
    }
    _reference = value;
    await _load();
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
  const GitGraphRow(this.lane, this.width, this.edges);
  final int lane, width;
  final List<(int, int, bool)> edges;
}

/// Lane continuity is computed from actual full parent identities, retaining
/// pending parent lanes across page boundaries.
List<GitGraphRow> graphRows(List<GitCommit> commits) {
  final lanes = <GitOid>[], rows = <GitGraphRow>[];
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
      ),
    );
  }
  return rows;
}

final class _GraphPainter extends CustomPainter {
  const _GraphPainter(this.row, this.color);
  final GitGraphRow row;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    double x(int lane) => (lane * 14.0 + 10).clamp(4, size.width - 4);
    for (final edge in row.edges) {
      final path = Path()
        ..moveTo(x(edge.$1), edge.$3 ? size.height / 2 : 0)
        ..lineTo(x(edge.$1), size.height / 2)
        ..lineTo(x(edge.$2), size.height);
      canvas.drawPath(path, paint);
    }
    canvas.drawLine(
      Offset(x(row.lane), 0),
      Offset(x(row.lane), size.height / 2),
      paint,
    );
    canvas.drawCircle(
      Offset(x(row.lane), size.height / 2),
      3.5,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.row != row || oldDelegate.color != color;
}
