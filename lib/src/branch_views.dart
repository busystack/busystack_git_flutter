import 'presentation.dart';
import 'reference_context_menu.dart';
import 'messages.dart';
import 'host.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'history_actions.dart';
import 'network_views.dart';
import 'reference_picker.dart';
import 'rebase_view.dart';

final class GitBranchesView extends StatefulWidget {
  const GitBranchesView({super.key, required this.session, this.onOpenFolder});
  final GitSession session;
  final ValueChanged<String>? onOpenFolder;
  @override
  State<GitBranchesView> createState() => _BranchesState();
}

final class _BranchesState extends GitDialogState<GitBranchesView> {
  @override
  GitSession get session => _session;
  late final GitSession _session;
  List<GitReference> refs = [];
  GitSnapshot? reviewed;
  String search = '';
  String? selectedReference;
  final _search = TextEditingController();
  final _searchKey = GlobalKey();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    _session = widget.session;
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(GitBranchesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != _session) {
      generation++;
      refs = [];
      reviewed = null;
      loading = false;
      error = const GitException(GitErrorCode.staleReview);
    }
  }

  Future<void> refresh() async {
    if (!mounted || widget.session != _session) return;
    final current = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await session.client.references(session.repository);
      if (!mounted || current != generation) return;
      final state = await session.readStatus();
      if (mounted && current == generation)
        setState(() {
          refs = values;
          reviewed = state;
        });
    } on GitException catch (failure) {
      if (mounted && current == generation) setState(() => error = failure);
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = session.host, spacing = session.host.spacing;
    final searchField = GitTextField(
      key: _searchKey,
      controller: _search,
      decoration: GitFieldDecoration(
        prefixIcon: const GitIcon(GitGlyph.search, size: 16),
        labelText: gitString(context, GitMessages.searchBranchesAndTags),
        isDense: true,
      ),
      onChanged: (value) => setState(() => search = value),
    );
    final create = GitButton.icon(
      key: const ValueKey('git-new-branch'),
      variant: GitActionStyle.standard,
      compact: true,
      onPressed:
          loading ||
              reviewed?.head == null ||
              !session.canWriteMetadata ||
              session.snapshot?.capabilities.replaceWorkingFiles != true
          ? null
          : () => unawaited(createBranch()),
      icon: const GitIcon(GitGlyph.add, size: 16),
      label: const GitLabel(GitMessages.newBranch),
    );
    final workflows = GitMenuButton(
      key: const ValueKey('git-branch-workflows'),
      host: session.host,
      tooltip: GitMessages.actions,
      glyph: GitGlyph.moreHorizontal,
      entries: [
        GitMenuEntry(
          'merge',
          gitString(
            context,
            GitMessages.mergeIntoArg0,
            values: {'arg0': reviewed?.branch ?? GitMessages.head},
          ),
          enabled:
              !session.running &&
              session.canWriteMetadata &&
              session.snapshot?.capabilities.replaceWorkingFiles == true &&
              session.snapshot?.operation.kind == GitOperationKind.none,
          localize: false,
        ),
        GitMenuEntry(
          'rebase',
          GitMessages.rebase2,
          enabled:
              !session.running &&
              session.canWriteMetadata &&
              session.snapshot?.capabilities.replaceWorkingFiles == true &&
              session.snapshot?.operation.kind == GitOperationKind.none,
        ),
      ],
      onSelected: (action) {
        if (!mounted ||
            session.running ||
            !session.canWriteMetadata ||
            session.snapshot?.capabilities.replaceWorkingFiles != true ||
            session.snapshot?.operation.kind != GitOperationKind.none)
          return;
        final ui = GitWorkflowUi(context, session);
        unawaited(action == 'merge' ? ui.merge() : ui.rebase());
      },
    );
    final groups = const ['refs/heads/', 'refs/remotes/', 'refs/tags/'];
    return GitReferenceNavigation(
      builder: (results) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          states(refresh: refresh),
          GitTooltip(
            message: session.repository.root,
            child: Text(
              session.repository.root
                  .split(RegExp(r'[/\\]'))
                  .where((part) => part.isNotEmpty)
                  .last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GitTheme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(height: spacing),
          if (session.snapshot != null && !session.canWriteMetadata)
            const GitLabel(
              GitMessages
                  .repositoryMetadataIsReadOnlyBranchInspectionAndComparisonRemain,
            ),
          if (session.canWriteMetadata &&
              session.snapshot?.capabilities.replaceWorkingFiles == false)
            const GitLabel(
              GitMessages
                  .workingFilesAreUnavailableOrReadOnlyBranchSwitchingAnd,
            ),
          LayoutBuilder(
            builder: (context, bounds) {
              final painter = TextPainter(
                text: TextSpan(
                  text: gitString(context, GitMessages.newBranch),
                  style: GitTheme.of(context).textTheme.labelLarge,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final searchPainter = TextPainter(
                text: TextSpan(
                  text: gitString(context, GitMessages.searchBranchesAndTags),
                  style: GitTheme.of(context).textTheme.bodyMedium,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              // Reserve the native icon/insets as well as the localized text.
              // Row height alone does not grow with desktop text scaling.
              final compact =
                  bounds.maxWidth <
                  painter.width +
                      searchPainter.width +
                      spacing * 14 +
                      host.rowHeight(context);
              painter.dispose();
              searchPainter.dispose();
              if (compact)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    gitReferenceSearchNavigation(
                      controller: _search,
                      results: results,
                      child: searchField,
                    ),
                    SizedBox(height: spacing),
                    Row(
                      children: [
                        create,
                        SizedBox(width: spacing),
                        workflows,
                      ],
                    ),
                  ],
                );
              return Row(
                children: [
                  Expanded(
                    child: gitReferenceSearchNavigation(
                      controller: _search,
                      results: results,
                      child: searchField,
                    ),
                  ),
                  SizedBox(width: spacing),
                  create,
                  SizedBox(width: spacing),
                  workflows,
                ],
              );
            },
          ),
          SizedBox(height: spacing),
          Flexible(
            child: gitReferenceResults(
              focus: results,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final prefix in groups) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: spacing,
                        vertical: spacing,
                      ),
                      child: Text(
                        gitString(context, switch (prefix) {
                          'refs/heads/' => GitMessages.localBranches,
                          'refs/remotes/' => GitMessages.remoteBranches,
                          _ => GitMessages.tags,
                        }),
                        style: GitTheme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (final reference in refs.where(
                      (e) =>
                          e.name.startsWith(prefix) &&
                          e.name.toLowerCase().contains(search.toLowerCase()),
                    ))
                      _reference(reference, prefix),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reference(GitReference reference, String prefix) {
    final actions = _actions;
    Future<void> menu(Offset position) async {
      if (loading || !actions.isCurrent()) return;
      final result = await session.host.menu(
        context,
        reference.shortName,
        actions.entries(reference),
        position: position,
        localizeTitle: false,
      );
      if (result != null && actions.isCurrent())
        await actions.act(reference, result);
    }

    final metadata = [
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
    ].join(' · ');
    return GitReferenceContextMenu(
      key: ValueKey(reference.name),
      open: loading ? null : menu,
      child: GitTooltip(
        message: '${reference.name}\n$metadata',
        child: GitActionRow(
          dense: true,
          selected: selectedReference == reference.name,
          onTap: () => setState(() => selectedReference = reference.name),
          onSecondaryTapUp: (details) =>
              unawaited(menu(details.globalPosition)),
          leading: GitIcon(
            reference.current
                ? GitGlyph.check
                : prefix == 'refs/tags/'
                ? GitGlyph.tag
                : GitGlyph.branch,
            size: 16,
          ),
          title: Text(
            reference.shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            metadata,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GitTheme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }

  GitBranchActions get _actions {
    final state = reviewed, references = refs;
    return GitBranchActions(
      context,
      session,
      reviewed: state,
      references: references,
      apply: apply,
      refresh: refresh,
      isCurrent: () =>
          mounted &&
          widget.session == _session &&
          !loading &&
          identical(reviewed, state) &&
          identical(refs, references),
      onOpenFolder: widget.onOpenFolder,
    );
  }

  Future<void> createBranch({GitReference? tracking}) =>
      _actions.createBranch(tracking: tracking);
}

/// Branch mutations and confirmations shared by Branches and Log context
/// menus. All requests keep the reviewed HEAD/index/reference-tip identities.
final class GitBranchActions {
  GitBranchActions(
    this.context,
    this.session, {
    required this.reviewed,
    required List<GitReference> references,
    required Future<GitOutcome?> Function(GitMutation) apply,
    required this.refresh,
    required this.isCurrent,
    this.onOpenFolder,
  }) : refs = List.unmodifiable(references),
       _apply = apply;
  final BuildContext context;
  final GitSession session;
  final GitSnapshot? reviewed;
  final List<GitReference> refs;
  final Future<GitOutcome?> Function(GitMutation) _apply;
  final Future<void> Function() refresh;
  final bool Function() isCurrent;
  final ValueChanged<String>? onOpenFolder;
  GitException? error;
  bool get mounted => context.mounted && isCurrent();
  GitWorkflowClient get workflows => session.client as GitWorkflowClient;
  Future<GitOutcome?> apply(GitMutation request) async {
    if (!mounted) return null;
    final result = await _apply(request);
    error = result?.error ?? session.failure;
    return result;
  }

  Future<R?> query<R>(Future<R> Function() action) async {
    try {
      return await action();
    } on Object catch (error) {
      final failure = error is GitException
          ? error
          : GitException(
              GitErrorCode.commandFailed,
              diagnostic: sanitizeGitDiagnostic('$error'),
            );
      if (mounted) session.host.notify(failure.diagnostic);
      return null;
    }
  }

  List<GitMenuEntry> entries(GitReference reference) {
    final local = reference.name.startsWith('refs/heads/');
    final remote = reference.name.startsWith('refs/remotes/');
    final destination = reviewed?.branch ?? GitMessages.head;
    final writable = !session.running && session.canWriteMetadata;
    final canReplace =
        writable &&
        session.snapshot?.capabilities.replaceWorkingFiles == true &&
        session.snapshot?.operation.kind == GitOperationKind.none;
    return [
      if (local && !reference.current)
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
              ? canReplace
              : onOpenFolder != null || session.host.openFolder != null,
        ),
      GitMenuEntry(
        'create',
        GitMessages.createBranch2,
        enabled: canReplace && reviewed?.head != null,
      ),
      if (remote)
        GitMenuEntry(
          'track',
          GitMessages.createLocalTrackingBranch,
          enabled: canReplace,
        ),
      GitMenuEntry(
        'compare',
        GitMessages.compareToCurrentHEAD,
        enabled: reviewed?.head != null,
      ),
      if (!reference.current) ...[
        GitMenuEntry(
          'merge',
          gitString(
            context,
            GitMessages.mergeArg0IntoArg1,
            values: {'arg0': reference.shortName, 'arg1': destination},
          ),
          enabled: canReplace,
        ),
        GitMenuEntry(
          'rebase',
          gitString(
            context,
            GitMessages.rebaseArg0OntoArg1,
            values: {'arg0': destination, 'arg1': reference.shortName},
          ),
          enabled: canReplace,
        ),
      ],
      if (local) ...[
        GitMenuEntry('rename', GitMessages.rename, enabled: writable),
        GitMenuEntry('upstream', GitMessages.changeUpstream, enabled: writable),
      ],
      const GitMenuEntry.separator(),
      if (!remote)
        GitMenuEntry(
          'delete',
          GitMessages.delete,
          enabled:
              writable &&
              (!local || !reference.current && reference.worktreePath == null),
        ),
      GitMenuEntry(
        'remoteDelete',
        GitMessages.deleteFromRemote,
        enabled: writable,
      ),
    ];
  }

  Future<void> createBranch({
    GitReference? tracking,
    GitReference? start,
  }) async {
    if (!mounted) return;
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
              values: {'arg0': (start?.oid ?? state!.head!).abbreviated},
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
        start: tracking?.oid ?? start?.oid ?? state!.head,
        upstream: tracking?.name,
        switchAfterCreate: true,
        expectedHead: state!.head,
        expectedIndex: state.indexToken,
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> act(GitReference reference, String action) async {
    if (!mounted) return;
    final state = reviewed;
    if (state == null) return;
    final name = reference.shortName;
    if (action == 'track') return createBranch(tracking: reference);
    if (action == 'create') return createBranch(start: reference);
    if (action == 'rebase') {
      await GitWorkflowUi(context, session).present(
        gitString(
          context,
          GitMessages.rebaseArg0OntoArg1,
          values: {'arg0': state.branch ?? GitMessages.head, 'arg1': name},
        ),
        GitRebaseView(session: session, source: reference),
        expanded: true,
      );
      if (mounted) await refresh();
      return;
    }
    if (action == 'open') {
      if (onOpenFolder case final open?) {
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
      if (mounted) await refresh();
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
      if (mounted) await refresh();
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
      if (error == null && mounted) await refresh();
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
  GitRevisionTarget? source;
  MergePolicy policy = MergePolicy.fastForward;
  bool stop = false;
  @override
  void initState() {
    super.initState();
    reviewed = session.snapshot!;
    final initial = widget.source;
    if (initial != null)
      source = GitRevisionTarget(
        initial.oid,
        initial.shortName,
        reference: initial.name,
        referenceTip: initial.oid,
      );
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
      GitButton.icon(
        variant: GitActionStyle.standard,
        onPressed: loading
            ? null
            : () async {
                final chosen = await gitChooseRevision(
                  context,
                  session,
                  GitMessages.sourceBranchOrTag,
                );
                if (mounted && chosen != null) setState(() => source = chosen);
              },
        icon: const GitIcon(GitGlyph.branch),
        label: Text(
          source == null
              ? gitString(context, GitMessages.sourceBranchOrTag)
              : '${source!.label} · ${source!.oid.abbreviated}',
        ),
      ),
      SizedBox(height: session.host.spacing),
      GitChoice<MergePolicy>(
        initialValue: policy,
        isExpanded: true,
        decoration: GitFieldDecoration(
          labelText: gitString(context, GitMessages.mergePolicy),
        ),
        items: [
          for (final p in MergePolicy.values)
            GitChoiceItem(
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
      GitCheckRow(
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
      GitButton.primary(
        onPressed: loading || source == null
            ? null
            : () async {
                if (source!.reference case final reference?) {
                  final refs = await query(
                    () => session.client.references(session.repository),
                  );
                  if (refs == null || !mounted) return;
                  if (!refs.any(
                    (ref) =>
                        ref.name == reference &&
                        ref.oid == source!.referenceTip,
                  )) {
                    session.reportFailure(
                      const GitException(GitErrorCode.staleReview),
                    );
                    return;
                  }
                }
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
              'arg0':
                  source?.label ??
                  gitString(context, GitMessages.sourceBranchOrTag),
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
        child: GitButton.icon(
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
              GitActionRow(
                title: Text(remote['name'] as String),
                subtitle: GitSelectableText(
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
