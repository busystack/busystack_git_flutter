import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

const child = RepositoryId(
  root: '/fixture/repo/nested',
  gitDir: '/fixture/repo/.git/modules/nested',
  commonDir: '/fixture/repo/.git/modules/nested',
  objectFormat: 'sha1',
);

final class SubmoduleClient extends FixtureClient implements GitWorkflowClient {
  String checkedOut = 'b' * 40;
  int inspections = 0;
  Completer<void>? inspectionGate;
  @override
  Future<Json> inspect(
    RepositoryId repository,
    GitInspection request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) async {
    inspections++;
    await inspectionGate?.future;
    return {
      'head': null,
      'indexToken': 'reviewed-parent-index',
      'hasMore': false,
      'entries': [
        {
          'path': RepoPath.text('nested').toJson(),
          'recorded': 'a' * 40,
          'checkedOut': checkedOut,
          'workingToken': 'reviewed-child-tip',
          'initialized': true,
          'dirty': false,
          'repository': child.toJson(),
        },
      ],
    };
  }

  @override
  Future<GitCreationOutcome> create(
    GitCreation request, {
    GitCancellation? cancellation,
    void Function(GitProgress)? onProgress,
  }) => throw StateError('Submodule review cannot create a repository.');
}

void main() {
  testWidgets(
    'external refresh does not repeatedly cancel a slow metadata read',
    (tester) async {
      final client = SubmoduleClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitSubmodulesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      client.inspectionGate = Completer<void>();
      await session.refresh();
      await tester.pump(const Duration(milliseconds: 250));
      expect(client.inspections, 2);
      await session.refresh();
      await tester.pump(const Duration(milliseconds: 250));
      expect(client.inspections, 2);
      client.inspectionGate!.complete();
      await tester.pumpAndSettle();
      client.inspectionGate = null;
      await session.refresh();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(client.inspections, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'metadata reconciliation retains an operation failure until explicit refresh',
    (tester) async {
      final client = SubmoduleClient(), original = host();
      final configured = GitHost(
        present: original.present,
        openDocument: original.openDocument,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: original.drafts,
        presentMenu: (_, _, {position}) async => 'stagePointer',
        prepareMutation: (_, _) async => true,
      );
      final session = GitSession(
        client: client,
        repository: repo,
        host: configured,
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitSubmodulesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      client.pending = Completer<GitOutcome>();
      await tester.tap(find.byTooltip('Actions'));
      await tester.pump();
      client.pending!.complete(
        GitOutcome(
          phase: GitOperationPhase.failed,
          snapshot: snapshot(),
          error: const GitException(
            GitErrorCode.staleReview,
            diagnostic: 'Reviewed pointer changed',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inspections = client.inspections;
      expect(find.byType(GitFailurePanel), findsOneWidget);
      await session.refresh();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(client.inspections, inspections);
      expect(find.byType(GitFailurePanel), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(client.inspections, inspections + 1);
      expect(find.byType(GitFailurePanel), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'submodule metadata reconciles external refresh without changing recursion or mutating',
    (tester) async {
      final client = SubmoduleClient();
      final session = GitSession(
        client: client,
        repository: repo,
        host: host(),
      );
      await session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitSubmodulesView(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(client.inspections, 1);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      final originalToken = session.snapshot!.token;
      client.checkedOut = 'c' * 40;
      await session.refresh();
      expect(session.snapshot!.token, originalToken);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(client.inspections, 2);
      expect(find.textContaining('Checked out: ${'c' * 40}'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(client.inspections, 3);
      expect(client.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  for (final allowChild in [true, false]) {
    testWidgets(
      'submodule update obtains child-scoped preparation before parent ($allowChild)',
      (tester) async {
        final client = SubmoduleClient(), prepared = <RepositoryId>[];
        final original = host();
        final configured = GitHost(
          present: original.present,
          openDocument: original.openDocument,
          chooseDirectory: original.chooseDirectory,
          notify: original.notify,
          drafts: original.drafts,
          presentMenu: (_, _, {position}) async => 'updateRecorded',
          prepareMutation: (repository, request) async {
            prepared.add(repository);
            expect(request, isA<SubmoduleMutation>());
            return repository != child || allowChild;
          },
        );
        final session = GitSession(
          client: client,
          repository: repo,
          host: configured,
        );
        await session.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: GitSubmodulesView(session: session)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply submodule operation'));
        await tester.pumpAndSettle();
        expect(prepared, allowChild ? [child, repo] : [child]);
        if (allowChild) {
          final request = client.mutations.single as SubmoduleMutation;
          expect(request.expectedIndex, 'reviewed-parent-index');
          expect(request.contentTokens, {
            RepoPath.text('nested').key: 'reviewed-child-tip',
          });
          expect(request.recursive, isFalse);
        } else {
          expect(client.mutations, isEmpty);
        }
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
