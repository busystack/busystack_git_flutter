import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'diff_view.dart';
import 'host.dart';
import 'session.dart';
import 'text_encoding.dart';
import 'dismissal.dart';
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
  const GitConflictView({
    super.key,
    required this.session,
    required this.path,
    @visibleForTesting this.computeDiffs,
  });
  final Future<List<TextDiff>> Function(
    String left,
    String right,
    String draft,
  )?
  computeDiffs;
  final GitSession session;
  final RepoPath path;
  @override
  State<GitConflictView> createState() => _ConflictState();
}

final class _ConflictState extends GitDialogState<GitConflictView> {
  @override
  GitSession get session => _ownerSession;
  late final GitSession _ownerSession = widget.session;
  late final RepoPath _ownerPath = widget.path;
  bool _bindingChanged = false;
  final result = GitHighlightedTextController();
  final _geometry = [for (var i = 0; i < 3; i++) GitTextPaneGeometry()];
  _ConflictCorrespondence? _correspondence;
  List<_ResultConflict> _remaining = const [];
  Timer? _regionTimer;
  int _regionGeneration = 0, _activeRemaining = -1, _correspondenceRevision = 0;
  bool _calculatingRegions = false;
  GitException? _regionFailure;
  int? _leftAnchor, _rightAnchor;
  final _ignoredSuggestions = <(int, bool)>{};
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
  bool _newerDraftRetained = false;
  int _versionGeneration = 0, _draftRevision = 0;
  String _lastDraftText = '';
  bool get _busy => loading || _readingVersions || session.running;
  bool get _canEditText =>
      left != null &&
      right != null &&
      working != null &&
      [left!, right!, working!].every(
        (content) =>
            content.availability == ContentAvailability.absent ||
            content.availability == ContentAvailability.present &&
                content.text != null,
      );
  int _anchorRevision = 0;
  int? _resultAnchor;
  @override
  void initState() {
    super.initState();
    result.addListener(_resultChanged);
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(covariant GitConflictView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.session, _ownerSession) && widget.path == _ownerPath)
      return;
    // State and base-class subscriptions retain the originating worktree. A
    // host must guard disposal; replacing a widget cannot retarget its draft.
    _bindingChanged = true;
    _versionGeneration++;
    generation++;
    cancellation?.cancel();
    _readingVersions = false;
    _invalidateCorrespondence();
    _calculatingRegions = false;
    loading = false;
    error = const GitException(GitErrorCode.staleReview);
  }

  void _resultChanged() {
    if (_lastDraftText == result.text) return;
    _lastDraftText = result.text;
    _draftRevision++;
    _invalidateCorrespondence();
    _scheduleCorrespondence();
    if (mounted)
      setState(() {
        saved = false;
        _draftDirty = result.text != (working?.text ?? '');
      });
  }

  @override
  void dispose() {
    _versionGeneration++;
    _regionGeneration++;
    _regionTimer?.cancel();
    _leftTextController.dispose();
    _rightTextController.dispose();
    result.removeListener(_resultChanged);
    result.dispose();
    undo.dispose();
    resultFocus.dispose();
    super.dispose();
  }

  Future<void> refresh({
    bool replaceSavedDraft = false,
    bool preserveDraft = false,
  }) async {
    if (_bindingChanged) return;
    if (_draftDirty &&
        !replaceSavedDraft &&
        !preserveDraft &&
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
      await load(GitInspection(GitInspectionKind.conflict, path: _ownerPath));
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
            _ownerPath,
            ContentVersion(ContentKind.conflictStage, stage: stage),
            cancellation: token,
          ),
        session.client.content(
          session.repository,
          _ownerPath,
          const ContentVersion.working(),
          cancellation: token,
        ),
        session.client.content(
          session.repository,
          _ownerPath,
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
        final savedText = working!.text ?? '';
        if (!preserveDraft) {
          _lastDraftText = savedText;
          _draftRevision++;
          if (result.text != savedText) result.text = savedText;
        } else {
          _lastDraftText = result.text;
        }
        reviewedRegions.clear();
        _ignoredSuggestions.clear();
        _invalidateCorrespondence();
        saved = false;
        _draftDirty = result.text != savedText;
        if (!preserveDraft) _newerDraftRetained = false;
      });
      _scheduleCorrespondence(immediate: true);
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

  void _invalidateCorrespondence() {
    _regionTimer?.cancel();
    _regionGeneration++;
    _correspondence = null;
    _remaining = const [];
    _activeRemaining = -1;
    _regionFailure = null;
    result.setHighlights(const []);
  }

  void _scheduleCorrespondence({bool immediate = false}) {
    if (!mounted || !_canEditText || _bindingChanged) return;
    _regionTimer?.cancel();
    _calculatingRegions = true;
    if (immediate) {
      unawaited(_computeCorrespondence());
    } else {
      _regionTimer = Timer(
        const Duration(milliseconds: 80),
        () => unawaited(_computeCorrespondence()),
      );
    }
  }

  bool _ownsCorrespondence(_ConflictCorrespondence? review) =>
      mounted &&
      review != null &&
      identical(review, _correspondence) &&
      !_bindingChanged &&
      review.versions == _versionGeneration &&
      review.draft == _draftRevision &&
      review.request == _regionGeneration &&
      identical(review.leftContent, left) &&
      identical(review.rightContent, right) &&
      review.text == result.text &&
      reviewed?.token == session.snapshot?.token;

  Future<void> _computeCorrespondence() async {
    if (!mounted || _bindingChanged || left == null || right == null) return;
    final request = ++_regionGeneration,
        versions = _versionGeneration,
        draft = _draftRevision,
        text = result.text,
        leftContent = left!,
        rightContent = right!;
    final a = leftContent.text ?? '', b = rightContent.text ?? '';
    final sourceRegions = List<_MergeRegion>.unmodifiable(regions);
    bool current() =>
        mounted &&
        !_bindingChanged &&
        request == _regionGeneration &&
        versions == _versionGeneration &&
        draft == _draftRevision &&
        identical(leftContent, left) &&
        identical(rightContent, right) &&
        text == result.text;
    try {
      late _ConflictDisplay display;
      final injected = widget.computeDiffs;
      if (injected == null) {
        display = await _backgroundConflictDisplay(a, b, text, sourceRegions);
      } else {
        final diffs = await injected(a, b, text);
        if (!current()) return;
        display = await _backgroundConflictDisplay(
          a,
          b,
          text,
          sourceRegions,
          diffs: diffs,
        );
      }
      if (!current()) return;
      final review = _ConflictCorrespondence(
        request,
        versions,
        draft,
        leftContent,
        rightContent,
        text,
        display.left,
        display.right,
      );
      setState(() {
        _correspondence = review;
        _correspondenceRevision++;
        _remaining = display.remaining;
        if (!_remaining.any((r) => r.sourceRegion == activeRegion)) {
          activeRegion = _remaining.firstOrNull?.sourceRegion ?? -1;
        }
        _calculatingRegions = false;
      });
      _leftTextController.setHighlights(display.leftHighlights);
      _rightTextController.setHighlights(display.rightHighlights);
      result.setHighlights(display.resultHighlights);
    } on Object catch (failure) {
      if (!current()) return;
      setState(() {
        _calculatingRegions = false;
        _regionFailure = failure is GitException
            ? failure
            : GitException(
                GitErrorCode.commandFailed,
                diagnostic: sanitizeGitDiagnostic('$failure'),
              );
      });
    }
  }

  int? _mapOffset(
    _ConflictCorrespondence? review,
    int source,
    int target,
    int offset,
  ) {
    if (!_ownsCorrespondence(review)) return null;
    final resultOffset = source == 1
        ? offset
        : source == 0
        ? review!.left.forward(offset)
        : review!.right.forward(offset);
    return target == 1
        ? resultOffset
        : target == 0
        ? review!.left.reverse(resultOffset)
        : review!.right.reverse(resultOffset);
  }

  VoidCallback? _localAction(
    _ConflictCorrespondence review,
    _ResultConflict region, {
    bool? acceptLeft,
    bool? ignoreLeft,
  }) {
    final sourceIndex = region.sourceRegion;
    if (sourceIndex == null || _busy || !_ownsCorrespondence(review))
      return null;
    return () {
      if (!_ownsCorrespondence(review) ||
          _busy ||
          region.end > result.text.length ||
          result.text.substring(region.start, region.end) != region.block)
        return;
      if (acceptLeft != null) {
        final source = region.source!;
        _replaceResult(
          region.start,
          region.end,
          acceptLeft ? source.left : source.right,
        );
        setState(() {
          activeRegion = sourceIndex;
          reviewedRegions.add(sourceIndex);
        });
      } else {
        setState(() {
          _ignoredSuggestions.add((sourceIndex, ignoreLeft!));
          reviewedRegions.add(sourceIndex);
        });
      }
    };
  }

  List<GitTextPaneAction> _sourceActions(bool useLeft) {
    final review = _correspondence;
    if (!_ownsCorrespondence(review)) return const [];
    return [
      for (final region in _remaining)
        if (region.sourceRegion != null)
          ..._sourceRegionActions(review!, region, useLeft),
    ];
  }

  List<GitTextPaneAction> _sourceRegionActions(
    _ConflictCorrespondence review,
    _ResultConflict region,
    bool useLeft,
  ) {
    final source = region.source!;
    final start = useLeft ? source.leftOffset : source.rightOffset;
    final text = useLeft ? source.left : source.right;
    final sourceText = (useLeft ? left : right)?.text ?? '';
    if (start == null ||
        start < 0 ||
        start + text.length > sourceText.length ||
        sourceText.substring(start, start + text.length) != text)
      return const [];
    return [
      GitTextPaneAction(
        start: start,
        end: start + text.length,
        label: useLeft
            ? GitMessages.acceptLeftRegion
            : GitMessages.acceptRightRegion,
        glyph: useLeft ? GitGlyph.next : GitGlyph.previous,
        onInvoke: _localAction(review, region, acceptLeft: useLeft),
      ),
      GitTextPaneAction(
        start: start,
        end: start + text.length,
        label: useLeft
            ? GitMessages.ignoreLeftRegion
            : GitMessages.ignoreRightRegion,
        glyph: GitGlyph.close,
        onInvoke: _ignoredSuggestions.contains((region.sourceRegion!, useLeft))
            ? null
            : _localAction(review, region, ignoreLeft: useLeft),
      ),
    ];
  }

  List<GitTextPaneAction> _resultActions() {
    final review = _correspondence;
    if (!_ownsCorrespondence(review)) return const [];
    return [
      for (final region in _remaining)
        if (region.sourceRegion != null) ...[
          GitTextPaneAction(
            start: region.start,
            end: region.end,
            label: GitMessages.acceptLeftRegion,
            glyph: GitGlyph.next,
            onInvoke: _localAction(review!, region, acceptLeft: true),
          ),
          GitTextPaneAction(
            start: region.start,
            end: region.end,
            label: GitMessages.acceptRightRegion,
            glyph: GitGlyph.previous,
            onInvoke: _localAction(review, region, acceptLeft: false),
          ),
        ],
    ];
  }

  void _replaceResult(int start, int end, String replacement) {
    result.value = result.value.replaced(
      TextRange(start: start, end: end),
      replacement,
    );
    setState(() {
      saved = false;
      _draftDirty = true;
    });
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
    final stale =
        reviewed != null && session.snapshot?.token != reviewed!.token;
    final correspondence = _correspondence;
    final text = _canEditText;
    return GitDraftGuard(
      host: session.host,
      canDismiss: !_draftDirty && !_busy,
      isDismissible: () => !_draftDirty && !_busy,
      revisionChanges: result,
      revisionIdentity: () => (_draftRevision, _versionGeneration),
      confirmDiscard: _confirmDiscard,
      child: CallbackShortcuts(
        bindings: {
          if (text &&
              !_busy &&
              _ownsCorrespondence(_correspondence) &&
              _remaining.isNotEmpty) ...{
            const SingleActivator(LogicalKeyboardKey.f7): () => navigate(1),
            const SingleActivator(LogicalKeyboardKey.f7, shift: true): () =>
                navigate(-1),
          },
          if (text &&
              !_busy &&
              !stale &&
              activeRegion >= 0 &&
              regions.isNotEmpty) ...{
            const SingleActivator(
              LogicalKeyboardKey.arrowRight,
              control: true,
              alt: true,
            ): _regionAction(
              true,
            ),
            const SingleActivator(
              LogicalKeyboardKey.arrowLeft,
              control: true,
              alt: true,
            ): _regionAction(
              false,
            ),
          },
          if (_keepManualAction() case final keep?)
            const SingleActivator(
              LogicalKeyboardKey.keyK,
              control: true,
              alt: true,
            ): keep,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            states(refresh: () => unawaited(refresh())),
            if (stale)
              GitFailurePanel(
                error: const GitException(GitErrorCode.staleReview),
                onRefresh: () => unawaited(refresh()),
              ),
            if (_readingVersions && !loading)
              LinearProgressIndicator(
                semanticsLabel: gitString(
                  context,
                  GitMessages.loadingConflictVersions,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: session.host.spacing,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${session.repository.root} · ${_ownerPath.display}',
                  ),
                ),
                Text(_kindLabel()),
              ],
            ),
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
              if (_calculatingRegions)
                const GitLabel(GitMessages.updatingConflictRegions),
              if (_regionFailure != null)
                GitFailurePanel(
                  error: _regionFailure!,
                  onRefresh: () => unawaited(_computeCorrespondence()),
                ),
              if (_ownsCorrespondence(_correspondence))
                GitLabel(
                  GitMessages.remainingConflictMarkers,
                  values: {'count': _remaining.length},
                ),
              Wrap(
                spacing: session.host.spacing,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GitIconButton(
                    tooltip: gitString(
                      context,
                      GitMessages.previousConflictRegion,
                    ),
                    onPressed:
                        _busy ||
                            !_ownsCorrespondence(_correspondence) ||
                            _remaining.isEmpty
                        ? null
                        : () => navigate(-1),
                    icon: const GitIcon(GitGlyph.up),
                  ),
                  GitIconButton(
                    tooltip: gitString(context, GitMessages.nextConflictRegion),
                    onPressed:
                        _busy ||
                            !_ownsCorrespondence(_correspondence) ||
                            _remaining.isEmpty
                        ? null
                        : () => navigate(1),
                    icon: const GitIcon(GitGlyph.down),
                  ),
                  Text(
                    activeRegion < 0 || regions.isEmpty
                        ? gitString(context, GitMessages.manualResolution)
                        : gitString(
                            context,
                            GitMessages.regionArg0Arg1Arg2Reviewed,
                            values: {
                              'arg0': _ownsCorrespondence(_correspondence)
                                  ? _remaining.indexWhere(
                                          (r) => r.sourceRegion == activeRegion,
                                        ) +
                                        1
                                  : activeRegion + 1,
                              'arg1': _ownsCorrespondence(_correspondence)
                                  ? _remaining.length
                                  : regions.length,
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
                    onPressed:
                        _busy || stale || activeRegion < 0 || regions.isEmpty
                        ? null
                        : _regionAction(true),
                    child: const GitLabel(GitMessages.acceptLeftRegion),
                  ),
                  TextButton(
                    onPressed:
                        _busy || stale || activeRegion < 0 || regions.isEmpty
                        ? null
                        : _regionAction(false),
                    child: const GitLabel(GitMessages.acceptRightRegion),
                  ),
                  TextButton(
                    onPressed: _keepManualAction(),
                    child: const GitLabel(
                      GitMessages.keepManualResultForRegion,
                    ),
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
                            result.value = TextEditingValue(
                              text: preview!.text!,
                            );
                            setState(() {
                              saved = false;
                              _draftDirty = true;
                            });
                          },
                    child: const GitLabel(
                      GitMessages.applyNonConflictingChanges,
                    ),
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
                  geometry: _geometry,
                  correspondenceRevision: _correspondenceRevision,
                  mapOffset: (source, target, offset) =>
                      _mapOffset(correspondence, source, target, offset),
                  panes: [
                    (scroll) => GitTextPane(
                      label: _sourceLabel(leftSource: true),
                      controller: _leftTextController,
                      geometry: _geometry[0],
                      minimumActionColumns: 2,
                      regionActions: _sourceActions(true),
                      readOnly: true,
                      semanticLabel: GitMessages.readOnlyRevisionContent,
                      scrollController: scroll,
                      revealRevision: _anchorRevision,
                      revealOffset: _leftAnchor,
                    ),
                    (scroll) => resultPane(scroll),
                    (scroll) => GitTextPane(
                      label: _sourceLabel(leftSource: false),
                      controller: _rightTextController,
                      geometry: _geometry[2],
                      minimumActionColumns: 2,
                      regionActions: _sourceActions(false),
                      readOnly: true,
                      semanticLabel: GitMessages.readOnlyRevisionContent,
                      scrollController: scroll,
                      revealRevision: _anchorRevision,
                      revealOffset: _rightAnchor,
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
            if (_newerDraftRetained)
              const GitLabel(GitMessages.newerConflictDraftRetained),
            if (saved)
              const GitLabel(
                GitMessages.resultSavedToDiskTheIndexStillDeterminesWhetherThis,
              ),
            if (text)
              GitLabel(gitTextFormatLabel(result.text, context: context)),
            if (text)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: session.host.spacing,
                children: [
                  OutlinedButton(
                    onPressed:
                        _busy || stale || error != null || reviewed == null
                        ? null
                        : () => unawaited(save(false)),
                    child: const GitLabel(GitMessages.saveResultDraft),
                  ),
                  FilledButton(
                    onPressed:
                        _busy || stale || error != null || reviewed == null
                        ? null
                        : () => unawaited(save(true)),
                    child: const GitLabel(
                      GitMessages.applyResultAndStageResolution,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    if (_busy) return false;
    final revision = _draftRevision, versions = _versionGeneration;
    final approved = await gitConfirm(
      context,
      session,
      GitMessages.discardUnsavedConflictDraft,
      GitMessages.closingTheConflictEditorDiscardsOnlyItsDraft,
      action: GitMessages.discardConflictDraft,
    );
    return mounted &&
        approved &&
        revision == _draftRevision &&
        versions == _versionGeneration;
  }

  Widget resultPane(ScrollController scroll) => GitTextPane(
    label: gitString(context, GitMessages.resultEditableUTF8WorkingContent),
    semanticLabel: gitString(context, GitMessages.editableConflictResult),
    controller: result,
    geometry: _geometry[1],
    minimumActionColumns: 2,
    regionActions: _resultActions(),
    readOnly: _busy,
    undoController: undo,
    focusNode: resultFocus,
    scrollController: scroll,
    revealOffset: _resultAnchor,
    revealRevision: _anchorRevision,
  );
  Widget nonText() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GitLabel(GitMessages.textComparisonIsUnavailableForTheseContents),
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
        _ownerPath,
        const ContentVersion(ContentKind.conflictStage, stage: 1),
        ContentVersion(ContentKind.conflictStage, stage: stage),
      ),
    ),
    expanded: true,
  );
  void navigate(int delta) {
    final review = _correspondence;
    if (!_ownsCorrespondence(review) || _remaining.isEmpty) return;
    final next = _activeRemaining < 0
        ? (delta > 0 ? 0 : _remaining.length - 1)
        : (_activeRemaining + delta) % _remaining.length;
    final region = _remaining[next];
    setState(() {
      _activeRemaining = next;
      activeRegion = region.sourceRegion ?? -1;
      _resultAnchor = region.start;
      _leftAnchor = review!.left.reverse(region.start);
      _rightAnchor = review.right.reverse(region.start);
      _anchorRevision++;
    });
    result.selection = TextSelection(
      baseOffset: region.start,
      extentOffset: region.end,
    );
    resultFocus.requestFocus();
  }

  VoidCallback? _keepManualAction() {
    if (_busy || activeRegion < 0 || activeRegion >= regions.length)
      return null;
    final draft = _draftRevision,
        versions = _versionGeneration,
        index = activeRegion;
    return () {
      if (!mounted ||
          _bindingChanged ||
          _busy ||
          draft != _draftRevision ||
          versions != _versionGeneration ||
          index != activeRegion)
        return;
      setState(() => reviewedRegions.add(index));
    };
  }

  VoidCallback _regionAction(bool useLeft) {
    final current = _correspondence, active = activeRegion;
    final matches = _remaining
        .where((region) => region.sourceRegion == active)
        .toList();
    if (_ownsCorrespondence(current) && matches.length == 1) {
      final action = _localAction(
        current!,
        matches.single,
        acceptLeft: useLeft,
      );
      return () {
        if (active == activeRegion) action?.call();
      };
    }
    final revision = _draftRevision,
        generation = _versionGeneration,
        region = regions[activeRegion],
        index = activeRegion,
        owner = session,
        path = _ownerPath;
    return () {
      if (!mounted ||
          _bindingChanged ||
          _busy ||
          revision != _draftRevision ||
          generation != _versionGeneration ||
          !identical(owner, session) ||
          path != _ownerPath ||
          index != activeRegion ||
          !identical(regions[activeRegion], region) ||
          reviewed?.token != session.snapshot?.token)
        return;
      acceptRegion(useLeft, index);
    };
  }

  void acceptRegion(bool useLeft, int index) {
    // A fresh callback can run before debounced correspondence is available.
    // Match only exact current blocks and reject source spans claimed by any
    // other current block, including a copied member of a grouped conflict.
    // An individually unique marker string does not establish source ownership.
    final candidates = [
      for (final actual in _remainingResultRegions(result.text))
        (
          actual: actual,
          groups: _sourceGroups(actual, regions, left!.text!, right!.text!),
        ),
    ];
    final matches = <(_ResultConflict, _MergeRegion)>[];
    for (final candidate in candidates) {
      if (candidate.groups.length != 1) continue;
      final group = candidate.groups.single;
      if (index < group.first || index > group.last) continue;
      if (candidates.any(
        (other) =>
            !identical(other.actual, candidate.actual) &&
            other.groups.any(
              (claim) => claim.first <= group.last && group.first <= claim.last,
            ),
      ))
        continue;
      matches.add((candidate.actual, group.region));
    }
    if (matches.length != 1) {
      session.host.notify(
        GitMessages.theResultWasEditedKeepTheManualResultOrSelect,
      );
      return;
    }
    final (actual, source) = matches.single;
    _replaceResult(
      actual.start,
      actual.end,
      useLeft ? source.left : source.right,
    );
    setState(() {
      reviewedRegions.add(index);
      saved = false;
      _draftDirty = true;
    });
  }

  Future<void> acceptWhole(ConflictChoice choice) async {
    final draft = _draftRevision, versions = _versionGeneration;
    if (_bindingChanged || _busy) return;
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
              values: {'arg0': _ownerPath.display},
            ),
      action: GitMessages.applyEntireFileDecision,
    ))
      return;
    if (!mounted ||
        draft != _draftRevision ||
        versions != _versionGeneration ||
        _bindingChanged)
      return;
    await resolve(choice);
  }

  Future<void> save(bool stage) async {
    if (!_canEditText || _bindingChanged || _busy) return;
    final text = result.text,
        draft = _draftRevision,
        versions = _versionGeneration;
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
              'arg0': _ownerPath.display,
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
    if (result.text != text ||
        draft != _draftRevision ||
        versions != _versionGeneration ||
        _bindingChanged) {
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
    if (_bindingChanged || reviewed == null || working == null || data == null)
      return;
    final stages = data!['stages'] as Json;
    final draft = _draftRevision, versions = _versionGeneration;
    final outcome = await apply(
      ResolveConflict(
        _ownerPath,
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
    final newerDraft = draft != _draftRevision;
    if (stage) {
      if (newerDraft || versions != _versionGeneration || _bindingChanged) {
        setState(() {
          _newerDraftRetained = true;
          _draftDirty = true;
        });
      } else {
        gitCompleteSurface(context);
      }
    } else {
      await refresh(replaceSavedDraft: true, preserveDraft: true);
      if (mounted)
        setState(() {
          saved = result.text == working?.text;
          _newerDraftRetained = newerDraft || !saved;
        });
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
  for (var i = 0; i < regions.length; i++) {
    leftAnchors[i] = _sourceRegionOffset(left, leftAnchors[i], regions[i].left);
    rightAnchors[i] = _sourceRegionOffset(
      right,
      rightAnchors[i],
      regions[i].right,
    );
  }
  return [
    for (var i = 0; i < regions.length; i++)
      _MergeRegion(
        regions[i].block,
        _sourceRegionText(left, leftAnchors[i], regions[i].left),
        _sourceRegionText(right, rightAnchors[i], regions[i].right),
        regions[i].previewLeft,
        regions[i].previewRight,
        leftOffset: leftAnchors[i],
        rightOffset: rightAnchors[i],
      ),
  ];
}

// A Git marker delimiter needs a line break even when a source ends without
// one. Keep that representation separate from the exact bytes being accepted.
// Remove only one synthetic delimiter proven by this source's EOF identity.
// Git can use either CRLF or LF; an existing trailing CR remains source data.
const _markerDelimiters = ['\r\n', '\n'];

String _sourceRegionText(String source, int? start, String markerBody) {
  if (start != null && start >= 0 && !source.endsWith('\n')) {
    for (final delimiter in _markerDelimiters) {
      if (markerBody.endsWith(delimiter) &&
          start + markerBody.length - delimiter.length == source.length &&
          source.substring(start) ==
              markerBody.substring(0, markerBody.length - delimiter.length)) {
        return source.substring(start);
      }
    }
  }
  return markerBody;
}

int? _sourceRegionOffset(String source, int? proposed, String markerBody) {
  // A line diff represents a missing final LF as removal plus insertion, so
  // its insertion anchor may be source EOF. Recover only the exact suffix
  // ending there, with one proven marker delimiter removed.
  if (proposed == source.length && !source.endsWith('\n')) {
    for (final delimiter in _markerDelimiters) {
      if (!markerBody.endsWith(delimiter)) continue;
      final raw = markerBody.substring(0, markerBody.length - delimiter.length),
          start = source.length - markerBody.length + delimiter.length;
      if (start >= 0 && source.substring(start) == raw) return start;
    }
  }
  return proposed;
}

bool _sameMarkerBody(String source, int end, String raw, String markerBody) =>
    raw == markerBody ||
    end == source.length &&
        !source.endsWith('\n') &&
        _markerDelimiters.any((delimiter) => markerBody == '$raw$delimiter');

Future<_ConflictDisplay> _backgroundConflictDisplay(
  String left,
  String right,
  String result,
  List<_MergeRegion> sourceRegions, {
  List<TextDiff>? diffs,
}) => Isolate.run(
  () => _conflictDisplay(
    diffs ?? [computeTextDiff(left, result), computeTextDiff(right, result)],
    left,
    right,
    result,
    sourceRegions,
  ),
);

final class _ConflictDisplay {
  const _ConflictDisplay(
    this.left,
    this.right,
    this.remaining,
    this.leftHighlights,
    this.rightHighlights,
    this.resultHighlights,
  );
  final GitTextCorrespondence left, right;
  final List<_ResultConflict> remaining;
  final List<GitTextHighlight> leftHighlights,
      rightHighlights,
      resultHighlights;
}

_ConflictDisplay _conflictDisplay(
  List<TextDiff> diffs,
  String left,
  String right,
  String result,
  List<_MergeRegion> sourceRegions,
) {
  final leftMap = GitTextCorrespondence(diffs[0], left, result),
      rightMap = GitTextCorrespondence(diffs[1], right, result);
  final parsed = _remainingResultRegions(result);
  final remaining = _associateResultRegions(
    parsed,
    sourceRegions,
    left,
    right,
    leftMap,
    rightMap,
  );
  List<GitTextHighlight> conflicts(bool useLeft) => [
    for (final region in remaining)
      if (region.sourceRegion != null)
        ..._sourceConflictHighlight(
          region.source!,
          useLeft,
          useLeft ? left : right,
        ),
  ];
  return _ConflictDisplay(
    leftMap,
    rightMap,
    remaining,
    [..._diffHighlights(diffs[0], source: true), ...conflicts(true)],
    [..._diffHighlights(diffs[1], source: true), ...conflicts(false)],
    [
      ..._diffHighlights(diffs[0], source: false),
      ..._diffHighlights(diffs[1], source: false),
      for (final region in remaining)
        GitTextHighlight(region.start, region.end, GitHighlightKind.conflict),
    ],
  );
}

List<GitTextHighlight> _sourceConflictHighlight(
  _MergeRegion region,
  bool useLeft,
  String source,
) {
  final start = useLeft ? region.leftOffset : region.rightOffset,
      text = useLeft ? region.left : region.right;
  if (start == null ||
      start < 0 ||
      start + text.length > source.length ||
      source.substring(start, start + text.length) != text)
    return const [];
  return [
    GitTextHighlight(start, start + text.length, GitHighlightKind.conflict),
  ];
}

final class _ConflictCorrespondence {
  const _ConflictCorrespondence(
    this.request,
    this.versions,
    this.draft,
    this.leftContent,
    this.rightContent,
    this.text,
    this.left,
    this.right,
  );
  final int request, versions, draft;
  final GitContent leftContent, rightContent;
  final String text;
  final GitTextCorrespondence left, right;
}

final class _ResultConflict {
  const _ResultConflict(
    this.start,
    this.end,
    this.block,
    this.sourceRegion, {
    this.left = '',
    this.right = '',
    this.closed = true,
    this.source,
    this.sourceIndices = const [],
  });
  final int start, end;
  final String block;
  final int? sourceRegion;
  final String left, right;
  final bool closed;
  final _MergeRegion? source;
  final List<int> sourceIndices;
}

List<GitTextHighlight> _diffHighlights(TextDiff diff, {required bool source}) {
  final ranges = <GitTextHighlight>[];
  var a = 0, b = 0;
  for (final edit in diff.edits) {
    if (source && edit.kind == TextEditKind.remove)
      ranges.add(
        GitTextHighlight(a, a + edit.text.length, GitHighlightKind.unstaged),
      );
    if (!source && edit.kind == TextEditKind.add)
      ranges.add(
        GitTextHighlight(b, b + edit.text.length, GitHighlightKind.unstaged),
      );
    if (edit.kind != TextEditKind.add) a += edit.text.length;
    if (edit.kind != TextEditKind.remove) b += edit.text.length;
  }
  return ranges;
}

List<_ResultConflict> _remainingResultRegions(String text) {
  final lines = exactLines(text), offsets = <int>[];
  var offset = 0;
  for (final line in lines) {
    offsets.add(offset);
    offset += line.length;
  }
  final result = <_ResultConflict>[];
  for (var start = 0; start < lines.length; start++) {
    final opening = RegExp(r'^(<{7,})(?: |\r?$)').firstMatch(lines[start]);
    if (opening == null) continue;
    final size = opening[1]!.length,
        left = StringBuffer(),
        right = StringBuffer();
    var i = start + 1;
    while (i < lines.length &&
        !lines[i].startsWith('|' * size) &&
        lines[i].trimRight() != '=' * size)
      left.write(lines[i++]);
    if (i < lines.length && lines[i].startsWith('|' * size))
      while (i < lines.length && lines[i].trimRight() != '=' * size) i++;
    if (i < lines.length) i++;
    while (i < lines.length &&
        !RegExp('^${'>' * size}(?: |\r?\$)').hasMatch(lines[i]))
      right.write(lines[i++]);
    final end = i < lines.length ? offsets[i] + lines[i].length : text.length;
    result.add(
      _ResultConflict(
        offsets[start],
        end,
        text.substring(offsets[start], end),
        null,
        left: left.toString(),
        right: right.toString(),
        closed: i < lines.length,
      ),
    );
    start = i;
  }
  return result;
}

List<_ResultConflict> _associateResultRegions(
  List<_ResultConflict> parsed,
  List<_MergeRegion> sources,
  String left,
  String right,
  GitTextCorrespondence leftMap,
  GitTextCorrespondence rightMap,
) {
  final result = <_ResultConflict>[];
  for (final region in parsed) {
    final groups = _sourceGroups(region, sources, left, right);
    final repeats = parsed
        .where(
          (other) => other.left == region.left && other.right == region.right,
        )
        .length;
    ({int first, int last, _MergeRegion region})? chosen;
    if (groups.length == 1 && repeats == 1) {
      chosen = groups.single;
    } else if (repeats <= groups.length) {
      final candidates = <({int first, int last, _MergeRegion region})>[];
      for (final group in groups) {
        final mappedA = leftMap.forward(group.region.leftOffset!),
            mappedB = rightMap.forward(group.region.rightOffset!);
        if (mappedA >= region.start &&
            mappedA < region.end &&
            mappedB >= region.start &&
            mappedB < region.end)
          candidates.add(group);
      }
      if (candidates.length == 1) chosen = candidates.single;
    }
    result.add(
      _ResultConflict(
        region.start,
        region.end,
        region.block,
        chosen?.first,
        left: region.left,
        right: region.right,
        closed: region.closed,
        source: chosen?.region,
        sourceIndices: chosen == null
            ? const []
            : [for (var i = chosen.first; i <= chosen.last; i++) i],
      ),
    );
  }
  return [
    for (final region in result)
      _ResultConflict(
        region.start,
        region.end,
        region.block,
        region.sourceRegion != null &&
                !result.any(
                  (other) =>
                      !identical(other, region) &&
                      other.sourceIndices.any(region.sourceIndices.contains),
                )
            ? region.sourceRegion
            : null,
        left: region.left,
        right: region.right,
        closed: region.closed,
        source: region.source,
        sourceIndices: region.sourceIndices,
      ),
  ];
}

// Git's saved merge markers can combine neighboring preview regions. Associate
// that actual block with exact contiguous spans from both immutable sources;
// this changes neither the saved result nor Git's merge decisions. Unknown or
// edited/ambiguous blocks remain manual, and overlapping source ownership is
// rejected above rather than selecting the first matching copy.
List<({int first, int last, _MergeRegion region})> _sourceGroups(
  _ResultConflict actual,
  List<_MergeRegion> sources,
  String left,
  String right,
) {
  if (!actual.closed) return const [];
  final groups = <({int first, int last, _MergeRegion region})>[];
  for (var first = 0; first < sources.length; first++) {
    final a = sources[first].leftOffset, b = sources[first].rightOffset;
    if (a == null || b == null || a < 0 || b < 0) continue;
    var previousA = a, previousB = b;
    for (var last = first; last < sources.length; last++) {
      final region = sources[last],
          startA = region.leftOffset,
          startB = region.rightOffset;
      if (startA == null ||
          startB == null ||
          startA < previousA ||
          startB < previousB)
        break;
      final endA = startA + region.left.length,
          endB = startB + region.right.length;
      if (endA > left.length ||
          endB > right.length ||
          left.substring(startA, endA) != region.left ||
          right.substring(startB, endB) != region.right)
        break;
      previousA = endA;
      previousB = endB;
      if (endA - a > actual.left.length || endB - b > actual.right.length)
        break;
      final rawLeft = left.substring(a, endA),
          rawRight = right.substring(b, endB);
      if (!_sameMarkerBody(left, endA, rawLeft, actual.left) ||
          !_sameMarkerBody(right, endB, rawRight, actual.right))
        continue;
      groups.add((
        first: first,
        last: last,
        region: _MergeRegion(
          actual.block,
          rawLeft,
          rawRight,
          sources[first].previewLeft,
          sources[first].previewRight,
          leftOffset: a,
          rightOffset: b,
        ),
      ));
    }
  }
  return groups;
}
