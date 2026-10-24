import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'diff_view.dart';
import 'host.dart';
import 'session.dart';
import 'workflow_ui.dart';
import 'organization_views.dart';

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
        'Delete REMOTE reference ${widget.reference}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const GitLabel(
        'This removes the reference on every actual push destination listed below. Local branches/tags are retained. The expected tips are fixed by this review.',
      ),
      for (final destination
          in (data?['destinations'] as List? ?? []).cast<Json>())
        GitSelectableText(
          '${destination['url']}\nExpected tip: ${destination['expectedTip'] ?? 'reference does not exist'}',
        ),
      if (completed) const GitLabel('Remote deletion completed.'),
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
                  'Delete ${widget.reference} from the remote?',
                  'The exact destination tips shown above will be removed. Any changed remote tip stops the operation for another review.',
                  action: 'Delete remote reference',
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
        child: const GitLabel('Review and delete from remote…'),
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
  late GitSnapshot reviewed;
  List<Json> remotes = [];
  List<GitReference> tags = [];
  final selectedTags = <String>{};
  String? remote;
  bool upstream = false, completed = false;
  GitCommit? selected;
  @override
  void initState() {
    super.initState();
    reviewed = session.snapshot!;
    destination.text = 'refs/heads/${reviewed.branch ?? ''}';
    unawaited(initialize());
  }

  @override
  void dispose() {
    destination.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    await load(const GitInspection(GitInspectionKind.remotes));
    if (!mounted || error != null) return;
    final refs = await query(
      () => session.client.references(session.repository),
    );
    final options = await query(
      () => workflows.inspect(
        session.repository,
        const GitInspection(GitInspectionKind.commitOptions),
      ),
    );
    if (!mounted || refs == null || options == null) return;
    setState(() {
      remotes = (data?['remotes'] as List? ?? []).cast<Json>();
      final configured = options['pushRemote'] as String?;
      remote = configured == null
          ? (remotes.length == 1 ? remotes.single['name'] as String : null)
          : remotes.any((e) => e['name'] == configured)
          ? configured
          : null;
      final tracking = options['upstreamBranch'] as String?;
      if (remote == options['upstreamRemote'] &&
          tracking?.startsWith('refs/heads/') == true)
        destination.text = tracking!;
      tags = refs.where((e) => e.name.startsWith('refs/tags/')).toList();
      data = null;
      upstream = reviewed.upstream == null && reviewed.branch != null;
    });
    if (remote != null) await preview();
  }

  void invalidate() {
    generation++;
    cancellation?.cancel();
    setState(() {
      data = null;
      selected = null;
      completed = false;
      loading = false;
    });
  }

  Future<void> preview() async {
    final source = remote,
        target = destination.text,
        tagsToReview = selectedTags.toList();
    final snapshot = await query(() => session.readStatus());
    if (!mounted ||
        snapshot == null ||
        source != remote ||
        target != destination.text ||
        tagsToReview.length != selectedTags.length ||
        !tagsToReview.every(selectedTags.contains))
      return;
    reviewed = snapshot;
    await load(
      GitInspection(
        GitInspectionKind.pushReview,
        remote: source,
        destination: target,
        revision: reviewed.head,
        tags: tagsToReview,
      ),
    );
    final outgoing = (data?['outgoing'] as List? ?? []).cast<Json>();
    final commits = [
      for (final entry in outgoing) ...(entry['commits'] as List).cast<Json>(),
    ];
    if (mounted && commits.isNotEmpty)
      setState(() => selected = GitCommit.fromJson(commits.first));
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
              '${reviewed.branch ?? 'detached HEAD'} · ${reviewed.head?.abbreviated ?? 'unborn'} →',
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                key: ValueKey(remote),
                initialValue: remote,
                decoration: InputDecoration(
                  labelText: gitString(context, 'Remote'),
                ),
                isExpanded: true,
                items: [
                  for (final entry in remotes)
                    DropdownMenuItem(
                      value: entry['name'] as String,
                      child: Text(entry['name'] as String),
                    ),
                ],
                onChanged: loading
                    ? null
                    : (value) {
                        remote = value;
                        invalidate();
                      },
              ),
            ),
            SizedBox(
              width: 300,
              child: TextField(
                controller: destination,
                decoration: InputDecoration(
                  labelText: gitString(context, 'Destination reference'),
                ),
                onChanged: (_) => invalidate(),
              ),
            ),
            OutlinedButton(
              onPressed: loading || remote == null || reviewed.head == null
                  ? null
                  : () => unawaited(preview()),
              child: const GitLabel('Review destinations'),
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
                  '${target['url']}\n${data!['destination']} · expected ${target['expectedTip'] ?? 'new remote branch'}',
              ].join('\n'),
            ),
          ),
        if (data?['needsFetch'] == true)
          MaterialBanner(
            content: const GitLabel(
              'A destination has commits that are unavailable locally. Fetch that reviewed destination before reviewing outgoing history.',
            ),
            actions: [
              TextButton(
                onPressed: loading
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
                child: const GitLabel('Fetch reviewed destination'),
              ),
            ],
          ),
        Expanded(
          child: data?['outgoing'] == null
              ? const Center(
                  child: GitLabel(
                    'Choose a destination and review the outgoing commits.',
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
                            title: GitLabel('No outgoing commits'),
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
                          child: GitLabel('Select an outgoing commit'),
                        )
                      : GitCommitFiles(session: session, commit: selected!),
                ),
        ),
        if (data?['hasMore'] == true)
          TextButton(
            onPressed: loading ? null : () => unawaited(nextPage()),
            child: const GitLabel('Load more outgoing commits'),
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
                  title: const GitLabel('Set this destination as upstream'),
                  onChanged: loading
                      ? null
                      : (v) => setState(() => upstream = v!),
                ),
              ),
            GitMenuButton(
              host: session.host,
              onSelected: (tag) {
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
              tooltip: gitString(context, 'Choose exact tags to publish'),
              child: Padding(
                padding: EdgeInsets.all(session.host.spacing),
                child: Text(
                  selectedTags.isEmpty
                      ? 'Tags: none'
                      : 'Tags: ${selectedTags.length} selected',
                ),
              ),
            ),
          ],
        ),
        if (selectedTags.isNotEmpty)
          GitSelectableText('Publish exactly: ${selectedTags.join(', ')}'),
        if (completed)
          const GitLabel(
            'Push completed. The local commit remains available in Log.',
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Tooltip(
              message:
                  data?['forceDisabledReason'] as String? ??
                  'Force requires the exact destination tips shown in this review.',
              child: TextButton(
                onPressed: eligible && data?['forceAllowed'] != false
                    ? () => unawaited(push(true))
                    : null,
                child: const GitLabel('Force with reviewed lease…'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: eligible ? () => unawaited(push(false)) : null,
              child: const GitLabel('Push'),
            ),
          ],
        ),
      ],
    );
  }

  bool get eligible =>
      !loading &&
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
    final plan = data!;
    if (force &&
        !await gitConfirm(
          context,
          session,
          'Force push with reviewed leases?',
          'Rewrite ${plan['destination']} only if every remote destination still has the exact tip shown above.\n'
              'Other people may already use this history. A background fetch will not renew this lease.',
          action: 'Force with lease',
        ))
      return;
    final result = await apply(
      PushReviewed(
        plan['token'] as String,
        forceWithLease: force,
        setUpstream: upstream,
        tags: selectedTags.toList(),
        expectedHead: reviewed.head,
        expectedIndex: reviewed.indexToken,
      ),
    );
    if (!mounted) return;
    setState(() {
      data = null;
      completed = result?.completed == true;
    });
    if (result?.phase == GitOperationPhase.uncertain)
      session.host.notify(
        'The remote outcome is uncertain. Review destinations again before another push.',
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
  GitException? error;
  GitOid? parent;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    parent = widget.commit.parents.firstOrNull;
    unawaited(load());
  }

  @override
  void didUpdateWidget(GitCommitFiles old) {
    super.didUpdateWidget(old);
    if (old.commit.oid != widget.commit.oid) {
      parent = widget.commit.parents.firstOrNull;
      unawaited(load());
    }
  }

  Future<void> load() async {
    final current = ++generation;
    setState(() {
      files = null;
      error = null;
    });
    try {
      final values = await widget.session.client.changedFiles(
        widget.session.repository,
        widget.commit.oid,
        parent: parent,
      );
      if (mounted && current == generation) setState(() => files = values);
    } on GitException catch (failure) {
      if (mounted && current == generation) setState(() => error = failure);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.all(widget.session.host.spacing),
        child: GitSelectableText(
          '${widget.commit.message}\n${widget.commit.author} · ${widget.commit.date.toLocal()}',
        ),
      ),
      if (widget.commit.parents.length > 1)
        DropdownButton<GitOid>(
          value: parent,
          items: [
            for (var i = 0; i < widget.commit.parents.length; i++)
              DropdownMenuItem(
                value: widget.commit.parents[i],
                child: Text(
                  'Parent ${i + 1} · ${widget.commit.parents[i].abbreviated}',
                ),
              ),
          ],
          onChanged: (value) {
            parent = value;
            unawaited(load());
          },
        ),
      if (error != null)
        GitFailurePanel(error: error!, onRefresh: () => unawaited(load())),
      if (files == null && error == null) const LinearProgressIndicator(),
      Expanded(
        child: ListView.builder(
          itemCount: files?.length ?? 0,
          itemBuilder: (context, i) {
            final file = files![i];
            return ListTile(
              dense: true,
              leading: Text(file.index),
              title: Text(file.path.display),
              onTap: () => widget.session.host.present<void>(
                context,
                '${parent?.abbreviated ?? 'empty tree'} → ${widget.commit.oid.abbreviated}',
                GitDiffView(
                  session: widget.session,
                  comparison: GitComparison(
                    file.path,
                    parent == null
                        ? const ContentVersion.absent()
                        : ContentVersion(ContentKind.commit, revision: parent),
                    ContentVersion(
                      ContentKind.commit,
                      revision: widget.commit.oid,
                    ),
                    leftPath: file.originalPath,
                  ),
                ),
                expanded: true,
              ),
            );
          },
        ),
      ),
    ],
  );
}

final class GitFetchView extends StatefulWidget {
  const GitFetchView({super.key, required this.session});
  final GitSession session;
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
    unawaited(load(const GitInspection(GitInspectionKind.remotes)));
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      states(),
      DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: gitString(context, 'Remote to fetch'),
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
        title: const GitLabel('Prune deleted remote-tracking branches'),
        onChanged: (v) => setState(() => prune = v!),
      ),
      const GitLabel(
        'Fetch updates remote-tracking information without replacing working files.',
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
                  Navigator.of(context).pop();
              },
        child: const GitLabel('Fetch'),
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
  PullStrategy strategy = PullStrategy.fastForwardOnly;
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
    if (!mounted) return;
    setState(() {
      initializing = false;
      if (options == null) return;
      final names = (data?['remotes'] as List? ?? [])
          .cast<Json>()
          .map((e) => e['name'] as String)
          .toList();
      final configured = options['upstreamRemote'] as String?;
      remote = configured == null
          ? (names.length == 1 ? names.single : null)
          : names.contains(configured)
          ? configured
          : null;
      final tracking = options['upstreamBranch'] as String?;
      if (tracking?.startsWith('refs/heads/') == true)
        branch.text = tracking!.substring('refs/heads/'.length);
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

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Destination: ${reviewed.branch ?? 'detached HEAD'} · ${reviewed.head?.abbreviated}',
      ),
      states(),
      DropdownButtonFormField<String>(
        key: ValueKey(remote),
        initialValue: remote,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: gitString(context, 'Source remote'),
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
            : (value) => setState(() => remote = value),
      ),
      SizedBox(height: session.host.spacing),
      TextField(
        controller: branch,
        enabled: !loading && !initializing,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: gitString(context, 'Source branch'),
        ),
      ),
      SizedBox(height: session.host.spacing),
      DropdownButtonFormField<PullStrategy>(
        key: ValueKey(strategy),
        initialValue: strategy,
        decoration: InputDecoration(
          labelText: gitString(context, 'Reviewed strategy'),
        ),
        items: [
          for (final value in PullStrategy.values)
            DropdownMenuItem(
              value: value,
              child: Text(switch (value) {
                PullStrategy.fastForwardOnly => 'Fast-forward only',
                PullStrategy.merge => 'Merge',
                PullStrategy.rebase => 'Rebase',
              }),
            ),
        ],
        onChanged: loading || initializing
            ? null
            : (value) => setState(() {
                strategy = value!;
                interactivePreference = false;
              }),
      ),
      Text(switch (strategy) {
        PullStrategy.fastForwardOnly =>
          'Stop if the destination cannot fast-forward; never merge or rebase.',
        PullStrategy.merge =>
          noFastForward
              ? 'Merge with a merge commit, including when fast-forward is possible.'
              : 'Merge; allow fast-forward when possible.',
        PullStrategy.rebase =>
          preserveMerges
              ? 'Rebase local history while preserving local merge commits.'
              : 'Rebase local commits as a linear history.',
      }),
      if (interactivePreference) ...[
        const GitLabel(
          'Git is configured for interactive rebase. Select a pull strategy explicitly here, or fetch and open Rebase… to review a plan.',
        ),
        TextButton(
          onPressed: () => setState(() => interactivePreference = false),
          child: const GitLabel('Use reviewed ordinary rebase for this pull'),
        ),
      ],
      if (strategy != PullStrategy.fastForwardOnly)
        ExpansionTile(
          title: const GitLabel('Options'),
          children: [
            if (strategy == PullStrategy.merge)
              CheckboxListTile(
                dense: true,
                value: noFastForward,
                title: const GitLabel(
                  'Always create a merge commit (no fast-forward)',
                ),
                onChanged: loading || initializing
                    ? null
                    : (value) => setState(() => noFastForward = value!),
              ),
            if (strategy == PullStrategy.rebase)
              CheckboxListTile(
                dense: true,
                value: preserveMerges,
                title: const GitLabel('Preserve local merge commits'),
                onChanged: loading || initializing
                    ? null
                    : (value) => setState(() => preserveMerges = value!),
              ),
          ],
        ),
      if (reviewed.changes.isNotEmpty)
        Wrap(
          children: [
            const GitLabel(
              'Local changes may prevent pull. Review/commit them or explicitly create a stash.',
            ),
            TextButton(
              onPressed: () async {
                await GitWorkflowUi(context, session).present(
                  'Stashes',
                  GitStashesView(session: session),
                  expanded: true,
                );
                if (!mounted) return;
                final current = session.snapshot;
                if (current != null &&
                    current.head == reviewed.head &&
                    current.branch == reviewed.branch) {
                  setState(() => reviewed = current);
                } else {
                  setState(
                    () => error = const GitException(GitErrorCode.staleReview),
                  );
                }
              },
              child: const GitLabel('Create or review stash…'),
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
                final result = await apply(
                  PullRemote(
                    remote!,
                    branch.text,
                    strategy,
                    expectedHead: reviewed.head,
                    expectedIndex: reviewed.indexToken,
                    preserveMerges:
                        strategy == PullStrategy.rebase && preserveMerges,
                    noFastForward:
                        strategy == PullStrategy.merge && noFastForward,
                  ),
                );
                if (mounted &&
                    result != null &&
                    (result.completed ||
                        result.phase == GitOperationPhase.stopped))
                  Navigator.of(context).pop();
              },
        child: const GitLabel('Pull with selected strategy'),
      ),
    ],
  );
}
