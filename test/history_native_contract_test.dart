import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'support/history_presentation_contract.dart';
import 'support/presentation_fixture.dart';

void main() {
  historyToggleSemanticsContract(
    mount: (tester, child, brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark
              ? createYaruDarkTheme(primaryColor: YaruColors.orange)
              : createYaruLightTheme(primaryColor: YaruColors.orange),
          home: Scaffold(
            body: GitHostScope(
              host: host(presentation: const YaruGitPresentation()),
              child: child,
            ),
          ),
        ),
      );
      await tester.pump();
    },
  );
}
