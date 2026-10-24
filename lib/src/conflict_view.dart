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
              ? 'No continuing Git operation'
              : '${operation.kind.name}${operation.editStop ? ' · stopped for editing/amend' : ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (operation?.kind == GitOperationKind.unmerged)
          const GitLabel(
            'These are unmerged index entries, possibly from a stash application. Git has no stash continue or abort command.',
          ),
        if (operation?.editStop == true)
          const GitLabel(
            'Edit the working files, stage and amend the current commit, then continue this rebase.',
          ),
        Expanded(
          child: ListView(
            children: [
              for (final change
                  in state?.changes.where((e) => e.conflicted) ?? <GitChange>[])
                ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(change.path.display),
                  subtitle: Text(
                    '${change.index}${change.worktree} · unmerged stages ${change.conflictStages.keys.join(', ')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      GitWorkflowUi(context, session).conflict(change.path),
                ),
              if (state != null && !state.operation.unmerged)
                const ListTile(
                  title: GitLabel('The index has no unresolved entries.'),
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
                          'Keep the current commit as an empty commit',
                          initial: page.commits.first.message,
                          multiline: true,
                          explanation:
                              'The real index has no staged changes. Create an explicit empty commit, then continue the sequencer if it remains active.',
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
                child: const GitLabel('Keep empty commit…'),
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
                              '${action.name} ${operation!.kind.name}?',
                              action == GitContinuation.abort
                                  ? 'Git will try to return to the operation’s starting point. Pre-existing unstaged, untracked and unsaved contents are not guaranteed to be recovered.'
                                  : action == GitContinuation.skip
                                  ? 'Skip the current commit and continue with the next planned commit.'
                                  : 'Forget this operation’s bookkeeping while retaining the current files and index.',
                              action: action.name,
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
                      ? 'Continue ${operation!.kind.name}'
                      : '${action.name}…',
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
  final undo = UndoHistoryController();
  final resultFocus = FocusNode();
  GitContent? left, right, base, working, preview;
  GitSnapshot? reviewed;
  final reviewedRegions = <int>{};
  List<_MergeRegion> regions = [];
  int activeRegion = 0;
  bool saved = false, _draftDirty = false;
  int _anchorRevision = 0;
  int? _resultAnchor;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void dispose() {
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
          'Reload conflict versions?',
          'Replace the unsaved Result draft with the current working file. Saved working content is retained.',
          action: 'Replace draft and reload',
        ))
      return;
    if (!mounted) return;
    await load(GitInspection(GitInspectionKind.conflict, path: widget.path));
    if (!mounted || data == null || error != null) return;
    try {
      final state = await session.readStatus();
      final versions = await Future.wait([
        for (final stage in [2, 1, 3])
          session.client.content(
            session.repository,
            widget.path,
            ContentVersion(ContentKind.conflictStage, stage: stage),
          ),
        session.client.content(
          session.repository,
          widget.path,
          const ContentVersion.working(),
        ),
        session.client.content(
          session.repository,
          widget.path,
          const ContentVersion(ContentKind.mergePreview),
        ),
      ]);
      final after = await session.readStatus();
      final stages = data!['stages'] as Json;
      if (state.token != after.token ||
          (data!['working'] as Json)['token'] != versions[3].token ||
          data!['leftRevision'] != state.operation.head?.value ||
          data!['rightRevision'] != state.operation.other?.value) {
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
          marker = data!['marker'] as String;
      final alignedRegions = await _backgroundRegions(
        leftText,
        rightText,
        previewText,
        marker,
      );
      if (!mounted) return;
      setState(() {
        left = versions[0];
        base = versions[1];
        right = versions[2];
        working = versions[3];
        preview = versions[4];
        reviewed = state;
        regions = alignedRegions;
        activeRegion = 0;
        result.regions = regions;
        result.activeRegion = 0;
        result.text = working!.text ?? '';
        reviewedRegions.clear();
        saved = false;
        _draftDirty = false;
      });
    } on GitException catch (failure) {
      if (mounted) setState(() => error = failure);
    }
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
        Text('${widget.path.display} · ${data?['kind'] ?? 'Loading conflict'}'),
        if (data != null)
          Wrap(
            spacing: session.host.spacing,
            children: [
              if (data!['baseAvailable'] == true)
                TextButton(
                  onPressed: () => compareBase(2),
                  child: const GitLabel('Base → left'),
                ),
              if (data!['baseAvailable'] == true)
                TextButton(
                  onPressed: () => compareBase(3),
                  child: const GitLabel('Base → right'),
                ),
              if (data!['baseAvailable'] != true)
                const GitLabel('No base entry for this conflict'),
              if (text)
                TextButton(
                  onPressed: loading
                      ? null
                      : () => unawaited(acceptWhole(ConflictChoice.left)),
                  child: const GitLabel('Accept entire left file…'),
                ),
              if (text)
                TextButton(
                  onPressed: loading
                      ? null
                      : () => unawaited(acceptWhole(ConflictChoice.right)),
                  child: const GitLabel('Accept entire right file…'),
                ),
            ],
          ),
        if (text) ...[
          Wrap(
            spacing: session.host.spacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GitIconButton(
                tooltip: 'Previous conflict region',
                onPressed: regions.isEmpty ? null : () => navigate(-1),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              GitIconButton(
                tooltip: 'Next conflict region',
                onPressed: regions.isEmpty ? null : () => navigate(1),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              Text(
                regions.isEmpty
                    ? 'Manual resolution'
                    : 'Region ${activeRegion + 1}/${regions.length} · ${reviewedRegions.length} reviewed',
              ),
              if (regions.any(
                (r) => r.leftOffset == null || r.rightOffset == null,
              ))
                const GitLabel(
                  'Source alignment exceeded the text comparison limit; source panes remain available for manual review.',
                ),
              TextButton(
                onPressed: regions.isEmpty ? null : () => acceptRegion(true),
                child: const GitLabel('Accept left region'),
              ),
              TextButton(
                onPressed: regions.isEmpty ? null : () => acceptRegion(false),
                child: const GitLabel('Accept right region'),
              ),
              TextButton(
                onPressed: regions.isEmpty
                    ? null
                    : () => setState(() => reviewedRegions.add(activeRegion)),
                child: const GitLabel('Keep manual result for region'),
              ),
              TextButton(
                onPressed: preview?.text == null
                    ? null
                    : () async {
                        if (!await gitConfirm(
                          context,
                          session,
                          'Apply Git’s non-conflicting changes?',
                          'Replace the current result draft with Git’s merge preview. This discards unsaved manual result edits; the working file is unchanged until Save.',
                          action: 'Use merge preview',
                        ))
                          return;
                        result.value = TextEditingValue(text: preview!.text!);
                        setState(() {
                          saved = false;
                          _draftDirty = true;
                        });
                      },
                child: const GitLabel('Apply non-conflicting changes…'),
              ),
            ],
          ),
          Expanded(
            child: GitRevisionPanes(
              labels: const ['Left source', 'Result', 'Right source'],
              anchorRevision: _anchorRevision,
              panes: [
                (scroll) => GitTextPane(
                  label: data?['leftLabel'] as String? ?? 'Stage 2',
                  text: left!.text ?? '(absent)',
                  scrollController: scroll,
                  revealRevision: _anchorRevision,
                  revealOffset: regions.isEmpty
                      ? null
                      : regions[activeRegion].leftOffset,
                ),
                (scroll) => resultPane(scroll),
                (scroll) => GitTextPane(
                  label: data?['rightLabel'] as String? ?? 'Stage 3',
                  text: right!.text ?? '(absent)',
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
                            'Conflict versions are unavailable. Refresh to review their current state.',
                          ),
                        )
                : nonText(),
          ),
        if (saved)
          const GitLabel(
            'Result saved to disk. The index still determines whether this file is resolved.',
          ),
        if (text) GitLabel(gitUtf8EncodingLabel(result.text)),
        if (text)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: session.host.spacing,
            children: [
              OutlinedButton(
                onPressed: loading || error != null || reviewed == null
                    ? null
                    : () => unawaited(save(false)),
                child: const GitLabel('Save result draft'),
              ),
              FilledButton(
                onPressed: loading || error != null || reviewed == null
                    ? null
                    : () => unawaited(save(true)),
                child: const GitLabel('Apply result and stage resolution'),
              ),
            ],
          ),
      ],
    );
  }

  Widget resultPane(ScrollController scroll) => GitTextPane(
    label: gitString(context, 'Result · editable UTF-8 working content'),
    semanticLabel: 'Editable conflict result',
    controller: result,
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
          'Left: ${left!.availability.name} · ${left!.mode}\nRight: ${right!.availability.name} · ${right!.mode}',
        ),
        const GitLabel(
          'Choose content, deletion, or a submodule commit explicitly. No binary data is decoded as editable text.',
        ),
        for (final choice in [
          ConflictChoice.left,
          ConflictChoice.right,
          ConflictChoice.delete,
        ])
          TextButton(
            onPressed: loading ? null : () => unawaited(acceptWhole(choice)),
            child: Text(switch (choice) {
              ConflictChoice.left => 'Use entire left content…',
              ConflictChoice.right => 'Use entire right content…',
              _ => 'Delete this path…',
            }),
          ),
        if (data?['kind'] == 'submodule')
          TextButton(
            onPressed: loading
                ? null
                : () async {
                    final value = await gitTextInput(
                      context,
                      session,
                      'Resolved submodule commit',
                      explanation:
                          'Stage this exact gitlink in the parent. This does not check out or commit the submodule.',
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
            child: const GitLabel('Set resolved gitlink…'),
          ),
      ],
    ),
  );
  Future<void> compareBase(int stage) => session.host.present<void>(
    context,
    'Base → stage $stage',
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
        'The result was edited. Keep the manual result or select another unchanged region.',
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
      'Apply ${choice.name} resolution?',
      data?['kind'] == 'submodule'
          ? 'Stage the chosen gitlink commit in the parent. The submodule checkout and its files are not replaced.'
          : 'Replaces the entire working path ${widget.path.display} and stages the decision. Current working content and any unsaved result draft will be discarded.',
      action: 'Apply entire file decision',
    ))
      return;
    await resolve(choice);
  }

  Future<void> save(bool stage) async {
    final bomChange = gitUtf8BomChange(working!.text ?? '', result.text);
    if (stage &&
        !await gitConfirm(
          context,
          session,
          'Stage this conflict resolution?',
          'Use the entire edited Result as ${widget.path.display}. Git records the path resolved when it is staged. Review all intended content first.${bomChange == null ? '' : '\n\n$bomChange'}',
          action: 'Apply and stage',
        ))
      return;
    if (!stage &&
        bomChange != null &&
        !await gitConfirm(
          context,
          session,
          'Change result byte-order mark?',
          bomChange,
          action: 'Save changed encoding',
        ))
      return;
    if (!mounted) return;
    await resolve(
      ConflictChoice.edited,
      bytes: Uint8List.fromList(utf8.encode(result.text)),
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
      Navigator.of(context).pop();
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
