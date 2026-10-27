import 'messages.dart';
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
          GitMessages
              .repositoryMetadataIsReadOnlyBranchInspectionAndComparisonRemain,
        ),
      if (session.canWriteMetadata &&
          session.snapshot?.capabilities.replaceWorkingFiles == false)
        const GitLabel(
          GitMessages.workingFilesAreUnavailableOrReadOnlyBranchSwitchingAnd,
        ),
      Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: GitIcon(GitGlyph.search),
                labelText: gitString(
                  context,
                  GitMessages.searchBranchesAndTags,
                ),
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
            label: const GitLabel(GitMessages.newBranch),
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
                  'refs/heads/' => gitString(
                    context,
                    GitMessages.localBranches,
                  ),
                  'refs/remotes/' => gitString(
                    context,
                    GitMessages.remoteBranches,
                  ),
                  _ => gitString(context, GitMessages.tags),
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
                        gitString(
                          context,
                          GitMessages.tracksArg0,
                          values: {'arg0': reference.upstream},
                        ),
                      if (reference.worktreePath != null)
                        gitString(
                          context,
                          GitMessages.checkedOutAtArg0,
                          values: {'arg0': reference.worktreePath},
                        ),
                      reference.oid.abbreviated,
                    ].join(' · '),
                  ),
                  trailing: GitMenuButton(
                    host: session.host,
                    enabled: !loading,
                    disabledReason: GitMessages.refreshingBranchMetadata,
                    onSelected: (action) => unawaited(act(reference, action)),
                    entries: [
                      if (prefix == 'refs/heads/' && !reference.current)
                        GitMenuEntry(
                          reference.worktreePath == null ? 'switch' : 'open',
                          reference.worktreePath == null
                              ? gitString(
                                  context,
                                  GitMessages.switchToArg0,
                                  values: {'arg0': reference.shortName},
                                )
                              : GitMessages.openOccupiedWorktree,
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
                          GitMessages.createLocalTrackingBranch,
                          enabled:
                              session.canWriteMetadata &&
                              session
                                      .snapshot
                                      ?.capabilities
                                      .replaceWorkingFiles ==
                                  true,
                        ),
                      GitMenuEntry('compare', GitMessages.compareToCurrentHEAD),
                      GitMenuEntry(
                        'merge',
                        GitMessages.mergeIntoCurrentBranch,
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
                          GitMessages.rename,
                          enabled: session.canWriteMetadata,
                        ),
                        GitMenuEntry(
                          'upstream',
                          GitMessages.changeUpstream,
                          enabled: session.canWriteMetadata,
                        ),
                      ],
                      const GitMenuEntry.separator(),
                      if (prefix != 'refs/remotes/')
                        GitMenuEntry(
                          'delete',
                          GitMessages.delete,
                          enabled: session.canWriteMetadata,
                        ),
                      GitMenuEntry(
                        'remoteDelete',
                        GitMessages.deleteFromRemote,
                        enabled: session.canWriteMetadata,
                      ),
                    ],
                    tooltip: gitString(
                      context,
                      GitMessages.actionsForArg0,
                      values: {'arg0': reference.name},
                    ),
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
      GitMessages.localBranchName,
      initial: tracking?.shortName.split('/').skip(1).join('/') ?? '',
      explanation: tracking == null
          ? gitString(
              context,
              GitMessages.createAtArg0TheNewBranchWillBeCheckedOut,
              values: {'arg0': state!.head!.abbreviated},
            )
          : gitString(
              context,
              GitMessages.theLocalBranchWillTrackArg0AndBeCheckedOut,
              values: {'arg0': tracking.name},
            ),
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
            GitMessages.chooseRemoteForDeletion,
            GitActionMenu(actions: {for (final name in names) name: name}),
            expanded: false,
          );
      if (!mounted || remote == null) return;
      final target = owner != null
          ? 'refs/heads/${reference.name.substring('refs/remotes/$owner/'.length)}'
          : reference.name;
      await GitWorkflowUi(context, session).present(
        GitMessages.deleteRemoteReference,
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
        gitString(
          context,
          GitMessages.mergeArg0IntoArg1,
          values: {'arg0': name, 'arg1': state.branch ?? GitMessages.head},
        ),
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
        gitString(context, GitMessages.renameArg0, values: {'arg0': name}),
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
        gitString(context, GitMessages.upstreamForArg0, values: {'arg0': name}),
        GitActionMenu(
          actions: {
            '': gitString(context, GitMessages.noUpstream),
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
          gitString(context, GitMessages.deleteArg0, values: {'arg0': name}),
          gitString(
            context,
            GitMessages.arg0TargetArg1LocalDeletionOnlyAnUnmergedBranchIs,
            values: {'arg0': reference.name, 'arg1': reference.oid.value},
          ),
          action: GitMessages.delete2,
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
          gitString(
            context,
            GitMessages.deleteUnmergedBranchArg0,
            values: {'arg0': name},
          ),
          gitString(
            context,
            GitMessages.arg0GitReportsThisBranchIsNotFullyMergedExplicitly,
            values: {'arg0': reference.oid.value},
          ),
          action: GitMessages.deleteUnmergedLocalBranch,
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
        gitString(
          context,
          GitMessages.destinationArg0Arg1,
          values: {
            'arg0':
                reviewed.branch ?? gitString(context, GitMessages.detachedHEAD),
            'arg1': reviewed.head?.abbreviated,
          },
        ),
      ),
      states(),
      DropdownButtonFormField<String>(
        initialValue: source?.name,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: gitString(context, GitMessages.sourceBranchOrTag),
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
          labelText: gitString(context, GitMessages.mergePolicy),
        ),
        items: [
          for (final p in MergePolicy.values)
            DropdownMenuItem(
              value: p,
              child: Text(switch (p) {
                MergePolicy.fastForward => gitString(
                  context,
                  GitMessages.fastForwardWhenPossible,
                ),
                MergePolicy.noFastForward => gitString(
                  context,
                  GitMessages.alwaysCreateAMergeCommit,
                ),
                MergePolicy.fastForwardOnly => gitString(
                  context,
                  GitMessages.fastForwardOnly,
                ),
                MergePolicy.squash => gitString(
                  context,
                  GitMessages.squashIntoStagedChanges,
                ),
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
        title: const GitLabel(GitMessages.stopBeforeCreatingTheMergeCommit),
        subtitle: stop
            ? const GitLabel(
                GitMessages.fastForwardIsDisabledSoHEADCannotMoveBeforeReview,
              )
            : null,
      ),
      Text(
        policy == MergePolicy.squash
            ? gitString(
                context,
                GitMessages.leavesStagedChangesForASeparateCommitThisIsNot,
              )
            : gitString(
                context,
                GitMessages
                    .conflictsRemainAvailableInTheSharedResolutionWorkspace,
              ),
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
          gitString(
            context,
            GitMessages.mergeArg0IntoArg1,
            values: {
              'arg0': source?.shortName ?? 'source',
              'arg1': reviewed.branch ?? GitMessages.head,
            },
          ),
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
          label: const GitLabel(GitMessages.addRemote),
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final remote in (data?['remotes'] as List? ?? []).cast<Json>())
              ListTile(
                title: Text(remote['name'] as String),
                subtitle: SelectableText(
                  gitString(
                    context,
                    GitMessages.fetchArg0PushArg1,
                    values: {
                      'arg0': (remote['fetchUrls'] as List).join(', '),
                      'arg1': (remote['pushUrls'] as List).join(', '),
                    },
                  ),
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
                        RemoteAction.rename => GitMessages.rename,
                        RemoteAction.remove => GitMessages.removeRemote,
                        RemoteAction.setFetchUrl => GitMessages.changeFetchURL,
                        RemoteAction.addPushUrl =>
                          GitMessages.addPushDestination,
                        RemoteAction.removePushUrl =>
                          GitMessages.removePushDestination,
                        _ => '',
                      }),
                  ],
                  tooltip: gitString(
                    context,
                    GitMessages.manageArg0,
                    values: {'arg0': remote['name']},
                  ),
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
        await gitTextInput(context, session, GitMessages.remoteName);
    if (!mounted || name == null || name.isEmpty) return;
    String? value;
    if (action != RemoteAction.remove)
      value = await gitTextInput(
        context,
        session,
        action == RemoteAction.rename
            ? GitMessages.newRemoteName
            : GitMessages.repositoryURLOrLocalSource,
        explanation: action == RemoteAction.removePushUrl
            ? GitMessages.enterTheExactReviewedDestinationToRemove
            : GitMessages
                  .credentialsAreSuppliedByConfiguredHelpersOrAPrivatePrompt,
      );
    else if (!await gitConfirm(
      context,
      session,
      gitString(context, GitMessages.removeRemoteArg0, values: {'arg0': name}),
      GitMessages.removesLocalRemoteConfigurationAndTrackingReferencesItDoesNot,
      action: GitMessages.removeRemote2,
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
