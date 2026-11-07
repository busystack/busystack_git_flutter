import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';
import 'support/history_presentation_contract.dart';
import 'support/presentation_fixture.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child,
  Brightness brightness,
) async {
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
}

void main() {
  historyToggleSemanticsContract(mount: _mount);
  referenceNavigationContract(mount: _mount);
}
