import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'host.dart';
import 'network_views.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'diff_view.dart';

final class GitRebaseView extends StatefulWidget {
  const GitRebaseView({super.key, required this.session, this.boundary});
  final GitSession session;
  final GitOid? boundary;
  @override
  State<GitRebaseView> createState() => _RebaseState();
}

final class _RebaseState extends GitDialogState<GitRebaseView> {
  @override
  GitSession get session => widget.session;
  final boundary = TextEditingController(), onto = TextEditingController();
  bool root = false, preserve = false, autosquash = false;
  List<RebaseStep> steps = [], original = [];
  Map<String, Json> metadata = {};
  GitCommit? selectedCommit;
  int selected = 0;
  @override
  void initState() {
    super.initState();
    boundary.text = widget.boundary?.value ?? '';
  }

  @override
  void dispose() {
    boundary.dispose();
    onto.dispose();
    super.dispose();
  }

  void invalidate() => setState(() {
    data = null;
    steps = [];
    metadata = {};
    selectedCommit = null;
  });
  Future<void> prepare() async {
    try {
      await load(
        GitInspection(
          GitInspectionKind.rebasePlan,
          revision: root ? null : GitOid(boundary.text),
          otherRevision: onto.text.isEmpty ? null : GitOid(onto.text),
          root: root,
          preserveMerges: preserve,
          autosquash: autosquash,
        ),
      );
      if (!mounted || data == null || error != null) return;
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
        selected = 0;
      });
      await select(0);
    } on FormatException {
      setState(
        () => error = const GitException(
          GitErrorCode.invalidRequest,
          diagnostic: 'Enter full object IDs, or select a boundary from Log.',
        ),
      );
    }
  }

  Future<void> select(int index) async {
    if (steps.isEmpty) return;
    setState(() {
      selected = index;
      selectedCommit = null;
    });
    final oid = steps[index].commit;
    try {
      final page = await session.client.history(
        session.repository,
        filter: HistoryFilter(reference: oid.value),
        limit: 1,
      );
      if (mounted && steps[selected].commit == oid)
        setState(() => selectedCommit = page.commits.firstOrNull);
    } on GitException catch (failure) {
      if (mounted) setState(() => error = failure);
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
        return 'The first retained commit in a branch block cannot squash or fixup: it has no preceding target.';
      target = true;
    }
    return null;
  }

  void move(int delta) {
    final next = selected + delta;
    if (!canMove(delta)) return;
    setState(() {
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
    final retained = steps.where((s) => s.action != RebaseAction.drop).toList(),
        messages = <GitOid, String>{};
    for (final step in retained) {
      final page = await query(
        () => session.client.history(
          session.repository,
          filter: HistoryFilter(reference: step.commit.value),
          limit: 1,
        ),
      );
      if (!mounted || page == null) return;
      messages[step.commit] = page.commits.first.message;
    }
    final groups = <String>[];
    int? previousBlock;
    for (final step in retained) {
      final message = messages[step.commit]!,
          modifier = metadata[step.commit.value]?['modifier'] as String? ?? '';
      final block = metadata[step.commit.value]?['block'] as int?;
      final sameBlock = !preserve || block == previousBlock;
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
          '${preserve ? 'Branch block $block\n' : ''}${step.action == RebaseAction.reword ? '[Reword will request a new message]\n' : ''}$message',
        );
      }
      previousBlock = block;
    }
    if (mounted)
      await session.host.present<void>(
        context,
        'Planned commit messages',
        GitTextPane(
          label:
              'Original/combined message preview · Git requests the final reword/squash messages',
          text: [
            for (var i = 0; i < groups.length; i++)
              'Result ${i + 1}\n${groups[i]}',
          ].join('\n\n────────────────\n\n'),
        ),
        expanded: true,
      );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      states(refresh: () => unawaited(prepare())),
      const GitLabel(
        'Rebase rewrites commit identities. Remote-tracking information cannot prove history has never been published.',
      ),
      Wrap(
        spacing: session.host.spacing,
        runSpacing: session.host.spacing,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: boundary,
              enabled: !root && !loading,
              decoration: InputDecoration(
                labelText: gitString(
                  context,
                  'Old boundary · excluded full object ID',
                ),
              ),
              onChanged: (_) => invalidate(),
            ),
          ),
          SizedBox(
            width: 340,
            child: TextField(
              controller: onto,
              enabled: !loading,
              decoration: InputDecoration(
                labelText: gitString(
                  context,
                  'New base · optional full object ID',
                ),
              ),
              onChanged: (_) => invalidate(),
            ),
          ),
          SizedBox(
            width: 200,
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const GitLabel('Include root commits'),
              value: root,
              onChanged: loading
                  ? null
                  : (v) {
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
                labelText: gitString(context, 'Merge commits'),
              ),
              items: const [
                DropdownMenuItem(
                  value: false,
                  child: GitLabel('Flatten history'),
                ),
                DropdownMenuItem(
                  value: true,
                  child: GitLabel('Preserve branch structure'),
                ),
              ],
              onChanged: loading
                  ? null
                  : (v) {
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
              title: const GitLabel('Autosquash'),
              onChanged: loading
                  ? null
                  : (v) {
                      autosquash = v!;
                      invalidate();
                    },
            ),
          ),
          OutlinedButton(
            onPressed: loading ? null : () => unawaited(prepare()),
            child: const GitLabel('Prepare Git plan'),
          ),
        ],
      ),
      if (data != null)
        Text(
          root
              ? 'Includes all root commits reachable from this branch.'
              : 'Includes commits after ${data!['boundaryExcluded']}; the boundary itself is excluded.',
        ),
      if (preserve && data != null)
        ExpansionTile(
          title: const GitLabel('Git branch/label/reset/merge structure'),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: SelectableText(data!['todo'] as String),
              ),
            ),
          ],
        ),
      Expanded(
        child: data == null
            ? const Center(
                child: GitLabel(
                  'Choose an explicit old boundary or root mode, then prepare the plan.',
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
                        event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1,
                      );
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Column(
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: canMove(-1) ? () => move(-1) : null,
                            icon: const GitIcon(GitGlyph.up),
                            label: const GitLabel('Move up'),
                          ),
                          TextButton.icon(
                            onPressed: canMove(1) ? () => move(1) : null,
                            icon: const GitIcon(GitGlyph.down),
                            label: const GitLabel('Move down'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                steps = List.from(original);
                                selected = 0;
                              });
                              unawaited(select(0));
                            },
                            child: const GitLabel('Reset plan'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: steps.length,
                          itemBuilder: (context, i) {
                            final step = steps[i];
                            return Semantics(
                              selected: i == selected,
                              label:
                                  '${i + 1}, ${step.action.name}, ${metadata[step.commit.value]?['subject']}',
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
                                  '${step.commit.abbreviated}${preserve ? ' · branch block ${metadata[step.commit.value]?["block"]}' : ''}${metadata[step.commit.value]?['modifier'] == '' ? '' : ' · ${metadata[step.commit.value]?['modifier']}'}',
                                ),
                                onTap: () => unawaited(select(i)),
                                trailing: DropdownButton<RebaseAction>(
                                  value: step.action,
                                  underline: const SizedBox.shrink(),
                                  items: [
                                    for (final action in RebaseAction.values)
                                      DropdownMenuItem(
                                        value: action,
                                        child: Text(action.name),
                                      ),
                                  ],
                                  onChanged: loading
                                      ? null
                                      : (action) => setState(
                                          () => steps[i] = RebaseStep(
                                            action!,
                                            step.commit,
                                          ),
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
                          'Select a commit for details and changed files',
                        ),
                      )
                    : GitCommitFiles(session: session, commit: selectedCommit!),
              ),
      ),
      if (invalid != null)
        Text(
          invalid!,
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
            child: const GitLabel('Preview combined commit messages…'),
          ),
        ),
      const GitLabel(
        'Alt+↑/↓ moves the selected commit. Unrelated branch references will not be updated automatically.',
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const GitLabel('Cancel plan'),
          ),
          FilledButton(
            onPressed: loading || data == null || invalid != null
                ? null
                : () async {
                    final plan = data!;
                    if (!await gitConfirm(
                      context,
                      session,
                      'Start reviewed rebase?',
                      'Rewrite ${steps.length} planned commits on ${session.snapshot?.branch ?? 'detached HEAD'}. Dropped commits remain visibly marked in this plan until you start.',
                      action: 'Start rebase',
                    ))
                      return;
                    final result = await apply(
                      RebaseCommits(
                        expectedHead: GitOid(plan['head'] as String),
                        expectedIndex: plan['index'] as String,
                        boundary: root ? null : GitOid(boundary.text),
                        onto: onto.text.isEmpty ? null : GitOid(onto.text),
                        root: root,
                        preserveMerges: preserve,
                        autosquash: autosquash,
                        interactive: true,
                        planToken: plan['token'] as String,
                        steps: List.from(steps),
                      ),
                    );
                    if (mounted &&
                        result != null &&
                        (result.completed ||
                            result.phase == GitOperationPhase.stopped))
                      Navigator.of(context).pop();
                  },
            child: const GitLabel('Start rebase'),
          ),
        ],
      ),
    ],
  );
}
