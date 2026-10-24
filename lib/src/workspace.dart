import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'commit_view.dart';
import 'diff_view.dart';
import 'host.dart';
import 'log_view.dart';
import 'session.dart';
import 'workflow_ui.dart';

final class GitWorkspace extends StatefulWidget {
  const GitWorkspace({
    super.key,
    required this.session,
    this.onReturn,
    this.onBranches,
    this.onPush,
    this.onMore,
    this.onCommitAction,
  });
  final GitSession session;
  final VoidCallback? onReturn, onBranches, onPush, onMore;
  final void Function(GitCommit, String)? onCommitAction;
  @override
  State<GitWorkspace> createState() => _GitWorkspaceState();
}

final class _GitWorkspaceState extends State<GitWorkspace> {
  bool _log = false;
  bool _logVisited = false;
  GitComparison? _comparison;
  VoidCallback? _navigate(int direction) {
    final targets = gitStatusComparisons(widget.session.snapshot);
    final index = gitComparisonIndex(targets, _comparison);
    final next = index + direction;
    return index < 0 || next < 0 || next >= targets.length
        ? null
        : () => setState(() => _comparison = targets[next]);
  }

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: widget.session.host,
    child: Builder(builder: _build),
  );
  Widget _build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          if (widget.onReturn != null)
            TextButton.icon(
              onPressed: widget.onReturn,
              icon: const Icon(Icons.arrow_back),
              label: const GitLabel('Return to Files'),
            ),
          Expanded(
            child: Tooltip(
              message: widget.session.repository.root,
              child: Text(
                _log ? widget.session.repository.root : 'Git',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: GitLabel('Commit')),
              ButtonSegment(value: true, label: GitLabel('Log')),
            ],
            selected: {_log},
            onSelectionChanged: (s) => setState(() {
              _log = s.single;
              _logVisited |= _log;
            }),
          ),
        ],
      ),
      const Divider(height: 1),
      Expanded(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: _log,
              child: ExcludeFocus(
                excluding: _log,
                child: ExcludeSemantics(
                  excluding: _log,
                  child: GitSplitter(
                    initial: .28,
                    minimum: 220,
                    value: widget.session.split('workspaceSplit', .28),
                    onChanged: (v) =>
                        widget.session.setViewState('workspaceSplit', v),
                    first: GitCommitView(
                      session: widget.session,
                      selectedComparison: _comparison,
                      onReview: (comparison) =>
                          setState(() => _comparison = comparison),
                      onLog: () => setState(() {
                        _log = true;
                        _logVisited = true;
                      }),
                      onBranches:
                          widget.onBranches ??
                          () =>
                              GitWorkflowUi(context, widget.session).branches(),
                      onPush:
                          widget.onPush ??
                          () => GitWorkflowUi(context, widget.session).push(),
                      onMore:
                          widget.onMore ??
                          () => GitWorkflowUi(context, widget.session).more(),
                    ),
                    second: _comparison == null
                        ? const Center(
                            child: GitLabel('Select a change to review'),
                          )
                        : GitDiffView(
                            session: widget.session,
                            comparison: _comparison!,
                            onPreviousFile: _navigate(-1),
                            onNextFile: _navigate(1),
                          ),
                  ),
                ),
              ),
            ),
            if (_logVisited)
              Offstage(
                offstage: !_log,
                child: ExcludeFocus(
                  excluding: !_log,
                  child: ExcludeSemantics(
                    excluding: !_log,
                    child: GitLogView(
                      session: widget.session,
                      active: _log,
                      onCommitAction: widget.onCommitAction,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
