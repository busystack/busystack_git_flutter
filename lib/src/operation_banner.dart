import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'host.dart';
import 'session.dart';
import 'workflow_ui.dart';

final class GitOperationBanner extends StatelessWidget {
  const GitOperationBanner({super.key, required this.session});
  final GitSession session;

  @override
  Widget build(BuildContext context) {
    final operation = session.snapshot?.operation;
    if (operation == null || operation.kind == GitOperationKind.none) {
      return const SizedBox.shrink();
    }
    final title = switch (operation.kind) {
      GitOperationKind.merge => GitMessages.mergeInProgress,
      GitOperationKind.rebase => GitMessages.rebaseInProgress,
      GitOperationKind.cherryPick => GitMessages.cherryPickInProgress,
      GitOperationKind.revert => GitMessages.revertInProgress,
      GitOperationKind.applyMailbox => GitMessages.patchApplicationInProgress,
      GitOperationKind.squash => GitMessages.squashMergeResultAwaitingCommit,
      GitOperationKind.unmerged => GitMessages.unresolvedIndexConflicts,
      GitOperationKind.none => '',
    };
    return MaterialBanner(
      content: Text(
        gitString(context, title) +
            (operation.unmerged && operation.kind != GitOperationKind.unmerged
                ? gitString(context, GitMessages.unresolvedConflicts)
                : ''),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              unawaited(GitWorkflowUi(context, session).operation()),
          child: const GitLabel(GitMessages.reviewOperation),
        ),
      ],
    );
  }
}
