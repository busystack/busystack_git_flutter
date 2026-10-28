import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'diff_view.dart';
import 'host.dart';
import 'session.dart';
import 'text_encoding.dart';
import 'workflow_ui.dart';

final class GitOperationView extends StatefulWidget {
  const GitOperationView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitOperationView> createState() => _OperationState();
}

final class _OperationState extends GitDialogState<GitOperationView> {
  @override
  GitSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    session.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    session.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = session.snapshot, operation = state?.operation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        states(refresh: () => unawaited(session.refresh())),
        Text(
          operation == null || operation.kind == GitOperationKind.none
              ? gitString(context, GitMessages.noContinuingGitOperation)
              : '${gitEnumLabel(context, operation.kind)}${operation.editStop ? gitString(context, GitMessages.stoppedForEditingAmend) : ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (operation?.kind == GitOperationKind.unmerged)
          const GitLabel(
            GitMessages
                .theseAreUnmergedIndexEntriesPossiblyFromAStashApplication,
          ),
        if (operation?.editStop == true)
          const GitLabel(
            GitMessages.editTheWorkingFilesStageAndAmendTheCurrentCommit,
          ),
        Expanded(
          child: ListView(
            children: [
              for (final change
                  in state?.changes.where((e) => e.conflicted) ?? <GitChange>[])
                ListTile(
                  leading: const GitIcon(GitGlyph.warning),
                  title: Text(change.path.display),
                  subtitle: Text(
                    gitString(
                      context,
                      GitMessages.arg0Arg1UnmergedStagesArg2,
                      values: {
                        'arg0': change.index,
                        'arg1': change.worktree,
                        'arg2': change.conflictStages.keys.join(', '),
                      },
                    ),
                  ),
                  trailing: const GitIcon(GitGlyph.next),
                  onTap: () =>
                      GitWorkflowUi(context, session).conflict(change.path),
                ),
              if (state != null && !state.operation.unmerged)
                const ListTile(
                  title: GitLabel(GitMessages.theIndexHasNoUnresolvedEntries),
                ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: session.host.spacing,
          children: [
            if (state != null &&
                !state.operation.unmerged &&
                !state.changes.any((c) => c.staged) &&
                operation?.editStop != true &&
                operation?.other != null &&
                {
                  GitOperationKind.rebase,
                  GitOperationKind.cherryPick,
                }.contains(operation?.kind))
              OutlinedButton(
                onPressed: loading || session.running
                    ? null
                    : () async {
                        final page = await query(
                          () => session.client.history(
                            session.repository,
                            filter: HistoryFilter(
                              reference: operation!.other!.value,
                            ),
                            limit: 1,
                          ),
                        );
                        if (!mounted || page == null || page.commits.isEmpty)
                          return;
                        final message = await gitTextInput(
                          context,
                          session,
                          GitMessages.keepTheCurrentCommitAsAnEmptyCommit,
                          initial: page.commits.first.message,
                          multiline: true,
                          explanation: GitMessages
                              .theRealIndexHasNoStagedChangesCreateAnExplicit,
                        );
                        if (!mounted || message == null) return;
                        await apply(
                          CommitIndex(
                            message,
                            allowEmpty: true,
                            expectedHead: state.head,
                            expectedIndex: state.indexToken,
                          ),
                        );
                      },
                child: const GitLabel(GitMessages.keepEmptyCommit),
              ),
            for (final action in operation?.actions ?? <GitContinuation>{})
              OutlinedButton(
                onPressed: loading || session.running
                    ? null
                    : () async {
                        if (action != GitContinuation.continueOperation &&
                            !await gitConfirm(
                              context,
                              session,
                              '${gitString(context, switch (action) {
                                GitContinuation.abort => GitMessages.abortInline,
                                GitContinuation.skip => GitMessages.skipInline,
                                GitContinuation.quit => GitMessages.quitInline,
                                _ => GitMessages.continueAction,
                              })} ${gitEnumLabel(context, operation!.kind)}?',
                              action == GitContinuation.abort
                                  ? GitMessages
                                        .gitWillTryToReturnToTheOperationSStarting
                                  : action == GitContinuation.skip
                                  ? GitMessages
                                        .skipTheCurrentCommitAndContinueWithTheNextPlanned
                                  : GitMessages
                                        .forgetThisOperationSBookkeepingWhileRetainingTheCurrentFiles,
                              action: gitString(context, switch (action) {
                                GitContinuation.abort =>
                                  GitMessages.abortInline,
                                GitContinuation.skip => GitMessages.skipInline,
                                GitContinuation.quit => GitMessages.quitInline,
                                _ => GitMessages.continueAction,
                              }),
                            ))
                          return;
                        await apply(
                          ContinueGitOperation(
                            operation!.kind,
                            action,
                            expectedHead: state!.head,
                            expectedIndex: state.indexToken,
                          ),
                        );
                      },
                child: Text(
                  action == GitContinuation.continueOperation
                      ? gitString(
                          context,
                          GitMessages.continueArg0,
                          values: {
                            'arg0': gitString(context, switch (operation!
                                .kind) {
                              GitOperationKind.merge => GitMessages.mergeInline,
                              GitOperationKind.rebase =>
                                GitMessages.rebaseInline,
                              GitOperationKind.cherryPick =>
                                GitMessages.cherryPickInline,
                              GitOperationKind.revert =>
                                GitMessages.revertInline,
                              GitOperationKind.applyMailbox =>
                                GitMessages.applyMailboxInline,
                              GitOperationKind.squash =>
                                GitMessages.squashInline,
                              _ => GitMessages.unmergedInline,
                            }),
                          },
                        )
                      : '${gitString(context, switch (action) {
                          GitContinuation.abort => GitMessages.abortInline,
                          GitContinuation.skip => GitMessages.skipInline,
                          GitContinuation.quit => GitMessages.quitInline,
                          _ => GitMessages.continueAction,
                        })}…',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

final class GitConflictView extends StatefulWidget {
  const GitConflictView({super.key, required this.session, required this.path});
  final GitSession session;
  final RepoPath path;
  @override
  State<GitConflictView> createState() => _ConflictState();
}

final class _ConflictState extends GitDialogState<GitConflictView> {
  @override
  GitSession get session => widget.session;
  final result = _ConflictResultController();
  final _leftTextController = GitHighlightedTextController();
  final _rightTextController = GitHighlightedTextController();
  final undo = UndoHistoryController();
  final resultFocus = FocusNode();
  GitContent? left, right, base, working, preview;
  GitSnapshot? reviewed;
  final reviewedRegions = <int>{};
  List<_MergeRegion> regions = [];
  int activeRegion = 0;
  bool saved = false, _draftDirty = false, _readingVersions = false;
  int _versionGeneration = 0;
  bool get _busy => loading || _readingVersions || session.running;
  int _anchorRevision = 0;
  int? _resultAnchor;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void dispose() {
    _versionGeneration++;
    _leftTextController.dispose();
    _rightTextController.dispose();
    result.dispose();
    undo.dispose();
    resultFocus.dispose();
    super.dispose();
  }

  Future<void> refresh({bool replaceSavedDraft = false}) async {
    if (_draftDirty &&
        !replaceSavedDraft &&
        !await gitConfirm(
          context,
          session,
          GitMessages.reloadConflictVersions,
          GitMessages.replaceTheUnsavedResultDraftWithTheCurrentWorkingFile,
          action: GitMessages.replaceDraftAndReload,
        ))
      return;
    if (!mounted) return;
    final current = ++_versionGeneration;
    final previousData = data;
    setState(() => _readingVersions = true);
    try {
      await load(GitInspection(GitInspectionKind.conflict, path: widget.path));
      if (!mounted ||
          current != _versionGeneration ||
          data == null ||
          error != null)
        return;
      final inspected = data!, token = cancellation;
      // Metadata and source panes become visible together, after all content
      // identities have been reconciled. Keep the previous review intact while
      // the next one is loading.
      setState(() => data = previousData);
      final state = await session.readStatus(cancellation: token);
      final versions = await Future.wait([
        for (final stage in [2, 1, 3])
          session.client.content(
            session.repository,
            widget.path,
            ContentVersion(ContentKind.conflictStage, stage: stage),
            cancellation: token,
          ),
        session.client.content(
          session.repository,
          widget.path,
          const ContentVersion.working(),
          cancellation: token,
        ),
        session.client.content(
          session.repository,
          widget.path,
          const ContentVersion(ContentKind.mergePreview),
          cancellation: token,
        ),
      ]);
      final after = await session.readStatus(cancellation: token);
      if (!mounted || current != _versionGeneration) return;
      final stages = inspected['stages'] as Json;
      if (state.token != after.token ||
          (inspected['working'] as Json)['token'] != versions[3].token ||
          inspected['leftRevision'] != state.operation.head?.value ||
          inspected['rightRevision'] != state.operation.other?.value) {
        throw const GitException(GitErrorCode.staleReview);
      }
      for (var i = 0; i < 3; i++) {
        final entry = stages['${[2, 1, 3][i]}'] as Json?;
        if (entry == null
            ? versions[i].availability != ContentAvailability.absent
            : entry['oid'] != versions[i].oid?.value ||
                  entry['mode'] != versions[i].mode) {
          throw const GitException(GitErrorCode.staleReview);
        }
      }
      final leftText = versions[0].text ?? '',
          rightText = versions[2].text ?? '',
          previewText = versions[4].text ?? '',
          marker = inspected['marker'] as String;
      final alignedRegions = await _backgroundRegions(
        leftText,
        rightText,
        previewText,
        marker,
      );
      if (!mounted || current != _versionGeneration) return;
      setState(() {
        data = inspected;
        left = versions[0];
        base = versions[1];
        right = versions[2];
        working = versions[3];
        preview = versions[4];
        reviewed = state;
        regions = alignedRegions;
        _leftTextController.text = leftText;
        _rightTextController.text = rightText;
        _leftTextController.setHighlights([
          for (final region in alignedRegions)
            if (region.leftOffset != null &&
                region.leftOffset! + region.left.length <= leftText.length &&
                leftText.substring(
                      region.leftOffset!,
                      region.leftOffset! + region.left.length,
                    ) ==
                    region.left)
              GitTextHighlight(
                region.leftOffset!,
                region.leftOffset! + region.left.length,
                GitHighlightKind.conflict,
              ),
        ]);
        _rightTextController.setHighlights([
          for (final region in alignedRegions)
            if (region.rightOffset != null &&
                region.rightOffset! + region.right.length <= rightText.length &&
                rightText.substring(
                      region.rightOffset!,
                      region.rightOffset! + region.right.length,
                    ) ==
                    region.right)
              GitTextHighlight(
                region.rightOffset!,
                region.rightOffset! + region.right.length,
                GitHighlightKind.conflict,
              ),
        ]);
        activeRegion = 0;
        result.regions = regions;
        result.activeRegion = 0;
        final savedText = working!.text ?? '';
        if (result.text != savedText) result.text = savedText;
        reviewedRegions.clear();
        saved = false;
        _draftDirty = false;
      });
    } on Object catch (failure) {
      if (mounted && current == _versionGeneration) {
        setState(
          () => error = failure is GitException
              ? failure
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$failure'),
                ),
        );
      }
    } finally {
      if (mounted && current == _versionGeneration)
        setState(() => _readingVersions = false);
    }
  }

  String _kindLabel() => gitString(context, switch (data?['kind']) {
    'content' => GitMessages.contentConflict,
    'submodule' => GitMessages.submoduleConflict,
    'symlink' => GitMessages.symlinkConflict,
    'add/add' => GitMessages.addAddConflict,
    'modify/delete or rename/delete' => GitMessages.modifyDeleteConflict,
    null => GitMessages.loadingConflict,
    _ => GitMessages.conflicts,
  });

  String _sourceLabel({required bool leftSource}) {
    final rebase =
        (data?['operation'] as Map?)?['kind'] == GitOperationKind.rebase.name;
    final revision =
        data?[leftSource ? 'leftRevision' : 'rightRevision'] as String?;
    return gitString(
      context,
      leftSource
          ? (rebase
                ? GitMessages.rebasedHistoryRevision
                : GitMessages.currentHistoryRevision)
          : (rebase
                ? GitMessages.replayedCommitRevision
                : GitMessages.incomingContentRevision),
      values: {
        'revision': revision == null
            ? gitString(
                context,
                leftSource ? GitMessages.stage2 : GitMessages.stage3,
              )
            : GitOid(revision).abbreviated,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text =
        left != null &&
        right != null &&
        [left!, right!, working!].every(
          (e) => {
            ContentAvailability.present,
            ContentAvailability.absent,
          }.contains(e.availability),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        states(refresh: () => unawaited(refresh())),
        if (_readingVersions && !loading)
          LinearProgressIndicator(
            semanticsLabel: gitString(
              context,
              GitMessages.loadingConflictVersions,
            ),
          ),
        Text('${widget.path.display} · ${_kindLabel()}'),
        if (data != null)
          Wrap(
            spacing: session.host.spacing,
            children: [
              if (data!['baseAvailable'] == true)
                TextButton(
                  onPressed: () => compareBase(2),
                  child: const GitLabel(GitMessages.baseLeft),
                ),
              if (data!['baseAvailable'] == true)
                TextButton(
                  onPressed: () => compareBase(3),
                  child: const GitLabel(GitMessages.baseRight),
                ),
              if (data!['baseAvailable'] != true)
                const GitLabel(GitMessages.noBaseEntryForThisConflict),
              if (text)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(acceptWhole(ConflictChoice.left)),
                  child: const GitLabel(GitMessages.acceptEntireLeftFile),
                ),
              if (text)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(acceptWhole(ConflictChoice.right)),
                  child: const GitLabel(GitMessages.acceptEntireRightFile),
                ),
            ],
          ),
        if (text) ...[
          Wrap(
            spacing: session.host.spacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GitIconButton(
                tooltip: gitString(context, GitMessages.previousConflictRegion),
                onPressed: _busy || regions.isEmpty ? null : () => navigate(-1),
                icon: const GitIcon(GitGlyph.up),
              ),
              GitIconButton(
                tooltip: gitString(context, GitMessages.nextConflictRegion),
                onPressed: _busy || regions.isEmpty ? null : () => navigate(1),
                icon: const GitIcon(GitGlyph.down),
              ),
              Text(
                regions.isEmpty
                    ? gitString(context, GitMessages.manualResolution)
                    : gitString(
                        context,
                        GitMessages.regionArg0Arg1Arg2Reviewed,
                        values: {
                          'arg0': activeRegion + 1,
                          'arg1': regions.length,
                          'arg2': reviewedRegions.length,
                        },
                      ),
              ),
              if (regions.any(
                (r) => r.leftOffset == null || r.rightOffset == null,
              ))
                const GitLabel(
                  GitMessages
                      .sourceAlignmentExceededTheTextComparisonLimitSourcePanesRemain,
                ),
              TextButton(
                onPressed: _busy || regions.isEmpty
                    ? null
                    : () => acceptRegion(true),
                child: const GitLabel(GitMessages.acceptLeftRegion),
              ),
              TextButton(
                onPressed: _busy || regions.isEmpty
                    ? null
                    : () => acceptRegion(false),
                child: const GitLabel(GitMessages.acceptRightRegion),
              ),
              TextButton(
                onPressed: _busy || regions.isEmpty
                    ? null
                    : () => setState(() => reviewedRegions.add(activeRegion)),
                child: const GitLabel(GitMessages.keepManualResultForRegion),
              ),
              TextButton(
                onPressed: _busy || preview?.text == null
                    ? null
                    : () async {
                        if (!await gitConfirm(
                          context,
                          session,
                          GitMessages.applyGitSNonConflictingChanges,
                          GitMessages
                              .replaceTheCurrentResultDraftWithGitSMergePreview,
                          action: GitMessages.useMergePreview,
                        ))
                          return;
                        result.value = TextEditingValue(text: preview!.text!);
                        setState(() {
                          saved = false;
                          _draftDirty = true;
                        });
                      },
                child: const GitLabel(GitMessages.applyNonConflictingChanges),
              ),
            ],
          ),
          Expanded(
            child: GitRevisionPanes(
              labels: const [
                GitMessages.leftSource,
                GitMessages.result,
                GitMessages.rightSource,
              ],
              anchorRevision: _anchorRevision,
              panes: [
                (scroll) => GitTextPane(
                  label: _sourceLabel(leftSource: true),
                  controller: _leftTextController,
                  readOnly: true,
                  semanticLabel: GitMessages.readOnlyRevisionContent,
                  scrollController: scroll,
                  revealRevision: _anchorRevision,
                  revealOffset: regions.isEmpty
                      ? null
                      : regions[activeRegion].leftOffset,
                ),
                (scroll) => resultPane(scroll),
                (scroll) => GitTextPane(
                  label: _sourceLabel(leftSource: false),
                  controller: _rightTextController,
                  readOnly: true,
                  semanticLabel: GitMessages.readOnlyRevisionContent,
                  scrollController: scroll,
                  revealRevision: _anchorRevision,
                  revealOffset: regions.isEmpty
                      ? null
                      : regions[activeRegion].rightOffset,
                ),
              ],
            ),
          ),
        ] else
          Expanded(
            child: left == null
                ? error == null
                      ? const Center(child: CircularProgressIndicator())
                      : const Center(
                          child: GitLabel(
                            GitMessages
                                .conflictVersionsAreUnavailableRefreshToReviewTheirCurrentState,
                          ),
                        )
                : nonText(),
          ),
        if (saved)
          const GitLabel(
            GitMessages.resultSavedToDiskTheIndexStillDeterminesWhetherThis,
          ),
        if (text) GitLabel(gitTextFormatLabel(result.text, context: context)),
        if (text)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: session.host.spacing,
            children: [
              OutlinedButton(
                onPressed: _busy || error != null || reviewed == null
                    ? null
                    : () => unawaited(save(false)),
                child: const GitLabel(GitMessages.saveResultDraft),
              ),
              FilledButton(
                onPressed: _busy || error != null || reviewed == null
                    ? null
                    : () => unawaited(save(true)),
                child: const GitLabel(
                  GitMessages.applyResultAndStageResolution,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget resultPane(ScrollController scroll) => GitTextPane(
    label: gitString(context, GitMessages.resultEditableUTF8WorkingContent),
    semanticLabel: gitString(context, GitMessages.editableConflictResult),
    controller: result,
    readOnly: _busy,
    undoController: undo,
    focusNode: resultFocus,
    scrollController: scroll,
    revealOffset: _resultAnchor,
    revealRevision: _anchorRevision,
    onChanged: (_) => setState(() {
      saved = false;
      _draftDirty = true;
    }),
  );
  Widget nonText() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          gitString(
            context,
            GitMessages.leftArg0Arg1RightArg2Arg3,
            values: {
              'arg0': gitEnumLabel(context, left!.availability),
              'arg1': left!.mode,
              'arg2': gitEnumLabel(context, right!.availability),
              'arg3': right!.mode,
            },
          ),
        ),
        const GitLabel(
          GitMessages.chooseContentDeletionOrASubmoduleCommitExplicitlyNoBinary,
        ),
        for (final choice in [
          ConflictChoice.left,
          ConflictChoice.right,
          ConflictChoice.delete,
        ])
          TextButton(
            onPressed: _busy ? null : () => unawaited(acceptWhole(choice)),
            child: Text(switch (choice) {
              ConflictChoice.left => gitString(
                context,
                GitMessages.useEntireLeftContent,
              ),
              ConflictChoice.right => gitString(
                context,
                GitMessages.useEntireRightContent,
              ),
              _ => gitString(context, GitMessages.deleteThisPath),
            }),
          ),
        if (data?['kind'] == 'submodule')
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final value = await gitTextInput(
                      context,
                      session,
                      GitMessages.resolvedSubmoduleCommit,
                      explanation: GitMessages
                          .stageThisExactGitlinkInTheParentThisDoesNot,
                    );
                    if (!mounted || value == null) return;
                    try {
                      await resolve(
                        ConflictChoice.gitlink,
                        gitlink: GitOid(value),
                      );
                    } on FormatException {
                      setState(
                        () => error = const GitException(
                          GitErrorCode.invalidRequest,
                        ),
                      );
                    }
                  },
            child: const GitLabel(GitMessages.setResolvedGitlink),
          ),
      ],
    ),
  );
  Future<void> compareBase(int stage) => session.host.present<void>(
    context,
    gitString(context, GitMessages.baseStageArg0, values: {'arg0': stage}),
    GitDiffView(
      session: session,
      comparison: GitComparison(
        widget.path,
        const ContentVersion(ContentKind.conflictStage, stage: 1),
        ContentVersion(ContentKind.conflictStage, stage: stage),
      ),
    ),
    expanded: true,
  );
  void navigate(int delta) {
    setState(() {
      activeRegion = (activeRegion + delta) % regions.length;
      result.activeRegion = activeRegion;
      _anchorRevision++;
    });
    final block = matchingResultRegion(result.text, regions[activeRegion]),
        offset = block == null ? -1 : result.text.indexOf(block);
    _resultAnchor = offset >= 0 ? offset : null;
    if (offset >= 0) {
      result.selection = TextSelection(
        baseOffset: offset,
        extentOffset: offset + block!.length,
      );
      resultFocus.requestFocus();
    }
  }

  void acceptRegion(bool useLeft) {
    final region = regions[activeRegion],
        block = matchingResultRegion(result.text, regions[activeRegion]);
    final offset = block == null ? -1 : result.text.indexOf(block);
    if (offset < 0) {
      session.host.notify(
        GitMessages.theResultWasEditedKeepTheManualResultOrSelect,
      );
      return;
    }
    final replacement = useLeft ? region.left : region.right;
    result.value = TextEditingValue(
      text: result.text.replaceRange(
        offset,
        offset + block!.length,
        replacement,
      ),
      selection: TextSelection.collapsed(offset: offset + replacement.length),
    );
    setState(() {
      reviewedRegions.add(activeRegion);
      saved = false;
      _draftDirty = true;
    });
  }

  Future<void> acceptWhole(ConflictChoice choice) async {
    if (!await gitConfirm(
      context,
      session,
      gitString(
        context,
        GitMessages.applyArg0Resolution,
        values: {'arg0': gitEnumLabel(context, choice)},
      ),
      data?['kind'] == 'submodule'
          ? GitMessages.stageTheChosenGitlinkCommitInTheParentTheSubmodule
          : gitString(
              context,
              GitMessages.replacesTheEntireWorkingPathArg0AndStagesTheDecision,
              values: {'arg0': widget.path.display},
            ),
      action: GitMessages.applyEntireFileDecision,
    ))
      return;
    await resolve(choice);
  }

  Future<void> save(bool stage) async {
    final text = result.text;
    final formatChange = gitTextFormatChange(
      working!.text ?? '',
      text,
      context: context,
    );
    if (stage &&
        !await gitConfirm(
          context,
          session,
          GitMessages.stageThisConflictResolution,
          gitString(
            context,
            GitMessages.useTheEntireEditedResultAsArg0GitRecordsThe,
            values: {
              'arg0': widget.path.display,
              'arg1': formatChange == null ? '' : '\n\n$formatChange',
            },
          ),
          action: GitMessages.applyAndStage,
        ))
      return;
    if (!stage &&
        formatChange != null &&
        !await gitConfirm(
          context,
          session,
          GitMessages.reviewResultTextFormatChanges,
          formatChange,
          action: GitMessages.saveReviewedResult,
        ))
      return;
    if (!mounted) return;
    if (result.text != text) {
      setState(
        () => error = const GitException(
          GitErrorCode.staleReview,
          diagnostic:
              GitMessages.theEditedResultChangedDuringFormatReviewReviewItAgain,
        ),
      );
      return;
    }
    await resolve(
      ConflictChoice.edited,
      bytes: Uint8List.fromList(utf8.encode(text)),
      stage: stage,
    );
  }

  Future<void> resolve(
    ConflictChoice choice, {
    Uint8List? bytes,
    GitOid? gitlink,
    bool stage = true,
  }) async {
    if (reviewed == null || working == null || data == null) return;
    final stages = data!['stages'] as Json;
    final outcome = await apply(
      ResolveConflict(
        widget.path,
        choice,
        expectedHead: reviewed!.head,
        expectedIndex: reviewed!.indexToken,
        expectedWorking: working!.token,
        expectedStages: {
          for (final entry in stages.entries)
            int.parse(
              entry.key,
            ): '${(entry.value as Json)['mode']}:${(entry.value as Json)['oid']}',
        },
        bytes: bytes,
        mode: choice == ConflictChoice.edited
            ? (working!.mode == '100755' ? '100755' : '100644')
            : null,
        gitlink: gitlink,
        stageResult: stage,
      ),
    );
    if (!mounted || outcome == null || outcome.error != null) return;
    if (stage) {
      gitCompleteSurface(context);
    } else {
      await refresh(replaceSavedDraft: true);
      if (mounted) setState(() => saved = true);
    }
  }
}

final class _MergeRegion {
  const _MergeRegion(
    this.block,
    this.left,
    this.right,
    this.previewLeft,
    this.previewRight, {
    this.leftOffset,
    this.rightOffset,
  });
  final String block, left, right;
  final int previewLeft, previewRight;
  final int? leftOffset, rightOffset;
}

// Index stages establish conflict state. Marker parsing here only locates a
// unique, unchanged region in an already-authoritative conflict, so ordinary
// marker-like prose never decides whether a path is resolved.
String? matchingResultRegion(String result, _MergeRegion region) {
  if (result.contains(region.block) &&
      result.indexOf(region.block) == result.lastIndexOf(region.block))
    return region.block;
  final lines = exactLines(result), candidates = <String>[];
  for (var start = 0; start < lines.length; start++) {
    final match = RegExp(r'^(<{7,})(?: |\r?$)').firstMatch(lines[start]);
    if (match == null) continue;
    final size = match[1]!.length,
        left = StringBuffer(),
        right = StringBuffer();
    var i = start + 1;
    while (i < lines.length &&
        !lines[i].startsWith('|' * size) &&
        lines[i].trimRight() != '=' * size) {
      left.write(lines[i++]);
    }
    if (i < lines.length && lines[i].startsWith('|' * size)) {
      while (i < lines.length && lines[i].trimRight() != '=' * size) {
        i++;
      }
    }
    if (i == lines.length) continue;
    i++;
    while (i < lines.length &&
        !RegExp('^${'>' * size}(?: |\r?\$)').hasMatch(lines[i])) {
      right.write(lines[i++]);
    }
    if (i < lines.length &&
        left.toString() == region.left &&
        right.toString() == region.right)
      candidates.add(lines.sublist(start, i + 1).join());
  }
  return candidates.length == 1 ? candidates.single : null;
}

List<_MergeRegion> mergeRegions(String text, String marker) {
  final lines = exactLines(text), result = <_MergeRegion>[];
  final offsets = <int>[];
  var position = 0;
  for (final line in lines) {
    offsets.add(position);
    position += line.length;
  }
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimRight() != '${'<' * 32} ${marker}_LEFT') continue;
    final start = i, left = StringBuffer(), right = StringBuffer();
    i++;
    final leftStart = i < offsets.length ? offsets[i] : text.length;
    while (i < lines.length &&
        lines[i].trimRight() != '${'|' * 32} ${marker}_BASE') {
      left.write(lines[i++]);
    }
    while (i < lines.length && lines[i].trimRight() != '=' * 32) {
      i++;
    }
    i++;
    final rightStart = i < offsets.length ? offsets[i] : text.length;
    while (i < lines.length &&
        lines[i].trimRight() != '${'>' * 32} ${marker}_RIGHT') {
      right.write(lines[i++]);
    }
    if (i < lines.length)
      result.add(
        _MergeRegion(
          lines.sublist(start, i + 1).join(),
          left.toString(),
          right.toString(),
          leftStart,
          rightStart,
        ),
      );
  }
  return result;
}

Future<List<_MergeRegion>> _backgroundRegions(
  String left,
  String right,
  String preview,
  String marker,
) => Isolate.run(() => _alignedRegions(left, right, preview, marker));

List<_MergeRegion> _alignedRegions(
  String left,
  String right,
  String preview,
  String marker,
) {
  final regions = mergeRegions(preview, marker);
  List<int?> anchors(String source, List<int> requested) {
    try {
      final diff = computeTextDiff(source, preview);
      final result = <int?>[];
      var oldOffset = 0, newOffset = 0, index = 0;
      for (final edit in diff.edits) {
        if (edit.kind == TextEditKind.remove) {
          oldOffset += edit.text.length;
          continue;
        }
        while (index < requested.length &&
            requested[index] < newOffset + edit.text.length) {
          result.add(
            edit.kind == TextEditKind.equal
                ? oldOffset + requested[index] - newOffset
                : oldOffset,
          );
          index++;
        }
        newOffset += edit.text.length;
        if (edit.kind == TextEditKind.equal) oldOffset += edit.text.length;
      }
      while (result.length < requested.length) {
        result.add(source.length);
      }
      return result;
    } on GitException catch (failure) {
      if (failure.code != GitErrorCode.outputLimit) rethrow;
      return List<int?>.filled(requested.length, null);
    }
  }

  final leftAnchors = anchors(left, regions.map((r) => r.previewLeft).toList()),
      rightAnchors = anchors(
        right,
        regions.map((r) => r.previewRight).toList(),
      );
  return [
    for (var i = 0; i < regions.length; i++)
      _MergeRegion(
        regions[i].block,
        regions[i].left,
        regions[i].right,
        regions[i].previewLeft,
        regions[i].previewRight,
        leftOffset: leftAnchors[i],
        rightOffset: rightAnchors[i],
      ),
  ];
}

final class _ConflictResultController extends TextEditingController {
  List<_MergeRegion> regions = [];
  int activeRegion = 0;
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final ranges = <(int, int, bool)>[];
    for (var i = 0; i < regions.length; i++) {
      final block = matchingResultRegion(text, regions[i]);
      if (block == null) continue;
      final offset = text.indexOf(block);
      ranges.add((offset, offset + block.length, i == activeRegion));
    }
    final composing = value.composing;
    final showComposing =
        withComposing && composing.isValid && composing.end <= text.length;
    final boundaries = <int>{
      0,
      text.length,
      for (final range in ranges) ...[range.$1, range.$2],
      if (showComposing) ...[composing.start, composing.end],
    }.toList()..sort();
    final colors = Theme.of(context).colorScheme;
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < boundaries.length - 1; i++)
          TextSpan(
            text: text.substring(boundaries[i], boundaries[i + 1]),
            style: TextStyle(
              backgroundColor:
                  ranges.any(
                    (r) => r.$1 <= boundaries[i] && r.$2 > boundaries[i],
                  )
                  ? colors.tertiary.withValues(
                      alpha:
                          ranges.any(
                            (r) =>
                                r.$3 &&
                                r.$1 <= boundaries[i] &&
                                r.$2 > boundaries[i],
                          )
                          ? .24
                          : .12,
                    )
                  : null,
              decoration:
                  showComposing &&
                      composing.start <= boundaries[i] &&
                      composing.end > boundaries[i]
                  ? TextDecoration.underline
                  : null,
            ),
          ),
      ],
    );
  }
}
