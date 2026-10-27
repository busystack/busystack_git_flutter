import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'branch_views.dart';
import 'network_views.dart';
import 'organization_views.dart';
import 'creation_view.dart';
import 'history_actions.dart';
import 'conflict_view.dart';
import 'rebase_view.dart';
import 'host.dart';
import 'session.dart';
import 'text_undo.dart';

/// Contextual entry points shared by the compact Commit area and full workspace.
final class GitWorkflowUi {
  const GitWorkflowUi(this.context, this.session);
  final BuildContext context;
  final GitSession session;
  GitWorkflowClient get workflows => session.client as GitWorkflowClient;
  Future<void> branches() => _folderDialog(
    GitMessages.branches,
    (open) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .62,
      child: GitBranchesView(session: session, onOpenFolder: open),
    ),
  );
  Future<void> push() => present(
    GitMessages.pushCommits,
    GitPushView(session: session),
    expanded: true,
  );
  Future<void> pull() => present(
    gitString(
      context,
      GitMessages.pullIntoArg0,
      values: {
        'arg0':
            session.snapshot?.branch ??
            gitString(context, GitMessages.detachedHEAD),
      },
    ),
    GitPullView(session: session),
  );
  Future<void> conflict(RepoPath path) => present(
    gitString(context, GitMessages.resolveArg0, values: {'arg0': path.display}),
    GitConflictView(session: session, path: path),
    expanded: true,
  );
  Future<void> operation() => present(
    GitMessages.currentOperation,
    GitOperationView(session: session),
    expanded: true,
  );
  Future<void> rebase({GitOid? boundary}) => present(
    GitMessages.rebaseCommits,
    GitRebaseView(session: session, boundary: boundary),
    expanded: true,
  );
  Future<void> commitAction(GitCommit commit, String action) =>
      GitHistoryActions(this).run(commit, action);
  Future<void> present(
    String title,
    Widget child, {
    bool expanded = false,
  }) async {
    await session.host.present<void>(
      context,
      '${session.host.message(title)} · ${session.repository.root}',
      child,
      expanded: expanded,
    );
  }

  Future<void> _folderDialog(
    String title,
    Widget Function(ValueChanged<String>) build, {
    bool expanded = false,
  }) async {
    final folder = await session.host.present<String>(
      context,
      '${session.host.message(title)} · ${session.repository.root}',
      Builder(
        builder: (dialogContext) =>
            build((folder) => Navigator.of(dialogContext).pop(folder)),
      ),
      expanded: expanded,
    );
    if (folder != null) await session.host.openFolder?.call(folder);
  }

  Future<void> more() async {
    final actions = {
      'fetch': GitMessages.fetch2,
      'pull': GitMessages.pull,
      'push': GitMessages.push2,
      'branches': GitMessages.branches2,
      'remotes': GitMessages.manageRemotes,
      'merge': gitString(
        context,
        GitMessages.mergeIntoArg0,
        values: {'arg0': session.snapshot?.branch ?? GitMessages.head},
      ),
      'rebase': GitMessages.rebase2,
      'conflicts': GitMessages.conflictsAndCurrentOperation,
      'stashes': GitMessages.stashes2,
      'worktrees': GitMessages.worktrees,
      'submodules': GitMessages.submodules,
      'recovery': GitMessages.reflogAndRecovery,
      'clone': GitMessages.cloneRepository,
      if (session.host.revokeRepositoryTrust != null)
        'revokeTrust': GitMessages.revokeRepositoryTrust,
    };
    final action = await session.host.menu(
      context,
      GitMessages.repositoryActions,
      [
        for (final e in actions.entries)
          GitMenuEntry(
            e.key,
            session.snapshot != null ||
                    const {'clone', 'revokeTrust'}.contains(e.key)
                ? e.value
                : '${session.host.message(e.value)} · ${session.loading ? gitString(context, GitMessages.waitingForRepositoryStatus) : gitString(context, GitMessages.repositoryStatusUnavailableRefresh)}',
            enabled:
                session.snapshot != null ||
                const {'clone', 'revokeTrust'}.contains(e.key),
            sectionStart: const {
              'merge',
              'stashes',
              'clone',
              'revokeTrust',
            }.contains(e.key),
          ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'branches':
        await branches();
      case 'push':
        await push();
      case 'pull':
        await pull();
      case 'fetch':
        await present(GitMessages.fetch, GitFetchView(session: session));
      case 'remotes':
        await present(
          GitMessages.manageRemotes2,
          GitRemotesView(session: session),
          expanded: true,
        );
      case 'merge':
        await present(
          gitString(
            context,
            GitMessages.mergeIntoArg02,
            values: {'arg0': session.snapshot?.branch ?? GitMessages.head},
          ),
          GitMergeView(session: session),
        );
      case 'rebase':
        await rebase();
      case 'conflicts':
        await operation();
      case 'stashes':
        await present(
          GitMessages.stashes,
          GitStashesView(session: session),
          expanded: true,
        );
      case 'worktrees':
        await _folderDialog(
          GitMessages.worktrees2,
          (open) => GitWorktreesView(session: session, onOpenFolder: open),
          expanded: true,
        );
      case 'submodules':
        await _folderDialog(
          GitMessages.submodules2,
          (open) => GitSubmodulesView(session: session, onOpenFolder: open),
          expanded: true,
        );
      case 'recovery':
        await present(
          GitMessages.reflogAndRecovery2,
          GitRecoveryView(session: session),
          expanded: true,
        );
      case 'clone':
        final created = await session.host.present<RepositoryId>(
          context,
          gitString(
            context,
            GitMessages.cloneRepositoryArg0,
            values: {'arg0': session.repository.root},
          ),
          GitCreationView(
            client: workflows,
            chooseDirectory: session.host.chooseDirectory,
          ),
        );
        if (created != null) await session.host.openFolder?.call(created.root);
      case 'revokeTrust':
        await session.host.revokeRepositoryTrust?.call(session.repository);
        session.restrictInspection();
        await session.refresh();
    }
  }
}

final class GitActionMenu extends StatelessWidget {
  const GitActionMenu({super.key, required this.actions});
  final Map<String, String> actions;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .7,
      maxWidth: 500,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final entry in actions.entries)
          ListTile(
            dense: true,
            title: Text(entry.value),
            onTap: () => Navigator.of(context).pop(entry.key),
          ),
      ],
    ),
  );
}

Future<String?> gitTextInput(
  BuildContext context,
  GitSession session,
  String title, {
  String initial = '',
  String? explanation,
  bool multiline = false,
}) => session.host.present<String>(
  context,
  title,
  _GitTextInput(
    title: title,
    initial: initial,
    explanation: explanation,
    multiline: multiline,
    spacing: session.host.spacing,
  ),
  expanded: false,
);

// A presentation future may resolve before its route's closing animation has
// removed the field. The dialog owns its controller until actual unmounting.
final class _GitTextInput extends StatefulWidget {
  const _GitTextInput({
    required this.title,
    required this.initial,
    required this.explanation,
    required this.multiline,
    required this.spacing,
  });
  final String title, initial;
  final String? explanation;
  final bool multiline;
  final double spacing;
  @override
  State<_GitTextInput> createState() => _GitTextInputState();
}

final class _GitTextInputState extends State<_GitTextInput> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.explanation != null)
        Padding(
          padding: EdgeInsets.only(bottom: widget.spacing),
          child: GitLabel(widget.explanation!),
        ),
      GitTextUndo(
        controller: controller,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: widget.multiline ? 8 : 1,
          decoration: InputDecoration(
            labelText: gitString(context, widget.title),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: widget.multiline
              ? null
              : (value) => Navigator.of(context).pop(value),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const GitLabel(GitMessages.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const GitLabel(GitMessages.apply),
          ),
        ],
      ),
    ],
  );
}

Future<bool> gitConfirm(
  BuildContext context,
  GitSession session,
  String title,
  String detail, {
  String action = GitMessages.continueAction,
}) async {
  var decisionSubmitted = false;
  final result = await session.host.present<bool>(
    context,
    title,
    Builder(
      builder: (dialogContext) {
        final route = ModalRoute.of(dialogContext);
        void decide(bool result) {
          if (decisionSubmitted ||
              !dialogContext.mounted ||
              route?.isCurrent != true) {
            return;
          }
          decisionSubmitted = true;
          Navigator.of(dialogContext).pop(result);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GitSelectableText(gitString(context, detail)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => decide(false),
                  child: const GitLabel(GitMessages.cancel),
                ),
                FilledButton(
                  onPressed: () => decide(true),
                  child: GitLabel(action),
                ),
              ],
            ),
          ],
        );
      },
    ),
    expanded: false,
  );
  decisionSubmitted = true;
  return result == true;
}

/// Common query/error lifecycle for focused Git dialogs. Each instance remains
/// bound to its original session and repository throughout asynchronous work.
abstract class GitDialogState<T extends StatefulWidget> extends State<T> {
  GitSession get session;
  Json? data;
  GitException? error;
  bool loading = false;
  int generation = 0;
  GitCancellation? cancellation;
  GitWorkflowClient get workflows => session.client as GitWorkflowClient;
  @override
  void initState() {
    super.initState();
    session.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (mounted) {
      setState(() {});
      onSessionChanged();
    }
  }

  void onSessionChanged() {}

  Future<R?> query<R>(Future<R> Function() action) async {
    try {
      return await action();
    } on Object catch (failure) {
      if (mounted)
        setState(
          () => error = failure is GitException
              ? failure
              : GitException(
                  GitErrorCode.commandFailed,
                  diagnostic: sanitizeGitDiagnostic('$failure'),
                ),
        );
      return null;
    }
  }

  Future<void> load(GitInspection request) async {
    final current = ++generation;
    cancellation?.cancel();
    final token = cancellation = GitCancellation();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (await session.host.prepareInspection?.call(
            session.repository,
            request,
          ) ==
          false)
        return;
      if (!mounted || generation != current || token.isCancelled) return;
      final value = await workflows.inspect(
        session.repository,
        request,
        cancellation: token,
      );
      if (mounted && generation == current) setState(() => data = value);
    } on Object catch (failure) {
      if (mounted && generation == current)
        setState(
          () => error = failure is GitException
              ? failure
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$failure'),
                ),
        );
    } finally {
      if (mounted && generation == current) setState(() => loading = false);
    }
  }

  Future<GitOutcome?> apply(GitMutation request) async {
    setState(() => loading = true);
    final result = await session.mutate(request);
    if (mounted)
      setState(() {
        loading = false;
        error = result?.error ?? session.failure;
      });
    return result;
  }

  Widget states({VoidCallback? refresh}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (loading) const LinearProgressIndicator(),
      if (error case final failure?)
        GitFailurePanel(error: failure, onRefresh: refresh),
      if (session.running)
        Row(
          children: [
            Expanded(
              child: Text(
                session.progress?.text.isNotEmpty == true
                    ? session.progress!.text
                    : gitString(context, GitMessages.gitOperationInProgress),
              ),
            ),
            TextButton(
              onPressed: session.cancel,
              child: const GitLabel(GitMessages.cancelProcess),
            ),
          ],
        ),
    ],
  );
  @override
  void dispose() {
    generation++;
    cancellation?.cancel();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
