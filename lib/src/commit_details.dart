import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/widgets.dart';

import 'host.dart';
import 'messages.dart';
import 'presentation.dart';

/// Complete immutable metadata. The host owns compact sizing and overflow;
/// this content must not introduce another scroll view or expanded surface.
final class GitCommitDetails extends StatelessWidget {
  const GitCommitDetails({
    super.key,
    required this.commit,
    required this.references,
  });

  final GitCommit commit;
  final List<GitReference> references;

  @override
  Widget build(BuildContext context) {
    final host = GitHostScope.of(context)!;
    final theme = GitTheme.of(context);
    Widget field(String label, Widget value) => Padding(
      padding: EdgeInsets.only(bottom: host.spacing * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: GitLabel(label, style: theme.textTheme.titleSmall),
          ),
          SizedBox(height: host.spacing / 2),
          value,
        ],
      ),
    );
    Widget identity(String name, String email, DateTime? date) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GitSelectableText(name),
        if (email.isNotEmpty) GitSelectableText(email),
        if (date != null)
          GitTooltip(
            message: date.toIso8601String(),
            child: GitSelectableText(
              gitPresentation(
                context,
              ).formatCommitDate(context, date, full: true),
            ),
          ),
      ],
    );
    return Column(
      key: const ValueKey('git-complete-commit-information'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field(
          GitMessages.commitMessage,
          GitSelectableText(
            commit.message,
            key: const ValueKey('git-commit-message'),
          ),
        ),
        field(
          GitMessages.author2,
          identity(commit.author, commit.email, commit.date),
        ),
        field(
          GitMessages.committer,
          identity(
            commit.committer,
            commit.committerEmail,
            commit.committerDate,
          ),
        ),
        field(GitMessages.commitHash, GitSelectableText(commit.oid.value)),
        if (commit.parents.isNotEmpty)
          field(
            GitMessages.parents,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final parent in commit.parents)
                  GitSelectableText(parent.value),
              ],
            ),
          ),
        if (references.isNotEmpty)
          field(
            GitMessages.commitReferences,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final reference in references)
                  GitSelectableText(reference.name),
              ],
            ),
          ),
        if (commit.boundary)
          const GitLabel(
            GitMessages.shallowPartialBoundaryAParentObjectIsUnavailable,
          ),
      ],
    );
  }
}
