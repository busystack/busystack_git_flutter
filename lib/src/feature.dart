import 'dart:math' as math;
import 'dart:convert';

import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/widgets.dart';

import 'commit_view.dart';
import 'linux_native.dart' show GitSpacing, GitSizes, NativeGitSurface;
import 'diff_view.dart';
import 'host.dart';
import 'log_view.dart';
import 'messages.dart';
import 'presentation.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'value_labels.dart';
import 'reference_context_menu.dart';
import 'package:flutter/material.dart' show MaterialLocalizations;

enum GitSidebarView { commit, log }

/// Captured endpoints and navigation belong to a tab, never to the sidebar.
/// Mutable reviews include the exact snapshot token; historical endpoints
/// include the selected merge parent and both actual paths.
final class GitReview {
  const GitReview(
    this.repository, {
    required this.comparison,
    this.reviewToken,
    this.reviewedFiles = const [],
  });
  final RepositoryId repository;
  final GitComparison comparison;
  final String? reviewToken;
  final List<GitComparison> reviewedFiles;

  bool get historical => comparison.right.kind == ContentKind.commit;
  String get id => jsonEncode([
    repository.key,
    (comparison.leftPath ?? comparison.path).toJson(),
    comparison.path.toJson(),
    comparison.left.toJson(),
    comparison.right.toJson(),
    if (!historical) reviewToken,
  ]);

  String title(BuildContext context) =>
      '${comparison.path.display} · ${gitVersionLabel(context, comparison.left)} → ${gitVersionLabel(context, comparison.right)}';

  GitReview? adjacent(int direction) {
    final index = gitComparisonIndex(reviewedFiles, comparison);
    final next = index + direction;
    if (index < 0 || next < 0 || next >= reviewedFiles.length) return null;
    return GitReview(
      repository,
      comparison: reviewedFiles[next],
      reviewToken: reviewToken,
      reviewedFiles: reviewedFiles,
    );
  }
}

/// Pure tab transitions also serve hosts with an existing document-tab store.
/// The host owns dismissal permission; closing here cannot discard an editor.
final class GitReviewTabs {
  const GitReviewTabs({this.entries = const [], this.activeId});
  final List<GitReview> entries;
  final String? activeId;
  GitReview? get active =>
      entries.where((entry) => entry.id == activeId).firstOrNull;

  GitReviewTabs open(GitReview review) => GitReviewTabs(
    entries: List.unmodifiable([
      ...entries,
      if (!entries.any((entry) => entry.id == review.id)) review,
    ]),
    activeId: review.id,
  );
  GitReviewTabs activate(String id) => entries.any((entry) => entry.id == id)
      ? GitReviewTabs(entries: entries, activeId: id)
      : this;
  GitReviewTabs deactivate() => GitReviewTabs(entries: entries);
  GitReviewTabs close(String id) {
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return this;
    final remaining = List<GitReview>.of(entries)..removeAt(index);
    return GitReviewTabs(
      entries: List.unmodifiable(remaining),
      activeId: activeId != id
          ? activeId
          : remaining.isEmpty
          ? null
          : remaining[(index - 1).clamp(0, remaining.length - 1)].id,
    );
  }
}

/// One coordinator per GitSession. Preferences use the session's existing
/// worktree storage. No alternate repository state or Git execution path.
final class GitFeatureController extends ChangeNotifier {
  GitFeatureController(this.session);
  final GitSession session;
  GitReviewTabs _tabs = const GitReviewTabs();
  GitReviewTabs get tabs => _tabs;
  int _generation = 0;
  int get generation => _generation;
  GitSidebarView get view => session.option('featureLog', false)
      ? GitSidebarView.log
      : GitSidebarView.commit;

  bool get sidebarVisible => session.option('featureSidebarVisible', true);
  void toggleSidebar() {
    session.setViewState('featureSidebarVisible', !sidebarVisible);
    _generation++;
    notifyListeners();
  }

  void select(GitSidebarView value) {
    if (value == view) return;
    session.setViewState('featureLog', value == GitSidebarView.log);
    _generation++;
    notifyListeners();
  }

  GitReview capture(GitComparison comparison, [List<GitComparison>? files]) =>
      GitReview(
        session.repository,
        comparison: comparison,
        reviewToken: session.snapshot?.token,
        reviewedFiles: List.unmodifiable(
          files ?? gitStatusComparisons(session.snapshot),
        ),
      );

  void open(GitReview review) {
    if (session.isDisposed) return;
    if (review.repository != session.repository) {
      throw ArgumentError('A Git review belongs to its captured worktree.');
    }
    _tabs = _tabs.open(review);
    _generation++;
    notifyListeners();
    session.host.mountReview?.call(_tabs.active!);
  }

  /// Reconcile a host document strip's lifetime/selection with this session.
  /// Git identities and transitions remain the shared GitReviewTabs model.
  void synchronizeHostTabs(GitReviewTabs tabs) {
    final entries = tabs.entries
        .where((review) => review.repository == session.repository)
        .toList(growable: false);
    final activeId = entries.any((entry) => entry.id == tabs.activeId)
        ? tabs.activeId
        : null;
    if (_tabs.activeId == activeId &&
        _tabs.entries.length == entries.length &&
        Iterable.generate(
          entries.length,
        ).every((i) => identical(entries[i], _tabs.entries[i])))
      return;
    _tabs = GitReviewTabs(
      entries: List.unmodifiable(entries),
      activeId: activeId,
    );
    _generation++;
    notifyListeners();
  }

  void activate(String id) {
    _tabs = _tabs.activate(id);
    _generation++;
    notifyListeners();
  }

  void closeEntries(Iterable<String> ids) {
    for (final id in ids) {
      _tabs = _tabs.close(id);
    }
    _generation++;
    notifyListeners();
  }

  void close(String id) {
    _tabs = _tabs.close(id);
    _generation++;
    notifyListeners();
  }
}

/// Ordinary workflow comparisons leave their own selection surface and open
/// the captured review in the canonical content-tab mount. Never pop a newer
/// unrelated surface or replace an existing review's endpoints.
void gitOpenComparison(
  BuildContext context,
  GitSession session,
  GitComparison comparison, {
  List<GitComparison>? files,
  bool closeSurface = true,
}) {
  if (!context.mounted ||
      session.isDisposed ||
      ModalRoute.of(context)?.isActive == false)
    return;
  final review = session.feature.capture(comparison, files ?? [comparison]);
  if (closeSurface && !gitCompleteReviewSelections(context)) return;
  session.feature.open(review);
}

/// Canonical Commit/Log composition. Host arguments describe document focus,
/// trust and tab mounting; no host supplies a Git layout or workflow tree.
final class GitFeatureSidebar extends StatefulWidget {
  const GitFeatureSidebar({
    super.key,
    required this.controller,
    required this.onReview,
    required this.view,
    required this.onSelectView,
    this.active = true,
    this.trusted = true,
    this.onTrust,
    this.selectedComparison,
    this.reviewContext,
    this.destinations = const [],
  });
  final List<GitSidebarDestination> destinations;
  final GitFeatureController controller;
  final GitSidebarView view;
  final ValueChanged<GitSidebarView> onSelectView;
  final ValueChanged<GitReview> onReview;
  final bool active, trusted;
  final VoidCallback? onTrust;
  final GitComparison? selectedComparison;
  final Object? Function()? reviewContext;

  @override
  State<GitFeatureSidebar> createState() => _GitFeatureSidebarState();
}

final class _GitFeatureSidebarState extends State<GitFeatureSidebar> {
  bool _logVisited = false;
  @override
  void didUpdateWidget(GitFeatureSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _logVisited = false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller, session = controller.session;
    final generation = controller.generation;
    bool current() =>
        mounted &&
        widget.active &&
        identical(widget.controller, controller) &&
        controller.generation == generation;
    final log = widget.view == GitSidebarView.log;
    _logVisited |= log;
    return GitHostScope(
      host: session.host,
      child: ColoredBox(
        color: NativeGitSurface.of(context).sidebar,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GitFeatureHeader(
              repository: session.repository,
              view: widget.view,
              onSelectView: (view) {
                if (!current()) return;
                controller.select(view);
                widget.onSelectView(view);
              },
              destinations: [
                for (final destination in widget.destinations)
                  GitSidebarDestination(
                    id: destination.id,
                    label: destination.label,
                    onSelect: () {
                      if (current()) destination.onSelect();
                    },
                  ),
              ],
            ),
            Expanded(
              child: IndexedStack(
                index: log ? 1 : 0,
                children: [
                  ExcludeFocus(
                    excluding: !widget.active || log,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Visibility(
                          visible: widget.trusted,
                          maintainState: true,
                          child: GitCommitView(
                            key: ObjectKey(session),
                            session: session,
                            active: widget.active && !log && widget.trusted,
                            protectMessageDrafts: false,
                            selectedComparison: widget.selectedComparison,
                            reviewContext:
                                widget.reviewContext ??
                                () => controller.generation,
                            onReview: (comparison) =>
                                widget.onReview(controller.capture(comparison)),
                            onLog: () {
                              controller.select(GitSidebarView.log);
                              widget.onSelectView(GitSidebarView.log);
                            },
                            onBranches: () =>
                                GitWorkflowUi(context, session).branches(),
                            onPush: () =>
                                GitWorkflowUi(context, session).push(),
                            onMore: (anchor) =>
                                GitWorkflowUi(anchor, session).more(
                                  showBranches: false,
                                  includeRefresh: true,
                                  showBranchOperations: false,
                                ),
                          ),
                        ),
                        if (!widget.trusted)
                          Positioned.fill(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    gitString(
                                      context,
                                      GitMessages.operationsRequireTrust,
                                    ),
                                    style: GitTheme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 16),
                                  GitButton.primary(
                                    onPressed: widget.onTrust,
                                    child: const GitLabel(
                                      GitMessages.trustWorkspace,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_logVisited)
                    ExcludeFocus(
                      excluding: !widget.active || !log,
                      child: FocusTraversalGroup(
                        policy: WidgetOrderTraversalPolicy(),
                        child: GitLogView(
                          key: ObjectKey(session),
                          session: session,
                          inspector: true,
                          active: widget.active && log,
                          onReview: (comparison, files) => widget.onReview(
                            controller.capture(comparison, files),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Both document hosts and dedicated Git content slots use this exact view.
final class GitReviewSurface extends StatelessWidget {
  const GitReviewSurface({
    super.key,
    required this.session,
    required this.review,
    required this.isActive,
    required this.onOpen,
  });
  final GitSession session;
  final GitReview review;
  final bool Function() isActive;
  final ValueChanged<GitReview> onOpen;

  VoidCallback? _navigate(BuildContext context, int direction) {
    final next = review.adjacent(direction);
    return next == null
        ? null
        : () {
            if (context.mounted && isActive()) onOpen(next);
          };
  }

  @override
  Widget build(BuildContext context) => GitDiffView(
    session: session,
    comparison: review.comparison,
    initialReviewToken: review.historical ? null : review.reviewToken,
    initialSideBySide: true,
    showFileHeader: false,
    onPreviousFile: _navigate(context, -1),
    onNextFile: _navigate(context, 1),
  );
}

/// Reusable content slot for hosts without an existing document-tab strip.
/// Retained keyed surfaces keep each captured review's scroll/search/selection.
final class GitReviewContent extends StatelessWidget {
  const GitReviewContent({super.key, required this.controller, this.mayClose});
  final GitFeatureController controller;
  final Future<bool> Function()? mayClose;
  @override
  Widget build(BuildContext context) => GitHostScope(
    host: controller.session.host,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        children: [
          GitReviewTabStrip(controller: controller, mayClose: mayClose),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller.tabs.entries.isEmpty)
                  const Center(
                    child: GitLabel(GitMessages.selectAChangeToReview),
                  ),
                for (final entry in controller.tabs.entries)
                  Offstage(
                    key: ValueKey(entry.id),
                    offstage: controller.tabs.activeId != entry.id,
                    child: ExcludeFocus(
                      excluding: controller.tabs.activeId != entry.id,
                      child: GitReviewSurface(
                        session: controller.session,
                        review: entry,
                        isActive: () =>
                            controller.tabs.activeId == entry.id &&
                            controller.tabs.entries.contains(entry),
                        onOpen: controller.open,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Host navigation is data and callbacks; Git controls and choices are shared.
final class GitSidebarDestination {
  const GitSidebarDestination({
    required this.id,
    required this.label,
    required this.onSelect,
  });
  final String id, label;
  final VoidCallback onSelect;
}

final class GitFeatureHeader extends StatelessWidget {
  const GitFeatureHeader({
    super.key,
    required this.repository,
    required this.view,
    required this.onSelectView,
    this.destinations = const [],
  });
  final RepositoryId repository;
  final GitSidebarView view;
  final ValueChanged<GitSidebarView> onSelectView;
  final List<GitSidebarDestination> destinations;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(
      GitSpacing.mdPlus,
      GitSpacing.sm,
      GitSpacing.sm,
      GitSpacing.sm,
    ),
    child: SizedBox(
      height: GitSizes.iconButton,
      child: Row(
        children: [
          const GitIcon(GitGlyph.repository, size: GitSizes.iconSm),
          const SizedBox(width: GitSpacing.sm),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: GitTooltip(
                message: repository.root,
                child: Text(
                  repository.root
                          .split(RegExp(r'[/\\]'))
                          .where((part) => part.isNotEmpty)
                          .lastOrNull ??
                      repository.root,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GitTheme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(width: GitSpacing.sm),
          GitSidebarSelector(
            view: view,
            onChanged: onSelectView,
            destinations: destinations,
          ),
        ],
      ),
    ),
  );
}

/// The same checked native menu is used in each host's main sidebar slot.
final class GitSidebarSelector extends StatelessWidget {
  const GitSidebarSelector({
    super.key,
    required this.view,
    required this.onChanged,
    this.destinations = const [],
  });
  final GitSidebarView view;
  final ValueChanged<GitSidebarView> onChanged;
  final List<GitSidebarDestination> destinations;
  @override
  Widget build(BuildContext context) => GitButton(
    compact: true,
    onPressed: () async {
      final action = await GitHostScope.of(context)!
          .menu(context, GitMessages.git, [
            for (final destination in destinations)
              GitMenuEntry(destination.id, destination.label, localize: false),
            GitMenuEntry(
              'commit',
              GitMessages.commit,
              checked: view == GitSidebarView.commit,
              radio: true,
              sectionStart: destinations.isNotEmpty,
            ),
            GitMenuEntry(
              'log',
              GitMessages.gitLog,
              checked: view == GitSidebarView.log,
              radio: true,
            ),
          ]);
      if (!context.mounted || action == null) return;
      if (action == 'commit' || action == 'log') {
        onChanged(action == 'log' ? GitSidebarView.log : GitSidebarView.commit);
      } else {
        destinations
            .where((entry) => entry.id == action)
            .firstOrNull
            ?.onSelect();
      }
    },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GitLabel(
          view == GitSidebarView.log ? GitMessages.gitLog : GitMessages.commit,
        ),
        const SizedBox(width: GitSpacing.sm),
        const GitIcon(GitGlyph.down, size: 16),
      ],
    ),
  );
}

/// Measure the two required native footer actions once, in the actual locale,
/// font and text scale. Hosts use this same minimum for their sidebar slot.
double gitSidebarMinimumWidth(
  BuildContext context, {
  GitPresentation? presentation,
  String? commitLabel,
  String? commitAndPushLabel,
}) {
  final native = presentation ?? gitPresentation(context);
  return math
      .max(
        300,
        native.buttonWidth(
              context,
              commitLabel ?? gitString(context, GitMessages.commit),
              GitActionStyle.suggested,
            ) +
            native.buttonWidth(
              context,
              commitAndPushLabel ??
                  gitString(context, GitMessages.commitAndPush),
              GitActionStyle.standard,
            ) +
            GitSpacing.sm * 3,
      )
      .ceilToDouble();
}

/// Shared natural form and footer spacing for host authorization services.
/// The host supplies policy text and decisions, never a second dialog grid.
final class GitDialogForm extends StatelessWidget {
  const GitDialogForm({super.key, required this.body, this.actions = const []});
  final Widget body;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      body,
      if (actions.isNotEmpty) ...[
        const SizedBox(height: GitSpacing.lg),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: GitSpacing.sm,
          overflowSpacing: GitSpacing.sm,
          children: actions,
        ),
      ],
    ],
  );
}

/// Independent review tabs for content hosts without a document strip. All
/// endpoints, selection and dismissal transitions remain in the shared model.
final class GitReviewTabStrip extends StatelessWidget {
  const GitReviewTabStrip({
    super.key,
    required this.controller,
    required this.mayClose,
  });
  final GitFeatureController controller;
  final Future<bool> Function()? mayClose;
  Future<void> _close(BuildContext context, List<String> ids) async {
    final generation = controller.generation;
    if (mayClose == null ||
        !await mayClose!() ||
        !context.mounted ||
        controller.generation != generation)
      return;
    controller.closeEntries(ids);
  }

  Future<void> _menu(
    BuildContext context,
    GitReview entry,
    Offset position,
  ) async {
    final generation = controller.generation;
    final captured = controller.tabs.entries
        .map((entry) => entry.id)
        .toList(growable: false);
    final action = await controller.session.host.menu(
      context,
      entry.title(context),
      [
        GitMenuEntry(
          'close',
          MaterialLocalizations.of(context).closeButtonTooltip,
          localize: false,
        ),
        GitMenuEntry(
          'others',
          GitMessages.closeOtherTabs,
          enabled: captured.length > 1,
        ),
        GitMenuEntry('all', GitMessages.closeAllTabs),
      ],
      position: position,
      localizeTitle: false,
    );
    if (!context.mounted ||
        generation != controller.generation ||
        action == null)
      return;
    await _close(context, switch (action) {
      'close' => [entry.id],
      'others' => captured.where((id) => id != entry.id).toList(),
      'all' => captured,
      _ => const [],
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.max(
      GitSizes.toolbarHeight,
      controller.session.host.rowHeight(context) + GitSpacing.sm,
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in controller.tabs.entries)
            GitReferenceContextMenu(
              key: ValueKey('git-review-tab:${entry.id}'),
              open: (position) => _menu(context, entry, position),
              child: GestureDetector(
                onSecondaryTapUp: (details) =>
                    _menu(context, entry, details.globalPosition),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GitTooltip(
                      message: entry.title(context),
                      child: GitButton(
                        onPressed: () => controller.activate(entry.id),
                        child: Text(
                          entry.title(context),
                          style: TextStyle(
                            fontWeight: controller.tabs.activeId == entry.id
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                      ),
                    ),
                    GitIconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => _close(context, [entry.id]),
                      icon: const GitIcon(GitGlyph.close),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
