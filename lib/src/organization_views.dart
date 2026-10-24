import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'history_actions.dart';
import 'host.dart';
import 'network_views.dart';
import 'session.dart';
import 'workflow_ui.dart';

final class GitStashesView extends StatefulWidget {
  const GitStashesView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitStashesView> createState() => _StashesState();
}

final class _StashesState extends GitDialogState<GitStashesView> {
  @override
  GitSession get session => widget.session;
  Json? selected;
  GitCommit? commit;
  bool restoreIndex = false;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() =>
      load(GitInspection(GitInspectionKind.stashes, offset: offset));
  Future<void> select(Json value) async {
    setState(() {
      selected = value;
      commit = null;
    });
    final page = await query(
      () => session.client.history(
        session.repository,
        filter: HistoryFilter(reference: value['identity'] as String),
        limit: 1,
      ),
    );
    if (mounted && page != null && selected?['identity'] == value['identity'])
      setState(() => commit = page.commits.firstOrNull);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(refresh: () => unawaited(refresh())),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: loading
              ? null
              : () async {
                  await GitWorkflowUi(context, session).present(
                    'Create named stash',
                    GitCreateStashView(session: session),
                    expanded: true,
                  );
                  await refresh();
                },
          icon: const Icon(Icons.add),
          label: const GitLabel('Create stash…'),
        ),
      ),
      Expanded(
        child: GitSplitter(
          initial: .4,
          minimum: 230,
          first: ListView(
            children: [
              if ((data?['entries'] as List? ?? []).isEmpty && !loading)
                const ListTile(title: GitLabel('No stashes')),
              for (final entry
                  in (data?['entries'] as List? ?? []).cast<Json>())
                ListTile(
                  dense: true,
                  selected: selected?['identity'] == entry['identity'],
                  title: Text(entry['message'] as String),
                  subtitle: Text(
                    '${(entry['identity'] as String).substring(0, 10)} · ${DateTime.fromMillisecondsSinceEpoch((entry['time'] as int) * 1000).toLocal()}',
                  ),
                  onTap: () => unawaited(select(entry)),
                ),
            ],
          ),
          second: commit == null
              ? const Center(
                  child: GitLabel('Select a stash to inspect its changes'),
                )
              : GitCommitFiles(session: session, commit: commit!),
        ),
      ),
      GitPageNavigation(
        offset: offset,
        hasMore: data?['hasMore'] == true,
        loading: loading,
        onPage: (value) {
          setState(() {
            offset = value;
            selected = null;
            commit = null;
          });
          unawaited(refresh());
        },
      ),
      if (commit != null && commit!.parents.length > 2)
        TextButton(
          onPressed: () => GitWorkflowUi(context, session).present(
            'Stashed untracked files',
            GitSnapshotView(session: session, revision: commit!.parents[2]),
            expanded: true,
          ),
          child: const GitLabel('Inspect stashed untracked files…'),
        ),
      CheckboxListTile(
        dense: true,
        value: restoreIndex,
        onChanged: (v) => setState(() => restoreIndex = v!),
        title: const GitLabel(
          'Reinstate the stash’s staged/index state when applying',
        ),
      ),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: session.host.spacing,
        children: [
          for (final action in [
            StashAction.apply,
            StashAction.pop,
            StashAction.branch,
            StashAction.drop,
          ])
            OutlinedButton(
              onPressed: loading || selected == null
                  ? null
                  : () => unawaited(act(action)),
              child: Text(switch (action) {
                StashAction.apply => 'Apply and retain',
                StashAction.pop => 'Pop…',
                StashAction.branch => 'Create branch…',
                _ => 'Drop stash…',
              }),
            ),
        ],
      ),
    ],
  );
  Future<void> act(StashAction action) async {
    final entry = selected!,
        state = session.snapshot!,
        identity = GitOid(entry['identity'] as String);
    String? branch;
    if (action == StashAction.branch) {
      branch = await gitTextInput(
        context,
        session,
        'Branch from stash',
        explanation:
            'Create/switch to a branch at the stash’s original base, then apply it. The original stash is retained for explicit later deletion.',
      );
      if (branch == null || branch.isEmpty) return;
    } else if (action != StashAction.apply &&
        !await gitConfirm(
          context,
          session,
          '${action.name} this stash?',
          '${entry['message']}\n${identity.value}\n${action == StashAction.pop ? 'The original stash is retained if applying conflicts.' : 'Deletes this stash entry. Its changes are not applied.'}',
          action: action.name,
        ))
      return;
    final result = await apply(
      StashMutation(
        action,
        identity: identity,
        restoreIndex: restoreIndex,
        branchName: branch,
        expectedHead: state.head,
        expectedIndex: state.indexToken,
      ),
    );
    if (!mounted || result == null) return;
    selected = null;
    commit = null;
    if (result.error == null) await refresh();
    if (result.phase == GitOperationPhase.stopped)
      session.host.notify(
        'Resolve the unmerged files. Git has no stash continue or abort command; the original stash remains.',
      );
  }
}

final class GitCreateStashView extends StatefulWidget {
  const GitCreateStashView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitCreateStashView> createState() => _CreateStashState();
}

final class _CreateStashState extends GitDialogState<GitCreateStashView> {
  @override
  GitSession get session => widget.session;
  final message = TextEditingController();
  late final GitSnapshot reviewed;
  final selected = <RepoPath>{};
  int mode = 0;
  bool untracked = false, all = true;
  @override
  void initState() {
    super.initState();
    reviewed = session.snapshot!;
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(),
      TextField(
        controller: message,
        decoration: InputDecoration(
          labelText: gitString(context, 'Stash name/message'),
        ),
      ),
      DropdownButtonFormField<int>(
        initialValue: mode,
        decoration: InputDecoration(
          labelText: gitString(context, 'Stash content and resulting index'),
        ),
        items: const [
          DropdownMenuItem(
            value: 0,
            child: GitLabel('Stash tracked working and staged changes'),
          ),
          DropdownMenuItem(
            value: 1,
            child: GitLabel(
              'Stash changes, leave staged changes in place (--keep-index)',
            ),
          ),
          DropdownMenuItem(
            value: 2,
            child: GitLabel('Stash only staged changes (--staged)'),
          ),
        ],
        onChanged: (v) => setState(() {
          mode = v!;
          if (mode == 2) untracked = false;
        }),
      ),
      CheckboxListTile(
        dense: true,
        value: untracked,
        onChanged: mode == 2 ? null : (v) => setState(() => untracked = v!),
        title: const GitLabel('Include untracked files'),
      ),
      CheckboxListTile(
        dense: true,
        value: all,
        onChanged: (v) => setState(() => all = v!),
        title: const GitLabel('All eligible paths in this repository'),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final change in reviewed.changes.where(
              (e) => !e.conflicted && (!e.untracked || untracked),
            ))
              CheckboxListTile(
                dense: true,
                value: all || selected.contains(change.path),
                onChanged: all
                    ? null
                    : (v) => setState(() {
                        if (v == true)
                          selected.add(change.path);
                        else
                          selected.remove(change.path);
                      }),
                title: Text(change.path.display),
                subtitle: Text('${change.index}${change.worktree}'),
              ),
          ],
        ),
      ),
      FilledButton(
        onPressed: loading || !all && selected.isEmpty
            ? null
            : () async {
                final result = await apply(
                  StashMutation(
                    StashAction.create,
                    message: message.text,
                    paths: all ? const [] : selected.toList(),
                    keepIndex: mode == 1,
                    stagedOnly: mode == 2,
                    includeUntracked: untracked,
                    expectedHead: reviewed.head,
                    expectedIndex: reviewed.indexToken,
                  ),
                );
                if (mounted && result?.completed == true)
                  Navigator.of(context).pop();
              },
        child: const GitLabel('Create stash'),
      ),
    ],
  );
}

final class GitWorktreesView extends StatefulWidget {
  const GitWorktreesView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitWorktreesView> createState() => _WorktreesState();
}

final class _WorktreesState extends GitDialogState<GitWorktreesView> {
  @override
  GitSession get session => widget.session;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() =>
      load(GitInspection(GitInspectionKind.worktrees, offset: offset));
  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(refresh: () => unawaited(refresh())),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: loading ? null : () => unawaited(create()),
          icon: const Icon(Icons.add),
          label: const GitLabel('Create worktree…'),
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final entry in (data?['entries'] as List? ?? []).cast<Json>())
              ListTile(
                title: Text(entry['path'] as String),
                subtitle: Text(
                  '${entry['branch'] ?? 'detached HEAD'}\n'
                  '${entry['current'] == true ? 'Current · ' : ''}${entry.containsKey('locked') ? 'Locked · ' : ''}'
                  '${entry['inUse'] == true ? 'Open in BusyStack · ' : ''}'
                  '${entry['dirty'] == null
                      ? 'Status not inspected'
                      : entry['dirty'] == true
                      ? 'Dirty'
                      : 'Clean'}',
                ),
                trailing: GitMenuButton(
                  host: session.host,
                  onSelected: (action) => unawaited(act(entry, action)),
                  entries: [
                    GitMenuEntry('open', 'Open working folder'),
                    if (entry['current'] != true) ...[
                      GitMenuEntry('move', 'Move worktree…'),
                      GitMenuEntry(
                        entry.containsKey('locked') ? 'unlock' : 'lock',
                        entry.containsKey('locked') ? 'Unlock' : 'Lock',
                      ),
                      const GitMenuEntry.separator(),
                      GitMenuEntry('remove', 'Remove clean worktree…'),
                      GitMenuEntry(
                        'forceRemove',
                        'Review removal including local changes…',
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      GitPageNavigation(
        offset: offset,
        hasMore: data?['hasMore'] == true,
        loading: loading,
        onPage: (value) {
          offset = value;
          unawaited(refresh());
        },
      ),
    ],
  );
  Future<void> create() async {
    final parent = await session.host.chooseDirectory(context);
    if (!mounted || parent == null) return;
    final folder = await gitTextInput(
      context,
      session,
      'New worktree folder name',
    );
    if (!mounted ||
        folder == null ||
        folder.isEmpty ||
        folder.contains('/') ||
        folder == '..' ||
        folder == '.')
      return;
    final branch = await gitTextInput(
      context,
      session,
      'New worktree branch',
      explanation: 'Create a new local branch at the current HEAD.',
    );
    if (!mounted || branch == null || branch.isEmpty) return;
    final s = session.snapshot!;
    await apply(
      WorktreeMutation(
        WorktreeAction.create,
        '$parent/$folder',
        branch: branch,
        start: s.head,
        expectedHead: s.head,
        expectedIndex: s.indexToken,
      ),
    );
    if (error == null) await refresh();
  }

  Future<void> act(Json entry, String action) async {
    final path = entry['path'] as String, s = session.snapshot!;
    if (action == 'open') {
      await session.host.openFolder?.call(path);
      return;
    }
    String? destination;
    if (action == 'move') {
      final parent = await session.host.chooseDirectory(context);
      if (!mounted || parent == null) return;
      final name = await gitTextInput(
        context,
        session,
        'Destination folder name',
      );
      if (name == null ||
          name.isEmpty ||
          name.contains('/') ||
          name == '..' ||
          name == '.')
        return;
      destination = '$parent/$name';
    }
    final force = action == 'forceRemove';
    if ({'remove', 'forceRemove'}.contains(action) &&
        !await gitConfirm(
          context,
          session,
          'Remove worktree?',
          '$path\n${force ? 'Explicitly discard all local tracked/untracked changes in this worktree. Locked/in-use worktrees remain protected.' : 'Git refuses removal if there are local changes, untracked files, or a lock.'}',
          action: force
              ? 'Discard local worktree contents and remove'
              : 'Remove clean worktree',
        ))
      return;
    await apply(
      WorktreeMutation(
        switch (action) {
          'move' => WorktreeAction.move,
          'lock' => WorktreeAction.lock,
          'unlock' => WorktreeAction.unlock,
          _ => WorktreeAction.remove,
        },
        path,
        destination: destination,
        forceReviewed: force,
        expectedHead: s.head,
        expectedIndex: s.indexToken,
      ),
    );
    if (error == null) await refresh();
  }
}

final class GitSubmodulesView extends StatefulWidget {
  const GitSubmodulesView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitSubmodulesView> createState() => _SubmodulesState();
}

final class _SubmodulesState extends GitDialogState<GitSubmodulesView> {
  @override
  GitSession get session => widget.session;
  int offset = 0;
  bool recursive = false;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() =>
      load(GitInspection(GitInspectionKind.submodules, offset: offset));
  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(refresh: () => unawaited(refresh())),
      CheckboxListTile(
        dense: true,
        value: recursive,
        onChanged: (v) => setState(() => recursive = v!),
        title: const GitLabel(
          'Explicitly recurse into nested submodules for updates/synchronization',
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            if ((data?['entries'] as List? ?? []).isEmpty && !loading)
              const ListTile(title: GitLabel('No recorded submodules')),
            for (final entry in (data?['entries'] as List? ?? []).cast<Json>())
              Builder(
                builder: (context) {
                  final path = RepoPath.fromJson(entry['path']);
                  return ListTile(
                    title: Text(path.display),
                    subtitle: SelectableText(
                      'Parent gitlink: ${entry['recorded']}\nChecked out: ${entry['checkedOut'] ?? 'not initialized'}\n'
                      '${entry['dirty'] == true
                          ? 'Dirty nested repository'
                          : entry['dirty'] == false
                          ? 'Clean nested repository'
                          : 'Nested status unavailable'}',
                    ),
                    trailing: GitMenuButton(
                      host: session.host,
                      onSelected: (action) => unawaited(act(entry, action)),
                      entries: [
                        if (entry['initialized'] == true)
                          GitMenuEntry('open', 'Enter nested repository'),
                        GitMenuEntry('initialize', 'Initialize configuration'),
                        GitMenuEntry(
                          'updateRecorded',
                          'Update to parent’s recorded commit…',
                        ),
                        GitMenuEntry(
                          'updateRemote',
                          'Follow configured remote branch…',
                        ),
                        GitMenuEntry(
                          'synchronize',
                          'Synchronize configured URLs…',
                        ),
                        const GitMenuEntry.separator(),
                        GitMenuEntry(
                          'stagePointer',
                          'Stage current submodule pointer in parent',
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      GitPageNavigation(
        offset: offset,
        hasMore: data?['hasMore'] == true,
        loading: loading,
        onPage: (value) {
          offset = value;
          unawaited(refresh());
        },
      ),
      const GitLabel(
        'Parent and submodule commits, pushes, and dirty state remain separate. Browsing does not initialize or update them.',
      ),
    ],
  );
  Future<void> act(Json entry, String action) async {
    final path = RepoPath.fromJson(entry['path']), s = session.snapshot!;
    if (action == 'open') {
      final child = RepositoryId.fromJson(entry['repository'] as Json);
      await session.host.openFolder?.call(child.root);
      return;
    }
    if (action != 'stagePointer' &&
        !await gitConfirm(
          context,
          session,
          '$action ${path.display}?',
          action == 'updateRemote'
              ? 'Fetch and check out the configured remote branch’s commit. This differs from the parent’s recorded gitlink. Recursive: $recursive.'
              : action == 'updateRecorded'
              ? 'Initialize as needed and check out exactly ${entry['recorded']}. Recursive: $recursive.'
              : 'Apply the reviewed submodule configuration operation. Recursive: $recursive.',
          action: 'Apply submodule operation',
        ))
      return;
    await apply(
      SubmoduleMutation(
        SubmoduleAction.values.byName(action),
        [path],
        recursive: recursive,
        expectedHead: s.head,
        expectedIndex: s.indexToken,
      ),
    );
    if (error == null) await refresh();
  }
}

final class GitRecoveryView extends StatefulWidget {
  const GitRecoveryView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitRecoveryView> createState() => _RecoveryState();
}

final class _RecoveryState extends GitDialogState<GitRecoveryView> {
  @override
  GitSession get session => widget.session;
  Json? selected;
  GitCommit? commit;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() =>
      load(GitInspection(GitInspectionKind.reflog, offset: offset));
  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(refresh: () => unawaited(refresh())),
      const GitLabel(
        'Inspect a recorded revision or create a recovery branch. Reflog does not recover arbitrary unsaved or untracked content.',
      ),
      Expanded(
        child: GitSplitter(
          initial: .48,
          minimum: 240,
          first: ListView(
            children: [
              for (final entry
                  in (data?['entries'] as List? ?? []).cast<Json>())
                ListTile(
                  dense: true,
                  selected: selected == entry,
                  title: Text(entry['action'] as String),
                  subtitle: Text('${entry['selector']}\n${entry['revision']}'),
                  onTap: () async {
                    setState(() {
                      selected = entry;
                      commit = null;
                    });
                    final page = await query(
                      () => session.client.history(
                        session.repository,
                        filter: HistoryFilter(
                          reference: entry['revision'] as String,
                        ),
                        limit: 1,
                      ),
                    );
                    if (mounted && page != null && selected == entry)
                      setState(() => commit = page.commits.firstOrNull);
                  },
                ),
            ],
          ),
          second: commit == null
              ? const Center(child: GitLabel('Select a reflog entry'))
              : GitCommitFiles(session: session, commit: commit!),
        ),
      ),
      Wrap(
        spacing: session.host.spacing,
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
          FilledButton(
            onPressed: selected == null
                ? null
                : () async {
                    final oid = GitOid(selected!['revision'] as String),
                        s = session.snapshot!;
                    final name = await gitTextInput(
                      context,
                      session,
                      'Recovery branch name',
                      explanation:
                          'Creates a branch at ${oid.value}; working files and the current branch are unchanged.',
                    );
                    if (name == null || name.isEmpty) return;
                    await apply(
                      BranchMutation(
                        BranchAction.create,
                        name,
                        start: oid,
                        expectedHead: s.head,
                        expectedIndex: s.indexToken,
                      ),
                    );
                  },
            child: const GitLabel('Create recovery branch…'),
          ),
          TextButton(
            onPressed: selected == null
                ? null
                : () => GitWorkflowUi(context, session).present(
                    'Read-only recovery snapshot',
                    GitSnapshotView(
                      session: session,
                      revision: GitOid(selected!['revision'] as String),
                    ),
                    expanded: true,
                  ),
            child: const GitLabel('Inspect snapshot…'),
          ),
          TextButton(
            onPressed: selected == null
                ? null
                : () => GitHistoryActions(
                    GitWorkflowUi(context, session),
                  ).reset(GitOid(selected!['revision'] as String)),
            child: const GitLabel('Review reset…'),
          ),
        ],
      ),
    ],
  );
}

final class GitPageNavigation extends StatelessWidget {
  const GitPageNavigation({
    super.key,
    required this.offset,
    required this.hasMore,
    required this.loading,
    required this.onPage,
  });
  final int offset;
  final bool hasMore, loading;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Text('Page ${offset ~/ 100 + 1}'),
      TextButton(
        onPressed: loading || offset == 0
            ? null
            : () => onPage((offset - 100).clamp(0, 1000000)),
        child: const GitLabel('Previous page'),
      ),
      TextButton(
        onPressed: loading || !hasMore ? null : () => onPage(offset + 100),
        child: const GitLabel('Next page'),
      ),
    ],
  );
}
