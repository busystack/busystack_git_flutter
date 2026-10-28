import 'value_labels.dart';
import 'messages.dart';
import 'dart:async';
import 'dart:ui' show SemanticsRole;
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'context_menu_keys.dart';
import 'host.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'history_actions.dart';
import 'native_table.dart';
import 'operation_banner.dart';
import 'text_undo.dart';
import 'dismissal.dart';

final class GitCommitView extends StatelessWidget {
  const GitCommitView({
    super.key,
    required this.session,
    required this.onReview,
    required this.onLog,
    required this.onBranches,
    required this.onPush,
    required this.onMore,
    this.selectedComparison,
    this.notice,
    this.active = true,
    this.reviewContext,
    this.protectMessageDrafts = true,
  });
  final GitSession session;
  final ValueChanged<GitComparison> onReview;
  final GitComparison? selectedComparison;
  final Widget? notice;
  final bool active;

  /// Hosts with a persistent window-level message guard disable this local guard.
  final bool protectMessageDrafts;

  /// Current host document/review identity. This guards late presentation
  /// updates; repository authorization remains the engine's responsibility.
  final Object? Function()? reviewContext;
  final VoidCallback onLog, onBranches, onPush;
  final ValueChanged<BuildContext> onMore;
  @override
  Widget build(BuildContext context) =>
      _GitCommitSession(key: ObjectKey(session), configuration: this);
}

// Session identity owns the editor state and every outstanding continuation.
// Reusing the public view for another worktree creates a new binding while the
// retired state finishes only its original operation and draft ownership.
final class _GitCommitSession extends StatefulWidget {
  const _GitCommitSession({super.key, required this.configuration});
  final GitCommitView configuration;
  @override
  State<_GitCommitSession> createState() => _GitCommitViewState();
}

final class _GitCommitViewState extends State<_GitCommitSession> {
  GitCommitView get view => widget.configuration;
  final _message = TextEditingController();
  bool _amend = false, _signOff = false;
  bool? _sign;
  bool _composing = false;
  int _reviewGeneration = 0;
  int _amendGeneration = 0, _messageRevision = 0;
  GitOid? _amendTarget;
  GitSession get session => view.session;
  GitHost get host => session.host;
  void _leaveReview(VoidCallback action) {
    _reviewGeneration++;
    action();
  }

  @override
  void initState() {
    super.initState();
    _message.text = session.draft;
    final recovering = session.viewState['commitAmendDraftTarget'];
    if (recovering is String &&
        RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(recovering)) {
      unawaited(_recoverAmend(GitOid(recovering)));
    }
    session.addListener(_changed);
    _message.addListener(_compositionChanged);
    session.commitAction = _commit;
    session.canCommit = _canCommit;
  }

  bool _canCommit() =>
      !session.running &&
      !session.repository.bare &&
      session.canWriteMetadata &&
      _message.text.trim().isNotEmpty &&
      (!_amend ||
          _amendTarget != null && _amendTarget == session.snapshot?.head) &&
      !(session.outcome?.phase == GitOperationPhase.uncertain &&
          session.failure != null) &&
      (!_message.value.composing.isValid ||
          _message.value.composing.isCollapsed) &&
      (session.snapshot!.changes.any((e) => e.staged) || _amend) &&
      !session.snapshot!.operation.unmerged;
  void _changed() {
    if (!mounted) return;
    final draft = _amend && _amendTarget != null
        ? session.messageDraft(_amendDraftKey(_amendTarget!)).text
        : session.draft;
    if (_message.text != draft && !session.running && !_composing) {
      _messageRevision++;
      _message.text = draft;
    }
    setState(() {});
  }

  void _compositionChanged() {
    final active =
        _message.value.composing.isValid &&
        !_message.value.composing.isCollapsed;
    if (mounted && active != _composing) setState(() => _composing = active);
  }

  @override
  void dispose() {
    _amendGeneration++;
    session.removeListener(_changed);
    if (session.commitAction == _commit) {
      session.commitAction = null;
      session.canCommit = null;
    }
    _message.removeListener(_compositionChanged);
    _message.dispose();
    super.dispose();
  }

  String _amendDraftKey(GitOid target) =>
      '${session.repository.presentationKey}:amend:${target.value}';

  void _storeMessage(String value) {
    _messageRevision++;
    if (_amend && _amendTarget != null) {
      session.setMessageDraft(_amendDraftKey(_amendTarget!), value);
      _rememberAmend(_amendTarget!);
    } else {
      session.setDraft(value);
    }
    if (mounted) setState(() {});
  }

  Future<void> _setAmend(bool value) async {
    if (value == _amend) return;
    final generation = ++_amendGeneration;
    if (!value) {
      setState(() {
        _amend = false;
        _amendTarget = null;
        _message.text = session.draft;
      });
      return;
    }
    final target = session.snapshot?.head;
    if (target == null) return;
    final revision = _messageRevision;
    setState(() {
      _amend = true;
      _amendTarget = target;
      _message.text = '';
    });
    try {
      final saved = await session.readMessageDraft(_amendDraftKey(target));
      String? message = saved.text.isNotEmpty ? saved.text : null;
      if (message == null) {
        final page = await session.client.history(
          session.repository,
          filter: HistoryFilter(reference: target.value),
          limit: 1,
        );
        if (page.commits.firstOrNull?.oid != target) {
          throw const GitException(GitErrorCode.staleReview);
        }
        message = page.commits.first.message;
      }
      if (!mounted ||
          generation != _amendGeneration ||
          !_amend ||
          _amendTarget != target ||
          session.snapshot?.head != target ||
          revision != _messageRevision ||
          _message.text.isNotEmpty)
        return;
      final String loadedMessage = message;
      session.setMessageDraft(_amendDraftKey(target), loadedMessage);
      _rememberAmend(target);
      setState(() => _message.text = loadedMessage);
    } on Object catch (error) {
      if (mounted && generation == _amendGeneration && _amend)
        session.reportFailure(error);
    }
  }

  List<GitOid> get _retainedAmends => [
    for (final target in switch (session.viewState['commitAmendDraftTargets']) {
      final List targets => targets,
      _ => const [],
    })
      if (target is String &&
          RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(target))
        GitOid(target),
  ];

  void _rememberAmend(GitOid target) {
    final targets = _retainedAmends.map((oid) => oid.value).toSet();
    if (targets.add(target.value)) {
      session.setViewState('commitAmendDraftTargets', targets.toList());
    }
    if (session.viewState['commitAmendDraftTarget'] != target.value) {
      session.setViewState('commitAmendDraftTarget', target.value);
    }
  }

  Future<void> _recoverAmend(GitOid target) async {
    final generation = ++_amendGeneration, revision = _messageRevision;
    try {
      final saved = await session.readMessageDraft(_amendDraftKey(target));
      if (!mounted ||
          generation != _amendGeneration ||
          revision != _messageRevision ||
          saved.text.isEmpty)
        return;
      setState(() {
        _amend = true;
        _amendTarget = target;
        _message.text = saved.text;
      });
    } on Object catch (error) {
      if (mounted && generation == _amendGeneration)
        session.reportFailure(error);
    }
  }

  @override
  Widget build(BuildContext context) => GitHostScope(
    host: view.session.host,
    child: Builder(
      builder: (context) => !view.protectMessageDrafts
          ? _build(context)
          : GitDraftGuard(
              host: host,
              canDismiss: !session.hasUnpersistedMessageDrafts,
              isDismissible: () => !session.hasUnpersistedMessageDrafts,
              revisionChanges: session,
              revisionIdentity: () => session.messageDraftRevisions,
              confirmDiscard: () => _confirmMessageClose(context),
              child: _build(context),
            ),
    ),
  );
  Future<bool> _confirmMessageClose(BuildContext context) =>
      gitMayDismissMessageDrafts(context, () => [session]);

  String get _messageKey => _amend && _amendTarget != null
      ? _amendDraftKey(_amendTarget!)
      : session.repository.presentationKey;

  Future<void> _reviewSavedMessage(BuildContext context) async {
    final key = session.reviewableMessageDraft(_messageKey);
    if (key == null) return;
    final review = await session.reviewMessageDraft(key);
    if (!mounted || review == null) return;
    final target = RegExp(
      r':amend:([0-9a-f]{40}|[0-9a-f]{64})$',
    ).firstMatch(key)?.group(1);
    final choice = await host.present<bool>(
      context,
      gitString(context, GitMessages.reviewSavedMessage),
      Builder(
        builder: (dialogContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (target != null)
              Text(
                '${gitString(context, GitMessages.amendLastCommit)} '
                '${GitOid(target).abbreviated}',
              ),
            GitLabel(GitMessages.commitMessage),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: SelectableText(review.local.text),
              ),
            ),
            const SizedBox(height: 12),
            const GitLabel(GitMessages.savedMessage),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: SelectableText(review.saved.text ?? ''),
              ),
            ),
            Wrap(
              spacing: host.spacing,
              children: [
                TextButton(
                  onPressed: () => gitCompleteSurface(dialogContext, false),
                  child: const GitLabel(GitMessages.keepThisMessage),
                ),
                TextButton(
                  onPressed: () => gitCompleteSurface(dialogContext, true),
                  child: const GitLabel(GitMessages.useSavedMessage),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (choice != null) {
      await session.resolveMessageDraft(review, useSaved: choice);
    }
  }

  Widget _build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (bounds.maxWidth < 1 || bounds.maxHeight < 1) return const SizedBox();
      final width = bounds.maxWidth.clamp(220.0, double.infinity);
      final minimumHeight = _minimumHeight(context, width);
      final messageMinimum = _messageMinimum(context, width);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: bounds.maxHeight,
          maxHeight: bounds.maxHeight,
          child: bounds.maxHeight < minimumHeight
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: SizedBox(
                          height: minimumHeight,
                          child: _panel(
                            context,
                            includeActions: false,
                            messageMinimum: messageMinimum,
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: bounds.maxHeight),
                      child: SingleChildScrollView(
                        child: _actions(stagedCount),
                      ),
                    ),
                  ],
                )
              : _panel(context, messageMinimum: messageMinimum),
        ),
      );
    },
  );
  double _minimumHeight(BuildContext context, double width) {
    final row = host.rowHeight(context), spacing = host.spacing;
    final theme = Theme.of(context).textTheme;
    double height(
      String text,
      TextStyle? style,
      double available, {
      int? maxLines,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: gitString(context, text), style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: available.clamp(24.0, double.infinity));
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final inner = width - spacing * 2;
    final messageMinimum = _messageMinimum(context, width);
    final header =
        row +
        spacing * 2 +
        height(
          GitMessages.commitScopeEntireRepository,
          theme.bodySmall,
          inner,
          maxLines: 1,
        ) +
        height(session.repository.root, theme.bodySmall, inner, maxLines: 1) +
        (session.snapshot?.upstream == null
            ? 0
            : height(
                GitMessages.cachedTracking,
                theme.bodySmall,
                inner,
                maxLines: 1,
              )) +
        (view.notice == null ? 0 : row * 3) +
        (session.repository.bare ? row * 3 : 0) +
        (session.snapshot?.capabilities.writeMetadata == false ? row * 3 : 0);
    return header +
        messageMinimum +
        row * 2 +
        spacing * 2 +
        (session.snapshot != null &&
                session.snapshot!.operation.kind != GitOperationKind.none
            ? row * 3
            : 0) +
        (session.running ? row * 3 : 0) +
        (session.failure == null ? 0 : row * 4);
  }

  double _messageMinimum(BuildContext context, double width) {
    final row = host.rowHeight(context);
    final theme = Theme.of(context).textTheme;
    double textHeight(
      String text,
      TextStyle? style, {
      int? maxLines,
      double inset = 0,
    }) {
      final measure =
          TextPainter(
            text: TextSpan(text: gitString(context, text), style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: maxLines,
          )..layout(
            maxWidth: (width - host.spacing * 2 - inset).clamp(
              24.0,
              double.infinity,
            ),
          );
      final height = measure.height;
      measure.dispose();
      return height;
    }

    return row * 2 +
        textHeight(
          GitMessages.amendLastCommit,
          theme.bodyMedium,
          inset: 96,
          maxLines: 1,
        ).clamp(48.0, double.infinity) +
        textHeight(
          GitMessages.configuredHooksAndSigningAreRespected,
          theme.bodySmall,
          maxLines: 1,
        ) +
        (_amend
            ? textHeight(
                GitMessages
                    .rewritesTheSelectedHEADCommitRemoteTrackingCannotProveIt,
                theme.bodyMedium,
              )
            : 0) +
        (_amend && _amendTarget != session.snapshot?.head
            ? textHeight(_staleAmendMessage(context), theme.bodyMedium)
            : 0) +
        (session.draftFailure == null
            ? 0
            : textHeight(_draftFailureMessage(context), theme.bodyMedium)) +
        (session.reviewableMessageDraft(_messageKey) == null
            ? 0
            : (textHeight(
                        GitMessages.reviewSavedMessage,
                        theme.labelLarge,
                        inset: 32,
                      ) +
                      24)
                  .clamp(row * 2, double.infinity));
  }

  String _draftFailureMessage(BuildContext context) => gitString(
    context,
    session.draftFailure!.code == GitErrorCode.staleReview
        ? GitMessages.commitDraftChangedInAnotherWindow
        : GitMessages.draftRetainedInMemorySavingItFailedArg0,
    values: {'arg0': session.draftFailure!.diagnostic},
  );

  String _staleAmendMessage(BuildContext context) =>
      '${gitString(context, GitMessages.theRequestedRevisionIsUnavailable)} '
      'HEAD ${_amendTarget?.abbreviated ?? ''} → '
      '${session.snapshot?.head?.abbreviated ?? ''}';

  int get stagedCount =>
      session.snapshot?.changes.where((e) => e.staged).length ?? 0;

  Widget _panel(
    BuildContext context, {
    bool includeActions = true,
    required double messageMinimum,
  }) {
    final snapshot = session.snapshot;
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(host.spacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _leaveReview(view.onBranches),
                        icon: GitIcon(GitGlyph.branch, size: 16),
                        label: Text(
                          snapshot?.branch ??
                              (snapshot?.head == null
                                  ? gitString(context, GitMessages.repository)
                                  : gitString(
                                      context,
                                      GitMessages.detachedArg0,
                                      values: {
                                        'arg0': snapshot!.head!.abbreviated,
                                      },
                                    )),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    GitIconButton(
                      tooltip: gitString(context, GitMessages.log),
                      onPressed: () => _leaveReview(view.onLog),
                      icon: GitIcon(GitGlyph.history, size: 18),
                    ),
                    GitIconButton(
                      tooltip: gitString(context, GitMessages.refresh),
                      onPressed: session.refreshing
                          ? null
                          : () => unawaited(
                              session.refresh(clearOperationFailure: true),
                            ),
                      icon: const GitIcon(GitGlyph.refresh, size: 18),
                    ),
                    Builder(
                      builder: (anchor) => GitIconButton(
                        tooltip: gitString(
                          context,
                          GitMessages.repositoryActions,
                        ),
                        onPressed: () =>
                            _leaveReview(() => view.onMore(anchor)),
                        icon: const GitIcon(GitGlyph.more, size: 18),
                      ),
                    ),
                  ],
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Tooltip(
                    message: session.repository.root,
                    child: Text(
                      session.repository.root,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Tooltip(
                  message: gitString(
                    context,
                    GitMessages.commitScopeEntireRepository,
                  ),
                  child: GitLabel(
                    GitMessages.commitScopeEntireRepository,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (snapshot?.upstream != null)
                  Tooltip(
                    message: gitString(
                      context,
                      GitMessages.cachedTrackingUpstreamAheadAheadBehindBehind,
                      values: {
                        'upstream': snapshot!.upstream!,
                        'ahead': snapshot.ahead,
                        'behind': snapshot.behind,
                      },
                    ),
                    child: GitLabel(
                      GitMessages.cachedTrackingUpstreamAheadAheadBehindBehind,
                      values: {
                        'upstream': snapshot.upstream!,
                        'ahead': snapshot.ahead,
                        'behind': snapshot.behind,
                      },
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (session.repository.bare)
                  const GitLabel(
                    GitMessages.bareRepositoryNoWorkingTreeOpenLogToInspectIts,
                  ),
                if (snapshot != null && !snapshot.capabilities.writeMetadata)
                  const GitLabel(
                    GitMessages
                        .readOnlyRepositoryStagingAndCommitsAreUnavailable,
                  ),
                if (view.notice != null) view.notice!,
              ],
            ),
          ),
          if (session.loading) const LinearProgressIndicator(),
          if (session.failure case final error?)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: host.rowHeight(context) * 4,
              ),
              child: SingleChildScrollView(
                child: GitFailurePanel(
                  error: error,
                  onAuthorize: error.code == GitErrorCode.trustRequired
                      ? () => unawaited(session.authorizeInspection())
                      : null,
                  onRefresh: () =>
                      unawaited(session.refresh(clearOperationFailure: true)),
                ),
              ),
            ),
          if (snapshot?.operation.kind != null &&
              snapshot!.operation.kind != GitOperationKind.none)
            GitOperationBanner(session: session),
          Expanded(
            child: GitSplitter(
              axis: Axis.vertical,
              initial: .62,
              minimum: host.rowHeight(context) * 2,
              minimumSecond: messageMinimum,
              value: session.split('commitMessageSplit', .62),
              onChanged: (v) => session.setViewState('commitMessageSplit', v),
              first: session.loading && snapshot == null
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot == null
                  ? const Center(
                      child: GitLabel(GitMessages.repositoryStatusUnavailable),
                    )
                  : GitChangeTree(
                      active: view.active,
                      reviewContext: () => (
                        _reviewGeneration,
                        view.reviewContext?.call(),
                        view.selectedComparison,
                      ),
                      session: session,
                      onReview: view.onReview,
                      selectedComparison: view.selectedComparison,
                    ),
              second: Padding(
                padding: EdgeInsets.symmetric(horizontal: host.spacing),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Semantics(
                          label: gitString(
                            context,
                            _amend
                                ? GitMessages.amendRevision
                                : GitMessages.amendLastCommit,
                            values: {
                              'revision': _amend
                                  ? _amendTarget?.abbreviated ?? ''
                                  : snapshot?.head?.abbreviated ?? '',
                            },
                          ),
                          checked: _amend,
                          enabled: !session.running && snapshot?.head != null,
                          onTap: session.running || snapshot?.head == null
                              ? null
                              : () => unawaited(_setAmend(!_amend)),
                          child: ExcludeSemantics(
                            child: Checkbox(
                              value: _amend,
                              onChanged:
                                  session.running || snapshot?.head == null
                                  ? null
                                  : (value) => unawaited(_setAmend(value!)),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ExcludeSemantics(
                            child: GitLabel(
                              _amend
                                  ? GitMessages.amendRevision
                                  : GitMessages.amendLastCommit,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              values: {
                                'revision': _amend
                                    ? _amendTarget?.abbreviated ?? ''
                                    : snapshot?.head?.abbreviated ?? '',
                              },
                            ),
                          ),
                        ),
                        GitMenuButton(
                          host: session.host,
                          onSelected: (value) => _options(value),
                          entries: [
                            GitMenuEntry(
                              'signoff',
                              GitMessages.addSignOffTrailer,
                              checked: _signOff,
                            ),
                            GitMenuEntry(
                              'configuredSigning',
                              GitMessages.useConfiguredSigningPolicy,
                              checked: _sign == null,
                              radio: true,
                            ),
                            GitMenuEntry(
                              'sign',
                              GitMessages.cryptographicallySignThisCommit,
                              checked: _sign == true,
                              radio: true,
                            ),
                            GitMenuEntry(
                              'unsigned',
                              GitMessages.doNotSignThisCommit,
                              checked: _sign == false,
                              radio: true,
                            ),
                            const GitMenuEntry.separator(),
                            for (final target in _retainedAmends)
                              GitMenuEntry(
                                'recoverAmend:${target.value}',
                                host.message(
                                  GitMessages.amendRevision,
                                  values: {'revision': target.abbreviated},
                                ),
                                localize: false,
                                enabled: !session.running,
                              ),
                            GitMenuEntry(
                              'recent',
                              GitMessages.recentCommitMessages,
                            ),
                            GitMenuEntry(
                              'template',
                              GitMessages.useConfiguredCommitTemplate,
                            ),
                            GitMenuEntry(
                              'identity',
                              GitMessages.authorIdentityAndConfiguredHooks,
                            ),
                            if (host.draftMessage != null)
                              GitMenuEntry('draft', GitMessages.draftMessage),
                          ],
                          tooltip: gitString(
                            context,
                            GitMessages.commitOptions,
                          ),
                        ),
                      ],
                    ),
                    if (_amend)
                      const GitLabel(
                        GitMessages
                            .rewritesTheSelectedHEADCommitRemoteTrackingCannotProveIt,
                      ),
                    if (_amend && _amendTarget != snapshot?.head)
                      Text(
                        _staleAmendMessage(context),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (session.draftFailure != null)
                      Text(
                        _draftFailureMessage(context),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (session.reviewableMessageDraft(_messageKey) != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () => _reviewSavedMessage(context),
                          child: const GitLabel(GitMessages.reviewSavedMessage),
                        ),
                      ),
                    Expanded(
                      child: GitTextUndo(
                        controller: _message,
                        child: TextField(
                          controller: _message,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            labelText: gitString(
                              context,
                              GitMessages.commitMessage,
                            ),
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _storeMessage(value);
                          },
                        ),
                      ),
                    ),
                    GitLabel(
                      GitMessages.configuredHooksAndSigningAreRespected,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (session.running)
            Padding(
              padding: EdgeInsets.all(host.spacing),
              child: SizedBox(
                // Transport progress alternates between short and wrapped
                // text. Keep the message editor and its IME/caret stationary.
                height: host.rowHeight(context) * 2,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    Expanded(
                      child: Text(
                        session.progress?.text.isNotEmpty == true
                            ? session.progress!.text
                            : gitString(
                                context,
                                GitMessages.gitOperationInProgress,
                              ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: session.cancel,
                      child: const GitLabel(GitMessages.cancel),
                    ),
                  ],
                ),
              ),
            ),
          if (includeActions) _actions(stagedCount),
        ],
      ),
    );
  }

  Widget _actions(int staged) => Padding(
    padding: EdgeInsets.all(host.spacing),
    child: Wrap(
      spacing: host.spacing,
      runSpacing: host.spacing,
      children: [
        FilledButton(
          onPressed: _canCommit() ? () => unawaited(_commit(false)) : null,
          child: GitLabel(
            _amend ? GitMessages.amendStaged : GitMessages.commitStagedCount,
            values: {'count': staged},
          ),
        ),
        OutlinedButton(
          onPressed: _canCommit() ? () => unawaited(_commit(true)) : null,
          child: const GitLabel(GitMessages.commitAndPush),
        ),
      ],
    ),
  );

  void _options(String option) {
    if (option.startsWith('recoverAmend:')) {
      unawaited(
        _recoverAmend(GitOid(option.substring('recoverAmend:'.length))),
      );
      return;
    }
    switch (option) {
      case 'signoff':
        setState(() => _signOff = !_signOff);
      case 'sign':
        setState(() => _sign = true);
      case 'unsigned':
        setState(() => _sign = false);
      case 'configuredSigning':
        setState(() => _sign = null);
      case 'recent':
        unawaited(_recent());
      case 'template':
        unawaited(_template());
      case 'identity':
        unawaited(_identity());
      case 'draft':
        unawaited(_draft());
    }
  }

  Future<void> _template() async {
    final generation = _amendGeneration, revision = _messageRevision;
    try {
      final client = session.client;
      if (client is! GitWorkflowClient) return;
      final options = await (client as GitWorkflowClient).inspect(
        session.repository,
        const GitInspection(GitInspectionKind.commitOptions),
      );
      if (!_ownsMessageRequest(generation, revision)) return;
      final template = options['template'] as String?;
      if (template == null) {
        host.notify(GitMessages.noReadableCommitTemplateIsConfigured);
        return;
      }
      if (_message.text.isNotEmpty && !await _confirmReplace()) return;
      if (!_ownsMessageRequest(generation, revision)) return;
      _message.text = template;
      _storeMessage(template);
    } on Object catch (error) {
      session.reportFailure(error);
    }
  }

  Future<void> _identity() async {
    await host.present<void>(
      context,
      GitMessages.commitIdentityAndHooks,
      GitIdentityView(session: session),
      expanded: false,
    );
  }

  Future<void> _draft() async {
    final generation = _amendGeneration, revision = _messageRevision;
    final before = _message.text;
    final value = await host.draftMessage?.call(session.repository);
    if (!_ownsMessageRequest(generation, revision) ||
        value == null ||
        _message.text != before)
      return;
    if (before.isNotEmpty && !await _confirmReplace()) return;
    if (!_ownsMessageRequest(generation, revision)) return;
    _message.text = value;
    _storeMessage(value);
  }

  Future<void> _recent() async {
    final generation = _amendGeneration, revision = _messageRevision;
    try {
      final page = await session.client.history(session.repository, limit: 20);
      if (!_ownsMessageRequest(generation, revision)) return;
      final value = await host.present<String>(
        context,
        GitMessages.recentMessages,
        SizedBox(
          height: 350,
          child: ListView(
            children: [
              for (final commit in page.commits)
                ListTile(
                  title: Text(commit.subject),
                  onTap: () => Navigator.of(context).pop(commit.message),
                ),
            ],
          ),
        ),
        expanded: false,
      );
      if (!_ownsMessageRequest(generation, revision) || value == null) return;
      if (_message.text.isNotEmpty && !await _confirmReplace()) return;
      if (!_ownsMessageRequest(generation, revision)) return;
      _message.text = value;
      _storeMessage(value);
    } on Object catch (error) {
      session.reportFailure(error);
    }
  }

  bool _ownsMessageRequest(int generation, int revision) =>
      mounted && generation == _amendGeneration && revision == _messageRevision;

  Future<bool> _confirmReplace() async =>
      await host.present<bool>(
        context,
        GitMessages.replaceMessageDraft,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GitLabel(
              GitMessages.replaceTheExistingCommitMessageWithTheSelectedMessage,
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const GitLabel(GitMessages.replaceDraft),
            ),
          ],
        ),
        expanded: false,
      ) ==
      true;
  Future<void> _commit(bool push) async {
    if (!_canCommit()) return;
    final snapshot = session.snapshot;
    if (snapshot == null) return;
    final message = _message.text,
        amendGeneration = _amendGeneration,
        amending = _amend,
        amendTarget = _amendTarget;
    final submitted = session.messageDraft(
      amending && amendTarget != null
          ? _amendDraftKey(amendTarget)
          : session.repository.presentationKey,
    );
    final result = await session.mutate(
      CommitIndex(
        message,
        expectedHead: snapshot.head,
        expectedIndex: snapshot.indexToken,
        amend: _amend,
        signOff: _signOff,
        sign: _sign,
      ),
    );
    if (result == null) return;
    if (mounted && result.error?.code == GitErrorCode.authorIdentity) {
      await _identity();
      return;
    }
    if (result.createdCommit != null &&
        result.completed &&
        result.error == null) {
      // Settle storage even if the originating view was closed. The version
      // belongs to its own slot, so later edits and the normal draft survive.
      final cleared = await session.clearMessageDraft(submitted);
      if (amending && cleared && amendTarget != null) {
        session.setViewState('commitAmendDraftTargets', [
          for (final target in _retainedAmends)
            if (target != amendTarget) target.value,
        ]);
        if (session.viewState['commitAmendDraftTarget'] == amendTarget.value) {
          session.setViewState('commitAmendDraftTarget', '');
        }
      }
      if (!mounted) return;
      if (amending &&
          _amend &&
          _amendTarget == amendTarget &&
          _amendGeneration == amendGeneration) {
        if (cleared) {
          _amendGeneration++;
          _amendTarget = null;
          _amend = false;
          _message.text = session.draft;
        }
        // Otherwise retain the newer amend draft with its original owner.
        // Its stale-target warning disables another amend until current HEAD
        // is explicitly reviewed; never retarget the draft to the new commit.
      } else if (!amending && !_amend && cleared) {
        _message.clear();
      }
      host.notify(
        gitString(
          context,
          GitMessages.localCommitArg0Exists,
          values: {'arg0': result.createdCommit!.abbreviated},
        ),
      );
      setState(() {});
      if (push) view.onPush();
    } else if (mounted && result.createdCommit != null) {
      host.notify(
        gitString(
          context,
          GitMessages
              .localCommitArg0ExistsReviewLogBeforeAttemptingAnotherCommit,
          values: {'arg0': result.createdCommit!.abbreviated},
        ),
      );
    }
  }
}

final class GitIdentityView extends StatefulWidget {
  const GitIdentityView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitIdentityView> createState() => _IdentityState();
}

final class _IdentityState extends GitDialogState<GitIdentityView> {
  @override
  GitSession get session => widget.session;
  final name = TextEditingController(), email = TextEditingController();
  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await load(const GitInspection(GitInspectionKind.commitOptions));
    if (mounted && data != null)
      setState(() {
        name.text = data!['name'] as String? ?? '';
        email.text = data!['email'] as String? ?? '';
      });
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      states(),
      TextField(
        controller: name,
        decoration: InputDecoration(
          labelText: gitString(context, GitMessages.commitAuthorName),
        ),
      ),
      TextField(
        controller: email,
        decoration: InputDecoration(
          labelText: gitString(context, GitMessages.commitAuthorEmail),
        ),
      ),
      Text(
        gitString(
          context,
          GitMessages.signingArg0Arg1,
          values: {
            'arg0':
                data?['signing'] ??
                gitString(context, GitMessages.configuredDefault),
            'arg1':
                data?['signingFormat'] ??
                gitString(context, GitMessages.openpgp),
          },
        ),
      ),
      SelectableText(
        gitString(
          context,
          GitMessages.configuredHooksArg0,
          values: {'arg0': (data?['hooks'] as List? ?? []).join(', ')},
        ),
      ),
      const GitLabel(GitMessages.aSignOffTrailerIsAStatementInTheMessage),
      FilledButton(
        onPressed: loading
            ? null
            : () async {
                final s = session.snapshot!;
                final result = await apply(
                  ConfigureIdentity(
                    name.text,
                    email.text,
                    expectedHead: s.head,
                    expectedIndex: s.indexToken,
                  ),
                );
                if (mounted && result?.completed == true)
                  Navigator.of(context).pop();
              },
        child: const GitLabel(GitMessages.saveRepositoryIdentity),
      ),
    ],
  );
}

final class GitChangeTree extends StatefulWidget {
  const GitChangeTree({
    super.key,
    required this.session,
    required this.onReview,
    this.selectedComparison,
    this.active = true,
    this.reviewContext,
  });
  final GitSession session;
  final ValueChanged<GitComparison> onReview;
  final GitComparison? selectedComparison;
  final bool active;
  final Object? Function()? reviewContext;
  @override
  State<GitChangeTree> createState() => _GitChangeTreeState();
}

final class _GitChangeTreeState extends State<GitChangeTree> {
  bool _preparingStage = false;
  final _collapsed = <String>{}, _selected = <String>{};
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'Git changes');
  final _contextMenuKeys = GitContextMenuKeys();
  List<_ChangeRow>? _cachedRows;
  Set<String> _rowKeys = {};
  String? _cachedKey;
  int _focused = 0, _anchor = 0;
  int _selectionGeneration = 0;
  @override
  void didUpdateWidget(GitChangeTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.selectedComparison;
    if (target == null || target == oldWidget.selectedComparison) return;
    _selectionGeneration++;
    final group = target.right.kind == ContentKind.indexVersion
        ? GitMessages.staged
        : widget.session.snapshot?.changes.any(
                (c) => c.path == target.path && c.untracked,
              ) ==
              true
        ? GitMessages.untracked
        : GitMessages.unstaged;
    _selected
      ..clear()
      ..add('$group:${target.path.key}');
    _collapsed.remove(group);
    var directory = '';
    for (final part in target.path.parent.split('/')) {
      if (part.isEmpty) continue;
      directory = directory.isEmpty ? part : '$directory/$part';
      _collapsed.remove('$group/$directory');
    }
    final index = _rows().indexWhere(
      (r) => r.key == '$group:${target.path.key}',
    );
    if (index >= 0) {
      _focused = _anchor = index;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _contextMenuKeys.clear();
    _focus.dispose();
    super.dispose();
  }

  List<_ChangeRow> _rows() {
    final collapsed = _collapsed.toList()..sort();
    final key = '${widget.session.snapshot?.token}:${collapsed.join('\u0000')}';
    if (_cachedKey == key && _cachedRows != null) return _cachedRows!;
    final rows = <_ChangeRow>[];
    final changes = widget.session.snapshot?.changes ?? [];
    final groups = {
      GitMessages.conflicts: changes.where((e) => e.conflicted),
      GitMessages.staged: changes.where((e) => e.staged),
      GitMessages.unstaged: changes.where((e) => e.unstaged),
      GitMessages.untracked: changes.where((e) => e.untracked),
    };
    for (final group in groups.entries) {
      final entries = group.value.toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (entries.isEmpty && group.key != GitMessages.staged) continue;
      rows.add(
        _ChangeRow(
          group.key,
          '${group.key} (${entries.length})',
          group.key,
          null,
          0,
          count: entries.length,
        ),
      );
      if (_collapsed.contains(group.key)) continue;
      final seenDirectories = <String>{};
      for (final change in entries) {
        var directory = '';
        var depth = 1;
        var hidden = false;
        for (final part in change.path.parent.split('/')) {
          if (part.isEmpty) continue;
          directory = directory.isEmpty ? part : '$directory/$part';
          final directoryKey = '${group.key}/$directory';
          if (!hidden && seenDirectories.add(directory)) {
            rows.add(
              _ChangeRow(
                directoryKey,
                part,
                group.key,
                null,
                depth,
                count: entries
                    .where(
                      (entry) => entry.path.display.startsWith('$directory/'),
                    )
                    .length,
              ),
            );
          }
          hidden = hidden || _collapsed.contains(directoryKey);
          depth++;
        }
        if (!hidden)
          rows.add(
            _ChangeRow(
              '${group.key}:${change.path.key}',
              change.path.basename,
              group.key,
              change,
              depth,
            ),
          );
      }
    }
    _cachedKey = key;
    _rowKeys = rows.map((r) => r.key).toSet();
    return _cachedRows = rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows(), host = widget.session.host;
    _selected.removeWhere((key) => !_rowKeys.contains(key));
    _focused = _focused.clamp(0, rows.isEmpty ? 0 : rows.length - 1);
    if (rows.length == 1 && rows.first.change == null)
      return const Center(child: GitLabel(GitMessages.noChanges));
    final parents = <int>[];
    final ancestors = <int>[];
    for (var i = 0; i < rows.length; i++) {
      while (ancestors.isNotEmpty &&
          rows[ancestors.last].depth >= rows[i].depth) {
        ancestors.removeLast();
      }
      parents.add(ancestors.lastOrNull ?? -1);
      if (rows[i].change == null) ancestors.add(i);
    }
    return LayoutBuilder(
      builder: (context, bounds) => GitNativeTable(
        name: gitString(context, GitMessages.repositoryChangeTree),
        description: widget.session.repository.root,
        revision: (widget.session.repository.key, _cachedKey),
        active: widget.active,
        tree: true,
        headers: false,
        busy: widget.session.running,
        rowCount: rows.length,
        columns: [gitString(context, GitMessages.changes)],
        widths: [bounds.maxWidth],
        rowHeight: host.rowHeight(context),
        rowAt: (index) {
          final row = rows[index], change = row.change;
          final canStage =
              change != null &&
              !change.conflicted &&
              !widget.session.running &&
              !_preparingStage &&
              widget.session.canWriteMetadata;
          return GitNativeRow(
            id: row.key,
            textInsets: [
              (Directionality.of(context) == TextDirection.rtl
                      ? host.spacing
                      : row.depth * host.spacing * 2) +
                  (change == null ? 16 : 22),
            ],
            cells: [
              change == null && row.depth == 0
                  ? gitString(
                      context,
                      GitMessages.groupCount,
                      values: {
                        'group': gitString(context, row.group),
                        'count': row.count,
                      },
                    )
                  : row.label,
            ],
            description: change == null
                ? ''
                : '${change.path.display}, ${gitString(context, row.group)}, '
                      '${change.index}${change.worktree}',
            parent: parents[index],
            depth: row.depth,
            expanded: change == null
                ? (_collapsed.contains(row.key) ? 0 : 1)
                : -1,
            actions: {
              if (change == null)
                'toggle': gitString(
                  context,
                  _collapsed.contains(row.key)
                      ? GitMessages.expand
                      : GitMessages.collapse,
                ),
              if (canStage)
                'stage': gitString(
                  context,
                  row.group == GitMessages.staged
                      ? GitMessages.unstageFile
                      : GitMessages.stageFile,
                ),
            },
          );
        },
        selected: [
          for (var i = 0; i < rows.length; i++)
            if (_selected.contains(rows[i].key)) i,
        ],
        focusedRow: rows.isEmpty ? -1 : _focused,
        scroll: _scroll,
        focus: _focus,
        onRequest: (request) => _nativeRequest(request, rows),
        builder: (nativeReady) => Focus(
          focusNode: _focus,
          onFocusChange: (focused) {
            if (!focused) _contextMenuKeys.clear();
          },
          onKeyEvent: (_, event) {
            final target = rows.isEmpty ? null : rows[_focused];
            final revision = _cachedKey, selection = _selectionGeneration;
            if (_contextMenuKeys.handle(
              event,
              target == null
                  ? null
                  : () {
                      if (!mounted) return;
                      final current = _rows();
                      if (widget.active &&
                          _focus.hasFocus &&
                          _cachedKey == revision &&
                          _selectionGeneration == selection &&
                          _focused < current.length &&
                          current[_focused].key == target.key) {
                        unawaited(_context(target, current));
                      }
                    },
            )) {
              return KeyEventResult.handled;
            }
            if (event is! KeyDownEvent || rows.isEmpty)
              return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.keyA &&
                HardwareKeyboard.instance.isControlPressed) {
              setState(() {
                _selected
                  ..clear()
                  ..addAll(
                    rows.where((r) => r.change != null).map((r) => r.key),
                  );
              });
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.home ||
                event.logicalKey == LogicalKeyboardKey.end) {
              _select(
                rows,
                event.logicalKey == LogicalKeyboardKey.home
                    ? 0
                    : rows.length - 1,
              );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              final row = rows[_focused],
                  expand = event.logicalKey == LogicalKeyboardKey.arrowRight;
              if (row.change == null) {
                setState(() {
                  if (expand) {
                    _collapsed.remove(row.key);
                  } else {
                    _collapsed.add(row.key);
                  }
                });
              } else if (!expand) {
                final parent = rows.lastIndexWhere(
                  (r) =>
                      r.change == null &&
                      r.group == row.group &&
                      r.depth < row.depth,
                  _focused,
                );
                if (parent >= 0) _select(rows, parent);
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _select(
                rows,
                (_focused +
                        (event.logicalKey == LogicalKeyboardKey.arrowDown
                            ? 1
                            : -1))
                    .clamp(0, rows.length - 1),
              );
              final offset = _focused * host.rowHeight(context);
              if (_scroll.hasClients)
                _scroll.animateTo(
                  offset.clamp(0, _scroll.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.linear,
                );
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              _activate(rows[_focused]);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.space &&
                rows[_focused].change != null) {
              unawaited(
                _stage(rows[_focused].group == GitMessages.staged, rows),
              );
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ExcludeFocus(
            // The native tree is one keyboard focus stop. Its existing row
            // keys and native cell actions cover review, staging and menus.
            excluding: nativeReady,
            child: ExcludeSemantics(
              excluding: nativeReady,
              child: CustomScrollView(
                controller: _scroll,
                semanticChildCount: rows.length,
                slivers: [
                  SliverSemantics(
                    role: SemanticsRole.list,
                    label: gitString(context, GitMessages.repositoryChangeTree),
                    container: true,
                    explicitChildNodes: true,
                    sliver: SliverFixedExtentList(
                      itemExtent: host.rowHeight(context),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final row = rows[index], change = row.change;
                          return Semantics(
                            role: SemanticsRole.listItem,
                            container: true,
                            expanded: change == null
                                ? !_collapsed.contains(row.key)
                                : null,
                            selected: _selected.contains(row.key),
                            label: change == null
                                ? row.depth == 0
                                      ? gitString(
                                          context,
                                          GitMessages.groupCount,
                                          values: {
                                            'group': gitString(
                                              context,
                                              row.group,
                                            ),
                                            'count': row.count,
                                          },
                                        )
                                      : row.label
                                : '${change.path.display}, ${gitString(context, row.group)}, ${change.index}${change.worktree}',
                            child: InkWell(
                              onTap: () {
                                _select(rows, index);
                                _activate(row);
                              },
                              onDoubleTap: change == null
                                  ? null
                                  : () => unawaited(
                                      host.openDocument(
                                        widget.session.repository,
                                        change.path,
                                      ),
                                    ),
                              onSecondaryTapUp: (details) {
                                if (!_selected.contains(row.key))
                                  _select(rows, index);
                                unawaited(
                                  _context(
                                    row,
                                    rows,
                                    position: details.globalPosition,
                                  ),
                                );
                              },
                              child: ColoredBox(
                                color: _selected.contains(row.key)
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : Colors.transparent,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: row.depth * host.spacing * 2,
                                    right: host.spacing,
                                  ),
                                  child: Row(
                                    children: [
                                      if (change == null)
                                        GitIcon(
                                          _collapsed.contains(row.key)
                                              ? GitGlyph.next
                                              : GitGlyph.expand,
                                          size: 16,
                                        )
                                      else
                                        SizedBox(
                                          width: 22,
                                          child: Text(
                                            change.conflicted
                                                ? '!'
                                                : change.untracked
                                                ? '?'
                                                : row.group ==
                                                      GitMessages.staged
                                                ? change.index
                                                : change.worktree,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ),
                                      Expanded(
                                        child: change == null && row.depth == 0
                                            ? GitLabel(
                                                GitMessages.groupCount,
                                                values: {
                                                  'group': gitString(
                                                    context,
                                                    row.group,
                                                  ),
                                                  'count': row.count,
                                                },
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              )
                                            : Text(
                                                row.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: change == null
                                                    ? const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      )
                                                    : null,
                                              ),
                                      ),
                                      if (row.group != GitMessages.conflicts &&
                                          (change == null ||
                                              !change.conflicted))
                                        GitIconButton(
                                          tooltip:
                                              row.group == GitMessages.staged
                                              ? gitString(
                                                  context,
                                                  change == null
                                                      ? GitMessages
                                                            .unstageSelectedFiles
                                                      : GitMessages.unstageFile,
                                                )
                                              : gitString(
                                                  context,
                                                  change == null
                                                      ? GitMessages
                                                            .stageSelectedFiles
                                                      : GitMessages.stageFile,
                                                ),
                                          onPressed:
                                              widget.session.running ||
                                                  _preparingStage ||
                                                  !widget
                                                      .session
                                                      .canWriteMetadata
                                              ? null
                                              : () {
                                                  if (!_selected.contains(
                                                    row.key,
                                                  ))
                                                    _select(rows, index);
                                                  unawaited(
                                                    _stage(
                                                      row.group ==
                                                          GitMessages.staged,
                                                      rows,
                                                    ),
                                                  );
                                                },
                                          icon: GitIcon(
                                            row.group == GitMessages.staged
                                                ? GitGlyph.remove
                                                : GitGlyph.add,
                                            size: 16,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: rows.length,
                        addSemanticIndexes: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _nativeRequest(GitNativeTableRequest request, List<_ChangeRow> rows) {
    final index = request.row;
    switch (request.action) {
      case 'clearSelection':
        setState(_selected.clear);
      case 'selectAll':
        setState(
          () => _selected.addAll(
            rows.where((r) => r.change != null).map((r) => r.key),
          ),
        );
      case 'select' || 'focus':
        _focus.requestFocus();
        _select(rows, index, keyboardModifiers: false);
        _scrollToNativeRow(index);
        if (rows[index].change != null) _activate(rows[index]);
      case 'scroll':
        _scrollToNativeRow(index);
      case 'context':
        if (!_selected.contains(rows[index].key)) {
          _select(rows, index, keyboardModifiers: false);
        }
        unawaited(_context(rows[index], rows));
      case 'addSelection':
        setState(() => _selected.add(rows[index].key));
      case 'removeSelection':
        setState(() => _selected.remove(rows[index].key));
      case 'toggle':
        _activate(rows[index]);
      case 'stage':
        // The named row action applies to exactly this file. Multi-selection
        // staging remains available in the existing contextual selection menu.
        unawaited(
          _stage(
            rows[index].group == GitMessages.staged,
            rows,
            selection: {rows[index].key},
          ),
        );
    }
  }

  void _scrollToNativeRow(int index) {
    if (!_scroll.hasClients) return;
    final height = widget.session.host.rowHeight(context);
    final start = index * height, end = start + height;
    final position = _scroll.position;
    if (start < position.pixels ||
        end > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(start.clamp(0, position.maxScrollExtent));
    }
  }

  void _select(
    List<_ChangeRow> rows,
    int index, {
    bool keyboardModifiers = true,
  }) {
    _focus.requestFocus();
    _selectionGeneration++;
    setState(() {
      _focused = index;
      if (keyboardModifiers && HardwareKeyboard.instance.isShiftPressed) {
        _selected.clear();
        for (
          var i = _anchor < index ? _anchor : index;
          i <= (_anchor > index ? _anchor : index);
          i++
        ) {
          if (rows[i].change != null) _selected.add(rows[i].key);
        }
      } else if (keyboardModifiers &&
          HardwareKeyboard.instance.isControlPressed) {
        if (!_selected.add(rows[index].key)) _selected.remove(rows[index].key);
      } else {
        _selected
          ..clear()
          ..add(rows[index].key);
        _anchor = index;
      }
    });
  }

  void _activate(_ChangeRow row) {
    if (row.change == null) {
      setState(() {
        if (!_collapsed.add(row.key)) _collapsed.remove(row.key);
      });
      return;
    }
    final snapshot = widget.session.snapshot!;
    if (row.change!.conflicted) {
      unawaited(
        GitWorkflowUi(context, widget.session).conflict(row.change!.path),
      );
      return;
    }
    widget.onReview(
      gitStatusComparison(
        snapshot,
        row.change!,
        staged: row.group == GitMessages.staged,
      ),
    );
  }

  Future<void> _stage(
    bool unstage,
    List<_ChangeRow> rows, {
    GitSnapshot? reviewed,
    Set<String>? selection,
  }) async {
    if (_preparingStage ||
        widget.session.running ||
        !widget.session.canWriteMetadata)
      return;
    final snapshot = reviewed ?? widget.session.snapshot!,
        keys = selection ?? _selected;
    // Expand a selected folder or group against the reviewed snapshot, not
    // against only the currently expanded/visible rows. The mutation still
    // carries the snapshot and per-path content preconditions below.
    final chosen = <_ChangeRow>[];
    for (final group in [
      GitMessages.staged,
      GitMessages.unstaged,
      GitMessages.untracked,
    ]) {
      if (unstage != (group == GitMessages.staged)) continue;
      for (final change in snapshot.changes) {
        if (change.conflicted || change.directory) continue;
        if ((group == GitMessages.staged && !change.staged) ||
            (group == GitMessages.unstaged && !change.unstaged) ||
            (group == GitMessages.untracked && !change.untracked))
          continue;
        final path = change.path.display;
        final selected =
            keys.contains('$group:${change.path.key}') ||
            keys.contains(group) ||
            keys.any(
              (key) =>
                  key.startsWith('$group/') &&
                  path.startsWith('${key.substring(group.length + 1)}/'),
            );
        if (selected) {
          chosen.add(
            _ChangeRow(
              '$group:${change.path.key}',
              change.path.basename,
              group,
              change,
              change.path.parent.isEmpty ? 1 : 2,
            ),
          );
        }
      }
    }
    final paths = {
      for (final row in chosen) ...[
        row.change!.path,
        if (unstage &&
            row.change!.index == 'R' &&
            row.change!.originalPath != null)
          row.change!.originalPath!,
      ],
    }.toList();
    if (paths.isEmpty) return;
    final selectionGeneration = _selectionGeneration;
    final reviewContext = widget.reviewContext?.call();
    setState(() => _preparingStage = true);
    try {
      final tokens = <String, String>{};
      if (!unstage)
        for (final path in paths) {
          final content = await widget.session.client.content(
            widget.session.repository,
            path,
            const ContentVersion.working(),
          );
          tokens[path.key] = content.token;
        }
      if (!mounted) return;
      final result = await widget.session.mutate(
        StagePaths(
          paths,
          expectedHead: snapshot.head,
          expectedIndex: snapshot.indexToken,
          unstage: unstage,
          contentTokens: tokens,
          expectedSnapshot: snapshot.token,
        ),
      );
      if (mounted &&
          result?.completed == true &&
          widget.active &&
          selectionGeneration == _selectionGeneration &&
          reviewContext == widget.reviewContext?.call()) {
        final refreshed = _rows(),
            chosenKeys = chosen.map((r) => r.key).toSet();
        final retained = chosenKeys.intersection(_rowKeys);
        var focused = refreshed.indexWhere((r) => retained.contains(r.key));
        if (focused < 0)
          focused = refreshed.indexWhere(
            (r) => r.change != null && paths.contains(r.change!.path),
          );
        if (focused < 0 && refreshed.any((r) => r.change != null)) {
          focused = _focused.clamp(0, refreshed.length - 1);
          while (focused < refreshed.length &&
              refreshed[focused].change == null) {
            focused++;
          }
          if (focused == refreshed.length)
            focused = refreshed.lastIndexWhere((r) => r.change != null);
        }
        if (focused >= 0) {
          setState(() {
            _focused = _anchor = focused;
            _selected
              ..clear()
              ..addAll(retained.isEmpty ? {refreshed[focused].key} : retained);
          });
          _activate(refreshed[focused]);
        }
      }
    } on Object catch (error) {
      widget.session.reportFailure(error);
    } finally {
      if (mounted) setState(() => _preparingStage = false);
    }
  }

  Future<void> _context(
    _ChangeRow row,
    List<_ChangeRow> rows, {
    Offset? position,
  }) async {
    final session = widget.session, reviewed = widget.session.snapshot!;
    final selection = Set<String>.from(_selected), change = row.change;
    final writable = !session.running && session.canWriteMetadata;
    final action = await session.host.menu(
      context,
      row.label,
      [
        GitMenuEntry(
          'review',
          change == null
              ? _collapsed.contains(row.key)
                    ? GitMessages.expandGroup
                    : GitMessages.collapseGroup
              : GitMessages.reviewDifference,
        ),
        if (row.group != GitMessages.conflicts &&
            (change == null || !change.conflicted))
          GitMenuEntry(
            'stage',
            row.group == GitMessages.staged
                ? GitMessages.unstageSelectedFiles
                : GitMessages.stageSelectedFiles,
            enabled: writable,
          ),
        if (change != null && reviewed.head != null)
          const GitMenuEntry('history', GitMessages.fileHistoryAndBlame),
        if (change != null &&
            row.group != GitMessages.staged &&
            !change.conflicted)
          GitMenuEntry(
            'discard',
            change.untracked
                ? GitMessages.deleteUntrackedFile
                : GitMessages.discardUnstagedChange,
            enabled: writable,
            sectionStart: true,
          ),
      ],
      position: position,
      localizeTitle: false,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'review':
        _activate(row);
      case 'stage':
        await _stage(
          row.group == GitMessages.staged,
          rows,
          reviewed: reviewed,
          selection: selection,
        );
      case 'history':
        await GitWorkflowUi(context, session).present(
          GitMessages.fileHistory,
          GitFileHistoryView(session: session, path: change!.path),
          expanded: true,
        );
      case 'discard':
        GitContent working;
        try {
          working = await session.client.content(
            session.repository,
            change!.path,
            const ContentVersion.working(),
          );
        } on Object catch (error) {
          session.reportFailure(error);
          return;
        }
        if (!mounted ||
            !await gitConfirm(
              context,
              session,
              gitString(
                context,
                GitMessages.discardUnstagedArg0,
                values: {'arg0': change.path.display},
              ),
              gitString(
                context,
                GitMessages.arg0BytesArg1ReplacesWorkingContentWithTheIndexOr,
                values: {
                  'arg0': working.size,
                  'arg1': gitEnumLabel(context, working.availability),
                },
              ),
              action: change.untracked
                  ? GitMessages.deleteUntrackedFile2
                  : GitMessages.discardWorkingChange,
            ))
          return;
        await session.mutate(
          RestorePaths(
            [change.path],
            discardUntracked: change.untracked,
            expectedHead: reviewed.head,
            expectedIndex: reviewed.indexToken,
            contentTokens: {change.path.key: working.token},
          ),
        );
    }
  }
}

GitComparison gitStatusComparison(
  GitSnapshot snapshot,
  GitChange change, {
  required bool staged,
}) => GitComparison(
  change.path,
  staged
      ? snapshot.head == null
            ? const ContentVersion.absent()
            : ContentVersion(ContentKind.commit, revision: snapshot.head)
      : const ContentVersion.index(),
  staged ? const ContentVersion.index() : const ContentVersion.working(),
  leftPath: staged
      ? change.originalPath
      : change.worktree == 'R'
      ? change.originalPath
      : null,
);

List<GitComparison> gitStatusComparisons(GitSnapshot? snapshot) {
  if (snapshot == null) return const [];
  final files =
      snapshot.changes.where((c) => !c.conflicted && !c.directory).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files.where((c) => c.staged))
      gitStatusComparison(snapshot, file, staged: true),
    for (final file in files.where((c) => c.unstaged || c.untracked))
      gitStatusComparison(snapshot, file, staged: false),
  ];
}

int gitComparisonIndex(
  List<GitComparison> comparisons,
  GitComparison? selected,
) => comparisons.indexWhere(
  (c) =>
      c.path == selected?.path &&
      c.left.kind == selected?.left.kind &&
      c.right.kind == selected?.right.kind,
);

final class _ChangeRow {
  const _ChangeRow(
    this.key,
    this.label,
    this.group,
    this.change,
    this.depth, {
    this.count = 0,
  });
  final String key, label, group;
  final int count;
  final GitChange? change;
  final int depth;
}
