import 'messages.dart';
import 'dismissal.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'commit_view.dart';
import 'diff_view.dart';
import 'host.dart';
import 'log_view.dart';
import 'operation_banner.dart';
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
    this.protectMessageDrafts = true,
  });
  final GitSession session;
  final bool protectMessageDrafts;
  final VoidCallback? onReturn, onBranches, onPush, onMore;
  final void Function(GitCommit, String)? onCommitAction;
  @override
  State<GitWorkspace> createState() => _GitWorkspaceState();
}

final class _GitWorkspaceState extends State<GitWorkspace> {
  bool _log = false;
  bool _logVisited = false;
  bool _compactReview = false;
  final _commitKey = GlobalKey(), _diffKey = GlobalKey();
  GitComparison? _comparison;
  List<GitComparison> _reviewedFiles = const [];
  int _reviewGeneration = 0;

  @override
  void didUpdateWidget(GitWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _reviewGeneration++;
      _comparison = null;
      _reviewedFiles = const [];
      _compactReview = false;
      _log = false;
      _logVisited = false;
    }
  }

  VoidCallback? _navigate(int direction) {
    final generation = _reviewGeneration;
    final targets = _reviewedFiles;
    final index = gitComparisonIndex(targets, _comparison);
    final next = index + direction;
    return index < 0 || next < 0 || next >= targets.length
        ? null
        : () {
            if (!mounted || generation != _reviewGeneration) return;
            setState(() {
              _reviewGeneration++;
              _comparison = targets[next];
            });
          };
  }

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: widget.session.host,
    child: Builder(
      builder: (context) => !widget.protectMessageDrafts
          ? _build(context)
          : ListenableBuilder(
              listenable: widget.session,
              builder: (context, _) => GitDraftGuard(
                host: widget.session.host,
                canDismiss: !widget.session.hasUnpersistedMessageDrafts,
                isDismissible: () =>
                    !widget.session.hasUnpersistedMessageDrafts,
                confirmDiscard: () =>
                    gitMayDismissMessageDrafts(context, () => [widget.session]),
                child: _build(context),
              ),
            ),
    ),
  );
  Widget _build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final host = widget.session.host;
      final row = host.rowHeight(context);
      final measure = TextPainter(
        text: TextSpan(
          text: '000000000000000000000000000000000000',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final minimumCommit = row * 9;
      final minimumReview = measure.width * 2 + host.spacing * 4;
      measure.dispose();
      return _workspace(
        context,
        bounds.maxWidth < minimumCommit + minimumReview + host.spacing,
        minimumCommit,
        minimumReview,
      );
    },
  );

  Widget _workspace(
    BuildContext context,
    bool compact,
    double minimumCommit,
    double minimumReview,
  ) => Column(
    children: [
      ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) => Column(
          children: [
            Row(
              children: [
                if (widget.onReturn != null)
                  TextButton.icon(
                    onPressed: widget.onReturn,
                    icon: const GitIcon(GitGlyph.back),
                    label: const GitLabel(GitMessages.returnToFiles),
                  ),
                Expanded(
                  child: Tooltip(
                    message: widget.session.repository.root,
                    child: _log || compact && _compactReview
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.session.repository.root,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              TextButton.icon(
                                onPressed:
                                    widget.onBranches ??
                                    () => unawaited(
                                      GitWorkflowUi(
                                        context,
                                        widget.session,
                                      ).branches(),
                                    ),
                                icon: const GitIcon(GitGlyph.branch),
                                label: Text(
                                  _branchLabel(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : const GitLabel(GitMessages.git),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: GitLabel(gitString(context, GitMessages.commit)),
                    ),
                    ButtonSegment(
                      value: true,
                      label: GitLabel(gitString(context, GitMessages.log)),
                    ),
                  ],
                  selected: {_log},
                  onSelectionChanged: (s) => setState(() {
                    _log = s.single;
                    _logVisited |= _log;
                    _compactReview = false;
                  }),
                ),
              ],
            ),
            if (_log || compact && _compactReview)
              GitOperationBanner(session: widget.session),
          ],
        ),
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
                  child: compact
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Offstage(
                              offstage: _compactReview,
                              child: ExcludeFocus(
                                excluding: _compactReview,
                                child: ExcludeSemantics(
                                  excluding: _compactReview,
                                  child: _commitView(!_compactReview),
                                ),
                              ),
                            ),
                            if (_comparison != null)
                              Offstage(
                                offstage: !_compactReview,
                                child: ExcludeFocus(
                                  excluding: !_compactReview,
                                  child: ExcludeSemantics(
                                    excluding: !_compactReview,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () => setState(
                                              () => _compactReview = false,
                                            ),
                                            icon: const GitIcon(GitGlyph.back),
                                            label: const GitLabel(
                                              GitMessages.backToCommit,
                                            ),
                                          ),
                                        ),
                                        Expanded(child: _reviewView()),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : GitSplitter(
                          initial: .28,
                          minimum: minimumCommit,
                          minimumSecond: minimumReview,
                          value: widget.session.split('workspaceSplit', .28),
                          onChanged: (v) =>
                              widget.session.setViewState('workspaceSplit', v),
                          first: _commitView(true),
                          second: _reviewView(),
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

  Widget _commitView(bool active) {
    final session = widget.session;
    final generation = _reviewGeneration;
    return GitCommitView(
      protectMessageDrafts: false,
      key: _commitKey,
      active: !_log && active,
      reviewContext: () => (_log, _compactReview, _comparison),
      session: session,
      selectedComparison: _comparison,
      onReview: (comparison) {
        if (!mounted ||
            widget.session != session ||
            generation != _reviewGeneration ||
            _log)
          return;
        setState(() {
          _reviewGeneration++;
          _reviewedFiles = List.unmodifiable(
            gitStatusComparisons(session.snapshot),
          );
          _comparison = comparison;
          _compactReview = true;
        });
      },
      onLog: () => setState(() {
        _log = true;
        _logVisited = true;
        _compactReview = false;
      }),
      onBranches:
          widget.onBranches ??
          () => GitWorkflowUi(context, widget.session).branches(),
      onPush:
          widget.onPush ?? () => GitWorkflowUi(context, widget.session).push(),
      onMore: (anchor) {
        if (widget.onMore != null) {
          widget.onMore!();
        } else {
          unawaited(GitWorkflowUi(anchor, widget.session).more());
        }
      },
    );
  }

  Widget _reviewView() => _comparison == null
      ? const Center(child: GitLabel(GitMessages.selectAChangeToReview))
      : GitDiffView(
          key: _diffKey,
          session: widget.session,
          comparison: _comparison!,
          onPreviousFile: _navigate(-1),
          onNextFile: _navigate(1),
        );

  String _branchLabel(BuildContext context) {
    final session = widget.session, snapshot = session.snapshot;
    if (snapshot == null) {
      return gitString(
        context,
        session.loading
            ? GitMessages.loadingBranch
            : GitMessages.branchUnavailable,
      );
    }
    return snapshot.branch ??
        (snapshot.head == null
            ? gitString(context, GitMessages.unbornHEAD)
            : gitString(
                context,
                GitMessages.detachedHEADRevision,
                values: {'revision': snapshot.head!.abbreviated},
              ));
  }
}
