import 'dart:async';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class WorktreeClient extends FixtureClient implements GitWorkflowClient {
  GitOid head = GitOid('a' * 40);
  String index = 'reviewed-index';
  @override
  Future<GitSnapshot> status(
    RepositoryId repository, {
    GitCancellation? cancellation,
    GitReadPolicy policy = GitReadPolicy.restricted,
  }) async => GitSnapshot(
    repository: repository,
    token: head.value,
    indexToken: index,
    head: head,
    branch: 'main',
    changes: const [],
    operation: const RepositoryOperation(GitOperationKind.none),
    observedAt: DateTime.utc(2026),
  );
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {'entries': <Json>[], 'hasMore': false};
  @override
  Future<GitOutcome> mutate(
    RepositoryId repository,
    GitMutation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    mutations.add(request);
    return GitOutcome(
      phase: GitOperationPhase.failed,
      error: const GitException(GitErrorCode.staleReview),
      snapshot: await status(repository),
    );
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Worktree creation uses Git mutation semantics.');
}

void main() {
  testWidgets(
    'worktree creation retains the reviewed HEAD while destination dialogs are open',
    (tester) async {
      final client = WorktreeClient();
      final directory = Completer<String?>();
      var choosing = false;
      final original = host();
      final prompts = <String>[];
      final configured = GitHost(
        present: <T>(context, title, child, {bool expanded = false}) async {
          prompts.add(title);
          return (prompts.length == 1 ? 'new-worktree' : 'new-branch') as T;
        },
        openDocument: original.openDocument,
        chooseDirectory: (_) {
          choosing = true;
          return directory.future;
        },
        notify: original.notify,
        drafts: original.drafts,
        prepareMutation: original.prepareMutation,
      );
      final session = GitSession(
        client: client,
        repository: repo,
        host: configured,
      );
      await session.start();
      final reviewed = session.snapshot!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitWorktreesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create worktree…'));
      await tester.pump();
      expect(choosing, isTrue);
      client.head = GitOid('b' * 40);
      client.index = 'external-index';
      await session.refresh();
      directory.complete('/fixture');
      await tester.pumpAndSettle();
      final request = client.mutations.single as WorktreeMutation;
      expect(request.path, '/fixture/new-worktree');
      expect(request.branch, 'new-branch');
      expect(request.start, reviewed.head);
      expect(request.expectedHead, reviewed.head);
      expect(request.expectedIndex, reviewed.indexToken);
      expect(session.failure?.code, GitErrorCode.staleReview);
      expect(prompts, ['New worktree folder name', 'New worktree branch']);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
