import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'diff_view.dart';
import 'branch_views.dart';
import 'host.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'organization_views.dart';

// Remote names may themselves contain '/'. Attribute cached tracking refs to
// the longest configured remote prefix before offering operation candidates.
String? _trackedBranchName(
  GitReference reference,
  String remote,
  Iterable<String> remotes,
) {
  final owners =
      remotes
          .where((name) => reference.name.startsWith('refs/remotes/$name/'))
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  if (owners.firstOrNull != remote) return null;
  final name = reference.name.substring('refs/remotes/$remote/'.length);
  return name == 'HEAD' ? null : name;
}

final class GitDeleteRemoteView extends StatefulWidget {
  const GitDeleteRemoteView({
    super.key,
    required this.session,
    required this.remote,
    required this.reference,
  });
  final GitSession session;
  final String remote, reference;
  @override
  State<GitDeleteRemoteView> createState() => _DeleteRemoteState();
}

final class _DeleteRemoteState extends GitDialogState<GitDeleteRemoteView> {
  @override
  GitSession get session => widget.session;
  late final GitSnapshot reviewed;
  bool completed = false;
  @override
  void initState() {
    super.initState();
    reviewed = session.snapshot!;
    unawaited(refresh());
  }

  Future<void> refresh() => load(
    GitInspection(
      GitInspectionKind.pushReview,
      remote: widget.remote,
      destination: widget.reference,
      revision: reviewed.head,
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      states(refresh: () => unawaited(refresh())),
      Text(
        gitString(
          context,
          GitMessages.deleteREMOTEReferenceArg0,
          values: {'arg0': widget.reference},
        ),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const GitLabel(
        GitMessages.thisRemovesTheReferenceOnEveryActualPushDestinationListed,
      ),
      for (final destination
          in (data?['destinations'] as List? ?? []).cast<Json>())
        GitSelectableText(
          gitString(
            context,
            GitMessages.arg0ExpectedTipArg1,
            values: {
              'arg0': destination['url'],
              'arg1':
                  destination['expectedTip'] ??
                  gitString(context, GitMessages.referenceDoesNotExist),
            },
          ),
        ),
      if (completed) const GitLabel(GitMessages.remoteDeletionCompleted),
      const SizedBox(height: 12),
      FilledButton(
        onPressed:
            completed ||
                loading ||
                data?['token'] == null ||
                (data!['destinations'] as List).any(
                  (e) => (e as Map)['expectedTip'] == null,
                )
            ? null
            : () async {
                final plan = data!;
                if (!await gitConfirm(
                  context,
                  session,
                  gitString(
                    context,
                    GitMessages.deleteArg0FromTheRemote,
                    values: {'arg0': widget.reference},
                  ),
                  GitMessages.theExactDestinationTipsShownAboveWillBeRemovedAny,
                  action: GitMessages.deleteRemoteReference,
                ))
                  return;
                final result = await apply(
                  DeleteRemoteReference(
                    plan['token'] as String,
                    expectedHead: reviewed.head,
                    expectedIndex: reviewed.indexToken,
                  ),
                );
                if (mounted)
                  setState(() {
                    completed = result?.completed == true;
                    data = null;
                  });
              },
        child: const GitLabel(GitMessages.reviewAndDeleteFromRemote),
      ),
    ],
  );
}

final class GitPushView extends StatefulWidget {
  const GitPushView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitPushView> createState() => _PushState();
}

final class _PushState extends GitDialogState<GitPushView> {
  @override
  GitSession get session => widget.session;
  final destination = TextEditingController();
  final branchName = TextEditingController();
  late GitSnapshot reviewed;
  List<Json> remotes = [];
  List<GitReference> tags = [];
  List<GitReference> remoteBranches = [];
  String destinationChoice = '__new__';
  final selectedTags = <String>{};
  String? remote;
  bool upstream = false, completed = false;
  bool _initializing = true, _configured = false;
  int _configurationGeneration = 0, _reviewGeneration = 0;
  bool get _busy => loading || _initializing || session.running;
  GitCommit? selected;
  @override
  void initState() {
    super.initState();
    reviewed = session.snapshot!;
    destination.text = 'refs/heads/${reviewed.branch ?? ''}';
    branchName.text = reviewed.branch ?? '';
    unawaited(initialize());
  }

  @override
  void dispose() {
    _configurationGeneration++;
    _reviewGeneration++;
    destination.dispose();
    branchName.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    final current = ++_configurationGeneration;
    _reviewGeneration++;
    setState(() {
      _initializing = true;
      data = null;
      selected = null;
    });
    try {
      await load(const GitInspection(GitInspectionKind.remotes));
      if (!mounted || current != _configurationGeneration || error != null)
        return;
      final configuredRemotes = (data?['remotes'] as List? ?? []).cast<Json>();
      final refs = await query(
        () => session.client.references(session.repository),
      );
      final options = await query(
        () => workflows.inspect(
          session.repository,
          const GitInspection(GitInspectionKind.commitOptions),
        ),
      );
      if (!mounted ||
          current != _configurationGeneration ||
          refs == null ||
          options == null)
        return;
      setState(() {
        remotes = configuredRemotes;
        final configured = options['pushRemote'] as String?;
        final previousRemote = remote;
        remote =
            previousRemote != null &&
                remotes.any((entry) => entry['name'] == previousRemote)
            ? previousRemote
            : configured == null
            ? (remotes.length == 1 ? remotes.single['name'] as String : null)
            : remotes.any((entry) => entry['name'] == configured)
            ? configured
            : null;
        final tracking = options['upstreamBranch'] as String?;
        if (!_configured &&
            remote == options['upstreamRemote'] &&
            tracking?.startsWith('refs/heads/') == true) {
          destination.text = tracking!;
        }
        tags = refs
            .where((entry) => entry.name.startsWith('refs/tags/'))
            .toList();
        remoteBranches = refs
            .where((entry) => entry.name.startsWith('refs/remotes/'))
            .toList();
        destinationChoice = _existingDestinations().contains(destination.text)
            ? destination.text
            : '__new__';
        if (destinationChoice == '__new__' &&
            destination.text.startsWith('refs/heads/')) {
          branchName.text = destination.text.substring('refs/heads/'.length);
        }
        if (!_configured)
          upstream = reviewed.upstream == null && reviewed.branch != null;
        _configured = true;
        data = null;
      });
    } finally {
      if (mounted && current == _configurationGeneration)
        setState(() => _initializing = false);
    }
    if (mounted &&
        current == _configurationGeneration &&
        remote != null &&
        error == null)
      await preview();
  }

  void invalidate() {
    _reviewGeneration++;
    generation++;
    cancellation?.cancel();
    setState(() {
      data = null;
      error = null;
      selected = null;
      completed = false;
      loading = false;
    });
  }

  List<String> _existingDestinations() {
    final selectedRemote = remote;
    if (selectedRemote == null) return const [];
    final names = remotes.map((entry) => entry['name'] as String);
    return [
      for (final ref in remoteBranches)
        if (_trackedBranchName(ref, selectedRemote, names)
            case final String branch)
          'refs/heads/$branch',
    ]..sort();
  }

  bool _currentReview(
    int current,
    String? source,
    String target,
    List<String> tags,
  ) =>
      mounted &&
      current == _reviewGeneration &&
      source == remote &&
      target == destination.text &&
      tags.length == selectedTags.length &&
      tags.every(selectedTags.contains);

  Future<void> preview() async {
    if (!mounted || _initializing || session.running) return;
    final current = ++_reviewGeneration;
    final source = remote,
        target = destination.text,
        tagsToReview = selectedTags.toList();
    generation++;
    cancellation?.cancel();
    setState(() {
      data = null;
      selected = null;
      error = null;
      loading = true;
      completed = false;
    });
    try {
      final snapshot = await session.readStatus();
      if (!_currentReview(current, source, target, tagsToReview)) return;
      reviewed = snapshot;
      await load(
        GitInspection(
          GitInspectionKind.pushReview,
          remote: source,
          destination: target,
          revision: snapshot.head,
          tags: tagsToReview,
        ),
      );
      if (!_currentReview(current, source, target, tagsToReview)) return;
      final outgoing = (data?['outgoing'] as List? ?? []).cast<Json>();
      final commits = [
        for (final entry in outgoing)
          ...(entry['commits'] as List).cast<Json>(),
      ];
      if (commits.isNotEmpty)
        setState(() => selected = GitCommit.fromJson(commits.first));
    } on Object catch (failure) {
      if (_currentReview(current, source, target, tagsToReview))
        setState(
          () => error = failure is GitException
              ? failure
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$failure'),
                ),
        );
    } finally {
      if (mounted && current == _reviewGeneration)
        setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outgoing = (data?['outgoing'] as List? ?? []).cast<Json>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        states(refresh: preview),
        Wrap(
          spacing: session.host.spacing,
          runSpacing: session.host.spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${reviewed.branch ?? gitString(context, GitMessages.detachedHEAD)} · ${reviewed.head?.abbreviated ?? 'unborn'} →',
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                key: ValueKey(remote),
                initialValue: remote,
                decoration: InputDecoration(
                  labelText: gitString(context, GitMessages.remote),
                ),
                isExpanded: true,
                items: [
                  for (final entry in remotes)
                    DropdownMenuItem(
                      value: entry['name'] as String,
                      child: Text(entry['name'] as String),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (!mounted || _busy) return;
                        remote = value;
                        destinationChoice =
                            _existingDestinations().contains(destination.text)
                            ? destination.text
                            : '__new__';
                        invalidate();
                      },
              ),
            ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                key: ValueKey('$remote:$destinationChoice'),
                initialValue: destinationChoice,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: gitString(
                    context,
                    GitMessages.destinationReference,
                  ),
                ),
                items: [
                  for (final reference in _existingDestinations())
                    DropdownMenuItem(
                      value: reference,
                      child: Text(reference.substring('refs/heads/'.length)),
                    ),
                  DropdownMenuItem(
                    value: '__new__',
                    child: GitLabel(GitMessages.newRemoteBranch),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (_busy || value == null) return;
                        destinationChoice = value;
                        destination.text = value == '__new__'
                            ? 'refs/heads/${branchName.text}'
                            : value;
                        invalidate();
                      },
              ),
            ),
            if (destinationChoice == '__new__')
              SizedBox(
                width: 220,
                child: TextField(
                  controller: branchName,
                  decoration: InputDecoration(
                    labelText: gitString(context, GitMessages.newRemoteBranch),
                  ),
                  enabled: !_busy,
                  onChanged: (value) {
                    if (!mounted || _busy) return;
                    destination.text = 'refs/heads/$value';
                    invalidate();
                  },
                ),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!mounted || _busy) return;
                      await session.host.present<void>(
                        context,
                        GitMessages.manageRemotes,
                        GitRemotesView(session: session),
                        expanded: true,
                      );
                      if (mounted) await initialize();
                    },
              child: const GitLabel(GitMessages.manageRemotes),
            ),
            OutlinedButton(
              onPressed: _busy || remote == null || reviewed.head == null
                  ? null
                  : () => unawaited(preview()),
              child: const GitLabel(GitMessages.reviewDestinations),
            ),
          ],
        ),
        if (data?['destinations'] is List)
          Padding(
            padding: EdgeInsets.all(session.host.spacing),
            child: GitSelectableText(
              [
                for (final target
                    in (data!['destinations'] as List).cast<Json>())
                  gitString(
                    context,
                    GitMessages.arg0Arg1ExpectedArg2,
                    values: {
                      'arg0': target['url'],
                      'arg1': data!['destination'],
                      'arg2':
                          target['expectedTip'] ??
                          gitString(context, GitMessages.newRemoteBranch),
                    },
                  ),
              ].join('\n'),
            ),
          ),
        if (data?['needsFetch'] == true)
          MaterialBanner(
            content: const GitLabel(
              GitMessages
                  .aDestinationHasCommitsThatAreUnavailableLocallyFetchThat,
            ),
            actions: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final result = await apply(
                          FetchPushDestination(
                            data!['token'] as String,
                            expectedHead: reviewed.head,
                            expectedIndex: reviewed.indexToken,
                          ),
                        );
                        if (result?.completed == true) await preview();
                      },
                child: const GitLabel(GitMessages.fetchReviewedDestination),
              ),
            ],
          ),
        Expanded(
          child: data?['outgoing'] == null
              ? const Center(
                  child: GitLabel(
                    GitMessages.chooseADestinationAndReviewTheOutgoingCommits,
                  ),
                )
              : GitSplitter(
                  initial: .42,
                  minimum: 240,
                  first: ListView(
                    children: [
                      for (final entry in outgoing) ...[
                        Padding(
                          padding: EdgeInsets.all(session.host.spacing),
                          child: Text(
                            entry['destination'] as String,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        if ((entry['commits'] as List).isEmpty)
                          const ListTile(
                            title: GitLabel(GitMessages.noOutgoingCommits),
                          ),
                        for (final commit
                            in (entry['commits'] as List).cast<Json>().map(
                              GitCommit.fromJson,
                            ))
                          ListTile(
                            dense: true,
                            selected: selected?.oid == commit.oid,
                            title: Text(commit.subject),
                            subtitle: Text(
                              '${commit.oid.abbreviated} · ${commit.author}',
                            ),
                            onTap: () => setState(() => selected = commit),
                          ),
                      ],
                    ],
                  ),
                  second: selected == null
                      ? const Center(
                          child: GitLabel(GitMessages.selectAnOutgoingCommit),
                        )
                      : GitCommitFiles(session: session, commit: selected!),
                ),
        ),
        if (data?['hasMore'] == true)
          TextButton(
            onPressed: _busy ? null : () => unawaited(nextPage()),
            child: const GitLabel(GitMessages.loadMoreOutgoingCommits),
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: session.host.spacing,
          children: [
            if (reviewed.branch != null)
              SizedBox(
                width: 300,
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: upstream,
                  title: const GitLabel(
                    GitMessages.setThisDestinationAsUpstream,
                  ),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => upstream = v!),
                ),
              ),
            GitMenuButton(
              host: session.host,
              enabled: !_busy,
              onSelected: (tag) {
                if (!mounted || _busy) return;
                if (!selectedTags.add(tag)) selectedTags.remove(tag);
                invalidate();
              },
              entries: [
                for (final tag in tags)
                  GitMenuEntry(
                    tag.name,
                    tag.name,
                    checked: selectedTags.contains(tag.name),
                    localize: false,
                  ),
              ],
              tooltip: gitString(context, GitMessages.chooseExactTagsToPublish),
              child: Padding(
                padding: EdgeInsets.all(session.host.spacing),
                child: Text(
                  selectedTags.isEmpty
                      ? gitString(context, GitMessages.tagsNone)
                      : gitString(
                          context,
                          GitMessages.tagsArg0Selected,
                          values: {'arg0': selectedTags.length},
                        ),
                ),
              ),
            ),
          ],
        ),
        if (selectedTags.isNotEmpty)
          GitSelectableText(
            gitString(
              context,
              GitMessages.publishExactlyArg0,
              values: {'arg0': selectedTags.join(', ')},
            ),
          ),
        if (completed)
          const GitLabel(
            GitMessages.pushCompletedTheLocalCommitRemainsAvailableInLog,
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Tooltip(
              message:
                  data?['forceDisabledReason'] as String? ??
                  gitString(
                    context,
                    GitMessages
                        .forceRequiresTheExactDestinationTipsShownInThisReview,
                  ),
              child: TextButton(
                onPressed: eligible && data?['forceAllowed'] != false
                    ? () => unawaited(push(true))
                    : null,
                child: const GitLabel(GitMessages.forceWithReviewedLease),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: eligible ? () => unawaited(push(false)) : null,
              child: const GitLabel(GitMessages.push),
            ),
          ],
        ),
      ],
    );
  }

  bool get eligible =>
      !_busy &&
      !completed &&
      data?['token'] != null &&
      data?['needsFetch'] != true;
  Future<void> nextPage() async {
    final plan = data!;
    final page = await query(
      () => workflows.inspect(
        session.repository,
        GitInspection(
          GitInspectionKind.pushPage,
          reviewToken: plan['token'] as String,
          offset: plan['nextOffset'] as int,
        ),
      ),
    );
    if (!mounted || page == null || data?['token'] != plan['token']) return;
    final previous = (plan['outgoing'] as List).cast<Json>();
    setState(
      () => data = {
        ...plan,
        'hasMore': page['hasMore'],
        'nextOffset': page['nextOffset'],
        'outgoing': [
          for (final entry in (page['outgoing'] as List).cast<Json>())
            {
              ...entry,
              'commits': [
                for (final old in previous.where(
                  (e) => e['destination'] == entry['destination'],
                ))
                  ...old['commits'] as List,
                ...entry['commits'] as List,
              ],
            },
        ],
      },
    );
  }

  Future<void> push(bool force) async {
    if (!mounted || !eligible) return;
    final plan = data!, snapshot = reviewed;
    final current = _reviewGeneration,
        source = remote,
        target = destination.text;
    final reviewedTags = selectedTags.toList(), reviewedUpstream = upstream;
    if (force &&
        !await gitConfirm(
          context,
          session,
          GitMessages.forcePushWithReviewedLeases,
          gitString(
                context,
                GitMessages.rewriteArg0OnlyIfEveryRemoteDestinationStillHasThe,
                values: {'arg0': plan['destination']},
              ) +
              gitString(
                context,
                GitMessages.otherPeopleMayAlreadyUseThisHistoryABackgroundFetch,
              ),
          action: GitMessages.forceWithLease,
        ))
      return;
    if (!eligible ||
        !_currentReview(current, source, target, reviewedTags) ||
        data?['token'] != plan['token'] ||
        upstream != reviewedUpstream)
      return;
    final result = await apply(
      PushReviewed(
        plan['token'] as String,
        forceWithLease: force,
        setUpstream: reviewedUpstream,
        tags: reviewedTags,
        expectedHead: snapshot.head,
        expectedIndex: snapshot.indexToken,
      ),
    );
    if (!mounted) return;
    setState(() {
      data = null;
      completed = result?.completed == true;
      if (result?.phase == GitOperationPhase.uncertain) {
        final cause = result?.error;
        error = GitException(
          GitErrorCode.uncertainOutcome,
          command: cause?.command ?? '',
          diagnostic: cause?.diagnostic ?? '',
          exitCode: cause?.exitCode,
        );
      }
    });
    if (result?.phase == GitOperationPhase.uncertain)
      session.host.notify(
        GitMessages
            .theRemoteOutcomeIsUncertainReviewDestinationsAgainBeforeAnother,
      );
  }
}

final class GitCommitFiles extends StatefulWidget {
  const GitCommitFiles({
    super.key,
    required this.session,
    required this.commit,
  });
  final GitSession session;
  final GitCommit commit;
  @override
  State<GitCommitFiles> createState() => _CommitFilesState();
}

final class _CommitFilesState extends State<GitCommitFiles> {
  List<GitChange>? files;
  GitChange? selected;
  GitException? error;
  GitOid? parent;
  bool expanded = false;
  int generation = 0;
  final _filesScroll = ScrollController(), _detailsScroll = ScrollController();
  final _previewKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    parent = widget.commit.parents.firstOrNull;
    unawaited(load());
  }

  @override
  void didUpdateWidget(GitCommitFiles old) {
    super.didUpdateWidget(old);
    if (old.commit.oid != widget.commit.oid || old.session != widget.session) {
      parent = widget.commit.parents.firstOrNull;
      unawaited(load());
    }
  }

  @override
  void dispose() {
    generation++;
    _filesScroll.dispose();
    _detailsScroll.dispose();
    super.dispose();
  }

  bool _owns(
    int current,
    GitSession session,
    GitOid revision,
    GitOid? chosenParent,
  ) =>
      mounted &&
      current == generation &&
      session == widget.session &&
      revision == widget.commit.oid &&
      chosenParent == parent;

  Future<void> load() async {
    final current = ++generation,
        session = widget.session,
        revision = widget.commit.oid,
        chosenParent = parent;
    setState(() {
      files = null;
      selected = null;
      error = null;
    });
    try {
      final values = await session.client.changedFiles(
        session.repository,
        revision,
        parent: chosenParent,
      );
      if (_owns(current, session, revision, chosenParent))
        setState(() {
          files = List.unmodifiable(values);
          selected = files!.firstOrNull;
        });
    } on Object catch (failure) {
      if (_owns(current, session, revision, chosenParent))
        setState(
          () => error = failure is GitException
              ? failure
              : GitException(
                  GitErrorCode.disconnected,
                  diagnostic: sanitizeGitDiagnostic('$failure'),
                ),
        );
    }
  }

  Widget _fileList(
    int current,
    GitSession session,
    GitCommit commit,
    GitOid? chosenParent,
  ) => ListView.builder(
    key: PageStorageKey((session, commit.oid, chosenParent, 'outgoing-files')),
    controller: _filesScroll,
    itemCount: files?.length ?? 0,
    itemBuilder: (context, index) {
      final file = files![index];
      return ListTile(
        dense: true,
        selected: selected == file,
        leading: Text(file.index),
        title: Text(file.path.display),
        subtitle: file.originalPath == null
            ? null
            : Text(file.originalPath!.display),
        onTap: () {
          if (_owns(current, session, commit.oid, chosenParent) &&
              files!.contains(file)) {
            setState(() => selected = file);
          }
        },
      );
    },
  );

  Widget _preview(
    int current,
    GitSession session,
    GitCommit commit,
    GitOid? chosenParent,
  ) {
    final file = selected!, ordered = files!, index = ordered.indexOf(file);
    void navigate(int next) {
      if (_owns(current, session, commit.oid, chosenParent) &&
          identical(files, ordered) &&
          next >= 0 &&
          next < ordered.length) {
        setState(() => selected = ordered[next]);
      }
    }

    return KeyedSubtree(
      key: _previewKey,
      child: Column(
        children: [
          Row(
            children: [
              GitIconButton(
                tooltip: gitString(
                  context,
                  expanded
                      ? GitMessages.collapse
                      : GitMessages.reviewDifference,
                ),
                onPressed: () {
                  if (_owns(current, session, commit.oid, chosenParent))
                    setState(() => expanded = !expanded);
                },
                icon: GitIcon(expanded ? GitGlyph.back : GitGlyph.expand),
              ),
              Expanded(
                child: Text(
                  '${file.originalPath == null ? file.path.display : '${file.originalPath!.display} → ${file.path.display}'} · '
                  '${chosenParent?.abbreviated ?? gitString(context, GitMessages.emptyTree)} → ${commit.oid.abbreviated}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Expanded(
            child: GitDiffView(
              key: ValueKey((
                session,
                commit.oid,
                chosenParent,
                file.path.key,
                file.originalPath?.key,
              )),
              session: session,
              preview: !expanded,
              comparison: GitComparison(
                file.path,
                chosenParent == null
                    ? const ContentVersion.absent()
                    : ContentVersion(
                        ContentKind.commit,
                        revision: chosenParent,
                      ),
                ContentVersion(ContentKind.commit, revision: commit.oid),
                leftPath: file.originalPath,
              ),
              onPreviousFile: index <= 0 ? null : () => navigate(index - 1),
              onNextFile: index < 0 || index + 1 >= ordered.length
                  ? null
                  : () => navigate(index + 1),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = generation,
        session = widget.session,
        commit = widget.commit,
        chosenParent = parent;
    final review = selected == null
        ? null
        : _preview(current, session, commit, chosenParent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!expanded)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: session.host.rowHeight(context) * 4,
            ),
            child: SingleChildScrollView(
              controller: _detailsScroll,
              padding: EdgeInsets.all(session.host.spacing),
              child: GitSelectableText(
                '${commit.message}\n${commit.author} · ${commit.date.toLocal()}',
              ),
            ),
          ),
        if (commit.parents.length > 1)
          DropdownButton<GitOid>(
            value: chosenParent,
            items: [
              for (var i = 0; i < commit.parents.length; i++)
                DropdownMenuItem(
                  value: commit.parents[i],
                  child: Text(
                    gitString(
                      context,
                      GitMessages.parentArg0Arg1,
                      values: {
                        'arg0': i + 1,
                        'arg1': commit.parents[i].abbreviated,
                      },
                    ),
                  ),
                ),
            ],
            onChanged: (value) {
              if (_owns(current, session, commit.oid, chosenParent) &&
                  value != null &&
                  commit.parents.contains(value)) {
                parent = value;
                unawaited(load());
              }
            },
          ),
        if (error != null)
          GitFailurePanel(error: error!, onRefresh: () => unawaited(load())),
        if (files == null && error == null)
          LinearProgressIndicator(
            semanticsLabel: gitString(context, GitMessages.loadingChangedFiles),
          ),
        Expanded(
          child: files?.isEmpty == true
              ? const Center(child: GitLabel(GitMessages.noChangedFiles))
              : review == null
              ? const SizedBox()
              : expanded
              ? review
              : GitSplitter(
                  axis: Axis.vertical,
                  initial: .32,
                  minimum: session.host.rowHeight(context) * 2,
                  value: session.split('outgoingFilesPreviewSplit', .32),
                  onChanged: (value) =>
                      session.setViewState('outgoingFilesPreviewSplit', value),
                  first: _fileList(current, session, commit, chosenParent),
                  second: review,
                ),
        ),
      ],
    );
  }
}

final class GitFetchView extends StatefulWidget {
  const GitFetchView({super.key, required this.session, this.initialRemote});
  final GitSession session;
  final String? initialRemote;
  @override
  State<GitFetchView> createState() => _FetchState();
}

final class _FetchState extends GitDialogState<GitFetchView> {
  @override
  GitSession get session => widget.session;
  String? remote;
  bool prune = false;
  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await load(const GitInspection(GitInspectionKind.remotes));
    if (!mounted || error != null) return;
    final names = (data?['remotes'] as List? ?? []).cast<Json>().map(
      (entry) => entry['name'] as String,
    );
    if (names.contains(widget.initialRemote))
      setState(() => remote = widget.initialRemote);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      states(),
      DropdownButtonFormField<String>(
        key: ValueKey(remote),
        initialValue: remote,
        decoration: InputDecoration(
          labelText: gitString(context, GitMessages.remoteToFetch),
        ),
        isExpanded: true,
        items: [
          for (final value in (data?['remotes'] as List? ?? []).cast<Json>())
            DropdownMenuItem(
              value: value['name'] as String,
              child: Text(value['name'] as String),
            ),
        ],
        onChanged: loading ? null : (value) => setState(() => remote = value),
      ),
      CheckboxListTile(
        dense: true,
        value: prune,
        title: const GitLabel(GitMessages.pruneDeletedRemoteTrackingBranches),
        onChanged: (v) => setState(() => prune = v!),
      ),
      const GitLabel(
        GitMessages
            .fetchUpdatesRemoteTrackingInformationWithoutReplacingWorkingFiles,
      ),
      FilledButton(
        onPressed: loading || remote == null
            ? null
            : () async {
                final state = session.snapshot!;
                final result = await apply(
                  FetchRemote(
                    remote!,
                    prune: prune,
                    expectedHead: state.head,
                    expectedIndex: state.indexToken,
                  ),
                );
                if (mounted && result?.completed == true)
                  gitCompleteSurface(context);
              },
        child: const GitLabel(GitMessages.fetch),
      ),
    ],
  );
}

final class GitPullView extends StatefulWidget {
  const GitPullView({super.key, required this.session});
  final GitSession session;
  @override
  State<GitPullView> createState() => _PullState();
}

final class _PullState extends GitDialogState<GitPullView> {
  @override
  GitSession get session => widget.session;
  late GitSnapshot reviewed;
  String? remote;
  final branch = TextEditingController();
  List<GitReference> remoteBranches = [];
  String? configuredBranch;
  String? configuredRemote;
  PullStrategy strategy = PullStrategy.fastForwardOnly;
  int _selectionGeneration = 0;
  bool initializing = true,
      preserveMerges = false,
      noFastForward = false,
      interactivePreference = false;
  @override
  void initState() {
    super.initState();
    reviewed = session.snapshot!;
    branch.text = reviewed.branch ?? '';
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await load(const GitInspection(GitInspectionKind.remotes));
    if (!mounted || error != null) {
      if (mounted) setState(() => initializing = false);
      return;
    }
    final options = await query(
      () => workflows.inspect(
        session.repository,
        const GitInspection(GitInspectionKind.commitOptions),
      ),
    );
    final references = await query(
      () => session.client.references(session.repository),
    );
    if (!mounted || references == null) return;
    setState(() {
      _selectionGeneration++;
      remoteBranches = references
          .where((ref) => ref.name.startsWith('refs/remotes/'))
          .toList();
      initializing = false;
      if (options == null) return;
      final names = (data?['remotes'] as List? ?? [])
          .cast<Json>()
          .map((e) => e['name'] as String)
          .toList();
      final configured = options['upstreamRemote'] as String?;
      configuredRemote = configured;
      remote = configured == null
          ? (names.length == 1 ? names.single : null)
          : names.contains(configured)
          ? configured
          : null;
      final tracking = options['upstreamBranch'] as String?;
      configuredBranch = tracking?.startsWith('refs/heads/') == true
          ? tracking!.substring('refs/heads/'.length)
          : null;
      if (tracking?.startsWith('refs/heads/') == true)
        branch.text = tracking!.substring('refs/heads/'.length);
      if (!_sourceBranches().contains(branch.text)) {
        branch.text = _sourceBranches().firstOrNull ?? '';
      }
      final rebase = (options['pullRebase'] as String?)?.toLowerCase();
      preserveMerges = const {'merges', 'm'}.contains(rebase);
      interactivePreference = const {'interactive', 'i'}.contains(rebase);
      final useRebase =
          preserveMerges ||
          interactivePreference ||
          const {'true', 'yes', 'on', '1'}.contains(rebase);
      final useMerge = const {'false', 'no', 'off', '0'}.contains(rebase);
      noFastForward = const {
        'false',
        'no',
        'off',
        '0',
      }.contains((options['pullFf'] as String?)?.toLowerCase());
      strategy = options['pullFf'] == 'only'
          ? PullStrategy.fastForwardOnly
          : useRebase
          ? PullStrategy.rebase
          : useMerge || noFastForward
          ? PullStrategy.merge
          : PullStrategy.fastForwardOnly;
      if (strategy != PullStrategy.rebase) interactivePreference = false;
    });
  }

  @override
  void dispose() {
    branch.dispose();
    super.dispose();
  }

  List<String> _sourceBranches() {
    final selectedRemote = remote;
    if (selectedRemote == null) return const [];
    final remotes = (data?['remotes'] as List? ?? []).cast<Json>().map(
      (entry) => entry['name'] as String,
    );
    return <String>{
      for (final ref in remoteBranches)
        if (_trackedBranchName(ref, selectedRemote, remotes)
            case final String branch)
          branch,
      if (configuredBranch != null && selectedRemote == configuredRemote)
        configuredBranch!,
    }.toList()..sort();
  }

  Future<void> _fetchSources() async {
    if (loading || initializing || session.running) return;
    final before = reviewed;
    await session.host.present<void>(
      context,
      GitMessages.fetch,
      GitFetchView(session: session, initialRemote: remote),
      expanded: false,
    );
    if (!mounted) return;
    final current = session.snapshot;
    if (current == null ||
        current.head != before.head ||
        current.indexToken != before.indexToken ||
        current.branch != before.branch) {
      setState(() => error = const GitException(GitErrorCode.staleReview));
      return;
    }
    setState(() => initializing = true);
    final values = await query(
      () => session.client.references(session.repository),
    );
    if (!mounted) return;
    setState(() {
      initializing = false;
      if (values == null) return;
      _selectionGeneration++;
      reviewed = current;
      remoteBranches = values
          .where((ref) => ref.name.startsWith('refs/remotes/'))
          .toList();
      if (!_sourceBranches().contains(branch.text)) branch.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _selectionGeneration,
        snapshot = reviewed,
        source = remote,
        sourceBranch = branch.text,
        selectedStrategy = strategy,
        selectedPreserve = preserveMerges,
        selectedNoFf = noFastForward;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          gitString(
            context,
            GitMessages.destinationArg0Arg1,
            values: {
              'arg0':
                  reviewed.branch ??
                  gitString(context, GitMessages.detachedHEAD),
              'arg1': reviewed.head?.abbreviated,
            },
          ),
        ),
        states(),
        DropdownButtonFormField<String>(
          key: ValueKey(remote),
          initialValue: remote,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: gitString(context, GitMessages.sourceRemote),
          ),
          items: [
            for (final value in (data?['remotes'] as List? ?? []).cast<Json>())
              DropdownMenuItem(
                value: value['name'] as String,
                child: Text(value['name'] as String),
              ),
          ],
          onChanged: loading || initializing
              ? null
              : (value) => setState(() {
                  _selectionGeneration++;
                  remote = value;
                  if (!_sourceBranches().contains(branch.text))
                    branch.text = _sourceBranches().firstOrNull ?? '';
                }),
        ),
        Row(
          children: [
            if (remote != null && branch.text.isNotEmpty)
              const Expanded(child: GitLabel(GitMessages.cachedTracking)),
            TextButton.icon(
              onPressed: loading || initializing || session.running
                  ? null
                  : () => unawaited(_fetchSources()),
              icon: const GitIcon(GitGlyph.refresh),
              label: const GitLabel(GitMessages.fetch),
            ),
          ],
        ),
        SizedBox(height: session.host.spacing),
        DropdownButtonFormField<String>(
          key: ValueKey('$remote:${branch.text}'),
          initialValue: _sourceBranches().contains(branch.text)
              ? branch.text
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: gitString(context, GitMessages.sourceBranch),
          ),
          items: [
            for (final name in _sourceBranches())
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: loading || initializing || _sourceBranches().isEmpty
              ? null
              : (value) => setState(() {
                  _selectionGeneration++;
                  branch.text = value ?? '';
                }),
        ),
        SizedBox(height: session.host.spacing),
        DropdownButtonFormField<PullStrategy>(
          key: ValueKey(strategy),
          initialValue: strategy,
          decoration: InputDecoration(
            labelText: gitString(context, GitMessages.reviewedStrategy),
          ),
          items: [
            for (final value in PullStrategy.values)
              DropdownMenuItem(
                value: value,
                child: Text(switch (value) {
                  PullStrategy.fastForwardOnly => gitString(
                    context,
                    GitMessages.fastForwardOnly,
                  ),
                  PullStrategy.merge => gitString(context, GitMessages.merge),
                  PullStrategy.rebase => gitString(context, GitMessages.rebase),
                }),
              ),
          ],
          onChanged: loading || initializing
              ? null
              : (value) => setState(() {
                  _selectionGeneration++;
                  strategy = value!;
                  interactivePreference = false;
                }),
        ),
        Text(switch (strategy) {
          PullStrategy.fastForwardOnly => gitString(
            context,
            GitMessages.stopIfTheDestinationCannotFastForwardNeverMergeOr,
          ),
          PullStrategy.merge =>
            noFastForward
                ? gitString(
                    context,
                    GitMessages.mergeWithAMergeCommitIncludingWhenFastForwardIs,
                  )
                : gitString(
                    context,
                    GitMessages.mergeAllowFastForwardWhenPossible,
                  ),
          PullStrategy.rebase =>
            preserveMerges
                ? gitString(
                    context,
                    GitMessages
                        .rebaseLocalHistoryWhilePreservingLocalMergeCommits,
                  )
                : gitString(
                    context,
                    GitMessages.rebaseLocalCommitsAsALinearHistory,
                  ),
        }),
        if (interactivePreference) ...[
          const GitLabel(
            GitMessages.gitIsConfiguredForInteractiveRebaseSelectAPullStrategy,
          ),
          TextButton(
            onPressed: () => setState(() {
              _selectionGeneration++;
              interactivePreference = false;
            }),
            child: const GitLabel(
              GitMessages.useReviewedOrdinaryRebaseForThisPull,
            ),
          ),
        ],
        if (strategy != PullStrategy.fastForwardOnly)
          ExpansionTile(
            title: const GitLabel(GitMessages.options),
            children: [
              if (strategy == PullStrategy.merge)
                CheckboxListTile(
                  dense: true,
                  value: noFastForward,
                  title: const GitLabel(
                    GitMessages.alwaysCreateAMergeCommitNoFastForward,
                  ),
                  onChanged: loading || initializing
                      ? null
                      : (value) => setState(() {
                          _selectionGeneration++;
                          noFastForward = value!;
                        }),
                ),
              if (strategy == PullStrategy.rebase)
                CheckboxListTile(
                  dense: true,
                  value: preserveMerges,
                  title: const GitLabel(GitMessages.preserveLocalMergeCommits),
                  onChanged: loading || initializing
                      ? null
                      : (value) => setState(() {
                          _selectionGeneration++;
                          preserveMerges = value!;
                        }),
                ),
            ],
          ),
        if (reviewed.changes.isNotEmpty)
          Wrap(
            children: [
              const GitLabel(
                GitMessages
                    .localChangesMayPreventPullReviewCommitThemOrExplicitly,
              ),
              TextButton(
                onPressed: () async {
                  await GitWorkflowUi(context, session).present(
                    GitMessages.stashes,
                    GitStashesView(session: session),
                    expanded: true,
                  );
                  if (!mounted) return;
                  final current = session.snapshot;
                  if (current != null &&
                      current.head == reviewed.head &&
                      current.branch == reviewed.branch) {
                    setState(() {
                      _selectionGeneration++;
                      reviewed = current;
                    });
                  } else {
                    setState(
                      () =>
                          error = const GitException(GitErrorCode.staleReview),
                    );
                  }
                },
                child: const GitLabel(GitMessages.createOrReviewStash),
              ),
            ],
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed:
              loading ||
                  initializing ||
                  interactivePreference ||
                  remote == null ||
                  reviewed.branch == null ||
                  branch.text.trim().isEmpty ||
                  error != null
              ? null
              : () async {
                  if (!mounted ||
                      current != _selectionGeneration ||
                      loading ||
                      initializing ||
                      session.running ||
                      error != null ||
                      ModalRoute.of(context)?.isCurrent != true)
                    return;
                  final result = await apply(
                    PullRemote(
                      source!,
                      sourceBranch,
                      selectedStrategy,
                      expectedHead: snapshot.head,
                      expectedIndex: snapshot.indexToken,
                      preserveMerges:
                          selectedStrategy == PullStrategy.rebase &&
                          selectedPreserve,
                      noFastForward:
                          selectedStrategy == PullStrategy.merge &&
                          selectedNoFf,
                    ),
                  );
                  if (mounted &&
                      result != null &&
                      (result.completed ||
                          result.phase == GitOperationPhase.stopped))
                    gitCompleteSurface(context);
                },
          child: const GitLabel(GitMessages.pullWithSelectedStrategy),
        ),
      ],
    );
  }
}
