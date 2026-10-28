import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'diff_view.dart';
import 'host.dart';
import 'network_views.dart';
import 'reference_picker.dart';
import 'session.dart';
import 'workflow_ui.dart';

final class GitHistoryActions {
  const GitHistoryActions(this.ui);
  final GitWorkflowUi ui;
  GitSession get session => ui.session;
  BuildContext get context => ui.context;
  Future<void> run(GitCommit commit, String action) async {
    switch (action) {
      case GitMessages.createBranch2:
        final reviewed = session.snapshot!;
        final name = await gitTextInput(
          context,
          session,
          gitString(
            context,
            GitMessages.branchAtArg0,
            values: {'arg0': commit.oid.abbreviated},
          ),
          explanation: GitMessages.createsALocalBranchWithoutCheckingItOut,
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
      case GitMessages.createTag:
        await ui.present(
          gitString(
            context,
            GitMessages.tagArg0,
            values: {'arg0': commit.oid.abbreviated},
          ),
          GitTagView(session: session, target: commit.oid),
        );
      case GitMessages.compareRevisions:
        await compare(commit.oid, null);
      case GitMessages.openSnapshot:
        await ui.present(
          gitString(
            context,
            GitMessages.readOnlySnapshotArg0,
            values: {'arg0': commit.oid.abbreviated},
          ),
          GitSnapshotView(session: session, revision: commit.oid),
          expanded: true,
        );
      case 'Cherry-pick':
        await ui.present(
          GitMessages.cherryPickCommits,
          GitCherryPickView(session: session, commits: [commit]),
          expanded: true,
        );
      case GitMessages.revertCommit:
        await ui.present(
          GitMessages.revertCommits,
          GitCherryPickView(session: session, commits: [commit], revert: true),
          expanded: true,
        );
      case GitMessages.interactiveRebaseAfterThisBoundary:
        await ui.rebase(boundary: commit.oid);
      case GitMessages.resetCurrentBranch:
        await reset(commit.oid);
    }
  }

  Future<void> compare(GitOid left, GitOid? right) async {
    if (right == null) {
      final target = await gitChooseRevision(
        context,
        session,
        GitMessages.compareRevisions,
      );
      if (target == null) return;
      right = target.oid;
    }
    if (!context.mounted) return;
    await ui.present(
      gitString(
        context,
        GitMessages.arg0Arg1TreeComparison,
        values: {'arg0': left.abbreviated, 'arg1': right.abbreviated},
      ),
      GitRevisionComparison(session: session, left: left, right: right),
      expanded: true,
    );
  }

  Future<void> reset(GitOid target) async {
    final state = session.snapshot!;
    final mode = await session.host.present<ResetMode>(
      context,
      gitString(
        context,
        GitMessages.resetArg0ToArg1,
        values: {
          'arg0': state.branch ?? GitMessages.head,
          'arg1': target.abbreviated,
        },
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GitLabel(
            GitMessages
                .movesHEADCurrentBranchReflogDoesNotRecoverArbitraryUntracked,
          ),
          for (final mode in ResetMode.values)
            ListTile(
              title: Text(gitEnumLabel(context, mode)),
              subtitle: Text(switch (mode) {
                ResetMode.soft => gitString(
                  context,
                  GitMessages.moveHEADKeepIndexAndWorkingFiles,
                ),
                ResetMode.mixed => gitString(
                  context,
                  GitMessages.moveHEADAndReplaceIndexKeepWorkingFiles,
                ),
                ResetMode.hard => gitString(
                  context,
                  GitMessages
                      .replaceHEADIndexAndTrackedWorkingFilesMayOverwriteObstructing,
                ),
                ResetMode.keep => gitString(
                  context,
                  GitMessages
                      .replaceHEADIndexAndEligibleFilesRefuseIfLocalChanges,
                ),
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
      gitString(
        context,
        GitMessages.resetWithArg0,
        values: {'arg0': gitEnumLabel(context, mode)},
      ),
      gitString(
        context,
        GitMessages.arg0Arg1ReviewTheSelectedModeSEffectsBeforeApplying,
        values: {'arg0': state.head?.value, 'arg1': target.value},
      ),
      action: gitString(
        context,
        GitMessages.resetArg0,
        values: {'arg0': gitEnumLabel(context, mode)},
      ),
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
      SelectableText(
        gitString(
          context,
          GitMessages.targetArg0,
          values: {'arg0': widget.target.value},
        ),
      ),
      states(),
      TextField(
        controller: name,
        decoration: InputDecoration(
          labelText: gitString(context, GitMessages.tagName),
        ),
      ),
      CheckboxListTile(
        value: annotated,
        title: const GitLabel(GitMessages.annotatedTag),
        onChanged: (v) => setState(() => annotated = v!),
      ),
      DropdownButtonFormField<int>(
        initialValue: 0,
        decoration: InputDecoration(
          labelText: gitString(context, GitMessages.cryptographicSigning),
        ),
        items: const [
          DropdownMenuItem(
            value: 0,
            child: GitLabel(GitMessages.configuredPolicy),
          ),
          DropdownMenuItem(value: 1, child: GitLabel(GitMessages.signThisTag)),
          DropdownMenuItem(value: 2, child: GitLabel(GitMessages.doNotSign)),
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
            labelText: gitString(context, GitMessages.tagMessage),
          ),
        ),
      const GitLabel(
        GitMessages.createsTheTagLocallyPublishSelectedTagsExplicitlyInPush,
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
        child: const GitLabel(GitMessages.createTag),
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
        gitString(
          context,
          GitMessages.completeTreesArg0Arg1,
          values: {
            'arg0': widget.left.abbreviated,
            'arg1': widget.right.abbreviated,
          },
        ),
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
          child: const GitLabel(GitMessages.nextChangedFilePage),
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
        GitMessages.readOnlyRepositorySnapshotOpeningAFileNeverChecksOut,
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
                      entries: [
                        const GitMenuEntry(
                          'open',
                          GitMessages.openReadOnlyVersion,
                        ),
                        const GitMenuEntry(
                          'history',
                          GitMessages.fileHistoryAndBlame,
                        ),
                        const GitMenuEntry.separator(),
                        GitMenuEntry(
                          'restore',
                          session.snapshot == null
                              ? GitMessages
                                    .restoreThisPathWaitingForRepositoryStatus
                              : GitMessages.restoreThisPath,
                          enabled:
                              session.snapshot != null &&
                              session.canWriteMetadata &&
                              !session.running,
                        ),
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
            child: const GitLabel(GitMessages.previousPage),
          ),
          TextButton(
            onPressed: data?['hasMore'] != true
                ? null
                : () {
                    offset += 200;
                    unawaited(refresh());
                  },
            child: const GitLabel(GitMessages.nextPage),
          ),
        ],
      ),
    ],
  );
  Future<void> open(IndexEntry entry, String action) async {
    if (action == 'history') {
      await GitWorkflowUi(context, session).present(
        gitString(
          context,
          GitMessages.historyArg0,
          values: {'arg0': entry.path.display},
        ),
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
        gitString(
          context,
          GitMessages.restoreArg0,
          values: {'arg0': entry.path.display},
        ),
        gitString(
          context,
          GitMessages
              .replaceThisWorkingPathWithRevisionArg0ExistingStagedContent,
          values: {'arg0': widget.revision.value},
        ),
        action: GitMessages.restoreWorkingFile,
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
  GitOid? selectedRevision;
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
  GitComparison _parentComparison(Json row) {
    final commit = GitCommit.fromJson(row['commit'] as Json);
    final path = RepoPath.fromJson(row['pathAtCommit']);
    final parentPath = RepoPath.fromJson(row['pathInParent']);
    final parent = commit.parents.firstOrNull;
    return GitComparison(
      path,
      parent == null
          ? const ContentVersion.absent()
          : ContentVersion(ContentKind.commit, revision: parent),
      ContentVersion(ContentKind.commit, revision: commit.oid),
      leftPath: parentPath,
    );
  }

  Future<void> _showParent(Json row) async {
    final comparison = _parentComparison(row);
    await session.host.present<void>(
      context,
      gitString(context, GitMessages.compareToParent),
      GitDiffView(session: session, comparison: comparison),
      expanded: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = (data?['entries'] as List? ?? []).cast<Json>();
    final selected =
        entries
            .where(
              (row) =>
                  GitCommit.fromJson(row['commit'] as Json).oid ==
                  selectedRevision,
            )
            .firstOrNull ??
        entries.firstOrNull;
    return Column(
      children: [
        states(),
        Row(
          children: [
            Expanded(
              child: Text(
                gitString(
                  context,
                  GitMessages.fileHistoryFollowsRenamesArg0,
                  values: {'arg0': widget.path.display},
                ),
              ),
            ),
            TextButton(
              onPressed: () => GitWorkflowUi(context, session).present(
                GitMessages.blameCommittedContent,
                GitBlameView(
                  session: session,
                  path: widget.path,
                  revision: widget.revision ?? session.snapshot!.head!,
                ),
                expanded: true,
              ),
              child: const GitLabel(GitMessages.blame),
            ),
          ],
        ),
        Expanded(
          child: selected == null
              ? ListView(children: const [])
              : GitSplitter(
                  axis: Axis.vertical,
                  initial: .42,
                  minimum: 130,
                  minimumSecond: 210,
                  value: session.split('fileHistoryPreviewSplit', .42),
                  onChanged: (value) =>
                      session.setViewState('fileHistoryPreviewSplit', value),
                  first: ListView(
                    children: [
                      for (final row in entries)
                        Builder(
                          builder: (context) {
                            final commit = GitCommit.fromJson(
                                  row['commit'] as Json,
                                ),
                                path = RepoPath.fromJson(row['pathAtCommit']);
                            return ListTile(
                              dense: true,
                              selected:
                                  commit.oid ==
                                  GitCommit.fromJson(
                                    selected['commit'] as Json,
                                  ).oid,
                              title: Text(commit.subject),
                              subtitle: Text(
                                '${commit.oid.abbreviated} · ${commit.author} · ${path.display}',
                              ),
                              onTap: () =>
                                  setState(() => selectedRevision = commit.oid),
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
                                      gitString(
                                        context,
                                        GitMessages.arg0WorkingTree,
                                        values: {
                                          'arg0': commit.oid.abbreviated,
                                        },
                                      ),
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
                                  } else if (action == 'parent') {
                                    await _showParent(row);
                                  } else if (action == 'files') {
                                    await GitWorkflowUi(
                                      context,
                                      session,
                                    ).present(
                                      gitString(
                                        context,
                                        GitMessages.commitArg0,
                                        values: {
                                          'arg0': commit.oid.abbreviated,
                                        },
                                      ),
                                      GitCommitFiles(
                                        session: session,
                                        commit: commit,
                                      ),
                                      expanded: true,
                                    );
                                  }
                                },
                                entries: const [
                                  GitMenuEntry(
                                    'open',
                                    GitMessages.openReadOnlyHistoricalFile,
                                  ),
                                  GitMenuEntry(
                                    'current',
                                    GitMessages.compareToCurrentFile,
                                  ),
                                  GitMenuEntry(
                                    'parent',
                                    GitMessages.compareToParent,
                                  ),
                                  GitMenuEntry(
                                    'files',
                                    GitMessages.changedFiles,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  second: GitDiffView(
                    key: ValueKey(
                      GitCommit.fromJson(selected['commit'] as Json).oid.value,
                    ),
                    session: session,
                    comparison: _parentComparison(selected),
                  ),
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
              child: const GitLabel(GitMessages.previousPage),
            ),
            TextButton(
              onPressed: data?['hasMore'] != true
                  ? null
                  : () {
                      offset += 100;
                      unawaited(refresh());
                    },
              child: const GitLabel(GitMessages.nextPage),
            ),
          ],
        ),
      ],
    );
  }
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
        gitString(
          context,
          GitMessages.committedArg0UnsavedEditorContentIsNotPartOfThese,
          values: {'arg0': widget.revision.abbreviated},
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: (data?['lines'] as List? ?? []).length,
          itemBuilder: (context, i) {
            final row = (data!['lines'] as List)[i] as Json,
                number = row['line'] as int;
            return InkWell(
              onTap: () => GitWorkflowUi(context, session).present(
                gitString(
                  context,
                  GitMessages.historyFromArg0,
                  values: {'arg0': row['revision']},
                ),
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
                        gitString(
                          context,
                          GitMessages.arg0Arg1OriginalLineArg2Arg3,
                          values: {
                            'arg0': (row['revision'] as String).substring(
                              0,
                              10,
                            ),
                            'arg1': row['author'],
                            'arg2': row['originalLine'],
                            'arg3': row['boundary'] == true
                                ? gitString(context, GitMessages.boundary)
                                : '',
                          },
                        ),
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
            child: const GitLabel(GitMessages.previousLines),
          ),
          TextButton(
            onPressed: offset + 200 >= lines.length
                ? null
                : () {
                    offset += 200;
                    unawaited(refresh());
                  },
            child: const GitLabel(GitMessages.nextLines),
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
        gitString(
          context,
          GitMessages.explicitApplicationOrderDestinationArg0,
          values: {'arg0': reviewed.branch ?? GitMessages.head},
        ),
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
                      GitMessages.addFullCommitObjectID,
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
            child: const GitLabel(GitMessages.addReviewedCommit),
          ),
          TextButton(
            onPressed: selected <= 0
                ? null
                : () => setState(() {
                    final c = commits.removeAt(selected);
                    commits.insert(--selected, c);
                  }),
            child: const GitLabel(GitMessages.moveEarlier),
          ),
          TextButton(
            onPressed: selected + 1 >= commits.length
                ? null
                : () => setState(() {
                    final c = commits.removeAt(selected);
                    commits.insert(++selected, c);
                  }),
            child: const GitLabel(GitMessages.moveLater),
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
                tooltip: gitString(
                  context,
                  GitMessages.removeFromReviewedSequence,
                ),
                onPressed: commits.length < 2
                    ? null
                    : () => setState(() {
                        commits.removeAt(i);
                        selected = selected.clamp(0, commits.length - 1);
                      }),
                icon: const GitIcon(GitGlyph.close),
              ),
            ),
          ),
          second: GitCommitFiles(session: session, commit: commits[selected]),
        ),
      ),
      CheckboxListTile(
        dense: true,
        value: noCommit,
        title: const GitLabel(GitMessages.applyChangesWithoutCreatingCommits),
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
                  GitMessages.useThisExplicitMainlineParentForMergeCommits,
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
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      gitString(
                        context,
                        GitMessages.parentArg0,
                        values: {'arg0': i},
                      ),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => mainline = v!),
            ),
          ],
        ),
      const GitLabel(GitMessages.emptyOrAlreadyAppliedCommitsMayStopGitForAn),
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
              ? gitString(context, GitMessages.revertInReviewedOrder)
              : gitString(context, GitMessages.cherryPickInReviewedOrder),
        ),
      ),
    ],
  );
}
