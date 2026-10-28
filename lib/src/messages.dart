// Shared message templates. Translation belongs to each host’s Flutter ARB catalog.
abstract final class GitMessages {
  static const mergeInProgress = "Merge in progress";
  static const rebaseInProgress = "Rebase in progress";
  static const cherryPickInProgress = "Cherry-pick in progress";
  static const revertInProgress = "Revert in progress";
  static const patchApplicationInProgress = "Patch application in progress";
  static const squashMergeResultAwaitingCommit =
      "Squash merge result awaiting commit";
  static const unresolvedIndexConflicts = "Unresolved index conflicts";
  static const unresolvedConflicts = " · unresolved conflicts";
  static const reviewOperation = "Review operation";
  static const refresh = "Refresh";
  static const createNamedStash = "Create named stash";
  static const createStash = "Create stash…";
  static const noStashes = "No stashes";
  static const selectAStashToInspectItsChanges =
      "Select a stash to inspect its changes";
  static const stashedUntrackedFiles = "Stashed untracked files";
  static const inspectStashedUntrackedFiles =
      "Inspect stashed untracked files…";
  static const reinstateTheStashSStagedIndexStateWhenApplying =
      "Reinstate the stash’s staged/index state when applying";
  static const applyAndRetain = "Apply and retain";
  static const pop = "Pop…";
  static const createBranch = "Create branch…";
  static const dropStash = "Drop stash…";
  static const branchFromStash = "Branch from stash";
  static const createSwitchToABranchAtTheStashSOriginal =
      "Create/switch to a branch at the stash’s original base, then apply it. The original stash is retained for explicit later deletion.";
  static const arg0ThisStash = "{arg0} this stash?";
  static const theOriginalStashIsRetainedIfApplyingConflicts =
      "The original stash is retained if applying conflicts.";
  static const deletesThisStashEntryItsChangesAreNotApplied =
      "Deletes this stash entry. Its changes are not applied.";
  static const resolveTheUnmergedFilesGitHasNoStashContinueOr =
      "Resolve the unmerged files. Git has no stash continue or abort command; the original stash remains.";
  static const stashNameMessage = "Stash name/message";
  static const stashContentAndResultingIndex =
      "Stash content and resulting index";
  static const stashTrackedWorkingAndStagedChanges =
      "Stash tracked working and staged changes";
  static const stashChangesLeaveStagedChangesInPlaceKeepIndex =
      "Stash changes, leave staged changes in place (--keep-index)";
  static const stashOnlyStagedChangesStaged =
      "Stash only staged changes (--staged)";
  static const includeUntrackedFiles = "Include untracked files";
  static const allEligiblePathsInThisRepository =
      "All eligible paths in this repository";
  static const noEligibleChangesForTheseStashOptions =
      "No eligible changes for these stash options.";
  static const selectAtLeastOneEligiblePath =
      "Select at least one eligible path.";
  static const createStash2 = "Create stash";
  static const createWorktree = "Create worktree…";
  static const createACommitBeforeCreatingAWorktreeAtHEAD =
      "Create a commit before creating a worktree at HEAD.";
  static const detachedHEAD = "detached HEAD";
  static const current = "Current · ";
  static const locked = "Locked · ";
  static const openInBusyStack = "Open in BusyStack · ";
  static const statusNotInspected = "Status not inspected";
  static const dirty = "Dirty";
  static const clean = "Clean";
  static const openWorkingFolder = "Open working folder";
  static const moveWorktree = "Move worktree…";
  static const unlock = "Unlock";
  static const lock = "Lock";
  static const removeCleanWorktree = "Remove clean worktree…";
  static const reviewRemovalIncludingLocalChanges =
      "Review removal including local changes…";
  static const newWorktreeFolderName = "New worktree folder name";
  static const newWorktreeBranch = "New worktree branch";
  static const createArg0Arg1WithANewLocalBranchAtArg2 =
      "Create {arg0}/{arg1} with a new local branch at {arg2} ({arg3}).";
  static const destinationFolderName = "Destination folder name";
  static const removeWorktree = "Remove worktree?";
  static const explicitlyDiscardAllLocalTrackedUntrackedChangesInThisWorktree =
      "Explicitly discard all local tracked/untracked changes in this worktree. Locked/in-use worktrees remain protected.";
  static const gitRefusesRemovalIfThereAreLocalChangesUntrackedFiles =
      "Git refuses removal if there are local changes, untracked files, or a lock.";
  static const discardLocalWorktreeContentsAndRemove =
      "Discard local worktree contents and remove";
  static const removeCleanWorktree2 = "Remove clean worktree";
  static const explicitlyRecurseIntoNestedSubmodulesForUpdatesSynchronization =
      "Explicitly recurse into nested submodules for updates/synchronization";
  static const noRecordedSubmodules = "No recorded submodules";
  static const notInitialized = "not initialized";
  static const parentGitlinkArg0CheckedOutArg1 =
      "Parent gitlink: {arg0}\nChecked out: {arg1}\n";
  static const dirtyNestedRepository = "Dirty nested repository";
  static const cleanNestedRepository = "Clean nested repository";
  static const nestedStatusUnavailable = "Nested status unavailable";
  static const enterNestedRepository = "Enter nested repository";
  static const initializeConfiguration = "Initialize configuration";
  static const updateToParentSRecordedCommit =
      "Update to parent’s recorded commit…";
  static const followConfiguredRemoteBranch =
      "Follow configured remote branch…";
  static const synchronizeConfiguredURLs = "Synchronize configured URLs…";
  static const stageCurrentSubmodulePointerInParent =
      "Stage current submodule pointer in parent";
  static const parentAndSubmoduleCommitsPushesAndDirtyStateRemainSeparate =
      "Parent and submodule commits, pushes, and dirty state remain separate. Browsing does not initialize or update them.";
  static const fetchAndCheckOutTheConfiguredRemoteBranchSCommit =
      "Fetch and check out the configured remote branch’s commit. This differs from the parent’s recorded gitlink. Recursive: {arg0}.";
  static const initializeAsNeededAndCheckOutExactlyArg0RecursiveArg1 =
      "Initialize as needed and check out exactly {arg0}. Recursive: {arg1}.";
  static const applyTheReviewedSubmoduleConfigurationOperationRecursiveArg0 =
      "Apply the reviewed submodule configuration operation. Recursive: {arg0}.";
  static const applySubmoduleOperation = "Apply submodule operation";
  static const inspectARecordedRevisionOrCreateARecoveryBranchReflog =
      "Inspect a recorded revision or create a recovery branch. Reflog does not recover arbitrary unsaved or untracked content.";
  static const selectAReflogEntry = "Select a reflog entry";
  static const previousPage = "Previous page";
  static const nextPage = "Next page";
  static const recoveryBranchName = "Recovery branch name";
  static const createsABranchAtArg0WorkingFilesAndTheCurrent =
      "Creates a branch at {arg0}; working files and the current branch are unchanged.";
  static const createRecoveryBranch = "Create recovery branch…";
  static const readOnlyRecoverySnapshot = "Read-only recovery snapshot";
  static const inspectSnapshot = "Inspect snapshot…";
  static const reviewReset = "Review reset…";
  static const pageArg0 = "Page {arg0}";
  static const aGitTextHistoryMustOwnItsEditableField =
      "A Git text history must own its editable field.";
  static const editHEADIndexWorkingTree = "Edit HEAD | Index | Working Tree…";
  static const theReviewedIndexOrWorkingContentChangedRefreshThisComparison =
      "The reviewed index or working content changed. Refresh this comparison before staging.";
  static const refreshComparison = "Refresh comparison";
  static const previousChangedFile = "Previous changed file";
  static const nextChangedFile = "Next changed file";
  static const previousDifference = "Previous difference";
  static const nextDifference = "Next difference";
  static const comparisonMode = "Comparison mode";
  static const sideBySide = "Side by side";
  static const unified = "Unified";
  static const diffDisplayOptions = "Diff display options";
  static const wrap = "Wrap";
  static const words = "Words";
  static const collapseContext = "Collapse context";
  static const ignoreWhitespace = "Ignore whitespace";
  static const searchComparison = "Search comparison";
  static const openCurrentFile = "Open current file";
  static const previousSearchMatch = "Previous search match";
  static const nextSearchMatch = "Next search match";
  static const searchMatchPosition = "{current} of {count} matches";
  static const searchResultsLimited =
      "Showing the first {count} matches. Refine the search to review more.";
  static const search = "Search";
  static const closeSearch = "Close search";
  static const stagingActions = "Staging actions";
  static const stagingActions2 = "Staging actions…";
  static const unstageSelectedChangedLines = "Unstage selected changed lines";
  static const stageSelectedChangedLines = "Stage selected changed lines";
  static const unstageWholeFile = "Unstage whole file";
  static const stageWholeFile = "Stage whole file";
  static const arg0WhitespaceOnlyChangedLinesHiddenShowExactChanges =
      "{arg0} whitespace-only changed lines hidden · Show exact changes";
  static const arg0ChangedLinesSelectedDisplaySettingsNeverAlterTheStaged =
      "{arg0} changed lines selected · Display settings never alter the staged bytes.";
  static const readOnlyComparisonCopyTextOrAdjustDisplaySettings =
      "Read-only comparison · Copy text or adjust display settings.";
  static const noFinalNewline = " · no final newline";
  static const arg0Arg1Arg2BytesArg3 = "{arg0} · {arg1} · {arg2} bytes{arg3}";
  static const textComparisonIsUnavailableForTheseContents =
      "Text comparison is unavailable for these contents.";
  static const thisComparisonExceedsTheBoundedTextReviewLimitTheContents =
      "This comparison exceeds the bounded text review limit. The contents have not been declared identical.";
  static const theComparedContentsAreIdentical =
      "The compared contents are identical.";
  static const unstage = "Unstage";
  static const stage = "Stage";
  static const arg0ChangedLine = "{arg0} changed line";
  static const context = "Context";
  static const expandUnchangedContext = "Expand unchanged context";
  static const unstageThisHunk = "Unstage this hunk";
  static const stageThisHunk = "Stage this hunk";
  static const editStagedContentArg0 = "Edit staged content · {arg0}";
  static const writingReviewedIndexResult = "Writing reviewed index result";
  static const head = "HEAD";
  static const index = "Index";
  static const workingTree = "Working Tree";
  static const headArg0 = "HEAD · {arg0}";
  static const indexEditableUTF8Blob = "Index · editable UTF-8 blob";
  static const undo = "Undo";
  static const redo = "Redo";
  static const reloadIndexReview = "Reload index review?";
  static const discardUnsavedIndexDraft = "Discard unsaved index draft?";
  static const closingTheIndexEditorDiscardsOnlyItsDraft =
      "Closing the index editor discards only its draft. The index and working file remain unchanged.";
  static const discardIndexDraft = "Discard index draft";
  static const reloadTheCurrentHEADIndexAndWorkingVersionsThisReplaces =
      "Reload the current HEAD, index and working versions. This replaces the unsaved index editor draft.";
  static const replaceDraftAndReload = "Replace draft and reload";
  static const reloadVersions = "Reload versions…";
  static const writeEditedResultToThisIndexEntry =
      "Write edited result to this index entry";
  static const workingFilesRemainOnDiskReviewTheEditedIndexBefore =
      "Working files remain on disk. Review the edited index before applying.";
  static const reviewIndexTextFormatChanges =
      "Review index text format changes";
  static const updateOnlyTheReviewedIndexEntryForArg0Arg1 =
      "Update only the reviewed index entry for {arg0}.\n\n{arg1}";
  static const writeReviewedIndexResult = "Write reviewed index result";
  static const theEditedResultChangedDuringFormatReviewReviewItAgain =
      "The edited result changed during format review. Review it again.";
  static const synchronizeScrolling = "Synchronize scrolling";
  static const changedLine = "Changed line";
  static const copyHeadRegionIntoIndexDraft =
      "Copy HEAD region into index draft";
  static const copyWorkingRegionIntoIndexDraft =
      "Copy working region into index draft";
  static const indexAppliedNewerDraftPreserved =
      "The submitted draft was written to the index. Newer text is still in this editor. Reload and review the current versions before applying it.";
  static const reviewSavedIndexAndKeepDraft =
      "Review saved index and keep draft";
  static const indexSourcesChangedSinceApply =
      "The saved index or its sources changed. The newer draft is retained; review those changes separately before applying it.";
  static const readOnlyRevisionContent = "Read-only revision content";
  static const editableIndexContent = "Editable index content";
  static const theRequestedRevisionIsOutsideTheCurrentFiltersResetFilters =
      "The requested revision is outside the current filters. Reset filters to reveal it.";
  static const filterLog = "Filter Log";
  static const filters = "Filters…";
  static const filtersCount = "Filters ({count})…";
  static const message = "Message…";
  static const author = "Author…";
  static const path = "Path…";
  static const date = "Date…";
  static const messageFilter = "Message filter";
  static const authorFilter = "Author filter";
  static const pathFilter = "Path filter";
  static const message2 = "Message";
  static const author2 = "Author";
  static const path2 = "Path";
  static const dateFilter = "Date filter…";
  static const revealRevisionWithoutFilters = "Reveal revision without filters";
  static const restoreHistoryFilters = "Restore history filters";
  static const graphLanes = "Graph lanes";
  static const showAllAffectedFiles = "Show All Affected Files";
  static const resetFilters = "Reset filters";
  static const refreshLog = "Refresh Log";
  static const goToCommitReference = "Go to commit/reference…";
  static const backToHEAD = "Back to HEAD";
  static const orderedCherryPick = "Ordered cherry-pick";
  static const reviewCherryPickArg0 = "Review cherry-pick ({arg0})…";
  static const compareTwoSelectedRevisions = "Compare two selected revisions…";
  static const toggleBranchesPane = "Toggle branches pane";
  static const filterBranchesAndTags = "Filter branches and tags";
  static const commitArg0 = "Commit {arg0}";
  static const commitDetails = "Commit details…";
  static const referenceArg0 = "Reference: {arg0}";
  static const selectThisCommit = "Select this commit";
  static const branchOrTag = "Branch or tag";
  static const allReferences = "All references";
  static const local = "Local";
  static const remote = "Remote";
  static const tags = "Tags";
  static const noCommitsMatchTheCurrentFilters =
      "No commits match the current filters.";
  static const objectID = "Object ID";
  static const subjectReferences = "Subject / references";
  static const date2 = "Date";
  static const gitCommits = "Git commits";
  static const parents = "Parents";
  static const arg0Parents = "{arg0} parents";
  static const loadMoreCommits = "Load more commits";
  static const loadingChangedFiles = "Loading changed files";
  static const noChangedFiles = "No changed files";
  static const selectACommit = "Select a commit";
  static const compareParentArg0Arg1 = "Compare parent {arg0}: {arg1}";
  static const changedFiles = "Changed files";
  static const authorArg0Arg1Arg2 = "Author: {arg0} <{arg1}>\n{arg2}";
  static const committerArg0Arg1Arg2 = "Committer: {arg0} <{arg1}>\n{arg2}";
  static const shallowPartialBoundaryAParentObjectIsUnavailable =
      "Shallow/partial boundary: a parent object is unavailable.";
  static const parentIsOutsideThisPageOrAShallowBoundary =
      "Parent is outside this page or a shallow boundary.";
  static const parentArg0 = "Parent {arg0}";
  static const commitActions = "Commit actions…";
  static const emptyTree = "empty tree";
  static const createBranch2 = "Create branch";
  static const createTag = "Create tag";
  static const compareRevisions = "Compare revisions";
  static const openSnapshot = "Open snapshot";
  static const revertCommit = "Revert commit";
  static const interactiveRebaseAfterThisBoundary =
      "Interactive rebase after this boundary";
  static const resetCurrentBranch = "Reset current branch";
  static const copyFullObjectID = "Copy full object ID";
  static const goToCommitReference2 = "Go to commit/reference";
  static const enterACommitIDOrReferenceToRevealInLog =
      "Enter a commit ID or reference to reveal in Log.";
  static const theRequestedRevisionIsUnavailable =
      "The requested revision is unavailable.";
  static const repositoryMetadataIsReadOnlyBranchInspectionAndComparisonRemain =
      "Repository metadata is read-only. Branch inspection and comparison remain available.";
  static const workingFilesAreUnavailableOrReadOnlyBranchSwitchingAnd =
      "Working files are unavailable or read-only. Branch switching and merging are unavailable.";
  static const searchBranchesAndTags = "Search branches and tags";
  static const newBranch = "New branch…";
  static const localBranches = "Local branches";
  static const remoteBranches = "Remote branches";
  static const tracksArg0 = "Tracks {arg0}";
  static const checkedOutAtArg0 = "Checked out at {arg0}";
  static const refreshingBranchMetadata = "Refreshing branch metadata";
  static const switchToArg0 = "Switch to {arg0}";
  static const openOccupiedWorktree = "Open occupied worktree";
  static const createLocalTrackingBranch = "Create local tracking branch…";
  static const compareToCurrentHEAD = "Compare to current HEAD";
  static const mergeIntoCurrentBranch = "Merge into current branch…";
  static const rename = "Rename…";
  static const changeUpstream = "Change upstream…";
  static const delete = "Delete…";
  static const deleteFromRemote = "Delete from remote…";
  static const actionsForArg0 = "Actions for {arg0}";
  static const localBranchName = "Local branch name";
  static const createAtArg0TheNewBranchWillBeCheckedOut =
      "Create at {arg0}. The new branch will be checked out.";
  static const theLocalBranchWillTrackArg0AndBeCheckedOut =
      "The local branch will track {arg0} and be checked out.";
  static const chooseRemoteForDeletion = "Choose remote for deletion";
  static const deleteRemoteReference = "Delete remote reference";
  static const mergeArg0IntoArg1 = "Merge {arg0} into {arg1}";
  static const renameArg0 = "Rename {arg0}";
  static const upstreamForArg0 = "Upstream for {arg0}";
  static const noUpstream = "No upstream";
  static const deleteArg0 = "Delete {arg0}?";
  static const arg0TargetArg1LocalDeletionOnlyAnUnmergedBranchIs =
      "{arg0}\nTarget {arg1}\nLocal deletion only. An unmerged branch is refused.";
  static const delete2 = "Delete";
  static const deleteUnmergedBranchArg0 = "Delete unmerged branch {arg0}?";
  static const arg0GitReportsThisBranchIsNotFullyMergedExplicitly =
      "{arg0}\nGit reports this branch is not fully merged. Explicitly delete the local reference after reviewing its commits; remote copies are unchanged.";
  static const deleteUnmergedLocalBranch = "Delete unmerged local branch";
  static const destinationArg0Arg1 = "Destination: {arg0} · {arg1}";
  static const sourceBranchOrTag = "Source branch or tag";
  static const mergePolicy = "Merge policy";
  static const fastForwardWhenPossible = "Fast-forward when possible";
  static const alwaysCreateAMergeCommit = "Always create a merge commit";
  static const fastForwardOnly = "Fast-forward only";
  static const squashIntoStagedChanges = "Squash into staged changes";
  static const stopBeforeCreatingTheMergeCommit =
      "Stop before creating the merge commit";
  static const fastForwardIsDisabledSoHEADCannotMoveBeforeReview =
      "Fast-forward is disabled so HEAD cannot move before review.";
  static const leavesStagedChangesForASeparateCommitThisIsNot =
      "Leaves staged changes for a separate commit; this is not a continuing merge.";
  static const conflictsRemainAvailableInTheSharedResolutionWorkspace =
      "Conflicts remain available in the shared resolution workspace.";
  static const addRemote = "Add remote…";
  static const fetchArg0PushArg1 = "Fetch: {arg0}\nPush: {arg1}";
  static const removeRemote = "Remove remote…";
  static const changeFetchURL = "Change fetch URL…";
  static const addPushDestination = "Add push destination…";
  static const removePushDestination = "Remove push destination…";
  static const manageArg0 = "Manage {arg0}";
  static const remoteName = "Remote name";
  static const newRemoteName = "New remote name";
  static const repositoryURLOrLocalSource = "Repository URL or local source";
  static const enterTheExactReviewedDestinationToRemove =
      "Enter the exact reviewed destination to remove.";
  static const credentialsAreSuppliedByConfiguredHelpersOrAPrivatePrompt =
      "Credentials are supplied by configured helpers or a private prompt.";
  static const removeRemoteArg0 = "Remove remote {arg0}?";
  static const removesLocalRemoteConfigurationAndTrackingReferencesItDoesNot =
      "Removes local remote configuration and tracking references. It does not delete the server repository.";
  static const removeRemote2 = "Remove remote";
  static const commitScopeEntireRepository = "Commit scope: entire repository";
  static const cachedTracking = "Cached tracking";
  static const amendLastCommit = "Amend last commit";
  static const configuredHooksAndSigningAreRespected =
      "Configured hooks and signing are respected.";
  static const rewritesTheSelectedHEADCommitRemoteTrackingCannotProveIt =
      "Rewrites the selected HEAD commit. Remote tracking cannot prove it is unpublished.";
  static const repository = "Repository";
  static const detachedArg0 = "Detached {arg0}";
  static const log = "Log";
  static const repositoryActions = "Repository actions";
  static const cachedTrackingUpstreamAheadAheadBehindBehind =
      "Cached tracking · {upstream} · {ahead} ahead · {behind} behind";
  static const bareRepositoryNoWorkingTreeOpenLogToInspectIts =
      "Bare repository · no working tree. Open Log to inspect its history.";
  static const readOnlyRepositoryStagingAndCommitsAreUnavailable =
      "Read-only repository · staging and commits are unavailable.";
  static const repositoryStatusUnavailable = "Repository status unavailable";
  static const amendRevision = "Amend {revision}";
  static const addSignOffTrailer = "Add sign-off trailer";
  static const useConfiguredSigningPolicy = "Use configured signing policy";
  static const cryptographicallySignThisCommit =
      "Cryptographically sign this commit";
  static const doNotSignThisCommit = "Do not sign this commit";
  static const recentCommitMessages = "Recent commit messages…";
  static const useConfiguredCommitTemplate = "Use configured commit template…";
  static const authorIdentityAndConfiguredHooks =
      "Author identity and configured hooks…";
  static const draftMessage = "Draft message…";
  static const commitOptions = "Commit options";
  static const draftRetainedInMemorySavingItFailedArg0 =
      "Draft retained in memory; saving it failed. {arg0}";
  static const commitMessage = "Commit message";
  static const gitOperationInProgress = "Git operation in progress";
  static const cancel = "Cancel";
  static const amendStaged = "Amend staged";
  static const commitStagedCount = "Commit staged ({count})";
  static const commitAndPush = "Commit and Push…";
  static const noReadableCommitTemplateIsConfigured =
      "No readable commit template is configured.";
  static const commitIdentityAndHooks = "Commit identity and hooks";
  static const recentMessages = "Recent messages";
  static const replaceMessageDraft = "Replace message draft?";
  static const replaceTheExistingCommitMessageWithTheSelectedMessage =
      "Replace the existing commit message with the selected message?";
  static const replaceDraft = "Replace draft";
  static const localCommitArg0Exists = "Local commit {arg0} exists.";
  static const localCommitArg0ExistsReviewLogBeforeAttemptingAnotherCommit =
      "Local commit {arg0} exists. Review Log before attempting another commit. The message draft has been retained.";
  static const commitAuthorName = "Commit author name";
  static const commitAuthorEmail = "Commit author email";
  static const configuredDefault = "configured default";
  static const openpgp = "OpenPGP";
  static const signingArg0Arg1 = "Signing: {arg0} · {arg1}";
  static const configuredHooksArg0 = "Configured hooks: {arg0}";
  static const aSignOffTrailerIsAStatementInTheMessage =
      "A sign-off trailer is a statement in the message. It is separate from a cryptographic signature. Saving identity changes repository-local configuration only; your draft is retained.";
  static const saveRepositoryIdentity = "Save repository identity";
  static const staged = "Staged";
  static const untracked = "Untracked";
  static const unstaged = "Unstaged";
  static const conflicts = "Conflicts";
  static const noChanges = "No changes";
  static const repositoryChangeTree = "Repository change tree";
  static const changes = "Changes";
  static const groupCount = "{group} ({count})";
  static const expand = "Expand";
  static const collapse = "Collapse";
  static const unstageFile = "Unstage file";
  static const stageFile = "Stage file";
  static const expandGroup = "Expand group";
  static const collapseGroup = "Collapse group";
  static const reviewDifference = "Review difference";
  static const unstageSelectedFiles = "Unstage selected files";
  static const stageSelectedFiles = "Stage selected files";
  static const fileHistoryAndBlame = "File history and blame…";
  static const deleteUntrackedFile = "Delete untracked file…";
  static const discardUnstagedChange = "Discard unstaged change…";
  static const fileHistory = "File history";
  static const discardUnstagedArg0 = "Discard unstaged {arg0}?";
  static const arg0BytesArg1ReplacesWorkingContentWithTheIndexOr =
      "{arg0} bytes · {arg1}\nReplaces working content with the index, or deletes this untracked file. Staged content is retained. Unsaved host documents must be reviewed first.";
  static const deleteUntrackedFile2 = "Delete untracked file";
  static const discardWorkingChange = "Discard working change";
  static const deleteREMOTEReferenceArg0 = "Delete REMOTE reference {arg0}";
  static const thisRemovesTheReferenceOnEveryActualPushDestinationListed =
      "This removes the reference on every actual push destination listed below. Local branches/tags are retained. The expected tips are fixed by this review.";
  static const referenceDoesNotExist = "reference does not exist";
  static const arg0ExpectedTipArg1 = "{arg0}\nExpected tip: {arg1}";
  static const remoteDeletionCompleted = "Remote deletion completed.";
  static const deleteArg0FromTheRemote = "Delete {arg0} from the remote?";
  static const theExactDestinationTipsShownAboveWillBeRemovedAny =
      "The exact destination tips shown above will be removed. Any changed remote tip stops the operation for another review.";
  static const reviewAndDeleteFromRemote = "Review and delete from remote…";
  static const destinationReference = "Destination reference";
  static const reviewDestinations = "Review destinations";
  static const newRemoteBranch = "new remote branch";
  static const arg0Arg1ExpectedArg2 = "{arg0}\n{arg1} · expected {arg2}";
  static const aDestinationHasCommitsThatAreUnavailableLocallyFetchThat =
      "A destination has commits that are unavailable locally. Fetch that reviewed destination before reviewing outgoing history.";
  static const fetchReviewedDestination = "Fetch reviewed destination";
  static const chooseADestinationAndReviewTheOutgoingCommits =
      "Choose a destination and review the outgoing commits.";
  static const noOutgoingCommits = "No outgoing commits";
  static const selectAnOutgoingCommit = "Select an outgoing commit";
  static const loadMoreOutgoingCommits = "Load more outgoing commits";
  static const setThisDestinationAsUpstream =
      "Set this destination as upstream";
  static const chooseExactTagsToPublish = "Choose exact tags to publish";
  static const tagsNone = "Tags: none";
  static const tagsArg0Selected = "Tags: {arg0} selected";
  static const publishExactlyArg0 = "Publish exactly: {arg0}";
  static const pushCompletedTheLocalCommitRemainsAvailableInLog =
      "Push completed. The local commit remains available in Log.";
  static const forceRequiresTheExactDestinationTipsShownInThisReview =
      "Force requires the exact destination tips shown in this review.";
  static const forceWithReviewedLease = "Force with reviewed lease…";
  static const push = "Push";
  static const forcePushWithReviewedLeases = "Force push with reviewed leases?";
  static const rewriteArg0OnlyIfEveryRemoteDestinationStillHasThe =
      "Rewrite {arg0} only if every remote destination still has the exact tip shown above.\n";
  static const otherPeopleMayAlreadyUseThisHistoryABackgroundFetch =
      "Other people may already use this history. A background fetch will not renew this lease.";
  static const forceWithLease = "Force with lease";
  static const theRemoteOutcomeIsUncertainReviewDestinationsAgainBeforeAnother =
      "The remote outcome is uncertain. Review destinations again before another push.";
  static const parentArg0Arg1 = "Parent {arg0} · {arg1}";
  static const remoteToFetch = "Remote to fetch";
  static const pruneDeletedRemoteTrackingBranches =
      "Prune deleted remote-tracking branches";
  static const fetchUpdatesRemoteTrackingInformationWithoutReplacingWorkingFiles =
      "Fetch updates remote-tracking information without replacing working files.";
  static const fetch = "Fetch";
  static const sourceRemote = "Source remote";
  static const sourceBranch = "Source branch";
  static const reviewedStrategy = "Reviewed strategy";
  static const merge = "Merge";
  static const rebase = "Rebase";
  static const stopIfTheDestinationCannotFastForwardNeverMergeOr =
      "Stop if the destination cannot fast-forward; never merge or rebase.";
  static const mergeWithAMergeCommitIncludingWhenFastForwardIs =
      "Merge with a merge commit, including when fast-forward is possible.";
  static const mergeAllowFastForwardWhenPossible =
      "Merge; allow fast-forward when possible.";
  static const rebaseLocalHistoryWhilePreservingLocalMergeCommits =
      "Rebase local history while preserving local merge commits.";
  static const rebaseLocalCommitsAsALinearHistory =
      "Rebase local commits as a linear history.";
  static const gitIsConfiguredForInteractiveRebaseSelectAPullStrategy =
      "Git is configured for interactive rebase. Select a pull strategy explicitly here, or fetch and open Rebase… to review a plan.";
  static const useReviewedOrdinaryRebaseForThisPull =
      "Use reviewed ordinary rebase for this pull";
  static const options = "Options";
  static const alwaysCreateAMergeCommitNoFastForward =
      "Always create a merge commit (no fast-forward)";
  static const preserveLocalMergeCommits = "Preserve local merge commits";
  static const localChangesMayPreventPullReviewCommitThemOrExplicitly =
      "Local changes may prevent pull. Review/commit them or explicitly create a stash.";
  static const stashes = "Stashes";
  static const createOrReviewStash = "Create or review stash…";
  static const pullWithSelectedStrategy = "Pull with selected strategy";
  static const repositoryURLOrLocalGitSource =
      "Repository URL or local Git source";
  static const httpsSSHOrLocalPath = "HTTPS, SSH, or local path";
  static const folderToInitialize = "Folder to initialize";
  static const finalCloneDestination = "Final clone destination";
  static const choose = "Choose…";
  static const createsGitMetadataOnlyExistingFilesAreNotStagedOr =
      "Creates Git metadata only. Existing files are not staged or committed.";
  static const theFinalDestinationMustBeAbsentOrEmptyExistingUser =
      "The final destination must be absent or empty. Existing user data is never overwritten.";
  static const initialBranchBlankUsesEffectiveGitPolicy =
      "Initial branch · blank uses effective Git policy";
  static const selectedBranchOptional = "Selected branch · optional";
  static const explicitlyInitializeUpdateSubmodulesRecursively =
      "Explicitly initialize/update submodules recursively";
  static const preparingGitOperation = "Preparing Git operation…";
  static const thisAttemptCreated = "This attempt created";
  static const theDestinationExistedBeforeThisAttempt =
      "The destination existed before this attempt:";
  static const theDirectoryRemainsForInspectionReviewItBeforeAnotherClone =
      "The directory remains for inspection. Review it before another clone attempt.";
  static const noDestinationDirectoryRemains =
      "No destination directory remains.";
  static const cancelProcess = "Cancel process";
  static const initialize = "Initialize";
  static const clone = "Clone";
  static const chooseNewBase = "Choose new base";
  static const chooseUpstreamBoundary = "Choose upstream boundary";
  static const newBase = "New base";
  static const upstreamBoundaryExcluded = "Upstream boundary · excluded";
  static const sameAsUpstreamBoundary = "Same as upstream boundary";
  static const chooseBranchTagOrCommit = "Choose branch, tag or commit…";
  static const useUpstreamAsNewBase = "Use upstream as new base";
  static const chooseAValidBranchTagOrCommitFromLog =
      "Choose a valid branch, tag or commit from Log.";
  static const theFirstRetainedCommitInABranchBlockCannotSquash =
      "The first retained commit in a branch block cannot squash or fixup: it has no preceding target.";
  static const branchBlockArg0 = "Branch block {arg0}\n";
  static const rewordWillRequestANewMessage =
      "[Reword will request a new message]\n";
  static const plannedCommitMessages = "Planned commit messages";
  static const originalCombinedMessagePreviewGitRequestsTheFinalRewordSquash =
      "Original/combined message preview · Git requests the final reword/squash messages";
  static const resultArg0Arg1 = "Result {arg0}\n{arg1}";
  static const currentBranchBranch = "Current branch: {branch}";
  static const detachedHEAD2 = "Detached HEAD";
  static const rebaseRewritesCommitIdentitiesRemoteTrackingInformationCannotProveHistory =
      "Rebase rewrites commit identities. Remote-tracking information cannot prove history has never been published.";
  static const includeRootCommits = "Include root commits";
  static const mergeCommits = "Merge commits";
  static const flattenHistory = "Flatten history";
  static const preserveBranchStructure = "Preserve branch structure";
  static const autosquash = "Autosquash";
  static const prepareGitPlan = "Prepare Git plan";
  static const commitsToReplayCount = "Commits to replay: {count}";
  static const includesAllRootCommitsReachableFromThisBranch =
      "Includes all root commits reachable from this branch.";
  static const commitsAfterBoundaryWillBeReplayedOntoBaseTheBoundary =
      "Commits after {boundary} will be replayed onto {base}; the boundary itself is excluded.";
  static const root = "Root";
  static const gitBranchLabelResetMergeStructure =
      "Git branch/label/reset/merge structure";
  static const chooseAnExplicitOldBoundaryOrRootModeThenPrepare =
      "Choose an explicit old boundary or root mode, then prepare the plan.";
  static const moveUp = "Move up";
  static const moveDown = "Move down";
  static const resetPlan = "Reset plan";
  static const branchBlockArg02 = " · branch block {arg0}";
  static const selectACommitForDetailsAndChangedFiles =
      "Select a commit for details and changed files";
  static const previewCombinedCommitMessages =
      "Preview combined commit messages…";
  static const altMovesTheSelectedCommitUnrelatedBranchReferencesWillNot =
      "Alt+↑/↓ moves the selected commit. Unrelated branch references will not be updated automatically.";
  static const cancelPlan = "Cancel plan";
  static const startReviewedRebase = "Start reviewed rebase?";
  static const rewriteArg0PlannedCommitsOnArg1DroppedCommitsRemainVisibly =
      "Rewrite {arg0} planned commits on {arg1}. Dropped commits remain visibly marked in this plan until you start.";
  static const startRebase = "Start rebase";
  static const noContinuingGitOperation = "No continuing Git operation";
  static const stoppedForEditingAmend = " · stopped for editing/amend";
  static const theseAreUnmergedIndexEntriesPossiblyFromAStashApplication =
      "These are unmerged index entries, possibly from a stash application. Git has no stash continue or abort command.";
  static const editTheWorkingFilesStageAndAmendTheCurrentCommit =
      "Edit the working files, stage and amend the current commit, then continue this rebase.";
  static const arg0Arg1UnmergedStagesArg2 =
      "{arg0}{arg1} · unmerged stages {arg2}";
  static const theIndexHasNoUnresolvedEntries =
      "The index has no unresolved entries.";
  static const keepTheCurrentCommitAsAnEmptyCommit =
      "Keep the current commit as an empty commit";
  static const theRealIndexHasNoStagedChangesCreateAnExplicit =
      "The real index has no staged changes. Create an explicit empty commit, then continue the sequencer if it remains active.";
  static const keepEmptyCommit = "Keep empty commit…";
  static const gitWillTryToReturnToTheOperationSStarting =
      "Git will try to return to the operation’s starting point. Pre-existing unstaged, untracked and unsaved contents are not guaranteed to be recovered.";
  static const skipTheCurrentCommitAndContinueWithTheNextPlanned =
      "Skip the current commit and continue with the next planned commit.";
  static const forgetThisOperationSBookkeepingWhileRetainingTheCurrentFiles =
      "Forget this operation’s bookkeeping while retaining the current files and index.";
  static const continueArg0 = "Continue {arg0}";
  static const discardUnsavedConflictDraft = "Discard unsaved conflict result?";
  static const closingTheConflictEditorDiscardsOnlyItsDraft =
      "Closing the conflict editor discards only its unsaved result draft. Saved working content and the index remain unchanged.";
  static const discardConflictDraft = "Discard conflict draft";
  static const reloadConflictVersions = "Reload conflict versions?";
  static const replaceTheUnsavedResultDraftWithTheCurrentWorkingFile =
      "Replace the unsaved Result draft with the current working file. Saved working content is retained.";
  static const loadingConflictVersions = "Loading conflict versions…";
  static const loadingConflict = "Loading conflict";
  static const baseLeft = "Base → left";
  static const baseRight = "Base → right";
  static const noBaseEntryForThisConflict = "No base entry for this conflict";
  static const acceptEntireLeftFile = "Accept entire left file…";
  static const acceptEntireRightFile = "Accept entire right file…";
  static const previousConflictRegion = "Previous conflict region";
  static const nextConflictRegion = "Next conflict region";
  static const manualResolution = "Manual resolution";
  static const regionArg0Arg1Arg2Reviewed =
      "Region {arg0}/{arg1} · {arg2} reviewed";
  static const sourceAlignmentExceededTheTextComparisonLimitSourcePanesRemain =
      "Source alignment exceeded the text comparison limit; source panes remain available for manual review.";
  static const acceptLeftRegion = "Accept left region";
  static const acceptRightRegion = "Accept right region";
  static const keepManualResultForRegion = "Keep manual result for region";
  static const applyGitSNonConflictingChanges =
      "Apply Git’s non-conflicting changes?";
  static const replaceTheCurrentResultDraftWithGitSMergePreview =
      "Replace the current result draft with Git’s merge preview. This discards unsaved manual result edits; the working file is unchanged until Save.";
  static const useMergePreview = "Use merge preview";
  static const applyNonConflictingChanges = "Apply non-conflicting changes…";
  static const leftSource = "Left source";
  static const result = "Result";
  static const rightSource = "Right source";
  static const stage2 = "Stage 2";
  static const stage3 = "Stage 3";
  static const conflictVersionsAreUnavailableRefreshToReviewTheirCurrentState =
      "Conflict versions are unavailable. Refresh to review their current state.";
  static const resultSavedToDiskTheIndexStillDeterminesWhetherThis =
      "Result saved to disk. The index still determines whether this file is resolved.";
  static const saveResultDraft = "Save result draft";
  static const applyResultAndStageResolution =
      "Apply result and stage resolution";
  static const resultEditableUTF8WorkingContent =
      "Result · editable UTF-8 working content";
  static const editableConflictResult = "Editable conflict result";
  static const leftArg0Arg1RightArg2Arg3 =
      "Left: {arg0} · {arg1}\nRight: {arg2} · {arg3}";
  static const chooseContentDeletionOrASubmoduleCommitExplicitlyNoBinary =
      "Choose content, deletion, or a submodule commit explicitly. No binary data is decoded as editable text.";
  static const useEntireLeftContent = "Use entire left content…";
  static const useEntireRightContent = "Use entire right content…";
  static const deleteThisPath = "Delete this path…";
  static const resolvedSubmoduleCommit = "Resolved submodule commit";
  static const stageThisExactGitlinkInTheParentThisDoesNot =
      "Stage this exact gitlink in the parent. This does not check out or commit the submodule.";
  static const setResolvedGitlink = "Set resolved gitlink…";
  static const baseStageArg0 = "Base → stage {arg0}";
  static const theResultWasEditedKeepTheManualResultOrSelect =
      "The result was edited. Keep the manual result or select another unchanged region.";
  static const applyArg0Resolution = "Apply {arg0} resolution?";
  static const stageTheChosenGitlinkCommitInTheParentTheSubmodule =
      "Stage the chosen gitlink commit in the parent. The submodule checkout and its files are not replaced.";
  static const replacesTheEntireWorkingPathArg0AndStagesTheDecision =
      "Replaces the entire working path {arg0} and stages the decision. Current working content and any unsaved result draft will be discarded.";
  static const applyEntireFileDecision = "Apply entire file decision";
  static const stageThisConflictResolution = "Stage this conflict resolution?";
  static const useTheEntireEditedResultAsArg0GitRecordsThe =
      "Use the entire edited Result as {arg0}. Git records the path resolved when it is staged. Review all intended content first.{arg1}";
  static const applyAndStage = "Apply and stage";
  static const reviewResultTextFormatChanges =
      "Review result text format changes";
  static const saveReviewedResult = "Save reviewed result";
  static const nativeGitTableAccessibilityIsUnavailableRetryAfterReconnectingThe =
      "Native Git table accessibility is unavailable. Retry after reconnecting the application.";
  static const sans = "Sans";
  static const select = "Select";
  static const contextMenu = "Context menu";
  static const copyText = "Copy text";
  static const loadingRow = "Loading row";
  static const retry = "Retry";
  static const gitMessage = "Git message";
  static const cancelPrompt = "Cancel prompt";
  static const reviewSavedMessage = "Review saved message";
  static const savedMessage = "Saved message";
  static const keepThisMessage = "Keep this message";
  static const useSavedMessage = "Use saved message";
  static const commitDraftChangedInAnotherWindow =
      "This message changed in another window. Review the saved message before replacing it.";
  static const discardUnsavedCommitMessages =
      "Discard unsaved commit messages?";
  static const messagesCouldNotBeSavedStayInThisWindow =
      "Messages that could not be saved are still in this window. Discarding leaves the saved versions unchanged.";
  static const discardCommitMessages = "Discard messages";
  static const useMessageAndContinue = "Use message and continue";
  static const respondPrivately = "Respond privately";
  static const viewPreferencesCouldNotBeSavedArg0 =
      "View preferences could not be saved: {arg0}";
  static const commitDraftStorageArg0 = "Commit draft storage: {arg0}";
  static const viewPreferencesCouldNotBeReadArg0 =
      "View preferences could not be read: {arg0}";
  static const commitDraftWasRetainedInMemoryButCouldNotBe =
      "Commit draft was retained in memory but could not be saved: {arg0}";
  static const theReviewedRepositoryIsReadOnlyForThisOperationHistory =
      "The reviewed repository is read-only for this operation. History and content inspection remain available.";
  static const gitReturnedArg0TheApplicationCouldNotRefreshItsDocuments =
      "Git returned {arg0}. The application could not refresh its documents: {arg1}";
  static const selectCommitInLog = "Select commit in Log…";
  static const currentBranch = "Current branch";
  static const noMatchingBranchesOrTagsSelectACommitInLog =
      "No matching branches or tags. Select a commit in Log.";
  static const branches = "Branches";
  static const pushCommits = "Push commits";
  static const pullIntoArg0 = "Pull into {arg0}";
  static const resolveArg0 = "Resolve {arg0}";
  static const currentOperation = "Current operation";
  static const rebaseCommits = "Rebase commits";
  static const fetch2 = "Fetch…";
  static const pull = "Pull…";
  static const push2 = "Push…";
  static const branches2 = "Branches…";
  static const manageRemotes = "Manage remotes…";
  static const mergeIntoArg0 = "Merge into {arg0}…";
  static const rebase2 = "Rebase…";
  static const conflictsAndCurrentOperation =
      "Conflicts and current operation…";
  static const stashes2 = "Stashes…";
  static const worktrees = "Worktrees…";
  static const submodules = "Submodules…";
  static const reflogAndRecovery = "Reflog and recovery…";
  static const cloneRepository = "Clone repository…";
  static const revokeRepositoryTrust = "Revoke repository trust";
  static const waitingForRepositoryStatus = "Waiting for repository status";
  static const repositoryStatusUnavailableRefresh =
      "Repository status unavailable; refresh";
  static const manageRemotes2 = "Manage remotes";
  static const mergeIntoArg02 = "Merge into {arg0}";
  static const worktrees2 = "Worktrees";
  static const submodules2 = "Submodules";
  static const reflogAndRecovery2 = "Reflog and recovery";
  static const cloneRepositoryArg0 = "Clone repository · {arg0}";
  static const apply = "Apply";
  static const resizeGitPanes = "Resize Git panes";
  static const arg0Percent = "{arg0} percent";
  static const exitStatusStatus = "Exit status: {status}";
  static const repositoryChangedRefreshAndReviewBeforeTryingAgain =
      "Repository changed. Refresh and review before trying again.";
  static const anotherOperationHoldsTheRepositoryOrIndexLockWaitThen =
      "Another operation holds the repository or index lock. Wait, then refresh.";
  static const repositoryTrustIsRequiredForThisOperation =
      "Repository trust is required for this operation.";
  static const theGitServiceDisconnectedReconnectAndReconcileTheRepository =
      "The Git service disconnected. Reconnect and reconcile the repository.";
  static const theInstalledGitExecutableCannotSupportThisOperationReviewIts =
      "The installed Git executable cannot support this operation. Review its runtime requirements below.";
  static const thisRepositoryIsReadOnlyForTheRequestedOperationReview =
      "This repository is read-only for the requested operation. Review and history remain available.";
  static const theOperationNeedsReconciliationReviewTheResultingRepositoryOrRemote =
      "The operation needs reconciliation. Review the resulting repository or remote state before repeating it.";
  static const gitAuthenticationFailedReviewTheCredentialHelperOrUnlockThe =
      "Git authentication failed. Review the credential helper or unlock the configured keyring.";
  static const sshHostVerificationFailedReviewTheHostIdentityThroughYour =
      "SSH host verification failed. Review the host identity through your configured SSH tools.";
  static const commitSigningFailedOrWasCancelledReviewTheSigningKey =
      "Commit signing failed or was cancelled. Review the signing key, agent and configured signing tool.";
  static const setARepositoryAuthorNameAndEmailThenReturnTo =
      "Set a repository author name and email, then return to the preserved message draft.";
  static const gitRejectedTheReviewedUpdateRefreshAndReviewTheActual =
      "Git rejected the reviewed update. Refresh and review the actual destination before trying again.";
  static const workingOrStagedChangesPreventThisOperationReviewCommitOr =
      "Working or staged changes prevent this operation. Review, commit or explicitly stash them.";
  static const aRequiredGitObjectIsUnavailableReviewShallowOrPartial =
      "A required Git object is unavailable. Review shallow or partial-repository boundaries and fetch explicitly if needed.";
  static const gitOperationFailedArg0 = "Git operation failed: {arg0}";
  static const diagnostics = "Diagnostics";
  static const authorizeGitInspection = "Authorize Git inspection…";
  static const copyDiagnostics = "Copy diagnostics";
  static const actions = "Actions";
  static const branchAtArg0 = "Branch at {arg0}";
  static const createsALocalBranchWithoutCheckingItOut =
      "Creates a local branch without checking it out.";
  static const tagArg0 = "Tag {arg0}";
  static const readOnlySnapshotArg0 = "Read-only snapshot · {arg0}";
  static const cherryPickCommits = "Cherry-pick commits";
  static const revertCommits = "Revert commits";
  static const compareToFullRevisionID = "Compare to full revision ID";
  static const treeComparisonDirectionArg0TheRevisionEnteredHere =
      "Tree comparison direction: {arg0} → the revision entered here.";
  static const enterAFullValidObjectID = "Enter a full valid object ID.";
  static const arg0Arg1TreeComparison = "{arg0} → {arg1} · tree comparison";
  static const resetArg0ToArg1 = "Reset {arg0} to {arg1}";
  static const movesHEADCurrentBranchReflogDoesNotRecoverArbitraryUntracked =
      "Moves HEAD/current branch. Reflog does not recover arbitrary untracked or unsaved content.";
  static const moveHEADKeepIndexAndWorkingFiles =
      "Move HEAD; keep index and working files.";
  static const moveHEADAndReplaceIndexKeepWorkingFiles =
      "Move HEAD and replace index; keep working files.";
  static const replaceHEADIndexAndTrackedWorkingFilesMayOverwriteObstructing =
      "Replace HEAD, index and tracked working files; may overwrite obstructing untracked files.";
  static const replaceHEADIndexAndEligibleFilesRefuseIfLocalChanges =
      "Replace HEAD/index and eligible files; refuse if local changes would be lost.";
  static const resetWithArg0 = "Reset with {arg0}?";
  static const arg0Arg1ReviewTheSelectedModeSEffectsBeforeApplying =
      "{arg0} → {arg1}\nReview the selected mode’s effects before applying.";
  static const resetArg0 = "Reset {arg0}";
  static const targetArg0 = "Target {arg0}";
  static const tagName = "Tag name";
  static const annotatedTag = "Annotated tag";
  static const cryptographicSigning = "Cryptographic signing";
  static const configuredPolicy = "Configured policy";
  static const signThisTag = "Sign this tag";
  static const doNotSign = "Do not sign";
  static const tagMessage = "Tag message";
  static const createsTheTagLocallyPublishSelectedTagsExplicitlyInPush =
      "Creates the tag locally. Publish selected tags explicitly in Push review.";
  static const completeTreesArg0Arg1 = "Complete trees: {arg0} → {arg1}";
  static const nextChangedFilePage = "Next changed-file page";
  static const readOnlyRepositorySnapshotOpeningAFileNeverChecksOut =
      "Read-only repository snapshot. Opening a file never checks out this revision.";
  static const openReadOnlyVersion = "Open read-only version";
  static const restoreThisPathWaitingForRepositoryStatus =
      "Restore this path… · Waiting for repository status";
  static const restoreThisPath = "Restore this path…";
  static const historyArg0 = "History · {arg0}";
  static const restoreArg0 = "Restore {arg0}?";
  static const replaceThisWorkingPathWithRevisionArg0ExistingStagedContent =
      "Replace this working path with revision {arg0}. Existing staged content is retained.";
  static const restoreWorkingFile = "Restore working file";
  static const fileHistoryFollowsRenamesArg0 =
      "File history follows renames · {arg0}";
  static const blameCommittedContent = "Blame · committed content";
  static const blame = "Blame…";
  static const arg0WorkingTree = "{arg0} → Working Tree";
  static const openReadOnlyHistoricalFile = "Open read-only historical file";
  static const compareToCurrentFile = "Compare to current file";
  static const compareToParent = "Compare to parent…";
  static const committedArg0UnsavedEditorContentIsNotPartOfThese =
      "Committed {arg0} · unsaved editor content is not part of these annotations";
  static const historyFromArg0 = "History from {arg0}";
  static const boundary = " · boundary";
  static const arg0Arg1OriginalLineArg2Arg3 =
      "{arg0}  {arg1}\nOriginal line {arg2}{arg3}";
  static const previousLines = "Previous lines";
  static const nextLines = "Next lines";
  static const explicitApplicationOrderDestinationArg0 =
      "Explicit application order · destination {arg0}";
  static const addFullCommitObjectID = "Add full commit object ID";
  static const addReviewedCommit = "Add reviewed commit…";
  static const moveEarlier = "Move earlier";
  static const moveLater = "Move later";
  static const removeFromReviewedSequence = "Remove from reviewed sequence";
  static const applyChangesWithoutCreatingCommits =
      "Apply changes without creating commits";
  static const useThisExplicitMainlineParentForMergeCommits =
      "Use this explicit mainline parent for merge commits";
  static const emptyOrAlreadyAppliedCommitsMayStopGitForAn =
      "Empty or already-applied commits may stop Git for an explicit skip or continuation decision.";
  static const revertInReviewedOrder = "Revert in reviewed order";
  static const cherryPickInReviewedOrder = "Cherry-pick in reviewed order";
  static const returnToFiles = "Return to Files";
  static const git = "Git";
  static const commit = "Commit";
  static const backToCommit = "Back to Commit";
  static const selectAChangeToReview = "Select a change to review";
  static const loadingBranch = "Loading branch…";
  static const branchUnavailable = "Branch unavailable";
  static const unbornHEAD = "Unborn HEAD";
  static const detachedHEADRevision = "Detached HEAD · {revision}";
  static const continueAction = "Continue";
  static const pick = "Pick";
  static const reword = "Reword";
  static const edit = "Edit";
  static const squash = "Squash";
  static const fixup = "Fixup";
  static const drop = "Drop";
  static const abort = "Abort";
  static const skip = "Skip";
  static const quit = "Quit operation";
  static const soft = "Soft";
  static const mixed = "Mixed";
  static const hard = "Hard";
  static const keep = "Keep";
  static const create = "Create";
  static const applyStash = "Apply stash";
  static const popStash = "Pop stash";
  static const dropStashAction = "Drop stash";
  static const editedResult = "Edited result";
  static const leftContent = "Left content";
  static const rightContent = "Right content";
  static const deletePath = "Delete path";
  static const submoduleCommit = "Submodule commit";
  static const presentContent = "Available content";
  static const absentContent = "Absent";
  static const binaryContent = "Binary content";
  static const tooLargeContent = "Content exceeds the display limit";
  static const unavailableContent = "Unavailable content";
  static const gitlinkContent = "Submodule pointer";
  static const symlinkContent = "Symbolic link";
  static const noOperation = "No operation";
  static const mergeOperation = "Merge";
  static const rebaseOperation = "Rebase";
  static const cherryPickOperation = "Cherry-pick";
  static const revertOperation = "Revert";
  static const applyMailboxOperation = "Apply patches";
  static const squashOperation = "Squash merge";
  static const unmergedOperation = "Unmerged index";
  static const preparingPhase = "Preparing Git operation…";
  static const runningPhase = "Git operation in progress";
  static const waitingForPromptPhase = "Waiting for your response";
  static const stoppedPhase = "Stopped for review";
  static const completedPhase = "Completed";
  static const failedPhase = "Failed";
  static const cancelledPhase = "Cancelled";
  static const uncertainPhase = "Outcome requires reconciliation";
  static const stageVersion = "Conflict stage {stage}";
  static const gitMergePreview = "Git merge preview";
  static const normalizedWorking = "Working Tree · Git normalized";
  static const percentValue = "{value} percent";
  static const operationActionQuestion = "{action} {operation}?";
  static const operationActionEllipsis = "{action}…";
  static const rebaseStepSemantics = "{position}, {action}, {subject}";
  static const utf8Bom = "UTF-8 with byte-order mark (BOM)";
  static const utf8NoBom = "UTF-8 without byte-order mark (BOM)";
  static const addsBom =
      "This edit adds a UTF-8 byte-order mark (BOM) at the start of the file.";
  static const removesBom =
      "This edit removes the UTF-8 byte-order mark (BOM) from the start of the file.";
  static const noLineTerminators = "No line terminators";
  static const lineEndings = "{format} line endings";
  static const mixedLineEndings = "Mixed line endings ({formats})";
  static const noFinalLf = "{format} · no final LF";
  static const lineEndingChange =
      "Line ending format changes from {before} to {after}. Clipboard text can use different line endings from the original file.";
  static const gitFailure =
      "Git operation failed. Review the diagnostics below.";
  static const abortInline = "abort";
  static const skipInline = "skip";
  static const quitInline = "quit";
  static const mergeInline = "merge";
  static const rebaseInline = "rebase";
  static const cherryPickInline = "cherry-pick";
  static const revertInline = "revert";
  static const applyMailboxInline = "applyMailbox";
  static const squashInline = "squash";
  static const unmergedInline = "unmerged";
  static const absentPlaceholder = "(absent)";
  static const unborn = "unborn";
  static const rebasedHistoryRevision = "Rebased history · {revision}";
  static const currentHistoryRevision = "Current history · {revision}";
  static const replayedCommitRevision = "Replayed commit · {revision}";
  static const incomingContentRevision = "Incoming content · {revision}";
  static const contentConflict = "Content conflict";
  static const submoduleConflict = "Submodule conflict";
  static const symlinkConflict = "Symbolic-link conflict";
  static const addAddConflict = "Added on both sides";
  static const modifyDeleteConflict = "Modified/deleted or renamed/deleted";
  static const conflictIdentity = "{path} · {kind}";

  static const rebaseArg0OntoArg1 = "Rebase {arg0} onto {arg1}";
  static const updatingConflictRegions = "Updating conflict regions";
  static const remainingConflictMarkers =
      "Result regions with conflict markers: {count}";
  static const ignoreLeftRegion = "Ignore left suggestion";
  static const ignoreRightRegion = "Ignore right suggestion";
  static const newerConflictDraftRetained =
      "The submitted result was saved. Your newer result draft is still unsaved.";
  static const noFileHistoryForThisPathAndRevision =
      "No file history is available for this path and revision.";
  static const all = <String>[
    mergeInProgress,
    rebaseInProgress,
    cherryPickInProgress,
    revertInProgress,
    patchApplicationInProgress,
    squashMergeResultAwaitingCommit,
    unresolvedIndexConflicts,
    unresolvedConflicts,
    reviewOperation,
    refresh,
    createNamedStash,
    createStash,
    noStashes,
    selectAStashToInspectItsChanges,
    stashedUntrackedFiles,
    inspectStashedUntrackedFiles,
    reinstateTheStashSStagedIndexStateWhenApplying,
    applyAndRetain,
    pop,
    createBranch,
    dropStash,
    branchFromStash,
    createSwitchToABranchAtTheStashSOriginal,
    arg0ThisStash,
    theOriginalStashIsRetainedIfApplyingConflicts,
    deletesThisStashEntryItsChangesAreNotApplied,
    resolveTheUnmergedFilesGitHasNoStashContinueOr,
    stashNameMessage,
    stashContentAndResultingIndex,
    stashTrackedWorkingAndStagedChanges,
    stashChangesLeaveStagedChangesInPlaceKeepIndex,
    stashOnlyStagedChangesStaged,
    includeUntrackedFiles,
    allEligiblePathsInThisRepository,
    noEligibleChangesForTheseStashOptions,
    selectAtLeastOneEligiblePath,
    createStash2,
    createWorktree,
    createACommitBeforeCreatingAWorktreeAtHEAD,
    detachedHEAD,
    current,
    locked,
    openInBusyStack,
    statusNotInspected,
    dirty,
    clean,
    openWorkingFolder,
    moveWorktree,
    unlock,
    lock,
    removeCleanWorktree,
    reviewRemovalIncludingLocalChanges,
    newWorktreeFolderName,
    newWorktreeBranch,
    createArg0Arg1WithANewLocalBranchAtArg2,
    destinationFolderName,
    removeWorktree,
    explicitlyDiscardAllLocalTrackedUntrackedChangesInThisWorktree,
    gitRefusesRemovalIfThereAreLocalChangesUntrackedFiles,
    discardLocalWorktreeContentsAndRemove,
    removeCleanWorktree2,
    explicitlyRecurseIntoNestedSubmodulesForUpdatesSynchronization,
    noRecordedSubmodules,
    notInitialized,
    parentGitlinkArg0CheckedOutArg1,
    dirtyNestedRepository,
    cleanNestedRepository,
    nestedStatusUnavailable,
    enterNestedRepository,
    initializeConfiguration,
    updateToParentSRecordedCommit,
    followConfiguredRemoteBranch,
    synchronizeConfiguredURLs,
    stageCurrentSubmodulePointerInParent,
    parentAndSubmoduleCommitsPushesAndDirtyStateRemainSeparate,
    fetchAndCheckOutTheConfiguredRemoteBranchSCommit,
    initializeAsNeededAndCheckOutExactlyArg0RecursiveArg1,
    applyTheReviewedSubmoduleConfigurationOperationRecursiveArg0,
    applySubmoduleOperation,
    inspectARecordedRevisionOrCreateARecoveryBranchReflog,
    selectAReflogEntry,
    previousPage,
    nextPage,
    recoveryBranchName,
    createsABranchAtArg0WorkingFilesAndTheCurrent,
    createRecoveryBranch,
    readOnlyRecoverySnapshot,
    inspectSnapshot,
    reviewReset,
    pageArg0,
    aGitTextHistoryMustOwnItsEditableField,
    editHEADIndexWorkingTree,
    theReviewedIndexOrWorkingContentChangedRefreshThisComparison,
    refreshComparison,
    previousChangedFile,
    nextChangedFile,
    previousDifference,
    nextDifference,
    comparisonMode,
    sideBySide,
    unified,
    diffDisplayOptions,
    wrap,
    words,
    collapseContext,
    ignoreWhitespace,
    searchComparison,
    openCurrentFile,
    previousSearchMatch,
    nextSearchMatch,
    searchMatchPosition,
    searchResultsLimited,
    search,
    closeSearch,
    stagingActions,
    stagingActions2,
    unstageSelectedChangedLines,
    stageSelectedChangedLines,
    unstageWholeFile,
    stageWholeFile,
    arg0WhitespaceOnlyChangedLinesHiddenShowExactChanges,
    arg0ChangedLinesSelectedDisplaySettingsNeverAlterTheStaged,
    readOnlyComparisonCopyTextOrAdjustDisplaySettings,
    noFinalNewline,
    arg0Arg1Arg2BytesArg3,
    textComparisonIsUnavailableForTheseContents,
    thisComparisonExceedsTheBoundedTextReviewLimitTheContents,
    theComparedContentsAreIdentical,
    unstage,
    stage,
    arg0ChangedLine,
    context,
    expandUnchangedContext,
    unstageThisHunk,
    stageThisHunk,
    editStagedContentArg0,
    writingReviewedIndexResult,
    head,
    index,
    workingTree,
    headArg0,
    indexEditableUTF8Blob,
    undo,
    redo,
    reloadIndexReview,
    discardUnsavedIndexDraft,
    closingTheIndexEditorDiscardsOnlyItsDraft,
    discardIndexDraft,
    reloadTheCurrentHEADIndexAndWorkingVersionsThisReplaces,
    replaceDraftAndReload,
    reloadVersions,
    writeEditedResultToThisIndexEntry,
    workingFilesRemainOnDiskReviewTheEditedIndexBefore,
    reviewIndexTextFormatChanges,
    updateOnlyTheReviewedIndexEntryForArg0Arg1,
    writeReviewedIndexResult,
    theEditedResultChangedDuringFormatReviewReviewItAgain,
    synchronizeScrolling,
    changedLine,
    copyHeadRegionIntoIndexDraft,
    copyWorkingRegionIntoIndexDraft,
    indexAppliedNewerDraftPreserved,
    reviewSavedIndexAndKeepDraft,
    indexSourcesChangedSinceApply,
    readOnlyRevisionContent,
    editableIndexContent,
    theRequestedRevisionIsOutsideTheCurrentFiltersResetFilters,
    filterLog,
    filters,
    filtersCount,
    message,
    author,
    path,
    date,
    messageFilter,
    authorFilter,
    pathFilter,
    message2,
    author2,
    path2,
    dateFilter,
    resetFilters,
    refreshLog,
    goToCommitReference,
    backToHEAD,
    orderedCherryPick,
    reviewCherryPickArg0,
    compareTwoSelectedRevisions,
    toggleBranchesPane,
    filterBranchesAndTags,
    commitArg0,
    commitDetails,
    referenceArg0,
    selectThisCommit,
    branchOrTag,
    allReferences,
    local,
    remote,
    tags,
    noCommitsMatchTheCurrentFilters,
    objectID,
    subjectReferences,
    date2,
    gitCommits,
    parents,
    arg0Parents,
    loadMoreCommits,
    loadingChangedFiles,
    noChangedFiles,
    selectACommit,
    compareParentArg0Arg1,
    changedFiles,
    authorArg0Arg1Arg2,
    committerArg0Arg1Arg2,
    shallowPartialBoundaryAParentObjectIsUnavailable,
    parentIsOutsideThisPageOrAShallowBoundary,
    parentArg0,
    commitActions,
    emptyTree,
    createBranch2,
    createTag,
    compareRevisions,
    openSnapshot,
    revertCommit,
    interactiveRebaseAfterThisBoundary,
    resetCurrentBranch,
    copyFullObjectID,
    goToCommitReference2,
    enterACommitIDOrReferenceToRevealInLog,
    theRequestedRevisionIsUnavailable,
    repositoryMetadataIsReadOnlyBranchInspectionAndComparisonRemain,
    workingFilesAreUnavailableOrReadOnlyBranchSwitchingAnd,
    searchBranchesAndTags,
    newBranch,
    localBranches,
    remoteBranches,
    tracksArg0,
    checkedOutAtArg0,
    refreshingBranchMetadata,
    switchToArg0,
    openOccupiedWorktree,
    createLocalTrackingBranch,
    compareToCurrentHEAD,
    mergeIntoCurrentBranch,
    rename,
    changeUpstream,
    delete,
    deleteFromRemote,
    actionsForArg0,
    localBranchName,
    createAtArg0TheNewBranchWillBeCheckedOut,
    theLocalBranchWillTrackArg0AndBeCheckedOut,
    chooseRemoteForDeletion,
    deleteRemoteReference,
    mergeArg0IntoArg1,
    renameArg0,
    upstreamForArg0,
    noUpstream,
    deleteArg0,
    arg0TargetArg1LocalDeletionOnlyAnUnmergedBranchIs,
    delete2,
    deleteUnmergedBranchArg0,
    arg0GitReportsThisBranchIsNotFullyMergedExplicitly,
    deleteUnmergedLocalBranch,
    destinationArg0Arg1,
    sourceBranchOrTag,
    mergePolicy,
    fastForwardWhenPossible,
    alwaysCreateAMergeCommit,
    fastForwardOnly,
    squashIntoStagedChanges,
    stopBeforeCreatingTheMergeCommit,
    fastForwardIsDisabledSoHEADCannotMoveBeforeReview,
    leavesStagedChangesForASeparateCommitThisIsNot,
    conflictsRemainAvailableInTheSharedResolutionWorkspace,
    addRemote,
    fetchArg0PushArg1,
    removeRemote,
    changeFetchURL,
    addPushDestination,
    removePushDestination,
    manageArg0,
    remoteName,
    newRemoteName,
    repositoryURLOrLocalSource,
    enterTheExactReviewedDestinationToRemove,
    credentialsAreSuppliedByConfiguredHelpersOrAPrivatePrompt,
    removeRemoteArg0,
    removesLocalRemoteConfigurationAndTrackingReferencesItDoesNot,
    removeRemote2,
    commitScopeEntireRepository,
    cachedTracking,
    amendLastCommit,
    configuredHooksAndSigningAreRespected,
    rewritesTheSelectedHEADCommitRemoteTrackingCannotProveIt,
    repository,
    detachedArg0,
    log,
    repositoryActions,
    cachedTrackingUpstreamAheadAheadBehindBehind,
    bareRepositoryNoWorkingTreeOpenLogToInspectIts,
    readOnlyRepositoryStagingAndCommitsAreUnavailable,
    repositoryStatusUnavailable,
    amendRevision,
    addSignOffTrailer,
    useConfiguredSigningPolicy,
    cryptographicallySignThisCommit,
    doNotSignThisCommit,
    recentCommitMessages,
    useConfiguredCommitTemplate,
    authorIdentityAndConfiguredHooks,
    draftMessage,
    commitOptions,
    draftRetainedInMemorySavingItFailedArg0,
    commitMessage,
    gitOperationInProgress,
    cancel,
    amendStaged,
    commitStagedCount,
    commitAndPush,
    noReadableCommitTemplateIsConfigured,
    commitIdentityAndHooks,
    recentMessages,
    replaceMessageDraft,
    replaceTheExistingCommitMessageWithTheSelectedMessage,
    replaceDraft,
    localCommitArg0Exists,
    localCommitArg0ExistsReviewLogBeforeAttemptingAnotherCommit,
    commitAuthorName,
    commitAuthorEmail,
    configuredDefault,
    openpgp,
    signingArg0Arg1,
    configuredHooksArg0,
    aSignOffTrailerIsAStatementInTheMessage,
    saveRepositoryIdentity,
    staged,
    untracked,
    unstaged,
    conflicts,
    noChanges,
    repositoryChangeTree,
    changes,
    groupCount,
    expand,
    collapse,
    unstageFile,
    stageFile,
    expandGroup,
    collapseGroup,
    reviewDifference,
    unstageSelectedFiles,
    stageSelectedFiles,
    fileHistoryAndBlame,
    deleteUntrackedFile,
    discardUnstagedChange,
    fileHistory,
    discardUnstagedArg0,
    arg0BytesArg1ReplacesWorkingContentWithTheIndexOr,
    deleteUntrackedFile2,
    discardWorkingChange,
    deleteREMOTEReferenceArg0,
    thisRemovesTheReferenceOnEveryActualPushDestinationListed,
    referenceDoesNotExist,
    arg0ExpectedTipArg1,
    remoteDeletionCompleted,
    deleteArg0FromTheRemote,
    theExactDestinationTipsShownAboveWillBeRemovedAny,
    reviewAndDeleteFromRemote,
    destinationReference,
    reviewDestinations,
    newRemoteBranch,
    arg0Arg1ExpectedArg2,
    aDestinationHasCommitsThatAreUnavailableLocallyFetchThat,
    fetchReviewedDestination,
    chooseADestinationAndReviewTheOutgoingCommits,
    noOutgoingCommits,
    selectAnOutgoingCommit,
    loadMoreOutgoingCommits,
    setThisDestinationAsUpstream,
    chooseExactTagsToPublish,
    tagsNone,
    tagsArg0Selected,
    publishExactlyArg0,
    pushCompletedTheLocalCommitRemainsAvailableInLog,
    forceRequiresTheExactDestinationTipsShownInThisReview,
    forceWithReviewedLease,
    push,
    forcePushWithReviewedLeases,
    rewriteArg0OnlyIfEveryRemoteDestinationStillHasThe,
    otherPeopleMayAlreadyUseThisHistoryABackgroundFetch,
    forceWithLease,
    theRemoteOutcomeIsUncertainReviewDestinationsAgainBeforeAnother,
    parentArg0Arg1,
    remoteToFetch,
    pruneDeletedRemoteTrackingBranches,
    fetchUpdatesRemoteTrackingInformationWithoutReplacingWorkingFiles,
    fetch,
    sourceRemote,
    sourceBranch,
    reviewedStrategy,
    merge,
    rebase,
    stopIfTheDestinationCannotFastForwardNeverMergeOr,
    mergeWithAMergeCommitIncludingWhenFastForwardIs,
    mergeAllowFastForwardWhenPossible,
    rebaseLocalHistoryWhilePreservingLocalMergeCommits,
    rebaseLocalCommitsAsALinearHistory,
    gitIsConfiguredForInteractiveRebaseSelectAPullStrategy,
    useReviewedOrdinaryRebaseForThisPull,
    options,
    alwaysCreateAMergeCommitNoFastForward,
    preserveLocalMergeCommits,
    localChangesMayPreventPullReviewCommitThemOrExplicitly,
    stashes,
    createOrReviewStash,
    pullWithSelectedStrategy,
    repositoryURLOrLocalGitSource,
    httpsSSHOrLocalPath,
    folderToInitialize,
    finalCloneDestination,
    choose,
    createsGitMetadataOnlyExistingFilesAreNotStagedOr,
    theFinalDestinationMustBeAbsentOrEmptyExistingUser,
    initialBranchBlankUsesEffectiveGitPolicy,
    selectedBranchOptional,
    explicitlyInitializeUpdateSubmodulesRecursively,
    preparingGitOperation,
    thisAttemptCreated,
    theDestinationExistedBeforeThisAttempt,
    theDirectoryRemainsForInspectionReviewItBeforeAnotherClone,
    noDestinationDirectoryRemains,
    cancelProcess,
    initialize,
    clone,
    chooseNewBase,
    chooseUpstreamBoundary,
    newBase,
    upstreamBoundaryExcluded,
    sameAsUpstreamBoundary,
    chooseBranchTagOrCommit,
    useUpstreamAsNewBase,
    chooseAValidBranchTagOrCommitFromLog,
    theFirstRetainedCommitInABranchBlockCannotSquash,
    branchBlockArg0,
    rewordWillRequestANewMessage,
    plannedCommitMessages,
    originalCombinedMessagePreviewGitRequestsTheFinalRewordSquash,
    resultArg0Arg1,
    currentBranchBranch,
    detachedHEAD2,
    rebaseRewritesCommitIdentitiesRemoteTrackingInformationCannotProveHistory,
    includeRootCommits,
    mergeCommits,
    flattenHistory,
    preserveBranchStructure,
    autosquash,
    prepareGitPlan,
    commitsToReplayCount,
    includesAllRootCommitsReachableFromThisBranch,
    commitsAfterBoundaryWillBeReplayedOntoBaseTheBoundary,
    root,
    gitBranchLabelResetMergeStructure,
    chooseAnExplicitOldBoundaryOrRootModeThenPrepare,
    moveUp,
    moveDown,
    resetPlan,
    branchBlockArg02,
    selectACommitForDetailsAndChangedFiles,
    previewCombinedCommitMessages,
    altMovesTheSelectedCommitUnrelatedBranchReferencesWillNot,
    cancelPlan,
    startReviewedRebase,
    rewriteArg0PlannedCommitsOnArg1DroppedCommitsRemainVisibly,
    startRebase,
    noContinuingGitOperation,
    stoppedForEditingAmend,
    theseAreUnmergedIndexEntriesPossiblyFromAStashApplication,
    editTheWorkingFilesStageAndAmendTheCurrentCommit,
    arg0Arg1UnmergedStagesArg2,
    theIndexHasNoUnresolvedEntries,
    keepTheCurrentCommitAsAnEmptyCommit,
    theRealIndexHasNoStagedChangesCreateAnExplicit,
    keepEmptyCommit,
    gitWillTryToReturnToTheOperationSStarting,
    skipTheCurrentCommitAndContinueWithTheNextPlanned,
    forgetThisOperationSBookkeepingWhileRetainingTheCurrentFiles,
    continueArg0,
    reloadConflictVersions,
    replaceTheUnsavedResultDraftWithTheCurrentWorkingFile,
    loadingConflictVersions,
    loadingConflict,
    baseLeft,
    baseRight,
    noBaseEntryForThisConflict,
    acceptEntireLeftFile,
    acceptEntireRightFile,
    previousConflictRegion,
    nextConflictRegion,
    manualResolution,
    regionArg0Arg1Arg2Reviewed,
    sourceAlignmentExceededTheTextComparisonLimitSourcePanesRemain,
    acceptLeftRegion,
    acceptRightRegion,
    keepManualResultForRegion,
    applyGitSNonConflictingChanges,
    replaceTheCurrentResultDraftWithGitSMergePreview,
    useMergePreview,
    applyNonConflictingChanges,
    leftSource,
    result,
    rightSource,
    stage2,
    stage3,
    conflictVersionsAreUnavailableRefreshToReviewTheirCurrentState,
    resultSavedToDiskTheIndexStillDeterminesWhetherThis,
    saveResultDraft,
    applyResultAndStageResolution,
    resultEditableUTF8WorkingContent,
    editableConflictResult,
    leftArg0Arg1RightArg2Arg3,
    chooseContentDeletionOrASubmoduleCommitExplicitlyNoBinary,
    useEntireLeftContent,
    useEntireRightContent,
    deleteThisPath,
    resolvedSubmoduleCommit,
    stageThisExactGitlinkInTheParentThisDoesNot,
    setResolvedGitlink,
    baseStageArg0,
    theResultWasEditedKeepTheManualResultOrSelect,
    applyArg0Resolution,
    stageTheChosenGitlinkCommitInTheParentTheSubmodule,
    replacesTheEntireWorkingPathArg0AndStagesTheDecision,
    applyEntireFileDecision,
    stageThisConflictResolution,
    useTheEntireEditedResultAsArg0GitRecordsThe,
    applyAndStage,
    reviewResultTextFormatChanges,
    saveReviewedResult,
    nativeGitTableAccessibilityIsUnavailableRetryAfterReconnectingThe,
    sans,
    select,
    contextMenu,
    copyText,
    loadingRow,
    retry,
    gitMessage,
    cancelPrompt,
    useMessageAndContinue,
    respondPrivately,
    viewPreferencesCouldNotBeSavedArg0,
    commitDraftStorageArg0,
    viewPreferencesCouldNotBeReadArg0,
    commitDraftWasRetainedInMemoryButCouldNotBe,
    theReviewedRepositoryIsReadOnlyForThisOperationHistory,
    gitReturnedArg0TheApplicationCouldNotRefreshItsDocuments,
    selectCommitInLog,
    currentBranch,
    noMatchingBranchesOrTagsSelectACommitInLog,
    branches,
    pushCommits,
    pullIntoArg0,
    resolveArg0,
    currentOperation,
    rebaseCommits,
    fetch2,
    pull,
    push2,
    branches2,
    manageRemotes,
    mergeIntoArg0,
    rebase2,
    conflictsAndCurrentOperation,
    stashes2,
    worktrees,
    submodules,
    reflogAndRecovery,
    cloneRepository,
    revokeRepositoryTrust,
    waitingForRepositoryStatus,
    repositoryStatusUnavailableRefresh,
    manageRemotes2,
    mergeIntoArg02,
    worktrees2,
    submodules2,
    reflogAndRecovery2,
    cloneRepositoryArg0,
    apply,
    resizeGitPanes,
    arg0Percent,
    exitStatusStatus,
    repositoryChangedRefreshAndReviewBeforeTryingAgain,
    anotherOperationHoldsTheRepositoryOrIndexLockWaitThen,
    repositoryTrustIsRequiredForThisOperation,
    theGitServiceDisconnectedReconnectAndReconcileTheRepository,
    theInstalledGitExecutableCannotSupportThisOperationReviewIts,
    thisRepositoryIsReadOnlyForTheRequestedOperationReview,
    theOperationNeedsReconciliationReviewTheResultingRepositoryOrRemote,
    gitAuthenticationFailedReviewTheCredentialHelperOrUnlockThe,
    sshHostVerificationFailedReviewTheHostIdentityThroughYour,
    commitSigningFailedOrWasCancelledReviewTheSigningKey,
    setARepositoryAuthorNameAndEmailThenReturnTo,
    gitRejectedTheReviewedUpdateRefreshAndReviewTheActual,
    workingOrStagedChangesPreventThisOperationReviewCommitOr,
    aRequiredGitObjectIsUnavailableReviewShallowOrPartial,
    gitOperationFailedArg0,
    diagnostics,
    authorizeGitInspection,
    copyDiagnostics,
    actions,
    branchAtArg0,
    createsALocalBranchWithoutCheckingItOut,
    tagArg0,
    readOnlySnapshotArg0,
    cherryPickCommits,
    revertCommits,
    compareToFullRevisionID,
    treeComparisonDirectionArg0TheRevisionEnteredHere,
    enterAFullValidObjectID,
    arg0Arg1TreeComparison,
    resetArg0ToArg1,
    movesHEADCurrentBranchReflogDoesNotRecoverArbitraryUntracked,
    moveHEADKeepIndexAndWorkingFiles,
    moveHEADAndReplaceIndexKeepWorkingFiles,
    replaceHEADIndexAndTrackedWorkingFilesMayOverwriteObstructing,
    replaceHEADIndexAndEligibleFilesRefuseIfLocalChanges,
    resetWithArg0,
    arg0Arg1ReviewTheSelectedModeSEffectsBeforeApplying,
    resetArg0,
    targetArg0,
    tagName,
    annotatedTag,
    cryptographicSigning,
    configuredPolicy,
    signThisTag,
    doNotSign,
    tagMessage,
    createsTheTagLocallyPublishSelectedTagsExplicitlyInPush,
    completeTreesArg0Arg1,
    nextChangedFilePage,
    readOnlyRepositorySnapshotOpeningAFileNeverChecksOut,
    openReadOnlyVersion,
    restoreThisPathWaitingForRepositoryStatus,
    restoreThisPath,
    historyArg0,
    restoreArg0,
    replaceThisWorkingPathWithRevisionArg0ExistingStagedContent,
    restoreWorkingFile,
    fileHistoryFollowsRenamesArg0,
    blameCommittedContent,
    blame,
    arg0WorkingTree,
    openReadOnlyHistoricalFile,
    compareToCurrentFile,
    compareToParent,
    committedArg0UnsavedEditorContentIsNotPartOfThese,
    historyFromArg0,
    boundary,
    arg0Arg1OriginalLineArg2Arg3,
    previousLines,
    nextLines,
    explicitApplicationOrderDestinationArg0,
    addFullCommitObjectID,
    addReviewedCommit,
    moveEarlier,
    moveLater,
    removeFromReviewedSequence,
    applyChangesWithoutCreatingCommits,
    useThisExplicitMainlineParentForMergeCommits,
    emptyOrAlreadyAppliedCommitsMayStopGitForAn,
    revertInReviewedOrder,
    cherryPickInReviewedOrder,
    returnToFiles,
    git,
    commit,
    backToCommit,
    selectAChangeToReview,
    loadingBranch,
    branchUnavailable,
    unbornHEAD,
    detachedHEADRevision,
    continueAction,
    pick,
    reword,
    edit,
    squash,
    fixup,
    drop,
    abort,
    skip,
    quit,
    soft,
    mixed,
    hard,
    keep,
    create,
    applyStash,
    popStash,
    dropStashAction,
    editedResult,
    leftContent,
    rightContent,
    deletePath,
    submoduleCommit,
    presentContent,
    absentContent,
    binaryContent,
    tooLargeContent,
    unavailableContent,
    gitlinkContent,
    symlinkContent,
    noOperation,
    mergeOperation,
    rebaseOperation,
    cherryPickOperation,
    revertOperation,
    applyMailboxOperation,
    squashOperation,
    unmergedOperation,
    preparingPhase,
    runningPhase,
    waitingForPromptPhase,
    stoppedPhase,
    completedPhase,
    failedPhase,
    cancelledPhase,
    uncertainPhase,
    stageVersion,
    gitMergePreview,
    normalizedWorking,
    percentValue,
    operationActionQuestion,
    operationActionEllipsis,
    rebaseStepSemantics,
    utf8Bom,
    utf8NoBom,
    addsBom,
    removesBom,
    noLineTerminators,
    lineEndings,
    mixedLineEndings,
    noFinalLf,
    lineEndingChange,
    gitFailure,
    abortInline,
    skipInline,
    quitInline,
    mergeInline,
    rebaseInline,
    cherryPickInline,
    revertInline,
    applyMailboxInline,
    squashInline,
    unmergedInline,
    absentPlaceholder,
    unborn,
    rebasedHistoryRevision,
    currentHistoryRevision,
    replayedCommitRevision,
    incomingContentRevision,
    contentConflict,
    submoduleConflict,
    symlinkConflict,
    addAddConflict,
    modifyDeleteConflict,
    conflictIdentity,
    discardUnsavedConflictDraft,
    closingTheConflictEditorDiscardsOnlyItsDraft,
    discardConflictDraft,
    revealRevisionWithoutFilters,
    restoreHistoryFilters,
    showAllAffectedFiles,
    graphLanes,
    rebaseArg0OntoArg1,
    updatingConflictRegions,
    remainingConflictMarkers,
    ignoreLeftRegion,
    ignoreRightRegion,
    newerConflictDraftRetained,
    noFileHistoryForThisPathAndRevision,
    reviewSavedMessage,
    savedMessage,
    keepThisMessage,
    useSavedMessage,
    commitDraftChangedInAnotherWindow,
    discardUnsavedCommitMessages,
    messagesCouldNotBeSavedStayInThisWindow,
    discardCommitMessages,
  ];
}
