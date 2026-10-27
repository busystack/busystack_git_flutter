import 'dart:convert';
import 'dart:io';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  test('every shared Git message has a reproducible host contract', () {
    final contract =
        (jsonDecode(File('tool/git_messages.json').readAsStringSync()) as Map)
            .cast<String, String>();
    expect(GitMessages.all, orderedEquals(contract.values));
    for (final message in GitMessages.all) {
      expect(message.trim(), isNotEmpty);
      final placeholders = RegExp(
        r'\{([A-Za-z][A-Za-z0-9_]*)\}',
      ).allMatches(message).map((m) => m[1]!).toSet();
      expect(
        message
            .replaceAll(RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}'), '')
            .contains('{'),
        isFalse,
        reason: 'Unbound message template: $message',
      );
      expect(placeholders.every((name) => name.isNotEmpty), isTrue);
    }
  });

  testWidgets('parameter values are inserted once after host translation', (
    tester,
  ) async {
    final original = host();
    final requested = <String>[];
    final localized = GitHost(
      present: original.present,
      openDocument: original.openDocument,
      prepareMutation: original.prepareMutation,
      chooseDirectory: original.chooseDirectory,
      notify: original.notify,
      drafts: original.drafts,
      translate: (key, fallback) {
        requested.add(fallback);
        return fallback == 'Review {path}: {branch}'
            ? '{branch} — {path}'
            : fallback;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GitHostScope(
          host: localized,
          child: const GitLabel(
            'Review {path}: {branch}',
            values: {
              'path': '{branch}/東京\nnotes.md',
              'branch': 'feature/{path}',
            },
          ),
        ),
      ),
    );
    expect(find.text('feature/{path} — {branch}/東京\nnotes.md'), findsOneWidget);
    expect(requested, ['Review {path}: {branch}']);
  });

  testWidgets(
    'host localization receives a template and exact repository data separately',
    (tester) async {
      final original = host();
      final requested = <(String, Map<String, Object?>)>[];
      final configured = GitHost(
        present: original.present,
        openDocument: original.openDocument,
        prepareMutation: original.prepareMutation,
        chooseDirectory: original.chooseDirectory,
        notify: original.notify,
        drafts: original.drafts,
        localize: (message, values) {
          requested.add((message, values));
          return 'Übersetzt: ${values['boundary']} → ${values['base']}';
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GitHostScope(
            host: configured,
            child: const GitLabel(
              GitMessages.commitsAfterBoundaryWillBeReplayedOntoBaseTheBoundary,
              values: {'boundary': 'Commit', 'base': '取消/Stage file'},
            ),
          ),
        ),
      );
      expect(find.text('Übersetzt: Commit → 取消/Stage file'), findsOneWidget);
      expect(
        requested.single.$1,
        GitMessages.commitsAfterBoundaryWillBeReplayedOntoBaseTheBoundary,
      );
      expect(requested.single.$2, {
        'boundary': 'Commit',
        'base': '取消/Stage file',
      });
    },
  );

  test(
    'shared widgets never embed English UI literals outside their message contract',
    () {
      final uiPatterns = [
        RegExp(
          r'''\b(?:Text|SelectableText|GitLabel)\(\s*['"]([A-Za-z][^'"\r\n\$]{2,})['"]''',
        ),
        RegExp(
          r'''\b(?:labelText|hintText|helperText|tooltip|semanticsLabel)\s*:\s*['"]([A-Za-z][^'"\r\n\$]{2,})['"]''',
        ),
      ];
      final failures = <String>[];
      for (final file in Directory(
        'lib/src',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (file.path.endsWith('messages.dart')) continue;
        final source = file.readAsStringSync();
        for (final pattern in uiPatterns) {
          for (final match in pattern.allMatches(source))
            failures.add('${file.path}: ${match[0]}');
        }
      }
      expect(failures, isEmpty);
    },
  );
}
