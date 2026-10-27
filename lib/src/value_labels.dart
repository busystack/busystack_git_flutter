import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/widgets.dart';
import 'host.dart';
import 'messages.dart';

/// Display labels only. Wire values, Git commands and repository data retain
/// their original identities.
String gitEnumLabel(BuildContext context, Enum value) =>
    gitString(context, gitEnumMessage(value));
String gitEnumMessage(Enum value) => switch (value) {
  RebaseAction.pick => GitMessages.pick,
  RebaseAction.reword => GitMessages.reword,
  RebaseAction.edit => GitMessages.edit,
  RebaseAction.squash => GitMessages.squash,
  RebaseAction.fixup => GitMessages.fixup,
  RebaseAction.drop => GitMessages.drop,
  GitContinuation.continueOperation => GitMessages.continueAction,
  GitContinuation.abort => GitMessages.abort,
  GitContinuation.skip => GitMessages.skip,
  GitContinuation.quit => GitMessages.quit,
  ResetMode.soft => GitMessages.soft,
  ResetMode.mixed => GitMessages.mixed,
  ResetMode.hard => GitMessages.hard,
  ResetMode.keep => GitMessages.keep,
  StashAction.create => GitMessages.create,
  StashAction.apply => GitMessages.applyStash,
  StashAction.pop => GitMessages.popStash,
  StashAction.drop => GitMessages.dropStashAction,
  StashAction.branch => GitMessages.branchFromStash,
  ConflictChoice.edited => GitMessages.editedResult,
  ConflictChoice.left => GitMessages.leftContent,
  ConflictChoice.right => GitMessages.rightContent,
  ConflictChoice.delete => GitMessages.deletePath,
  ConflictChoice.gitlink => GitMessages.submoduleCommit,
  ContentAvailability.present => GitMessages.presentContent,
  ContentAvailability.absent => GitMessages.absentContent,
  ContentAvailability.binary => GitMessages.binaryContent,
  ContentAvailability.tooLarge => GitMessages.tooLargeContent,
  ContentAvailability.unavailable => GitMessages.unavailableContent,
  ContentAvailability.gitlink => GitMessages.gitlinkContent,
  ContentAvailability.symlink => GitMessages.symlinkContent,
  GitOperationKind.none => GitMessages.noOperation,
  GitOperationKind.merge => GitMessages.mergeOperation,
  GitOperationKind.rebase => GitMessages.rebaseOperation,
  GitOperationKind.cherryPick => GitMessages.cherryPickOperation,
  GitOperationKind.revert => GitMessages.revertOperation,
  GitOperationKind.applyMailbox => GitMessages.applyMailboxOperation,
  GitOperationKind.squash => GitMessages.squashOperation,
  GitOperationKind.unmerged => GitMessages.unmergedOperation,
  GitOperationPhase.preparing => GitMessages.preparingPhase,
  GitOperationPhase.running => GitMessages.runningPhase,
  GitOperationPhase.waitingForPrompt => GitMessages.waitingForPromptPhase,
  GitOperationPhase.stopped => GitMessages.stoppedPhase,
  GitOperationPhase.completed => GitMessages.completedPhase,
  GitOperationPhase.failed => GitMessages.failedPhase,
  GitOperationPhase.cancelled => GitMessages.cancelledPhase,
  GitOperationPhase.uncertain => GitMessages.uncertainPhase,
  _ => throw ArgumentError.value(value, 'value', 'No Git display label'),
};
String gitVersionLabel(BuildContext context, ContentVersion version) =>
    switch (version.kind) {
      ContentKind.workingTree => gitString(context, GitMessages.workingTree),
      ContentKind.indexVersion => gitString(context, GitMessages.index),
      ContentKind.commit => version.revision!.abbreviated,
      ContentKind.conflictStage => gitString(
        context,
        GitMessages.stageVersion,
        values: {'stage': version.stage},
      ),
      ContentKind.absent => gitString(context, GitMessages.absentContent),
      ContentKind.mergePreview => gitString(
        context,
        GitMessages.gitMergePreview,
      ),
      ContentKind.normalizedWorking => gitString(
        context,
        GitMessages.normalizedWorking,
      ),
    };
