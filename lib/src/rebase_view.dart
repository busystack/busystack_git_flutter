import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'host.dart';
import 'network_views.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'diff_view.dart';
import 'reference_picker.dart';

final class GitRebaseView extends StatefulWidget {
  const GitRebaseView({super.key, required this.session, this.boundary});
  final GitSession session;
  final GitOid? boundary;
  @override
  State<GitRebaseView> createState() => _RebaseState();
}

final class _RebaseState extends GitDialogState<GitRebaseView> {
  @override
  GitSession get session => _session;
  late final GitSession _session;
  GitRevisionTarget? boundary, onto;
  GitSnapshot? _reviewedState;
  int _targetGeneration = 0;
  bool _defaultTargetRequested = false;
  bool root = false, preserve = false, autosquash = false;
  List<RebaseStep> steps = [], original = [];
  Map<String, Json> metadata = {};
  GitCommit? selectedCommit;
  GitException? _selectionError;
  int selected = -1;
  int _planGeneration = 0, _selectionGeneration = 0, _messageGeneration = 0;
  GitCancellation? _selectionCancellation;
  @override
  void initState() {
    _session = widget.session;
    super.initState();
    if (widget.boundary case final oid?)
      boundary = GitRevisionTarget(oid, oid.abbreviated);
    _reviewedState = session.snapshot;
    unawaited(_chooseDefaultBoundary());
  }

  Future<void> _chooseDefaultBoundary() async {
    final upstream = session.snapshot?.upstream;
    if (_defaultTargetRequested ||
        upstream == null ||
        boundary != null ||
        root ||
        data != null)
      return;
    _defaultTargetRequested = true;
    final current = _targetGeneration;
    try {
      final refs = await session.client.references(session.repository);
      if (!mounted ||
          current != _targetGeneration ||
          boundary != null ||
          root ||
          data != null)
        return;
      final canonical = refs.where((ref) => ref.current).firstOrNull?.upstream;
      final candidates = refs
          .where(
            (ref) =>
                !ref.name.startsWith('refs/tags/') &&
                (canonical != null
                    ? ref.name == canonical
                    : ref.name == upstream || ref.shortName == upstream),
          )
          .toList();
      if (candidates.length != 1) return;
      final target = candidates.single;
      setState(
        () => boundary = GitRevisionTarget(
          target.oid,
          target.shortName,
          reference: target.name,
          referenceTip: target.oid,
        ),
      );
    } on GitException catch (failure) {
      if (mounted && current == _targetGeneration)
        setState(() => error = failure);
    }
  }

  @override
  void dispose() {
    _planGeneration++;
    _selectionGeneration++;
    _messageGeneration++;
    _selectionCancellation?.cancel();
    _targetGeneration++;
    super.dispose();
  }

  @override
  void didUpdateWidget(GitRebaseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != session) {
      invalidate();
      setState(() => error = const GitException(GitErrorCode.staleReview));
      return;
    }
    if (oldWidget.boundary != widget.boundary) {
      final oid = widget.boundary;
      boundary = oid == null ? null : GitRevisionTarget(oid, oid.abbreviated);
      invalidate();
    }
  }

  VoidCallback? planAction(VoidCallback action) {
    if (widget.session != session || loading || data == null || session.running)
      return null;
    final reviewedGeneration = _planGeneration;
    return () {
      if (!mounted ||
          loading ||
          data == null ||
          reviewedGeneration != _planGeneration)
        return;
      action();
    };
  }

  void changeAction(
    GitOid commit,
    int reviewedGeneration,
    RebaseAction? action,
  ) {
    if (!mounted ||
        loading ||
        data == null ||
        reviewedGeneration != _planGeneration ||
        action == null)
      return;
    final index = steps.indexWhere((step) => step.commit == commit);
    if (index < 0) return;
    setState(() {
      _messageGeneration++;
      steps[index] = RebaseStep(action, commit);
    });
  }

  @override
  void onSessionChanged() {
    final state = session.snapshot, before = _reviewedState;
    _reviewedState = state;
    if (state != null &&
        before != null &&
        !session.running &&
        (state.head != before.head ||
            state.indexToken != before.indexToken ||
            state.token != before.token ||
            state.branch != before.branch ||
            state.operation.kind != before.operation.kind ||
            state.operation.editStop != before.operation.editStop ||
            state.operation.unmerged != before.operation.unmerged)) {
      _targetGeneration++;
      invalidate();
      setState(() => error = const GitException(GitErrorCode.staleReview));
    }
    unawaited(_chooseDefaultBoundary());
  }

  Future<void> chooseTarget({required bool newBase}) async {
    if (widget.session != session) return;
    final current = ++_targetGeneration;
    final target = await gitChooseRevision(
      context,
      session,
      newBase ? GitMessages.chooseNewBase : GitMessages.chooseUpstreamBoundary,
    );
    if (!mounted || current != _targetGeneration || target == null) return;
    if (newBase) {
      onto = target;
    } else {
      boundary = target;
    }
    invalidate();
  }

  Future<bool> targetsCurrent() async {
    final targets = [
      if (!root && boundary != null) boundary!,
      if (onto != null) onto!,
    ];
    if (!targets.any((target) => target.reference != null)) return true;
    final refs = await session.client.references(session.repository);
    return targets.every(
      (target) =>
          target.reference == null ||
          refs.any(
            (ref) =>
                ref.name == target.reference && ref.oid == target.referenceTip,
          ),
    );
  }

  Widget targetControl({required bool newBase}) {
    final target = newBase ? onto : boundary;
    final title = newBase
        ? GitMessages.newBase
        : GitMessages.upstreamBoundaryExcluded;
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GitLabel(title),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: !newBase && root
                      ? null
                      : () => unawaited(chooseTarget(newBase: newBase)),
                  icon: const GitIcon(GitGlyph.branch),
                  label: target == null
                      ? GitLabel(
                          newBase
                              ? gitString(
                                  context,
                                  GitMessages.sameAsUpstreamBoundary,
                                )
                              : gitString(
                                  context,
                                  GitMessages.chooseBranchTagOrCommit,
                                ),
                        )
                      : Text(
                          '${target.label} · ${target.oid.abbreviated}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
              if (newBase && target != null)
                GitIconButton(
                  tooltip: gitString(context, GitMessages.useUpstreamAsNewBase),
                  onPressed: () {
                    _targetGeneration++;
                    onto = null;
                    invalidate();
                  },
                  icon: const GitIcon(GitGlyph.close),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void invalidate() => setState(() {
    _targetGeneration++;
    _planGeneration++;
    _selectionGeneration++;
    _messageGeneration++;
    generation++;
    cancellation?.cancel();
    _selectionCancellation?.cancel();
    loading = false;
    data = null;
    steps = [];
    original = [];
    metadata = {};
    selectedCommit = null;
    _selectionError = null;
    selected = -1;
    error = null;
  });
  Future<void> prepare() async {
    if (widget.session != session) return;
    invalidate();
    final planGeneration = _planGeneration;
    try {
      if (!root && boundary == null) return;
      if (!await targetsCurrent()) {
        if (mounted && planGeneration == _planGeneration)
          setState(() => error = const GitException(GitErrorCode.staleReview));
        return;
      }
      if (!mounted || planGeneration != _planGeneration) return;
      await load(
        GitInspection(
          GitInspectionKind.rebasePlan,
          revision: root ? null : boundary?.oid,
          otherRevision: onto?.oid,
          root: root,
          preserveMerges: preserve,
          autosquash: autosquash,
        ),
      );
      if (!mounted ||
          planGeneration != _planGeneration ||
          data == null ||
          error != null)
        return;
      final values = (data!['steps'] as List).cast<Json>();
      setState(() {
        metadata = {for (final row in values) row['commit'] as String: row};
        steps = [
          for (final row in values)
            RebaseStep(
              RebaseAction.values.byName(row['action'] as String),
              GitOid(row['commit'] as String),
            ),
        ];
        original = List.from(steps);
        selected = -1;
      });
      await select(0);
    } on FormatException {
      if (!mounted || planGeneration != _planGeneration) return;
      setState(
        () => error = const GitException(
          GitErrorCode.invalidRequest,
          diagnostic: GitMessages.chooseAValidBranchTagOrCommitFromLog,
        ),
      );
    } on GitException catch (failure) {
      if (mounted && planGeneration == _planGeneration)
        setState(() => error = failure);
    }
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= steps.length || data == null) return;
    final planGeneration = _planGeneration;
    final selectionGeneration = ++_selectionGeneration;
    _selectionCancellation?.cancel();
    final token = _selectionCancellation = GitCancellation();
    final oid = steps[index].commit;
    bool current() =>
        mounted &&
        planGeneration == _planGeneration &&
        selectionGeneration == _selectionGeneration &&
        data != null &&
        selected >= 0 &&
        selected < steps.length &&
        steps[selected].commit == oid;
    setState(() {
      selected = index;
      selectedCommit = null;
      if (identical(error, _selectionError)) error = null;
      _selectionError = null;
    });
    try {
      final page = await session.client.history(
        session.repository,
        filter: HistoryFilter(reference: oid.value),
        limit: 1,
        cancellation: token,
      );
      if (!current()) return;
      if (page.commits.isEmpty)
        throw const GitException(GitErrorCode.missingContent);
      if (page.commits.first.oid != oid)
        throw const GitException(GitErrorCode.staleReview);
      setState(() => selectedCommit = page.commits.first);
    } on GitException catch (failure) {
      if (current()) setState(() => error = _selectionError = failure);
    }
  }

  String? get invalid {
    var target = false;
    int? previousBlock;
    for (final step in steps) {
      if (preserve) {
        final block = metadata[step.commit.value]?['block'] as int?;
        if (block != previousBlock) target = false;
        previousBlock = block;
      }
      if (step.action == RebaseAction.drop) continue;
      if (!target &&
          {RebaseAction.squash, RebaseAction.fixup}.contains(step.action))
        return GitMessages.theFirstRetainedCommitInABranchBlockCannotSquash;
      target = true;
    }
    return null;
  }

  void move(int delta) {
    final next = selected + delta;
    if (!canMove(delta)) return;
    setState(() {
      _messageGeneration++;
      final step = steps.removeAt(selected);
      steps.insert(next, step);
      selected = next;
    });
  }

  bool canMove(int delta) {
    final next = selected + delta;
    return selected >= 0 &&
        selected < steps.length &&
        next >= 0 &&
        next < steps.length &&
        (!preserve ||
            metadata[steps[selected].commit.value]?['block'] ==
                metadata[steps[next].commit.value]?['block']);
  }

  Future<void> previewMessages() async {
    final planGeneration = _planGeneration,
        messageGeneration = ++_messageGeneration;
    final reviewedMetadata = Map<String, Json>.from(metadata);
    final reviewedPreserve = preserve;
    bool current() =>
        mounted &&
        planGeneration == _planGeneration &&
        messageGeneration == _messageGeneration &&
        data != null;
    final retained = steps.where((s) => s.action != RebaseAction.drop).toList(),
        messages = <GitOid, String>{};
    for (final step in retained) {
      HistoryPage? page;
      try {
        page = await session.client.history(
          session.repository,
          filter: HistoryFilter(reference: step.commit.value),
          limit: 1,
        );
      } on GitException catch (failure) {
        if (current()) setState(() => error = failure);
        return;
      }
      if (!current()) return;
      if (page.commits.isEmpty) return;
      messages[step.commit] = page.commits.first.message;
    }
    final groups = <String>[];
    int? previousBlock;
    for (final step in retained) {
      final message = messages[step.commit]!,
          modifier =
              reviewedMetadata[step.commit.value]?['modifier'] as String? ?? '';
      final block = reviewedMetadata[step.commit.value]?['block'] as int?;
      final sameBlock = !reviewedPreserve || block == previousBlock;
      if (step.action == RebaseAction.squash &&
          groups.isNotEmpty &&
          sameBlock) {
        groups[groups.length - 1] += '\n\n$message';
      } else if (step.action == RebaseAction.fixup &&
          groups.isNotEmpty &&
          sameBlock) {
        if (modifier == '-C' || modifier == '-c')
          groups[groups.length - 1] = message;
      } else {
        groups.add(
          '${preserve ? gitString(context, GitMessages.branchBlockArg0, values: {'arg0': block}) : ''}${step.action == RebaseAction.reword ? gitString(context, GitMessages.rewordWillRequestANewMessage) : ''}$message',
        );
      }
      previousBlock = block;
    }
    if (current())
      await session.host.present<void>(
        context,
        GitMessages.plannedCommitMessages,
        GitTextPane(
          label: gitString(
            context,
            GitMessages
                .originalCombinedMessagePreviewGitRequestsTheFinalRewordSquash,
          ),
          text: [
            for (var i = 0; i < groups.length; i++)
              gitString(
                context,
                GitMessages.resultArg0Arg1,
                values: {'arg0': i + 1, 'arg1': groups[i]},
              ),
          ].join('\n\n────────────────\n\n'),
        ),
        expanded: true,
      );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: bounds.maxHeight * .42),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                states(refresh: () => unawaited(prepare())),
                GitLabel(
                  GitMessages.currentBranchBranch,
                  values: {
                    'branch':
                        session.snapshot?.branch ??
                        gitString(context, GitMessages.detachedHEAD2),
                  },
                ),
                const GitLabel(
                  GitMessages
                      .rebaseRewritesCommitIdentitiesRemoteTrackingInformationCannotProveHistory,
                ),
                Wrap(
                  spacing: session.host.spacing,
                  runSpacing: session.host.spacing,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    targetControl(newBase: false),
                    targetControl(newBase: true),
                    SizedBox(
                      width: 200,
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const GitLabel(GitMessages.includeRootCommits),
                        value: root,
                        onChanged: (v) {
                          root = v!;
                          invalidate();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: DropdownButtonFormField<bool>(
                        initialValue: preserve,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: gitString(
                            context,
                            GitMessages.mergeCommits,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: false,
                            child: GitLabel(GitMessages.flattenHistory),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: GitLabel(
                              GitMessages.preserveBranchStructure,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          preserve = v!;
                          invalidate();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: autosquash,
                        title: const GitLabel(GitMessages.autosquash),
                        onChanged: (v) {
                          autosquash = v!;
                          invalidate();
                        },
                      ),
                    ),
                    OutlinedButton(
                      onPressed: loading || (!root && boundary == null)
                          ? null
                          : () => unawaited(prepare()),
                      child: const GitLabel(GitMessages.prepareGitPlan),
                    ),
                  ],
                ),
                if (data != null)
                  GitLabel(
                    GitMessages.commitsToReplayCount,
                    values: {
                      'count': steps
                          .where((step) => step.action != RebaseAction.drop)
                          .length,
                    },
                  ),
                if (data != null)
                  GitLabel(
                    root
                        ? GitMessages
                              .includesAllRootCommitsReachableFromThisBranch
                        : GitMessages
                              .commitsAfterBoundaryWillBeReplayedOntoBaseTheBoundary,
                    values: {
                      'boundary': boundary?.label ?? '',
                      'base':
                          (onto ?? boundary)?.label ??
                          gitString(context, GitMessages.root),
                    },
                  ),
                if (preserve && data != null)
                  ExpansionTile(
                    title: const GitLabel(
                      GitMessages.gitBranchLabelResetMergeStructure,
                    ),
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: SelectableText(data!['todo'] as String),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: data == null
              ? const Center(
                  child: GitLabel(
                    GitMessages
                        .chooseAnExplicitOldBoundaryOrRootModeThenPrepare,
                  ),
                )
              : GitSplitter(
                  initial: .56,
                  minimum: 260,
                  first: Focus(
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          HardwareKeyboard.instance.isAltPressed &&
                          {
                            LogicalKeyboardKey.arrowUp,
                            LogicalKeyboardKey.arrowDown,
                          }.contains(event.logicalKey)) {
                        move(
                          event.logicalKey == LogicalKeyboardKey.arrowUp
                              ? -1
                              : 1,
                        );
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Column(
                      children: [
                        Wrap(
                          children: [
                            TextButton.icon(
                              onPressed: canMove(-1) ? () => move(-1) : null,
                              icon: const GitIcon(GitGlyph.up),
                              label: const GitLabel(GitMessages.moveUp),
                            ),
                            TextButton.icon(
                              onPressed: canMove(1) ? () => move(1) : null,
                              icon: const GitIcon(GitGlyph.down),
                              label: const GitLabel(GitMessages.moveDown),
                            ),
                            TextButton(
                              onPressed: planAction(() {
                                setState(() {
                                  _messageGeneration++;
                                  steps = List.from(original);
                                  selected = 0;
                                });
                                unawaited(select(0));
                              }),
                              child: const GitLabel(GitMessages.resetPlan),
                            ),
                          ],
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: steps.length,
                            itemBuilder: (context, i) {
                              final step = steps[i],
                                  reviewedGeneration = _planGeneration;
                              return Semantics(
                                selected: i == selected,
                                label: gitString(
                                  context,
                                  GitMessages.rebaseStepSemantics,
                                  values: {
                                    'position': i + 1,
                                    'action': gitEnumLabel(
                                      context,
                                      step.action,
                                    ),
                                    'subject':
                                        metadata[step
                                            .commit
                                            .value]?['subject'] ??
                                        step.commit.abbreviated,
                                  },
                                ),
                                child: ListTile(
                                  dense: true,
                                  selected: i == selected,
                                  leading: Text('${i + 1}'),
                                  title: Text(
                                    metadata[step.commit.value]?['subject']
                                            as String? ??
                                        step.commit.abbreviated,
                                    style: step.action == RebaseAction.drop
                                        ? const TextStyle(
                                            decoration:
                                                TextDecoration.lineThrough,
                                          )
                                        : null,
                                  ),
                                  subtitle: Text(
                                    '${step.commit.abbreviated}${preserve ? gitString(context, GitMessages.branchBlockArg02, values: {'arg0': metadata[step.commit.value]?["block"]}) : ''}${metadata[step.commit.value]?['modifier'] == '' ? '' : ' · ${metadata[step.commit.value]?['modifier']}'}',
                                  ),
                                  onTap: planAction(
                                    () => unawaited(
                                      select(
                                        steps.indexWhere(
                                          (entry) =>
                                              entry.commit == step.commit,
                                        ),
                                      ),
                                    ),
                                  ),
                                  trailing: DropdownButton<RebaseAction>(
                                    value: step.action,
                                    underline: const SizedBox.shrink(),
                                    items: [
                                      for (final action in RebaseAction.values)
                                        DropdownMenuItem(
                                          value: action,
                                          child: Text(
                                            gitEnumLabel(context, action),
                                          ),
                                        ),
                                    ],
                                    onChanged: loading
                                        ? null
                                        : (action) => changeAction(
                                            step.commit,
                                            reviewedGeneration,
                                            action,
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  second: selectedCommit == null
                      ? const Center(
                          child: GitLabel(
                            GitMessages.selectACommitForDetailsAndChangedFiles,
                          ),
                        )
                      : GitCommitFiles(
                          session: session,
                          commit: selectedCommit!,
                        ),
                ),
        ),
        if (invalid != null)
          Text(
            gitString(context, invalid!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (steps.any(
          (e) =>
              e.action == RebaseAction.squash || e.action == RebaseAction.fixup,
        ))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: loading || invalid != null
                  ? null
                  : () => unawaited(previewMessages()),
              child: const GitLabel(GitMessages.previewCombinedCommitMessages),
            ),
          ),
        const GitLabel(
          GitMessages.altMovesTheSelectedCommitUnrelatedBranchReferencesWillNot,
        ),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const GitLabel(GitMessages.cancelPlan),
            ),
            FilledButton(
              onPressed: invalid != null
                  ? null
                  : planAction(() async {
                      final plan = data!;
                      final planGeneration = _planGeneration,
                          messageGeneration = _messageGeneration;
                      final reviewedSteps = List<RebaseStep>.of(steps);
                      final reviewedRoot = root,
                          reviewedPreserve = preserve,
                          reviewedAutosquash = autosquash;
                      final reviewedBoundary = boundary?.oid,
                          reviewedOnto = onto?.oid;
                      if (!await gitConfirm(
                        context,
                        session,
                        GitMessages.startReviewedRebase,
                        gitString(
                          context,
                          GitMessages
                              .rewriteArg0PlannedCommitsOnArg1DroppedCommitsRemainVisibly,
                          values: {
                            'arg0': steps.length,
                            'arg1':
                                session.snapshot?.branch ??
                                gitString(context, GitMessages.detachedHEAD),
                          },
                        ),
                        action: GitMessages.startRebase,
                      ))
                        return;
                      if (!mounted ||
                          planGeneration != _planGeneration ||
                          messageGeneration != _messageGeneration)
                        return;
                      bool targetsValid;
                      try {
                        targetsValid = await targetsCurrent();
                      } on GitException catch (failure) {
                        if (mounted && planGeneration == _planGeneration)
                          setState(() => error = failure);
                        return;
                      }
                      if (!targetsValid) {
                        if (mounted && planGeneration == _planGeneration) {
                          invalidate();
                          setState(
                            () => error = const GitException(
                              GitErrorCode.staleReview,
                            ),
                          );
                        }
                        return;
                      }
                      if (!mounted ||
                          planGeneration != _planGeneration ||
                          messageGeneration != _messageGeneration)
                        return;
                      final result = await apply(
                        RebaseCommits(
                          expectedHead: GitOid(plan['head'] as String),
                          expectedIndex: plan['index'] as String,
                          boundary: reviewedRoot ? null : reviewedBoundary,
                          onto: reviewedOnto,
                          root: reviewedRoot,
                          preserveMerges: reviewedPreserve,
                          autosquash: reviewedAutosquash,
                          interactive: true,
                          planToken: plan['token'] as String,
                          steps: reviewedSteps,
                        ),
                      );
                      if (mounted &&
                          result != null &&
                          (result.completed ||
                              result.phase == GitOperationPhase.stopped))
                        gitCompleteSurface(context);
                    }),
              child: const GitLabel(GitMessages.startRebase),
            ),
          ],
        ),
      ],
    ),
  );
}
