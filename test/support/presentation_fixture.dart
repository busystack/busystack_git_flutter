import 'dart:async';
import 'dart:convert';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';

const repo = RepositoryId(
  root: '/fixture/repo',
  gitDir: '/fixture/repo/.git',
  commonDir: '/fixture/repo/.git',
  objectFormat: 'sha1',
);
GitSnapshot snapshot() => GitSnapshot(
  repository: repo,
  token: 'review',
  indexToken: 'index',
  changes: [
    GitChange(
      path: RepoPath.text('chapter/notes.md'),
      index: 'M',
      worktree: 'M',
    ),
  ],
  operation: const RepositoryOperation(GitOperationKind.none),
  observedAt: DateTime.utc(2026),
);

class FixtureClient implements GitClient {
  List<GitCommit> historyCommits = [];
  List<GitReference> historyReferences = [];
  final historyFilters = <HistoryFilter>[];
  final mutations = <GitMutation>[];
  Completer<GitOutcome>? pending;
  @override
  Future<RepositoryId?> discover(
    String localPath, {
    GitCancellation? cancellation,
  }) async => repo;
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => snapshot();
  @override
  Future<List<GitReference>> references(RepositoryId repository) async =>
      historyReferences;
  @override
  Future<HistoryPage> history(
    RepositoryId repository, {
    HistoryFilter filter = const HistoryFilter(),
    int offset = 0,
    int limit = 100,
    String? anchor,
    GitCancellation? cancellation,
  }) async {
    historyFilters.add(filter);
    return HistoryPage(
      historyCommits,
      nextOffset: historyCommits.length,
      hasMore: false,
      anchor: 'refs',
    );
  }

  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async => GitContent(
    path: path,
    version: version,
    availability: ContentAvailability.present,
    token: version.label,
    mode: '100644',
    bytes: utf8.encode(
      version.kind == ContentKind.indexVersion ? 'one\ntwo\n' : 'ONE\ntwo\n',
    ),
  );
  @override
  Future<List<GitChange>> changedFiles(
    RepositoryId repository,
    GitOid revision, {
    GitOid? parent,
  }) async => [];
  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    return pending == null
        ? GitOutcome(phase: GitOperationPhase.completed, snapshot: snapshot())
        : pending!.future;
  }

  @override
  Stream<void> watch(RepositoryId repository) => Stream<void>.multi((_) {});
}

GitHost host() => GitHost(
  present: <T>(context, title, child, {bool expanded = false}) => showDialog<T>(
    context: context,
    builder: (_) => Dialog(child: child),
  ),
  openDocument: (_, _, {snapshot}) async {},
  prepareMutation: (_, _) async => true,
  chooseDirectory: (_) async => null,
  notify: (_) {},
  drafts: MemoryGitDraftStore(),
);
