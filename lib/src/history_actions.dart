import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'diff_view.dart';
import 'host.dart';
import 'network_views.dart';
import 'session.dart';
import 'workflow_ui.dart';

final class GitHistoryActions {
  const GitHistoryActions(this.ui);
  final GitWorkflowUi ui;
  GitSession get session => ui.session;
  BuildContext get context => ui.context;
  Future<void> run(GitCommit commit, String action) async {
    final reviewed = session.snapshot!;
    switch (action) {
      case 'Create branch':
        final name = await gitTextInput(
          context,
          session,
          'Branch at ${commit.oid.abbreviated}',
          explanation: 'Creates a local branch without checking it out.',
        );
        if (name == null || name.isEmpty) return;
        await session.mutate(
          BranchMutation(
            BranchAction.create,
            name,
            start: commit.oid,
            expectedHead: reviewed.head,
            expectedIndex: reviewed.indexToken,
          ),
        );
      case 'Create tag':
        await ui.present(
          'Tag ${commit.oid.abbreviated}',
          GitTagView(session: session, target: commit.oid),
        );
      case 'Compare revisions':
        await compare(commit.oid, null);
      case 'Open snapshot':
        await ui.present(
          'Read-only snapshot · ${commit.oid.abbreviated}',
          GitSnapshotView(session: session, revision: commit.oid),
          expanded: true,
        );
      case 'Cherry-pick':
        await ui.present(
          'Cherry-pick commits',
          GitCherryPickView(session: session, commits: [commit]),
          expanded: true,
        );
      case 'Revert commit':
        await ui.present(
          'Revert commits',
          GitCherryPickView(session: session, commits: [commit], revert: true),
          expanded: true,
        );
      case 'Interactive rebase after this boundary':
        await ui.rebase(boundary: commit.oid);
      case 'Reset current branch':
        await reset(commit.oid);
    }
  }

  Future<void> compare(GitOid left, GitOid? right) async {
    if (right == null) {
      final input = await gitTextInput(
        context,
        session,
        'Compare to full revision ID',
        initial: session.snapshot?.head?.value ?? '',
        explanation:
            'Tree comparison direction: ${left.abbreviated} → the revision entered here.',
      );
      if (input == null) return;
      try {
        right = GitOid(input);
      } on FormatException {
        session.host.notify('Enter a full valid object ID.');
        return;
      }
    }
    if (!context.mounted) return;
    await ui.present(
      '${left.abbreviated} → ${right.abbreviated} · tree comparison',
      GitRevisionComparison(session: session, left: left, right: right),
      expanded: true,
    );
  }

  Future<void> reset(GitOid target) async {
    final state = session.snapshot!;
    final mode = await session.host.present<ResetMode>(
      context,
      'Reset ${state.branch ?? 'HEAD'} to ${target.abbreviated}',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GitLabel(
            'Moves HEAD/current branch. Reflog does not recover arbitrary untracked or unsaved content.',
          ),
          for (final mode in ResetMode.values)
            ListTile(
              title: Text(mode.name),
              subtitle: Text(switch (mode) {
                ResetMode.soft => 'Move HEAD; keep index and working files.',
                ResetMode.mixed =>
                  'Move HEAD and replace index; keep working files.',
                ResetMode.hard =>
                  'Replace HEAD, index and tracked working files; may overwrite obstructing untracked files.',
                ResetMode.keep =>
                  'Replace HEAD/index and eligible files; refuse if local changes would be lost.',
              }),
              onTap: () => Navigator.of(context).pop(mode),
            ),
        ],
      ),
      expanded: false,
    );
    if (mode == null || !context.mounted) return;
    if (!await gitConfirm(
      context,
      session,
      'Reset with ${mode.name}?',
      '${state.head?.value} → ${target.value}\nReview the selected mode’s effects before applying.',
      action: 'Reset ${mode.name}',
    ))
      return;
    await session.mutate(
      ResetBranch(
        target,
        mode,
        expectedHead: state.head,
        expectedIndex: state.indexToken,
        expectedWorkingToken: state.token,
      ),
    );
  }
}

final class GitTagView extends StatefulWidget {
  const GitTagView({super.key, required this.session, required this.target});
  final GitSession session;
  final GitOid target;
  @override
  State<GitTagView> createState() => _TagState();
}

final class _TagState extends GitDialogState<GitTagView> {
  @override
  GitSession get session => widget.session;
  final name = TextEditingController(), message = TextEditingController();
  bool annotated = false;
  bool? sign;
  @override
  void dispose() {
    name.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SelectableText('Target ${widget.target.value}'),
      states(),
      TextField(
        controller: name,
        decoration: InputDecoration(labelText: gitString(context, 'Tag name')),
      ),
      CheckboxListTile(
        value: annotated,
        title: const GitLabel('Annotated tag'),
        onChanged: (v) => setState(() => annotated = v!),
      ),
      DropdownButtonFormField<int>(
        initialValue: 0,
        decoration: InputDecoration(
          labelText: gitString(context, 'Cryptographic signing'),
        ),
        items: const [
          DropdownMenuItem(value: 0, child: GitLabel('Configured policy')),
          DropdownMenuItem(value: 1, child: GitLabel('Sign this tag')),
          DropdownMenuItem(value: 2, child: GitLabel('Do not sign')),
        ],
        onChanged: (v) => setState(() {
          sign = v == 0 ? null : v == 1;
          if (sign == true) annotated = true;
        }),
      ),
      if (annotated)
        TextField(
          controller: message,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: gitString(context, 'Tag message'),
          ),
        ),
      const GitLabel(
        'Creates the tag locally. Publish selected tags explicitly in Push review.',
      ),
      FilledButton(
        onPressed: loading
            ? null
            : () async {
                final s = session.snapshot!;
                final result = await apply(
                  TagMutation(
                    TagAction.create,
                    name.text,
                    target: widget.target,
                    annotated: annotated,
                    sign: sign,
                    message: message.text,
                    expectedHead: s.head,
                    expectedIndex: s.indexToken,
                  ),
                );
                if (mounted && result?.completed == true)
                  Navigator.of(context).pop();
              },
        child: const GitLabel('Create tag'),
      ),
    ],
  );
}

final class GitRevisionComparison extends StatefulWidget {
  const GitRevisionComparison({
    super.key,
    required this.session,
    required this.left,
    required this.right,
  });
  final GitSession session;
  final GitOid left, right;
  @override
  State<GitRevisionComparison> createState() => _ComparisonState();
}

final class _ComparisonState extends GitDialogState<GitRevisionComparison> {
  int offset = 0;
  @override
  GitSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    unawaited(
      load(
        GitInspection(
          GitInspectionKind.compareRevisions,
          revision: widget.right,
          otherRevision: widget.left,
          limit: 300,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(),
      Text(
        'Complete trees: ${widget.left.abbreviated} → ${widget.right.abbreviated}',
      ),
      Expanded(
        child: ListView(
          children: [
            for (final row in (data?['changes'] as List? ?? []).cast<Json>())
              Builder(
                builder: (context) {
                  final change = GitChange.fromJson(row);
                  return ListTile(
                    dense: true,
                    leading: Text(change.index),
                    title: Text(change.path.display),
                    onTap: () => session.host.present<void>(
                      context,
                      change.path.display,
                      GitDiffView(
                        session: session,
                        comparison: GitComparison(
                          change.path,
                          ContentVersion(
                            ContentKind.commit,
                            revision: widget.left,
                          ),
                          ContentVersion(
                            ContentKind.commit,
                            revision: widget.right,
                          ),
                          leftPath: change.originalPath,
                        ),
                      ),
                      expanded: true,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      if (data?['hasMore'] == true)
        TextButton(
          onPressed: () {
            offset += 300;
            unawaited(
              load(
                GitInspection(
                  GitInspectionKind.compareRevisions,
                  revision: widget.right,
                  otherRevision: widget.left,
                  offset: offset,
                  limit: 300,
                ),
              ),
            );
          },
          child: const GitLabel('Next changed-file page'),
        ),
    ],
  );
}

final class GitSnapshotView extends StatefulWidget {
  const GitSnapshotView({
    super.key,
    required this.session,
    required this.revision,
  });
  final GitSession session;
  final GitOid revision;
  @override
  State<GitSnapshotView> createState() => _SnapshotState();
}

final class _SnapshotState extends GitDialogState<GitSnapshotView> {
  @override
  GitSession get session => widget.session;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() => load(
    GitInspection(
      GitInspectionKind.tree,
      revision: widget.revision,
      offset: offset,
      limit: 200,
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(),
      const GitLabel(
        'Read-only repository snapshot. Opening a file never checks out this revision.',
      ),
      Expanded(
        child: ListView(
          children: [
            for (final row in (data?['entries'] as List? ?? []).cast<Json>())
              Builder(
                builder: (context) {
                  final entry = IndexEntry.fromJson(row);
                  return ListTile(
                    dense: true,
                    title: Text(entry.path.display),
                    subtitle: Text('${entry.mode} · ${entry.oid.abbreviated}'),
                    trailing: GitMenuButton(
                      host: session.host,
                      onSelected: (action) => unawaited(open(entry, action)),
                      entries: const [
                        GitMenuEntry('open', 'Open read-only version'),
                        GitMenuEntry('history', 'File history and blame…'),
                        const GitMenuEntry.separator(),
                        GitMenuEntry('restore', 'Restore this path…'),
                      ],
                    ),
                    onTap: () => unawaited(open(entry, 'open')),
                  );
                },
              ),
          ],
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: offset == 0
                ? null
                : () {
                    offset = (offset - 200).clamp(0, 1000000);
                    unawaited(refresh());
                  },
            child: const GitLabel('Previous page'),
          ),
          TextButton(
            onPressed: data?['hasMore'] != true
                ? null
                : () {
                    offset += 200;
                    unawaited(refresh());
                  },
            child: const GitLabel('Next page'),
          ),
        ],
      ),
    ],
  );
  Future<void> open(IndexEntry entry, String action) async {
    if (action == 'history') {
      await GitWorkflowUi(context, session).present(
        'History · ${entry.path.display}',
        GitFileHistoryView(
          session: session,
          path: entry.path,
          revision: widget.revision,
        ),
        expanded: true,
      );
      return;
    }
    if (action == 'restore') {
      final s = session.snapshot!;
      final working = await query(
        () => session.client.content(
          session.repository,
          entry.path,
          const ContentVersion.working(),
        ),
      );
      if (!mounted || working == null) return;
      if (!await gitConfirm(
        context,
        session,
        'Restore ${entry.path.display}?',
        'Replace this working path with revision ${widget.revision.value}. Existing staged content is retained.',
        action: 'Restore working file',
      ))
        return;
      await apply(
        RestorePaths(
          [entry.path],
          revision: widget.revision,
          expectedHead: s.head,
          expectedIndex: s.indexToken,
          contentTokens: {entry.path.key: working.token},
        ),
      );
      return;
    }
    try {
      final content = await session.client.content(
        session.repository,
        entry.path,
        ContentVersion(ContentKind.commit, revision: widget.revision),
      );
      await session.host.openDocument(
        session.repository,
        entry.path,
        snapshot: content,
      );
    } on GitException catch (failure) {
      if (mounted) setState(() => error = failure);
    }
  }
}

final class GitFileHistoryView extends StatefulWidget {
  const GitFileHistoryView({
    super.key,
    required this.session,
    required this.path,
    this.revision,
  });
  final GitSession session;
  final RepoPath path;
  final GitOid? revision;
  @override
  State<GitFileHistoryView> createState() => _FileHistoryState();
}

final class _FileHistoryState extends GitDialogState<GitFileHistoryView> {
  @override
  GitSession get session => widget.session;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() => load(
    GitInspection(
      GitInspectionKind.fileHistory,
      path: widget.path,
      revision: widget.revision,
      offset: offset,
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(),
      Row(
        children: [
          Expanded(
            child: Text(
              'File history follows renames · ${widget.path.display}',
            ),
          ),
          TextButton(
            onPressed: () => GitWorkflowUi(context, session).present(
              'Blame · committed content',
              GitBlameView(
                session: session,
                path: widget.path,
                revision: widget.revision ?? session.snapshot!.head!,
              ),
              expanded: true,
            ),
            child: const GitLabel('Blame…'),
          ),
        ],
      ),
      Expanded(
        child: ListView(
          children: [
            for (final row in (data?['entries'] as List? ?? []).cast<Json>())
              Builder(
                builder: (context) {
                  final commit = GitCommit.fromJson(row['commit'] as Json),
                      path = RepoPath.fromJson(row['pathAtCommit']);
                  return ListTile(
                    dense: true,
                    title: Text(commit.subject),
                    subtitle: Text(
                      '${commit.oid.abbreviated} · ${commit.author} · ${path.display}',
                    ),
                    trailing: GitMenuButton(
                      host: session.host,
                      onSelected: (action) async {
                        if (action == 'open') {
                          final value = await session.client.content(
                            session.repository,
                            path,
                            ContentVersion(
                              ContentKind.commit,
                              revision: commit.oid,
                            ),
                          );
                          await session.host.openDocument(
                            session.repository,
                            path,
                            snapshot: value,
                          );
                        } else if (action == 'current') {
                          await session.host.present<void>(
                            context,
                            '${commit.oid.abbreviated} → Working Tree',
                            GitDiffView(
                              session: session,
                              comparison: GitComparison(
                                widget.path,
                                ContentVersion(
                                  ContentKind.commit,
                                  revision: commit.oid,
                                ),
                                const ContentVersion.working(),
                                leftPath: path,
                              ),
                            ),
                            expanded: true,
                          );
                        } else {
                          await GitWorkflowUi(context, session).present(
                            'Commit ${commit.oid.abbreviated}',
                            GitCommitFiles(session: session, commit: commit),
                            expanded: true,
                          );
                        }
                      },
                      entries: const [
                        GitMenuEntry('open', 'Open read-only historical file'),
                        GitMenuEntry('current', 'Compare to current file'),
                        GitMenuEntry('parent', 'Compare to parent…'),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      Row(
        children: [
          TextButton(
            onPressed: offset == 0
                ? null
                : () {
                    offset = (offset - 100).clamp(0, 1000000);
                    unawaited(refresh());
                  },
            child: const GitLabel('Previous page'),
          ),
          TextButton(
            onPressed: data?['hasMore'] != true
                ? null
                : () {
                    offset += 100;
                    unawaited(refresh());
                  },
            child: const GitLabel('Next page'),
          ),
        ],
      ),
    ],
  );
}

final class GitBlameView extends StatefulWidget {
  const GitBlameView({
    super.key,
    required this.session,
    required this.path,
    required this.revision,
  });
  final GitSession session;
  final RepoPath path;
  final GitOid revision;
  @override
  State<GitBlameView> createState() => _BlameState();
}

final class _BlameState extends GitDialogState<GitBlameView> {
  @override
  GitSession get session => widget.session;
  List<String> lines = [];
  int offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    final content = await query(
      () => session.client.content(
        session.repository,
        widget.path,
        ContentVersion(ContentKind.commit, revision: widget.revision),
      ),
    );
    if (!mounted || content == null) return;
    if (content.text == null) {
      setState(
        () => error = const GitException(GitErrorCode.unsupportedContent),
      );
      return;
    }
    lines = exactLines(content.text!);
    await refresh();
  }

  Future<void> refresh() => load(
    GitInspection(
      GitInspectionKind.blame,
      path: widget.path,
      revision: widget.revision,
      offset: offset,
      limit: (lines.length - offset).clamp(1, 200),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(),
      Text(
        'Committed ${widget.revision.abbreviated} · unsaved editor content is not part of these annotations',
      ),
      Expanded(
        child: ListView.builder(
          itemCount: (data?['lines'] as List? ?? []).length,
          itemBuilder: (context, i) {
            final row = (data!['lines'] as List)[i] as Json,
                number = row['line'] as int;
            return InkWell(
              onTap: () => GitWorkflowUi(context, session).present(
                'History from ${row['revision']}',
                GitFileHistoryView(
                  session: session,
                  path: RepoPath.fromJson(row['path']),
                  revision: GitOid(row['revision'] as String),
                ),
                expanded: true,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 2,
                  horizontal: session.host.spacing,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Text(
                        '${(row['revision'] as String).substring(0, 10)}  ${row['author']}\nOriginal line ${row['originalLine']}${row['boundary'] == true ? ' · boundary' : ''}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    SizedBox(width: 45, child: Text('$number')),
                    Expanded(
                      child: SelectableText(
                        number <= lines.length
                            ? lines[number - 1].trimRight()
                            : '',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      Row(
        children: [
          TextButton(
            onPressed: offset == 0
                ? null
                : () {
                    offset = (offset - 200).clamp(0, lines.length);
                    unawaited(refresh());
                  },
            child: const GitLabel('Previous lines'),
          ),
          TextButton(
            onPressed: offset + 200 >= lines.length
                ? null
                : () {
                    offset += 200;
                    unawaited(refresh());
                  },
            child: const GitLabel('Next lines'),
          ),
        ],
      ),
    ],
  );
}

final class GitCherryPickView extends StatefulWidget {
  const GitCherryPickView({
    super.key,
    required this.session,
    required this.commits,
    this.revert = false,
  });
  final GitSession session;
  final List<GitCommit> commits;
  final bool revert;
  @override
  State<GitCherryPickView> createState() => _PickState();
}

final class _PickState extends GitDialogState<GitCherryPickView> {
  @override
  GitSession get session => widget.session;
  late final List<GitCommit> commits;
  late final GitSnapshot reviewed;
  int selected = 0, mainline = 1;
  bool noCommit = false, reviewedMainline = false;
  @override
  void initState() {
    super.initState();
    commits = List.from(widget.commits);
    reviewed = session.snapshot!;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(),
      Text(
        'Explicit application order · destination ${reviewed.branch ?? 'HEAD'}',
      ),
      Wrap(
        children: [
          TextButton(
            onPressed: loading
                ? null
                : () async {
                    final value = await gitTextInput(
                      context,
                      session,
                      'Add full commit object ID',
                    );
                    if (value == null) return;
                    try {
                      final oid = GitOid(value),
                          page = await session.client.history(
                            session.repository,
                            filter: HistoryFilter(reference: oid.value),
                            limit: 1,
                          );
                      if (mounted && page.commits.isNotEmpty)
                        setState(() => commits.add(page.commits.first));
                    } on Object catch (failure) {
                      if (mounted)
                        setState(
                          () => error = failure is GitException
                              ? failure
                              : const GitException(GitErrorCode.invalidRequest),
                        );
                    }
                  },
            child: const GitLabel('Add reviewed commit…'),
          ),
          TextButton(
            onPressed: selected <= 0
                ? null
                : () => setState(() {
                    final c = commits.removeAt(selected);
                    commits.insert(--selected, c);
                  }),
            child: const GitLabel('Move earlier'),
          ),
          TextButton(
            onPressed: selected + 1 >= commits.length
                ? null
                : () => setState(() {
                    final c = commits.removeAt(selected);
                    commits.insert(++selected, c);
                  }),
            child: const GitLabel('Move later'),
          ),
        ],
      ),
      Expanded(
        child: GitSplitter(
          initial: .4,
          minimum: 240,
          first: ListView.builder(
            itemCount: commits.length,
            itemBuilder: (context, i) => ListTile(
              selected: selected == i,
              leading: Text('${i + 1}'),
              title: Text(commits[i].subject),
              subtitle: Text(commits[i].oid.abbreviated),
              onTap: () => setState(() => selected = i),
              trailing: GitIconButton(
                tooltip: 'Remove from reviewed sequence',
                onPressed: commits.length < 2
                    ? null
                    : () => setState(() {
                        commits.removeAt(i);
                        selected = selected.clamp(0, commits.length - 1);
                      }),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          second: GitCommitFiles(session: session, commit: commits[selected]),
        ),
      ),
      CheckboxListTile(
        dense: true,
        value: noCommit,
        title: const GitLabel('Apply changes without creating commits'),
        onChanged: (v) => setState(() => noCommit = v!),
      ),
      if (commits.any((e) => e.parents.length > 1))
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                dense: true,
                value: reviewedMainline,
                title: const GitLabel(
                  'Use this explicit mainline parent for merge commits',
                ),
                onChanged: (v) => setState(() => reviewedMainline = v!),
              ),
            ),
            DropdownButton<int>(
              value: mainline,
              items: [
                for (
                  var i = 1;
                  i <=
                      commits
                          .where((e) => e.parents.length > 1)
                          .map((e) => e.parents.length)
                          .reduce((a, b) => a < b ? a : b);
                  i++
                )
                  DropdownMenuItem(value: i, child: Text('Parent $i')),
              ],
              onChanged: (v) => setState(() => mainline = v!),
            ),
          ],
        ),
      const GitLabel(
        'Empty or already-applied commits may stop Git for an explicit skip or continuation decision.',
      ),
      FilledButton(
        onPressed:
            loading ||
                commits.any((e) => e.parents.length > 1) && !reviewedMainline
            ? null
            : () async {
                final result = await apply(
                  PickCommits(
                    commits.map((e) => e.oid).toList(),
                    revert: widget.revert,
                    noCommit: noCommit,
                    mainline: commits.any((e) => e.parents.length > 1)
                        ? mainline
                        : null,
                    expectedHead: reviewed.head,
                    expectedIndex: reviewed.indexToken,
                  ),
                );
                if (mounted &&
                    result != null &&
                    (result.completed ||
                        result.phase == GitOperationPhase.stopped))
                  Navigator.of(context).pop();
              },
        child: Text(
          widget.revert
              ? 'Revert in reviewed order'
              : 'Cherry-pick in reviewed order',
        ),
      ),
    ],
  );
}
