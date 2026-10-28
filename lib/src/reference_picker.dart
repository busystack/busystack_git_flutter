import 'messages.dart';
import 'dart:async';
import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'host.dart';
import 'log_view.dart';
import 'session.dart';

/// The reviewed object is immutable; the optional reference retains its exact
/// observed tip so moving/deleting a branch or annotated tag invalidates review.
final class GitRevisionTarget {
  const GitRevisionTarget(
    this.oid,
    this.label, {
    this.reference,
    this.referenceTip,
  });
  final GitOid oid;
  final String label;
  final String? reference;
  final GitOid? referenceTip;
}

Future<GitRevisionTarget?> gitChooseRevision(
  BuildContext context,
  GitSession session,
  String title,
) => session.host.present<GitRevisionTarget>(
  context,
  title,
  _RevisionPicker(session: session),
  expanded: true,
);

final class _RevisionPicker extends StatefulWidget {
  const _RevisionPicker({required this.session});
  final GitSession session;
  @override
  State<_RevisionPicker> createState() => _RevisionPickerState();
}

final class _RevisionPickerState extends State<_RevisionPicker> {
  List<GitReference> _refs = [];
  String _search = '';
  bool _loading = true, _log = false, _submitted = false;
  GitException? _error;
  int _generation = 0;
  GitCancellation? _cancellation;
  void _complete(GitRevisionTarget target) {
    if (_submitted || !mounted || ModalRoute.of(context)?.isCurrent != true)
      return;
    _submitted = true;
    gitCompleteSurface(context, target);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final refs = await widget.session.client.references(
        widget.session.repository,
      );
      if (mounted && generation == _generation) setState(() => _refs = refs);
    } on GitException catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<void> _choose(GitReference reference) async {
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = _cancellation = GitCancellation();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Resolve the reviewed object, not a name that can move and return while
      // the request is running. History also peels annotated tag objects.
      final page = await widget.session.client.history(
        widget.session.repository,
        filter: HistoryFilter(reference: reference.oid.value),
        limit: 1,
        cancellation: cancellation,
      );
      final refs = await widget.session.client.references(
        widget.session.repository,
      );
      if (!mounted || generation != _generation) return;
      if (!refs.any(
        (ref) => ref.name == reference.name && ref.oid == reference.oid,
      )) {
        throw const GitException(GitErrorCode.staleReview);
      }
      if (page.commits.isEmpty)
        throw const GitException(GitErrorCode.missingContent);
      _complete(
        GitRevisionTarget(
          page.commits.first.oid,
          reference.shortName,
          reference: reference.name,
          referenceTip: reference.oid,
        ),
      );
    } on GitException catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_log)
      return GitLogView(
        session: widget.session,
        onChooseCommit: (commit) =>
            _complete(GitRevisionTarget(commit.oid, commit.subject)),
      );
    final matches = _refs
        .where(
          (ref) => ref.shortName.toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();
    final rows = <Object>[];
    for (final group in const {
      'refs/heads/': GitMessages.localBranches,
      'refs/remotes/': GitMessages.remoteBranches,
      'refs/tags/': GitMessages.tags,
    }.entries) {
      final values = matches
          .where((ref) => ref.name.startsWith(group.key))
          .toList();
      if (values.isNotEmpty) {
        rows.add(group.value);
        rows.addAll(values);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.session.repository.root),
        TextField(
          autofocus: true,
          decoration: InputDecoration(
            labelText: gitString(context, GitMessages.searchBranchesAndTags),
            prefixIcon: const GitIcon(GitGlyph.search),
          ),
          onChanged: (value) => setState(() => _search = value),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                _generation++;
                _cancellation?.cancel();
                setState(() => _log = true);
              },
              icon: const GitIcon(GitGlyph.history),
              label: const GitLabel(GitMessages.selectCommitInLog),
            ),
            TextButton(
              onPressed: _loading ? null : _load,
              child: const GitLabel(GitMessages.refresh),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) GitFailurePanel(error: _error!, onRefresh: _load),
        Expanded(
          child: !_loading && matches.isEmpty
              ? const Center(
                  child: GitLabel(
                    GitMessages.noMatchingBranchesOrTagsSelectACommitInLog,
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row is String)
                      return Padding(
                        padding: EdgeInsets.all(widget.session.host.spacing),
                        child: GitLabel(row),
                      );
                    final ref = row as GitReference;
                    return ListTile(
                      key: ValueKey(ref.name),
                      dense: true,
                      enabled: !_loading,
                      leading: GitIcon(
                        ref.current
                            ? GitGlyph.check
                            : ref.name.startsWith('refs/tags/')
                            ? GitGlyph.tag
                            : GitGlyph.branch,
                      ),
                      title: Text(ref.shortName),
                      subtitle: Text(ref.subject),
                      trailing: ref.current
                          ? const GitLabel(GitMessages.currentBranch)
                          : null,
                      onTap: () => unawaited(_choose(ref)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
