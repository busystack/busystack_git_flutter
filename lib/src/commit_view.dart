import 'dart:async';
import 'dart:ui' show SemanticsRole;
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'context_menu_keys.dart';
import 'host.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'history_actions.dart';
import 'native_table.dart';
import 'operation_banner.dart';

final class GitCommitView extends StatefulWidget {
  const GitCommitView({
    super.key,
    required this.session,
    required this.onReview,
    required this.onLog,
    required this.onBranches,
    required this.onPush,
    required this.onMore,
    this.selectedComparison,
    this.notice,
    this.active = true,
    this.reviewContext,
  });
  final GitSession session;
  final ValueChanged<GitComparison> onReview;
  final GitComparison? selectedComparison;
  final Widget? notice;
  final bool active;

  /// Current host document/review identity. This guards late presentation
  /// updates; repository authorization remains the engine's responsibility.
  final Object? Function()? reviewContext;
  final VoidCallback onLog, onBranches, onPush;
  final ValueChanged<BuildContext> onMore;
  @override
  State<GitCommitView> createState() => _GitCommitViewState();
}

final class _GitCommitViewState extends State<GitCommitView> {
  final _message = TextEditingController();
  bool _amend = false, _signOff = false;
  bool? _sign;
  bool _composing = false;
  int _reviewGeneration = 0;
  GitSession get session => widget.session;
  GitHost get host => session.host;
  void _leaveReview(VoidCallback action) {
    _reviewGeneration++;
    action();
  }

  @override
  void initState() {
    super.initState();
    _message.text = session.draft;
    session.addListener(_changed);
    _message.addListener(_compositionChanged);
    session.commitAction = _commit;
    session.canCommit = _canCommit;
  }

  bool _canCommit() =>
      !session.running &&
      !session.repository.bare &&
      session.canWriteMetadata &&
      _message.text.trim().isNotEmpty &&
      !(session.outcome?.phase == GitOperationPhase.uncertain &&
          session.failure != null) &&
      (!_message.value.composing.isValid ||
          _message.value.composing.isCollapsed) &&
      (session.snapshot!.changes.any((e) => e.staged) || _amend) &&
      !session.snapshot!.operation.unmerged;
  void _changed() {
    if (!mounted) return;
    if (_message.text != session.draft && !session.running)
      _message.text = session.draft;
    setState(() {});
  }

  void _compositionChanged() {
    final active =
        _message.value.composing.isValid &&
        !_message.value.composing.isCollapsed;
    if (mounted && active != _composing) setState(() => _composing = active);
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    if (session.commitAction == _commit) {
      session.commitAction = null;
      session.canCommit = null;
    }
    _message.removeListener(_compositionChanged);
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: widget.session.host,
    child: Builder(builder: _build),
  );
  Widget _build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (bounds.maxWidth < 1 || bounds.maxHeight < 1) return const SizedBox();
      final width = bounds.maxWidth.clamp(220.0, double.infinity);
      final minimumHeight = _minimumHeight(context, width);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: bounds.maxHeight,
          maxHeight: bounds.maxHeight,
          child: bounds.maxHeight < minimumHeight
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: SizedBox(
                          height: minimumHeight,
                          child: _panel(context, includeActions: false),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: bounds.maxHeight),
                      child: SingleChildScrollView(
                        child: _actions(stagedCount),
                      ),
                    ),
                  ],
                )
              : _panel(context),
        ),
      );
    },
  );
  double _minimumHeight(BuildContext context, double width) {
    final row = host.rowHeight(context), spacing = host.spacing;
    final theme = Theme.of(context).textTheme;
    double height(
      String text,
      TextStyle? style,
      double available, {
      int? maxLines,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: gitString(context, text), style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: available.clamp(24.0, double.infinity));
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final inner = width - spacing * 2;
    final amend = height(
      _amend ? 'Amend selected commit' : 'Amend last commit',
      theme.bodyMedium,
      inner - 96,
    ).clamp(48.0, double.infinity);
    final hint = height(
      'Configured hooks and signing are respected.',
      theme.bodySmall,
      inner,
    );
    final messageMinimum =
        amend +
        hint +
        row * 4 +
        (_amend
            ? height(
                'Rewrites the selected HEAD commit. Remote tracking cannot prove it is unpublished.',
                theme.bodyMedium,
                inner,
              )
            : 0) +
        (session.draftFailure == null ? 0 : row * 3);
    final header =
        row +
        spacing * 2 +
        height('Commit scope: entire repository', theme.bodySmall, inner) +
        height(session.repository.root, theme.bodySmall, inner, maxLines: 1) +
        (session.snapshot?.upstream == null ? 0 : row * 2) +
        (widget.notice == null ? 0 : row * 3) +
        (session.repository.bare ? row * 3 : 0) +
        (session.snapshot?.capabilities.writeMetadata == false ? row * 3 : 0);
    final actions = ['Commit staged (999)', 'Commit and Push…'].fold<double>(
      0,
      (sum, text) =>
          sum +
          (height(text, theme.labelLarge, inner - 48) + 24).clamp(
            48.0,
            double.infinity,
          ),
    );
    return header +
        messageMinimum +
        row * 2 +
        actions +
        spacing * 5 +
        (session.snapshot?.operation.kind != GitOperationKind.none
            ? row * 3
            : 0) +
        (session.running ? row * 3 : 0) +
        (session.failure == null ? 0 : row * 4);
  }

  int get stagedCount =>
      session.snapshot?.changes.where((e) => e.staged).length ?? 0;

  Widget _panel(BuildContext context, {bool includeActions = true}) {
    final snapshot = session.snapshot;
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(host.spacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _leaveReview(widget.onBranches),
                        icon: GitIcon(GitGlyph.branch, size: 16),
                        label: Text(
                          snapshot?.branch ??
                              (snapshot?.head == null
                                  ? 'Repository'
                                  : 'Detached ${snapshot!.head!.abbreviated}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    GitIconButton(
                      tooltip: 'Log',
                      onPressed: () => _leaveReview(widget.onLog),
                      icon: GitIcon(GitGlyph.history, size: 18),
                    ),
                    GitIconButton(
                      tooltip: 'Refresh',
                      onPressed: session.refreshing
                          ? null
                          : () => unawaited(
                              session.refresh(clearOperationFailure: true),
                            ),
                      icon: const GitIcon(GitGlyph.refresh, size: 18),
                    ),
                    Builder(
                      builder: (anchor) => GitIconButton(
                        tooltip: 'Repository actions',
                        onPressed: () =>
                            _leaveReview(() => widget.onMore(anchor)),
                        icon: const GitIcon(GitGlyph.more, size: 18),
                      ),
                    ),
                  ],
                ),
                Tooltip(
                  message: session.repository.root,
                  child: Text(
                    session.repository.root,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                GitLabel(
                  'Commit scope: entire repository',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (snapshot?.upstream != null)
                  GitLabel(
                    'Cached tracking · {upstream} · {ahead} ahead · {behind} behind',
                    values: {
                      'upstream': snapshot!.upstream!,
                      'ahead': snapshot.ahead,
                      'behind': snapshot.behind,
                    },
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (session.repository.bare)
                  const GitLabel(
                    'Bare repository · no working tree. Open Log to inspect its history.',
                  ),
                if (snapshot != null && !snapshot.capabilities.writeMetadata)
                  const GitLabel(
                    'Read-only repository · staging and commits are unavailable.',
                  ),
                if (widget.notice != null) widget.notice!,
              ],
            ),
          ),
          if (session.loading) const LinearProgressIndicator(),
          if (session.failure case final error?)
            Flexible(
              child: SingleChildScrollView(
                child: GitFailurePanel(
                  error: error,
                  onAuthorize: error.code == GitErrorCode.trustRequired
                      ? () => unawaited(session.authorizeInspection())
                      : null,
                  onRefresh: () =>
                      unawaited(session.refresh(clearOperationFailure: true)),
                ),
              ),
            ),
          if (snapshot?.operation.kind != null &&
              snapshot!.operation.kind != GitOperationKind.none)
            GitOperationBanner(session: session),
          Expanded(
            child: GitSplitter(
              axis: Axis.vertical,
              initial: .62,
              minimum: host.rowHeight(context) * 2,
              minimumSecond: host.rowHeight(context) * 8 + host.spacing * 2,
              value: session.split('commitMessageSplit', .62),
              onChanged: (v) => session.setViewState('commitMessageSplit', v),
              first: session.loading && snapshot == null
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot == null
                  ? const Center(
                      child: GitLabel('Repository status unavailable'),
                    )
                  : GitChangeTree(
                      active: widget.active,
                      reviewContext: () => (
                        _reviewGeneration,
                        widget.reviewContext?.call(),
                        widget.selectedComparison,
                      ),
                      session: session,
                      onReview: widget.onReview,
                      selectedComparison: widget.selectedComparison,
                    ),
              second: Padding(
                padding: EdgeInsets.symmetric(horizontal: host.spacing),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Semantics(
                          label: gitString(
                            context,
                            _amend ? 'Amend {revision}' : 'Amend last commit',
                            values: {
                              'revision': snapshot?.head?.abbreviated ?? '',
                            },
                          ),
                          checked: _amend,
                          enabled: !session.running && snapshot?.head != null,
                          onTap: session.running || snapshot?.head == null
                              ? null
                              : () => setState(() => _amend = !_amend),
                          child: ExcludeSemantics(
                            child: Checkbox(
                              value: _amend,
                              onChanged:
                                  session.running || snapshot?.head == null
                                  ? null
                                  : (value) => setState(() => _amend = value!),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ExcludeSemantics(
                            child: GitLabel(
                              _amend ? 'Amend {revision}' : 'Amend last commit',
                              values: {
                                'revision': snapshot?.head?.abbreviated ?? '',
                              },
                            ),
                          ),
                        ),
                        GitMenuButton(
                          host: session.host,
                          onSelected: (value) => _options(value),
                          entries: [
                            GitMenuEntry(
                              'signoff',
                              'Add sign-off trailer',
                              checked: _signOff,
                            ),
                            GitMenuEntry(
                              'configuredSigning',
                              'Use configured signing policy',
                              checked: _sign == null,
                              radio: true,
                            ),
                            GitMenuEntry(
                              'sign',
                              'Cryptographically sign this commit',
                              checked: _sign == true,
                              radio: true,
                            ),
                            GitMenuEntry(
                              'unsigned',
                              'Do not sign this commit',
                              checked: _sign == false,
                              radio: true,
                            ),
                            const GitMenuEntry.separator(),
                            GitMenuEntry('recent', 'Recent commit messages…'),
                            GitMenuEntry(
                              'template',
                              'Use configured commit template…',
                            ),
                            GitMenuEntry(
                              'identity',
                              'Author identity and configured hooks…',
                            ),
                            if (host.draftMessage != null)
                              GitMenuEntry('draft', 'Draft message…'),
                          ],
                          tooltip: gitString(context, 'Commit options'),
                        ),
                      ],
                    ),
                    if (_amend)
                      const GitLabel(
                        'Rewrites the selected HEAD commit. Remote tracking cannot prove it is unpublished.',
                      ),
                    if (session.draftFailure != null)
                      Text(
                        'Draft retained in memory; saving it failed. ${session.draftFailure!.diagnostic}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _message,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          labelText: gitString(context, 'Commit message'),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          session.setDraft(value);
                          setState(() {});
                        },
                      ),
                    ),
                    GitLabel(
                      'Configured hooks and signing are respected.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (session.running)
            Padding(
              padding: EdgeInsets.all(host.spacing),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Expanded(
                    child: Text(
                      session.progress?.text.isNotEmpty == true
                          ? session.progress!.text
                          : 'Git operation in progress',
                      maxLines: 2,
                    ),
                  ),
                  TextButton(
                    onPressed: session.cancel,
                    child: const GitLabel('Cancel'),
                  ),
                ],
              ),
            ),
          if (includeActions) _actions(stagedCount),
        ],
      ),
    );
  }

  Widget _actions(int staged) => Padding(
    padding: EdgeInsets.all(host.spacing),
    child: Wrap(
      spacing: host.spacing,
      runSpacing: host.spacing,
      children: [
        FilledButton(
          onPressed: _canCommit() ? () => unawaited(_commit(false)) : null,
          child: GitLabel(
            _amend ? 'Amend staged' : 'Commit staged ({count})',
            values: {'count': staged},
          ),
        ),
        OutlinedButton(
          onPressed: _canCommit() ? () => unawaited(_commit(true)) : null,
          child: const GitLabel('Commit and Push…'),
        ),
      ],
    ),
  );

  void _options(String option) {
    switch (option) {
      case 'signoff':
        setState(() => _signOff = !_signOff);
      case 'sign':
        setState(() => _sign = true);
      case 'unsigned':
        setState(() => _sign = false);
      case 'configuredSigning':
        setState(() => _sign = null);
      case 'recent':
        unawaited(_recent());
      case 'template':
        unawaited(_template());
      case 'identity':
        unawaited(_identity());
      case 'draft':
        unawaited(_draft());
    }
  }

  Future<void> _template() async {
    try {
      final client = session.client;
      if (client is! GitWorkflowClient) return;
      final options = await (client as GitWorkflowClient).inspect(
        session.repository,
        const GitInspection(GitInspectionKind.commitOptions),
      );
      if (!mounted) return;
      final template = options['template'] as String?;
      if (template == null) {
        host.notify('No readable commit template is configured.');
        return;
      }
      if (_message.text.isNotEmpty && !await _confirmReplace()) return;
      _message.text = template;
      session.setDraft(template);
      setState(() {});
    } on Object catch (error) {
      session.reportFailure(error);
    }
  }

  Future<void> _identity() async {
    await host.present<void>(
      context,
      'Commit identity and hooks',
      GitIdentityView(session: session),
      expanded: false,
    );
  }

  Future<void> _draft() async {
    final before = _message.text;
    final value = await host.draftMessage?.call(session.repository);
    if (!mounted || value == null || _message.text != before) return;
    if (before.isNotEmpty && !await _confirmReplace()) return;
    _message.text = value;
    session.setDraft(value);
    setState(() {});
  }

  Future<void> _recent() async {
    try {
      final page = await session.client.history(session.repository, limit: 20);
      if (!mounted) return;
      final value = await host.present<String>(
        context,
        'Recent messages',
        SizedBox(
          height: 350,
          child: ListView(
            children: [
              for (final commit in page.commits)
                ListTile(
                  title: Text(commit.subject),
                  onTap: () => Navigator.of(context).pop(commit.message),
                ),
            ],
          ),
        ),
        expanded: false,
      );
      if (!mounted || value == null) return;
      if (_message.text.isNotEmpty && !await _confirmReplace()) return;
      _message.text = value;
      session.setDraft(value);
      setState(() {});
    } on Object catch (error) {
      session.reportFailure(error);
    }
  }

  Future<bool> _confirmReplace() async =>
      await host.present<bool>(
        context,
        'Replace message draft?',
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GitLabel(
              'Replace the existing commit message with the selected message?',
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const GitLabel('Replace draft'),
            ),
          ],
        ),
        expanded: false,
      ) ==
      true;
  Future<void> _commit(bool push) async {
    if (!_canCommit()) return;
    final snapshot = session.snapshot;
    if (snapshot == null) return;
    final message = _message.text, revision = session.draftRevision;
    final result = await session.mutate(
      CommitIndex(
        message,
        expectedHead: snapshot.head,
        expectedIndex: snapshot.indexToken,
        amend: _amend,
        signOff: _signOff,
        sign: _sign,
      ),
    );
    if (!mounted || result == null) return;
    if (result.error?.code == GitErrorCode.authorIdentity) {
      await _identity();
      return;
    }
    if (result.createdCommit != null &&
        result.completed &&
        result.error == null) {
      if (_message.text == message && session.draftRevision == revision) {
        _message.clear();
        session.setDraft('');
      }
      host.notify('Local commit ${result.createdCommit!.abbreviated} exists.');
      setState(() => _amend = false);
      if (push) widget.onPush();
    } else if (result.createdCommit != null) {
      host.notify(
        'Local commit ${result.createdCommit!.abbreviated} exists. Review Log before attempting another commit. The message draft has been retained.',
      );
    }
  }
}

final class GitIdentityView extends StatefulWidget {
  const GitIdentityView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitIdentityView> createState() => _IdentityState();
}

final class _IdentityState extends GitDialogState<GitIdentityView> {
  @override
  GitSession get session => widget.session;
  final name = TextEditingController(), email = TextEditingController();
  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await load(const GitInspection(GitInspectionKind.commitOptions));
    if (mounted && data != null)
      setState(() {
        name.text = data!['name'] as String? ?? '';
        email.text = data!['email'] as String? ?? '';
      });
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      states(),
      TextField(
        controller: name,
        decoration: InputDecoration(
          labelText: gitString(context, 'Commit author name'),
        ),
      ),
      TextField(
        controller: email,
        decoration: InputDecoration(
          labelText: gitString(context, 'Commit author email'),
        ),
      ),
      Text(
        'Signing: ${data?['signing'] ?? 'configured default'} · ${data?['signingFormat'] ?? 'OpenPGP'}',
      ),
      SelectableText(
        'Configured hooks: ${(data?['hooks'] as List? ?? []).join(', ')}',
      ),
      const GitLabel(
        'A sign-off trailer is a statement in the message. It is separate from a cryptographic signature. Saving identity changes repository-local configuration only; your draft is retained.',
      ),
      FilledButton(
        onPressed: loading
            ? null
            : () async {
                final s = session.snapshot!;
                final result = await apply(
                  ConfigureIdentity(
                    name.text,
                    email.text,
                    expectedHead: s.head,
                    expectedIndex: s.indexToken,
                  ),
                );
                if (mounted && result?.completed == true)
                  Navigator.of(context).pop();
              },
        child: const GitLabel('Save repository identity'),
      ),
    ],
  );
}

final class GitChangeTree extends StatefulWidget {
  const GitChangeTree({
    super.key,
    required this.session,
    required this.onReview,
    this.selectedComparison,
    this.active = true,
    this.reviewContext,
  });
  final GitSession session;
  final ValueChanged<GitComparison> onReview;
  final GitComparison? selectedComparison;
  final bool active;
  final Object? Function()? reviewContext;
  @override
  State<GitChangeTree> createState() => _GitChangeTreeState();
}

final class _GitChangeTreeState extends State<GitChangeTree> {
  bool _preparingStage = false;
  final _collapsed = <String>{}, _selected = <String>{};
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'Git changes');
  final _contextMenuKeys = GitContextMenuKeys();
  List<_ChangeRow>? _cachedRows;
  Set<String> _rowKeys = {};
  String? _cachedKey;
  int _focused = 0, _anchor = 0;
  int _selectionGeneration = 0;
  @override
  void didUpdateWidget(GitChangeTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.selectedComparison;
    if (target == null || target == oldWidget.selectedComparison) return;
    _selectionGeneration++;
    final group = target.right.kind == ContentKind.indexVersion
        ? 'Staged'
        : widget.session.snapshot?.changes.any(
                (c) => c.path == target.path && c.untracked,
              ) ==
              true
        ? 'Untracked'
        : 'Unstaged';
    _selected
      ..clear()
      ..add('$group:${target.path.key}');
    _collapsed.remove(group);
    _collapsed.remove('$group/${target.path.parent}');
    final index = _rows().indexWhere(
      (r) => r.key == '$group:${target.path.key}',
    );
    if (index >= 0) {
      _focused = _anchor = index;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _contextMenuKeys.clear();
    _focus.dispose();
    super.dispose();
  }

  List<_ChangeRow> _rows() {
    final collapsed = _collapsed.toList()..sort();
    final key = '${widget.session.snapshot?.token}:${collapsed.join('\u0000')}';
    if (_cachedKey == key && _cachedRows != null) return _cachedRows!;
    final rows = <_ChangeRow>[];
    final changes = widget.session.snapshot?.changes ?? [];
    final groups = {
      'Conflicts': changes.where((e) => e.conflicted),
      'Staged': changes.where((e) => e.staged),
      'Unstaged': changes.where((e) => e.unstaged),
      'Untracked': changes.where((e) => e.untracked),
    };
    for (final group in groups.entries) {
      final entries = group.value.toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (entries.isEmpty && group.key != 'Staged') continue;
      rows.add(
        _ChangeRow(
          group.key,
          '${group.key} (${entries.length})',
          group.key,
          null,
          0,
          count: entries.length,
        ),
      );
      if (_collapsed.contains(group.key)) continue;
      String? parent;
      for (final change in entries) {
        final directory = change.path.parent;
        if (directory.isNotEmpty && directory != parent) {
          rows.add(
            _ChangeRow(
              '${group.key}/$directory',
              directory,
              group.key,
              null,
              1,
            ),
          );
          parent = directory;
        }
        if (!_collapsed.contains('${group.key}/$directory'))
          rows.add(
            _ChangeRow(
              '${group.key}:${change.path.key}',
              change.path.basename,
              group.key,
              change,
              directory.isEmpty ? 1 : 2,
            ),
          );
      }
    }
    _cachedKey = key;
    _rowKeys = rows.map((r) => r.key).toSet();
    return _cachedRows = rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows(), host = widget.session.host;
    _selected.removeWhere((key) => !_rowKeys.contains(key));
    _focused = _focused.clamp(0, rows.isEmpty ? 0 : rows.length - 1);
    if (rows.length == 1 && rows.first.change == null)
      return const Center(child: GitLabel('No changes'));
    final parents = <int>[];
    final ancestors = <int>[];
    for (var i = 0; i < rows.length; i++) {
      while (ancestors.isNotEmpty &&
          rows[ancestors.last].depth >= rows[i].depth) {
        ancestors.removeLast();
      }
      parents.add(ancestors.lastOrNull ?? -1);
      if (rows[i].change == null) ancestors.add(i);
    }
    return LayoutBuilder(
      builder: (context, bounds) => GitNativeTable(
        name: gitString(context, 'Repository change tree'),
        description: widget.session.repository.root,
        revision: (widget.session.repository.key, _cachedKey),
        active: widget.active,
        tree: true,
        headers: false,
        busy: widget.session.running,
        rowCount: rows.length,
        columns: [gitString(context, 'Changes')],
        widths: [bounds.maxWidth],
        rowHeight: host.rowHeight(context),
        rowAt: (index) {
          final row = rows[index], change = row.change;
          final canStage =
              change != null &&
              !change.conflicted &&
              !widget.session.running &&
              !_preparingStage &&
              widget.session.canWriteMetadata;
          return GitNativeRow(
            id: row.key,
            textInsets: [
              (Directionality.of(context) == TextDirection.rtl
                      ? host.spacing
                      : row.depth * host.spacing * 2) +
                  (change == null ? 16 : 22),
            ],
            cells: [
              change == null && row.depth == 0
                  ? gitString(
                      context,
                      '{group} ({count})',
                      values: {
                        'group': gitString(context, row.group),
                        'count': row.count,
                      },
                    )
                  : row.label,
            ],
            description: change == null
                ? ''
                : '${change.path.display}, ${gitString(context, row.group)}, '
                      '${change.index}${change.worktree}',
            parent: parents[index],
            depth: row.depth,
            expanded: change == null
                ? (_collapsed.contains(row.key) ? 0 : 1)
                : -1,
            actions: {
              if (change == null)
                'toggle': gitString(
                  context,
                  _collapsed.contains(row.key) ? 'Expand' : 'Collapse',
                ),
              if (canStage)
                'stage': gitString(
                  context,
                  row.group == 'Staged' ? 'Unstage file' : 'Stage file',
                ),
            },
          );
        },
        selected: [
          for (var i = 0; i < rows.length; i++)
            if (_selected.contains(rows[i].key)) i,
        ],
        focusedRow: rows.isEmpty ? -1 : _focused,
        scroll: _scroll,
        focus: _focus,
        onRequest: (request) => _nativeRequest(request, rows),
        builder: (nativeReady) => Focus(
          focusNode: _focus,
          onFocusChange: (focused) {
            if (!focused) _contextMenuKeys.clear();
          },
          onKeyEvent: (_, event) {
            final target = rows.isEmpty ? null : rows[_focused];
            final revision = _cachedKey, selection = _selectionGeneration;
            if (_contextMenuKeys.handle(
              event,
              target == null
                  ? null
                  : () {
                      if (!mounted) return;
                      final current = _rows();
                      if (widget.active &&
                          _focus.hasFocus &&
                          _cachedKey == revision &&
                          _selectionGeneration == selection &&
                          _focused < current.length &&
                          current[_focused].key == target.key) {
                        unawaited(_context(target, current));
                      }
                    },
            )) {
              return KeyEventResult.handled;
            }
            if (event is! KeyDownEvent || rows.isEmpty)
              return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.keyA &&
                HardwareKeyboard.instance.isControlPressed) {
              setState(() {
                _selected
                  ..clear()
                  ..addAll(
                    rows.where((r) => r.change != null).map((r) => r.key),
                  );
              });
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.home ||
                event.logicalKey == LogicalKeyboardKey.end) {
              _select(
                rows,
                event.logicalKey == LogicalKeyboardKey.home
                    ? 0
                    : rows.length - 1,
              );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              final row = rows[_focused],
                  expand = event.logicalKey == LogicalKeyboardKey.arrowRight;
              if (row.change == null) {
                setState(() {
                  if (expand) {
                    _collapsed.remove(row.key);
                  } else {
                    _collapsed.add(row.key);
                  }
                });
              } else if (!expand) {
                final parent = rows.lastIndexWhere(
                  (r) =>
                      r.change == null &&
                      r.group == row.group &&
                      r.depth < row.depth,
                  _focused,
                );
                if (parent >= 0) _select(rows, parent);
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _select(
                rows,
                (_focused +
                        (event.logicalKey == LogicalKeyboardKey.arrowDown
                            ? 1
                            : -1))
                    .clamp(0, rows.length - 1),
              );
              final offset = _focused * host.rowHeight(context);
              if (_scroll.hasClients)
                _scroll.animateTo(
                  offset.clamp(0, _scroll.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.linear,
                );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              _activate(rows[_focused]);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.space &&
                rows[_focused].change != null) {
              unawaited(_stage(rows[_focused].group == 'Staged', rows));
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ExcludeFocus(
            // The native tree is one keyboard focus stop. Its existing row
            // keys and native cell actions cover review, staging and menus.
            excluding: nativeReady,
            child: ExcludeSemantics(
              excluding: nativeReady,
              child: CustomScrollView(
                controller: _scroll,
                semanticChildCount: rows.length,
                slivers: [
                  SliverSemantics(
                    role: SemanticsRole.list,
                    label: gitString(context, 'Repository change tree'),
                    container: true,
                    explicitChildNodes: true,
                    sliver: SliverFixedExtentList(
                      itemExtent: host.rowHeight(context),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final row = rows[index], change = row.change;
                          return Semantics(
                            role: SemanticsRole.listItem,
                            container: true,
                            expanded: change == null
                                ? !_collapsed.contains(row.key)
                                : null,
                            selected: _selected.contains(row.key),
                            label: change == null
                                ? row.depth == 0
                                      ? gitString(
                                          context,
                                          '{group} ({count})',
                                          values: {
                                            'group': gitString(
                                              context,
                                              row.group,
                                            ),
                                            'count': row.count,
                                          },
                                        )
                                      : row.label
                                : '${change.path.display}, ${gitString(context, row.group)}, ${change.index}${change.worktree}',
                            child: InkWell(
                              onTap: () {
                                _select(rows, index);
                                _activate(row);
                              },
                              onDoubleTap: change == null
                                  ? null
                                  : () => unawaited(
                                      host.openDocument(
                                        widget.session.repository,
                                        change.path,
                                      ),
                                    ),
                              onSecondaryTapUp: (details) {
                                if (!_selected.contains(row.key))
                                  _select(rows, index);
                                unawaited(
                                  _context(
                                    row,
                                    rows,
                                    position: details.globalPosition,
                                  ),
                                );
                              },
                              child: ColoredBox(
                                color: _selected.contains(row.key)
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : Colors.transparent,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: row.depth * host.spacing * 2,
                                    right: host.spacing,
                                  ),
                                  child: Row(
                                    children: [
                                      if (change == null)
                                        GitIcon(
                                          _collapsed.contains(row.key)
                                              ? GitGlyph.next
                                              : GitGlyph.expand,
                                          size: 16,
                                        )
                                      else
                                        SizedBox(
                                          width: 22,
                                          child: Text(
                                            change.conflicted
                                                ? '!'
                                                : change.untracked
                                                ? '?'
                                                : row.group == 'Staged'
                                                ? change.index
                                                : change.worktree,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ),
                                      Expanded(
                                        child: change == null && row.depth == 0
                                            ? GitLabel(
                                                '{group} ({count})',
                                                values: {
                                                  'group': gitString(
                                                    context,
                                                    row.group,
                                                  ),
                                                  'count': row.count,
                                                },
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              )
                                            : Text(
                                                row.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: change == null
                                                    ? const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      )
                                                    : null,
                                              ),
                                      ),
                                      if (change != null && !change.conflicted)
                                        GitIconButton(
                                          tooltip: row.group == 'Staged'
                                              ? 'Unstage file'
                                              : 'Stage file',
                                          onPressed:
                                              widget.session.running ||
                                                  _preparingStage ||
                                                  !widget
                                                      .session
                                                      .canWriteMetadata
                                              ? null
                                              : () {
                                                  if (!_selected.contains(
                                                    row.key,
                                                  ))
                                                    _select(rows, index);
                                                  unawaited(
                                                    _stage(
                                                      row.group == 'Staged',
                                                      rows,
                                                    ),
                                                  );
                                                },
                                          icon: GitIcon(
                                            row.group == 'Staged'
                                                ? GitGlyph.remove
                                                : GitGlyph.add,
                                            size: 16,
                                          ),
                                        ),
                                    ],
                                  ),
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
            ),
          ),
        ),
      ),
    );
  }

  void _nativeRequest(GitNativeTableRequest request, List<_ChangeRow> rows) {
    final index = request.row;
    switch (request.action) {
      case 'clearSelection':
        setState(_selected.clear);
      case 'selectAll':
        setState(
          () => _selected.addAll(
            rows.where((r) => r.change != null).map((r) => r.key),
          ),
        );
      case 'select' || 'focus':
        _focus.requestFocus();
        _select(rows, index, keyboardModifiers: false);
        _scrollToNativeRow(index);
        if (rows[index].change != null) _activate(rows[index]);
      case 'scroll':
        _scrollToNativeRow(index);
      case 'context':
        if (!_selected.contains(rows[index].key)) {
          _select(rows, index, keyboardModifiers: false);
        }
        unawaited(_context(rows[index], rows));
      case 'addSelection':
        setState(() => _selected.add(rows[index].key));
      case 'removeSelection':
        setState(() => _selected.remove(rows[index].key));
      case 'toggle':
        _activate(rows[index]);
      case 'stage':
        // The named row action applies to exactly this file. Multi-selection
        // staging remains available in the existing contextual selection menu.
        unawaited(
          _stage(
            rows[index].group == 'Staged',
            rows,
            selection: {rows[index].key},
          ),
        );
    }
  }

  void _scrollToNativeRow(int index) {
    if (!_scroll.hasClients) return;
    final height = widget.session.host.rowHeight(context);
    final start = index * height, end = start + height;
    final position = _scroll.position;
    if (start < position.pixels ||
        end > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(start.clamp(0, position.maxScrollExtent));
    }
  }

  void _select(
    List<_ChangeRow> rows,
    int index, {
    bool keyboardModifiers = true,
  }) {
    _focus.requestFocus();
    _selectionGeneration++;
    setState(() {
      _focused = index;
      if (keyboardModifiers && HardwareKeyboard.instance.isShiftPressed) {
        _selected.clear();
        for (
          var i = _anchor < index ? _anchor : index;
          i <= (_anchor > index ? _anchor : index);
          i++
        ) {
          if (rows[i].change != null) _selected.add(rows[i].key);
        }
      } else if (keyboardModifiers &&
          HardwareKeyboard.instance.isControlPressed) {
        if (!_selected.add(rows[index].key)) _selected.remove(rows[index].key);
      } else {
        _selected
          ..clear()
          ..add(rows[index].key);
        _anchor = index;
      }
    });
  }

  void _activate(_ChangeRow row) {
    if (row.change == null) {
      setState(() {
        if (!_collapsed.add(row.key)) _collapsed.remove(row.key);
      });
      return;
    }
    final snapshot = widget.session.snapshot!;
    if (row.change!.conflicted) {
      unawaited(
        GitWorkflowUi(context, widget.session).conflict(row.change!.path),
      );
      return;
    }
    widget.onReview(
      gitStatusComparison(snapshot, row.change!, staged: row.group == 'Staged'),
    );
  }

  Future<void> _stage(
    bool unstage,
    List<_ChangeRow> rows, {
    GitSnapshot? reviewed,
    Set<String>? selection,
  }) async {
    if (_preparingStage ||
        widget.session.running ||
        !widget.session.canWriteMetadata)
      return;
    final snapshot = reviewed ?? widget.session.snapshot!,
        keys = selection ?? _selected;
    final chosen = rows
        .where(
          (row) =>
              keys.contains(row.key) &&
              row.change != null &&
              !row.change!.conflicted &&
              (unstage ? row.group == 'Staged' : row.group != 'Staged'),
        )
        .toList();
    final paths = {
      for (final row in chosen) ...[
        row.change!.path,
        if (unstage &&
            row.change!.index == 'R' &&
            row.change!.originalPath != null)
          row.change!.originalPath!,
      ],
    }.toList();
    if (paths.isEmpty) return;
    final selectionGeneration = _selectionGeneration;
    final reviewContext = widget.reviewContext?.call();
    setState(() => _preparingStage = true);
    try {
      final tokens = <String, String>{};
      if (!unstage)
        for (final path in paths) {
          final content = await widget.session.client.content(
            widget.session.repository,
            path,
            const ContentVersion.working(),
          );
          tokens[path.key] = content.token;
        }
      if (!mounted) return;
      final result = await widget.session.mutate(
        StagePaths(
          paths,
          expectedHead: snapshot.head,
          expectedIndex: snapshot.indexToken,
          unstage: unstage,
          contentTokens: tokens,
          expectedSnapshot: snapshot.token,
        ),
      );
      if (mounted &&
          result?.completed == true &&
          widget.active &&
          selectionGeneration == _selectionGeneration &&
          reviewContext == widget.reviewContext?.call()) {
        final refreshed = _rows(),
            chosenKeys = chosen.map((r) => r.key).toSet();
        final retained = chosenKeys.intersection(_rowKeys);
        var focused = refreshed.indexWhere((r) => retained.contains(r.key));
        if (focused < 0)
          focused = refreshed.indexWhere(
            (r) => r.change != null && paths.contains(r.change!.path),
          );
        if (focused < 0 && refreshed.any((r) => r.change != null)) {
          focused = _focused.clamp(0, refreshed.length - 1);
          while (focused < refreshed.length &&
              refreshed[focused].change == null) {
            focused++;
          }
          if (focused == refreshed.length)
            focused = refreshed.lastIndexWhere((r) => r.change != null);
        }
        if (focused >= 0) {
          setState(() {
            _focused = _anchor = focused;
            _selected
              ..clear()
              ..addAll(retained.isEmpty ? {refreshed[focused].key} : retained);
          });
          _activate(refreshed[focused]);
        }
      }
    } on Object catch (error) {
      widget.session.reportFailure(error);
    } finally {
      if (mounted) setState(() => _preparingStage = false);
    }
  }

  Future<void> _context(
    _ChangeRow row,
    List<_ChangeRow> rows, {
    Offset? position,
  }) async {
    final session = widget.session, reviewed = widget.session.snapshot!;
    final selection = Set<String>.from(_selected), change = row.change;
    final writable = !session.running && session.canWriteMetadata;
    final action = await session.host.menu(context, row.label, [
      GitMenuEntry(
        'review',
        change == null
            ? _collapsed.contains(row.key)
                  ? 'Expand group'
                  : 'Collapse group'
            : 'Review difference',
      ),
      if (change != null && !change.conflicted)
        GitMenuEntry(
          'stage',
          row.group == 'Staged'
              ? 'Unstage selected files'
              : 'Stage selected files',
          enabled: writable,
        ),
      if (change != null && reviewed.head != null)
        const GitMenuEntry('history', 'File history and blame…'),
      if (change != null && row.group != 'Staged' && !change.conflicted)
        GitMenuEntry(
          'discard',
          change.untracked
              ? 'Delete untracked file…'
              : 'Discard unstaged change…',
          enabled: writable,
          sectionStart: true,
        ),
    ], position: position);
    if (!mounted || action == null) return;
    switch (action) {
      case 'review':
        _activate(row);
      case 'stage':
        await _stage(
          row.group == 'Staged',
          rows,
          reviewed: reviewed,
          selection: selection,
        );
      case 'history':
        await GitWorkflowUi(context, session).present(
          'File history',
          GitFileHistoryView(session: session, path: change!.path),
          expanded: true,
        );
      case 'discard':
        GitContent working;
        try {
          working = await session.client.content(
            session.repository,
            change!.path,
            const ContentVersion.working(),
          );
        } on Object catch (error) {
          session.reportFailure(error);
          return;
        }
        if (!mounted ||
            !await gitConfirm(
              context,
              session,
              'Discard unstaged ${change.path.display}?',
              '${working.size} bytes · ${working.availability.name}\nReplaces working content with the index, or deletes this untracked file. Staged content is retained. Unsaved host documents must be reviewed first.',
              action: change.untracked
                  ? 'Delete untracked file'
                  : 'Discard working change',
            ))
          return;
        await session.mutate(
          RestorePaths(
            [change.path],
            discardUntracked: change.untracked,
            expectedHead: reviewed.head,
            expectedIndex: reviewed.indexToken,
            contentTokens: {change.path.key: working.token},
          ),
        );
    }
  }
}

GitComparison gitStatusComparison(
  GitSnapshot snapshot,
  GitChange change, {
  required bool staged,
}) => GitComparison(
  change.path,
  staged
      ? snapshot.head == null
            ? const ContentVersion.absent()
            : ContentVersion(ContentKind.commit, revision: snapshot.head)
      : const ContentVersion.index(),
  staged ? const ContentVersion.index() : const ContentVersion.working(),
  leftPath: staged
      ? change.originalPath
      : change.worktree == 'R'
      ? change.originalPath
      : null,
);

List<GitComparison> gitStatusComparisons(GitSnapshot? snapshot) {
  if (snapshot == null) return const [];
  final files =
      snapshot.changes.where((c) => !c.conflicted && !c.directory).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files.where((c) => c.staged))
      gitStatusComparison(snapshot, file, staged: true),
    for (final file in files.where((c) => c.unstaged || c.untracked))
      gitStatusComparison(snapshot, file, staged: false),
  ];
}

int gitComparisonIndex(
  List<GitComparison> comparisons,
  GitComparison? selected,
) => comparisons.indexWhere(
  (c) =>
      c.path == selected?.path &&
      c.left.kind == selected?.left.kind &&
      c.right.kind == selected?.right.kind,
);

final class _ChangeRow {
  const _ChangeRow(
    this.key,
    this.label,
    this.group,
    this.change,
    this.depth, {
    this.count = 0,
  });
  final String key, label, group;
  final int count;
  final GitChange? change;
  final int depth;
}
