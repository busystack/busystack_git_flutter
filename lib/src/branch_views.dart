import 'host.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'history_actions.dart';
import 'network_views.dart';

final class GitBranchesView extends StatefulWidget {
  const GitBranchesView({super.key, required this.session, this.onOpenFolder});
  final GitSession session;
  final ValueChanged<String>? onOpenFolder;
  @override
  State<GitBranchesView> createState() => _BranchesState();
}

final class _BranchesState extends GitDialogState<GitBranchesView> {
  @override
  GitSession get session => widget.session;
  List<GitReference> refs = [];
  GitSnapshot? reviewed;
  String search = '';
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await session.client.references(session.repository);
      final state = await session.readStatus();
      if (mounted)
        setState(() {
          refs = values;
          reviewed = state;
        });
    } on GitException catch (failure) {
      if (mounted) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      states(refresh: refresh),
      if (session.snapshot != null && !session.canWriteMetadata)
        const GitLabel(
          'Repository metadata is read-only. Branch inspection and comparison remain available.',
        ),
      if (session.canWriteMetadata &&
          session.snapshot?.capabilities.replaceWorkingFiles == false)
        const GitLabel(
          'Working files are unavailable or read-only. Branch switching and merging are unavailable.',
        ),
      Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: GitIcon(GitGlyph.search),
                labelText: gitString(context, 'Search branches and tags'),
              ),
              onChanged: (value) => setState(() => search = value),
            ),
          ),
          TextButton.icon(
            onPressed:
                loading ||
                    reviewed?.head == null ||
                    !session.canWriteMetadata ||
                    session.snapshot?.capabilities.replaceWorkingFiles != true
                ? null
                : () => unawaited(createBranch()),
            icon: const GitIcon(GitGlyph.add),
            label: const GitLabel('New branch…'),
          ),
        ],
      ),
      Expanded(
        child: ListView(
          children: [
            for (final prefix in const [
              'refs/heads/',
              'refs/remotes/',
              'refs/tags/',
            ]) ...[
              Padding(
                padding: EdgeInsets.all(session.host.spacing),
                child: Text(switch (prefix) {
                  'refs/heads/' => 'Local branches',
                  'refs/remotes/' => 'Remote branches',
                  _ => 'Tags',
                }, style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final reference in refs.where(
                (e) =>
                    e.name.startsWith(prefix) &&
                    e.name.toLowerCase().contains(search.toLowerCase()),
              ))
                ListTile(
                  dense: true,
                  leading: GitIcon(
                    reference.current
                        ? GitGlyph.check
                        : prefix == 'refs/tags/'
                        ? GitGlyph.tag
                        : GitGlyph.branch,
                    size: 18,
                  ),
                  title: Text(reference.name.substring(prefix.length)),
                  subtitle: Text(
                    [
                      if (reference.upstream != null)
                        'Tracks ${reference.upstream}',
                      if (reference.worktreePath != null)
                        'Checked out at ${reference.worktreePath}',
                      reference.oid.abbreviated,
                    ].join(' · '),
                  ),
                  trailing: GitMenuButton(
                    host: session.host,
                    enabled: !loading,
                    disabledReason: 'Refreshing branch metadata',
                    onSelected: (action) => unawaited(act(reference, action)),
                    entries: [
                      if (prefix == 'refs/heads/' && !reference.current)
                        GitMenuEntry(
                          reference.worktreePath == null ? 'switch' : 'open',
                          reference.worktreePath == null
                              ? 'Switch to ${reference.shortName}'
                              : 'Open occupied worktree',
                          enabled: reference.worktreePath == null
                              ? session.canWriteMetadata &&
                                    session
                                            .snapshot
                                            ?.capabilities
                                            .replaceWorkingFiles ==
                                        true
                              : widget.onOpenFolder != null ||
                                    session.host.openFolder != null,
                        ),
                      if (prefix == 'refs/remotes/')
                        GitMenuEntry(
                          'track',
                          'Create local tracking branch…',
                          enabled:
                              session.canWriteMetadata &&
                              session
                                      .snapshot
                                      ?.capabilities
                                      .replaceWorkingFiles ==
                                  true,
                        ),
                      GitMenuEntry('compare', 'Compare to current HEAD'),
                      GitMenuEntry(
                        'merge',
                        'Merge into current branch…',
                        enabled:
                            session.canWriteMetadata &&
                            session
                                    .snapshot
                                    ?.capabilities
                                    .replaceWorkingFiles ==
                                true,
                      ),
                      if (prefix == 'refs/heads/') ...[
                        GitMenuEntry(
                          'rename',
                          'Rename…',
                          enabled: session.canWriteMetadata,
                        ),
                        GitMenuEntry(
                          'upstream',
                          'Change upstream…',
                          enabled: session.canWriteMetadata,
                        ),
                      ],
                      const GitMenuEntry.separator(),
                      if (prefix != 'refs/remotes/')
                        GitMenuEntry(
                          'delete',
                          'Delete…',
                          enabled: session.canWriteMetadata,
                        ),
                      GitMenuEntry(
                        'remoteDelete',
                        'Delete from remote…',
                        enabled: session.canWriteMetadata,
                      ),
                    ],
                    tooltip: 'Actions for ${reference.name}',
                  ),
                ),
            ],
          ],
        ),
      ),
    ],
  );
  Future<void> createBranch({GitReference? tracking}) async {
    final state = reviewed;
    if (state?.head == null) return;
    final name = await gitTextInput(
      context,
      session,
      'Local branch name',
      initial: tracking?.shortName.split('/').skip(1).join('/') ?? '',
      explanation: tracking == null
          ? 'Create at ${state!.head!.abbreviated}. The new branch will be checked out.'
          : 'The local branch will track ${tracking.name} and be checked out.',
    );
    if (!mounted || name == null || name.isEmpty) return;
    await apply(
      BranchMutation(
        BranchAction.create,
        name,
        start: tracking?.oid ?? state!.head,
        upstream: tracking?.name,
        switchAfterCreate: true,
        expectedHead: state!.head,
        expectedIndex: state.indexToken,
      ),
    );
    await refresh();
  }

  Future<void> act(GitReference reference, String action) async {
    final state = reviewed;
    if (state == null) return;
    final name = reference.shortName;
    if (action == 'track') return createBranch(tracking: reference);
    if (action == 'open') {
      if (widget.onOpenFolder case final open?) {
        open(reference.worktreePath!);
      } else {
        await session.host.openFolder?.call(reference.worktreePath!);
      }
      return;
    }
    if (action == 'compare') {
      await GitHistoryActions(
        GitWorkflowUi(context, session),
      ).compare(reference.oid, state.head);
      return;
    }
    if (action == 'remoteDelete') {
      final values = await query(
        () => workflows.inspect(
          session.repository,
          const GitInspection(GitInspectionKind.remotes),
        ),
      );
      if (!mounted || values == null) return;
      final names =
          (values['remotes'] as List)
              .cast<Json>()
              .map((e) => e['name'] as String)
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));
      final owner = names
          .where((remote) => reference.name.startsWith('refs/remotes/$remote/'))
          .firstOrNull;
      final remote =
          owner ??
          await session.host.present<String>(
            context,
            'Choose remote for deletion',
            GitActionMenu(actions: {for (final name in names) name: name}),
            expanded: false,
          );
      if (!mounted || remote == null) return;
      final target = owner != null
          ? 'refs/heads/${reference.name.substring('refs/remotes/$owner/'.length)}'
          : reference.name;
      await GitWorkflowUi(context, session).present(
        'Delete remote reference',
        GitDeleteRemoteView(
          session: session,
          remote: remote,
          reference: target,
        ),
        expanded: false,
      );
      await refresh();
      return;
    }
    if (action == 'merge') {
      await GitWorkflowUi(context, session).present(
        'Merge $name into ${state.branch ?? 'HEAD'}',
        GitMergeView(session: session, source: reference),
      );
      return;
    }
    GitMutation? request;
    if (action == 'switch')
      request = BranchMutation(
        BranchAction.switchBranch,
        name,
        expectedHead: state.head,
        expectedIndex: state.indexToken,
        expectedTip: reference.oid,
      );
    if (action == 'rename') {
      final value = await gitTextInput(
        context,
        session,
        'Rename $name',
        initial: name,
      );
      if (value != null && value.isNotEmpty)
        request = BranchMutation(
          BranchAction.rename,
          name,
          newName: value,
          expectedTip: reference.oid,
          expectedHead: state.head,
          expectedIndex: state.indexToken,
        );
    }
    if (action == 'upstream') {
      final value = await session.host.present<String>(
        context,
        'Upstream for $name',
        GitActionMenu(
          actions: {
            '': 'No upstream',
            for (final ref in refs.where(
              (r) => r.name.startsWith('refs/remotes/'),
            ))
              ref.name: ref.shortName,
          },
        ),
        expanded: false,
      );
      if (value != null)
        request = BranchMutation(
          BranchAction.setUpstream,
          name,
          upstream: value.isEmpty ? null : value,
          expectedHead: state.head,
          expectedIndex: state.indexToken,
          expectedTip: reference.oid,
        );
    }
    if (action == 'delete' &&
        mounted &&
        await gitConfirm(
          context,
          session,
          'Delete $name?',
          '${reference.name}\nTarget ${reference.oid.value}\nLocal deletion only. An unmerged branch is refused.',
          action: 'Delete',
        )) {
      request = reference.name.startsWith('refs/tags/')
          ? TagMutation(
              TagAction.delete,
              name,
              target: reference.oid,
              expectedTip: reference.oid,
              expectedHead: state.head,
              expectedIndex: state.indexToken,
            )
          : BranchMutation(
              BranchAction.delete,
              name,
              expectedTip: reference.oid,
              expectedHead: state.head,
              expectedIndex: state.indexToken,
            );
    }
    if (request != null) {
      final result = await apply(request);
      if (request is BranchMutation &&
          request.action == BranchAction.delete &&
          result?.error?.diagnostic.contains('not fully merged') == true &&
          mounted) {
        if (await gitConfirm(
          context,
          session,
          'Delete unmerged branch $name?',
          '${reference.oid.value}\nGit reports this branch is not fully merged. Explicitly delete the local reference after reviewing its commits; remote copies are unchanged.',
          action: 'Delete unmerged local branch',
        )) {
          await apply(
            BranchMutation(
              BranchAction.delete,
              name,
              forceDeleteReviewed: true,
              expectedTip: reference.oid,
              expectedHead: state.head,
              expectedIndex: state.indexToken,
            ),
          );
        }
      }
      if (error == null) await refresh();
    }
  }
}

final class GitMergeView extends StatefulWidget {
  const GitMergeView({super.key, required this.session, this.source});
  final GitSession session;
  final GitReference? source;
  @override
  State<GitMergeView> createState() => _MergeState();
}

final class _MergeState extends GitDialogState<GitMergeView> {
  @override
  GitSession get session => widget.session;
  late final GitSnapshot reviewed;
  List<GitReference> refs = [];
  GitReference? source;
  MergePolicy policy = MergePolicy.fastForward;
  bool stop = false;
  @override
  void initState() {
    super.initState();
    reviewed = session.snapshot!;
    source = widget.source;
    unawaited(_load());
  }

  Future<void> _load() async {
    final values = await query(
      () => session.client.references(session.repository),
    );
    if (mounted && values != null)
      setState(() => refs = values.where((e) => !e.current).toList());
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Destination: ${reviewed.branch ?? 'detached HEAD'} · ${reviewed.head?.abbreviated}',
      ),
      states(),
      DropdownButtonFormField<String>(
        initialValue: source?.name,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: gitString(context, 'Source branch or tag'),
        ),
        items: [
          for (final ref in refs)
            DropdownMenuItem(value: ref.name, child: Text(ref.shortName)),
        ],
        onChanged: loading
            ? null
            : (name) => setState(
                () => source = refs.firstWhere((e) => e.name == name),
              ),
      ),
      SizedBox(height: session.host.spacing),
      DropdownButtonFormField<MergePolicy>(
        initialValue: policy,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: gitString(context, 'Merge policy'),
        ),
        items: [
          for (final p in MergePolicy.values)
            DropdownMenuItem(
              value: p,
              child: Text(switch (p) {
                MergePolicy.fastForward => 'Fast-forward when possible',
                MergePolicy.noFastForward => 'Always create a merge commit',
                MergePolicy.fastForwardOnly => 'Fast-forward only',
                MergePolicy.squash => 'Squash into staged changes',
              }),
            ),
        ],
        onChanged: loading
            ? null
            : (value) => setState(() {
                policy = value!;
                if (policy == MergePolicy.fastForwardOnly) stop = false;
              }),
      ),
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: stop,
        onChanged:
            policy == MergePolicy.fastForwardOnly ||
                policy == MergePolicy.squash ||
                loading
            ? null
            : (v) => setState(() => stop = v!),
        title: const GitLabel('Stop before creating the merge commit'),
        subtitle: stop
            ? const GitLabel(
                'Fast-forward is disabled so HEAD cannot move before review.',
              )
            : null,
      ),
      Text(
        policy == MergePolicy.squash
            ? 'Leaves staged changes for a separate commit; this is not a continuing merge.'
            : 'Conflicts remain available in the shared resolution workspace.',
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: loading || source == null
            ? null
            : () async {
                final result = await apply(
                  MergeRevision(
                    source!.oid,
                    policy: policy,
                    stopBeforeCommit: stop,
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
          'Merge ${source?.shortName ?? 'source'} into ${reviewed.branch ?? 'HEAD'}',
        ),
      ),
    ],
  );
}

final class GitRemotesView extends StatefulWidget {
  const GitRemotesView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitRemotesView> createState() => _RemotesState();
}

final class _RemotesState extends GitDialogState<GitRemotesView> {
  @override
  GitSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() =>
      load(const GitInspection(GitInspectionKind.remotes));
  @override
  Widget build(BuildContext context) => Column(
    children: [
      states(refresh: refresh),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: loading
              ? null
              : () => unawaited(edit(null, RemoteAction.add)),
          icon: const GitIcon(GitGlyph.add),
          label: const GitLabel('Add remote…'),
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final remote in (data?['remotes'] as List? ?? []).cast<Json>())
              ListTile(
                title: Text(remote['name'] as String),
                subtitle: SelectableText(
                  'Fetch: ${(remote['fetchUrls'] as List).join(', ')}\nPush: ${(remote['pushUrls'] as List).join(', ')}',
                ),
                trailing: GitMenuButton(
                  host: session.host,
                  onSelected: (action) => unawaited(
                    edit(remote, RemoteAction.values.byName(action)),
                  ),
                  entries: [
                    for (final action in RemoteAction.values.where(
                      (e) => e != RemoteAction.add,
                    ))
                      GitMenuEntry((action).name, switch (action) {
                        RemoteAction.rename => 'Rename…',
                        RemoteAction.remove => 'Remove remote…',
                        RemoteAction.setFetchUrl => 'Change fetch URL…',
                        RemoteAction.addPushUrl => 'Add push destination…',
                        RemoteAction.removePushUrl =>
                          'Remove push destination…',
                        _ => '',
                      }),
                  ],
                  tooltip: 'Manage ${remote['name']}',
                ),
              ),
          ],
        ),
      ),
    ],
  );
  Future<void> edit(Json? remote, RemoteAction action) async {
    final state = session.snapshot!;
    final name =
        remote?['name'] as String? ??
        await gitTextInput(context, session, 'Remote name');
    if (!mounted || name == null || name.isEmpty) return;
    String? value;
    if (action != RemoteAction.remove)
      value = await gitTextInput(
        context,
        session,
        action == RemoteAction.rename
            ? 'New remote name'
            : 'Repository URL or local source',
        explanation: action == RemoteAction.removePushUrl
            ? 'Enter the exact reviewed destination to remove.'
            : 'Credentials are supplied by configured helpers or a private prompt.',
      );
    else if (!await gitConfirm(
      context,
      session,
      'Remove remote $name?',
      'Removes local remote configuration and tracking references. It does not delete the server repository.',
      action: 'Remove remote',
    ))
      return;
    if (action != RemoteAction.remove && (value == null || value.isEmpty))
      return;
    await apply(
      RemoteMutation(
        action,
        name,
        value: value,
        expectedConfiguration: remote?['token'] as String?,
        expectedHead: state.head,
        expectedIndex: state.indexToken,
      ),
    );
    if (error == null) await refresh();
  }
}
