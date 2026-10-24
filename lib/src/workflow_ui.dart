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

/// Contextual entry points shared by the compact Commit area and full workspace.
final class GitWorkflowUi {
  const GitWorkflowUi(this.context, this.session);
  final BuildContext context;
  final GitSession session;
  GitWorkflowClient get workflows => session.client as GitWorkflowClient;
  Future<void> branches() => present(
    'Branches',
    SizedBox(
      height: MediaQuery.sizeOf(context).height * .62,
      child: GitBranchesView(session: session),
    ),
  );
  Future<void> push() =>
      present('Push commits', GitPushView(session: session), expanded: true);
  Future<void> pull() => present(
    'Pull into ${session.snapshot?.branch ?? 'detached HEAD'}',
    GitPullView(session: session),
  );
  Future<void> conflict(RepoPath path) => present(
    'Resolve ${path.display}',
    GitConflictView(session: session, path: path),
    expanded: true,
  );
  Future<void> operation() => present(
    'Current operation',
    GitOperationView(session: session),
    expanded: true,
  );
  Future<void> rebase({GitOid? boundary}) => present(
    'Rebase commits',
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
      '$title · ${session.repository.root}',
      child,
      expanded: expanded,
    );
  }

  Future<void> more() async {
    final actions = {
      'fetch': 'Fetch…',
      'pull': 'Pull…',
      'push': 'Push…',
      'branches': 'Branches…',
      'remotes': 'Manage remotes…',
      'merge': 'Merge into ${session.snapshot?.branch ?? 'HEAD'}…',
      'rebase': 'Rebase…',
      'conflicts': 'Conflicts and current operation…',
      'stashes': 'Stashes…',
      'worktrees': 'Worktrees…',
      'submodules': 'Submodules…',
      'recovery': 'Reflog and recovery…',
      'clone': 'Clone repository…',
      if (session.host.revokeRepositoryTrust != null)
        'revokeTrust': 'Revoke repository trust',
    };
    final action = await session.host.menu(context, 'Repository actions', [
      for (final e in actions.entries)
        GitMenuEntry(
          e.key,
          e.value,
          sectionStart: const {
            'merge',
            'stashes',
            'clone',
            'revokeTrust',
          }.contains(e.key),
        ),
    ]);
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'branches':
        await branches();
      case 'push':
        await push();
      case 'pull':
        await pull();
      case 'fetch':
        await present('Fetch', GitFetchView(session: session));
      case 'remotes':
        await present(
          'Manage remotes',
          GitRemotesView(session: session),
          expanded: true,
        );
      case 'merge':
        await present(
          'Merge into ${session.snapshot?.branch ?? 'HEAD'}',
          GitMergeView(session: session),
        );
      case 'rebase':
        await rebase();
      case 'conflicts':
        await operation();
      case 'stashes':
        await present(
          'Stashes',
          GitStashesView(session: session),
          expanded: true,
        );
      case 'worktrees':
        await present(
          'Worktrees',
          GitWorktreesView(session: session),
          expanded: true,
        );
      case 'submodules':
        await present(
          'Submodules',
          GitSubmodulesView(session: session),
          expanded: true,
        );
      case 'recovery':
        await present(
          'Reflog and recovery',
          GitRecoveryView(session: session),
          expanded: true,
        );
      case 'clone':
        final created = await session.host.present<RepositoryId>(
          context,
          'Clone repository · ${session.repository.root}',
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
}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await session.host.present<String>(
      context,
      title,
      Builder(
        builder: (dialogContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (explanation != null)
              Padding(
                padding: EdgeInsets.only(bottom: session.host.spacing),
                child: Text(explanation),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: multiline ? 8 : 1,
              decoration: InputDecoration(
                labelText: title,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: multiline
                  ? null
                  : (value) => Navigator.of(dialogContext).pop(value),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const GitLabel('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(controller.text),
                  child: const GitLabel('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
      expanded: false,
    );
  } finally {
    controller.dispose();
  }
}

Future<bool> gitConfirm(
  BuildContext context,
  GitSession session,
  String title,
  String detail, {
  String action = 'Continue',
}) async =>
    await session.host.present<bool>(
      context,
      title,
      Builder(
        builder: (dialogContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(detail),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const GitLabel('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(action),
                ),
              ],
            ),
          ],
        ),
      ),
      expanded: false,
    ) ==
    true;

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
    if (mounted) setState(() {});
  }

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
                session.progress?.text ?? 'Git operation in progress',
              ),
            ),
            TextButton(
              onPressed: session.cancel,
              child: const GitLabel('Cancel process'),
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
