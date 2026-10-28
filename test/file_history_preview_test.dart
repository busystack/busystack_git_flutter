import 'dart:convert';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/presentation_fixture.dart';

final class _HistoryClient extends FixtureClient implements GitWorkflowClient {
  final parent = GitOid('b' * 40), commit = GitOid('a' * 40);
  final contentCalls = <(RepoPath, ContentVersion)>[];
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async => {
    'entries': [
      {
        'commit': GitCommit(
          oid: commit,
          parents: [parent],
          subject: 'Rename chapter',
          author: 'Fixture',
          email: 'fixture@example.invalid',
          date: DateTime.utc(2026),
          message: 'Rename chapter',
        ).toJson(),
        'pathAtCommit': RepoPath.text('new/chapter.md').toJson(),
        'pathInParent': RepoPath.text('old/chapter.md').toJson(),
        'status': 'R100',
        'deleted': false,
      },
    ],
    'hasMore': false,
  };

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('History inspection must not create a repository.');

  @override
  Future<GitContent> content(
    RepositoryId repository,
    RepoPath path,
    ContentVersion version, {
    GitCancellation? cancellation,
  }) async {
    contentCalls.add((path, version));
    return GitContent(
      path: path,
      version: version,
      availability: ContentAvailability.present,
      token: '${path.key}:${version.revision}',
      mode: '100644',
      bytes: utf8.encode('same text\n'),
    );
  }
}

void main() {
  testWidgets('file history previews the renamed file against its parent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _HistoryClient();
    final session = GitSession(client: client, repository: repo, host: host());
    await session.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHostScope(
            host: session.host,
            child: GitFileHistoryView(
              session: session,
              path: RepoPath.text('new/chapter.md'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      client.contentCalls.any(
        (call) =>
            call.$1.display == 'old/chapter.md' &&
            call.$2.revision == client.parent,
      ),
      isTrue,
    );
    expect(
      client.contentCalls.any(
        (call) =>
            call.$1.display == 'new/chapter.md' &&
            call.$2.revision == client.commit,
      ),
      isTrue,
    );
    expect(find.byType(GitDiffView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
