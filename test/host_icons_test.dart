import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/presentation_fixture.dart';

void main() {
  testWidgets('every Git glyph follows the active host catalog', (
    tester,
  ) async {
    final original = host();
    GitHost configured(IconData icon) => GitHost(
      present: original.present,
      openDocument: original.openDocument,
      prepareMutation: original.prepareMutation,
      chooseDirectory: original.chooseDirectory,
      notify: original.notify,
      drafts: original.drafts,
      icons: {for (final glyph in GitGlyph.values) glyph: icon},
    );
    Widget surface(GitHost host) => MaterialApp(
      home: GitHostScope(
        host: host,
        child: Wrap(
          children: [for (final glyph in GitGlyph.values) GitIcon(glyph)],
        ),
      ),
    );
    for (final icon in [Icons.spa, Icons.ac_unit]) {
      await tester.pumpWidget(surface(configured(icon)));
      expect(
        tester.widgetList<Icon>(find.byType(Icon)).map((e) => e.icon),
        List.filled(GitGlyph.values.length, icon),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
