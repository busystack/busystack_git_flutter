import 'dart:convert';
import 'dart:io';
import 'check_native_presentation.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final configFile = File('${root.path}/.dart_tool/package_config.json');
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  for (final package in config['packages'] as List) {
    package['rootUri'] = configFile.uri
        .resolve(package['rootUri'] as String)
        .toString();
  }
  final temp = Directory.systemTemp.createTempSync('native-git-audit-');
  try {
    Directory('${temp.path}/.dart_tool').createSync();
    File(
      '${temp.path}/.dart_tool/package_config.json',
    ).writeAsStringSync(jsonEncode(config));
    // A host service callback is part of the Git rendering chain too.
    final notificationHelper = File('${temp.path}/notification_helper.dart')
      ..writeAsStringSync("""
import 'package:flutter/material.dart';
void showFeedback(BuildContext context, String message) =>
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
""");
    final notificationHost = File('${temp.path}/notification_host.dart')
      ..writeAsStringSync("""
import 'package:flutter/widgets.dart';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'notification_helper.dart';
GitHost createHost(BuildContext context, GitHost base) => GitHost(
  present: <T>(c, title, child, {bool expanded = false}) async => null,
  openDocument: base.openDocument, prepareMutation: base.prepareMutation,
  chooseDirectory: base.chooseDirectory,
  notify: (message) => showFeedback(context, message),
  drafts: base.drafts, icons: base.icons, presentation: base.presentation,
  presentMenu: base.presentMenu,
);
""");
    Future<void> requireNotificationViolation(String reason) async {
      if ((await auditNativeGitSources([notificationHost.path])).isEmpty) {
        throw StateError(reason);
      }
    }

    await requireNotificationViolation(
      'Git notification callback concealed a Material snackbar',
    );
    notificationHelper.writeAsStringSync("""
import 'package:flutter/material.dart';
void showFeedback(BuildContext context, String message) =>
    context.findAncestorStateOfType<HostToastState>()?.enqueue(message);
class HostToastState extends State<StatefulWidget> {
  void enqueue(String message) => setState(() {});
  @override
  Widget build(BuildContext context) => const Material(child: Text('hidden'));
}
""");
    await requireNotificationViolation(
      'Git notification callback concealed a stateful Material toast',
    );
    notificationHelper.writeAsStringSync("""
import 'package:flutter/widgets.dart';
void showFeedback(BuildContext context, String message) {
  Overlay.of(context).insert(OverlayEntry(builder: (_) => Text(message)));
}
""");
    await requireNotificationViolation(
      'A host retained its own Git notification widget tree',
    );
    notificationHelper.writeAsStringSync("""
import 'package:flutter/material.dart';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
void showFeedback(BuildContext context, String message) =>
    showGitNotification(context, message: message);
// Unrelated application feedback is outside this Git callback's ownership.
Widget unrelated() => const Material(child: Text('not Git'));
""");
    if ((await auditNativeGitSources([notificationHost.path])).isNotEmpty) {
      throw StateError('Rejected the common Git notification bridge');
    }
    final nonGitSidebar = File('${temp.path}/non_git_sidebar.dart')
      ..writeAsStringSync("""
import 'package:flutter/material.dart';
class NativeSidebar extends StatelessWidget {
  const NativeSidebar({super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.findAncestorStateOfType<AppFeedbackState>()?.enqueue(),
    child: const Text('Native row'),
  );
}
class AppFeedbackState extends State<StatefulWidget> {
  void enqueue() => setState(() {});
  @override
  Widget build(BuildContext context) => const Material(child: Text('Host feedback'));
}
""");
    if ((await auditFirstPartyPresentationChain(nonGitSidebar.path, [
      'NativeSidebar',
    ], scope: FirstPartyPresentationScope.sidebarGeometry)).isNotEmpty) {
      throw StateError(
        'Non-Git row geometry incorrectly owns application notifications',
      );
    }
    if ((await auditFirstPartyPresentationChain(nonGitSidebar.path, [
      'NativeSidebar',
    ])).isEmpty) {
      throw StateError('The full Git audit lost stateful service rendering');
    }
    nonGitSidebar.writeAsStringSync("""
import 'package:flutter/material.dart';
class NativeSidebar extends StatefulWidget {
  const NativeSidebar({super.key});
  @override
  State<NativeSidebar> createState() => RowState();
}
class RowState extends State<NativeSidebar> {
  @override
  Widget build(BuildContext context) => const Material(child: Text('Bad row'));
}
""");
    if ((await auditFirstPartyPresentationChain(nonGitSidebar.path, [
      'NativeSidebar',
    ], scope: FirstPartyPresentationScope.sidebarGeometry)).isEmpty) {
      throw StateError(
        'Non-Git geometry audit lost a real stateful widget construction',
      );
    }
    nonGitSidebar.writeAsStringSync("""
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
final class NativeSidebar extends YaruGitPresentation { const NativeSidebar(); }
""");
    var rejectedGitScope = false;
    try {
      await auditFirstPartyPresentationChain(nonGitSidebar.path, [
        'NativeSidebar',
      ], scope: FirstPartyPresentationScope.sidebarGeometry);
    } on StateError catch (error) {
      rejectedGitScope =
          error.message ==
          'Git feature roots require the full rendering/service audit.';
    }
    if (!rejectedGitScope)
      throw StateError(
        'A Git presentation root escaped the mandatory full audit',
      );
    final forbidden = <String>[
      "import 'package:flutter/material.dart'; Widget surface() => TextButton(onPressed: () {}, child: const Text('bad'));",
      "import 'package:flutter/material.dart' as m; m.Widget surface() => m.TextField();",
      "import 'package:flutter/material.dart' as m; typedef Hidden = m.FilledButton; final construct = Hidden.new;",
      "import 'package:flutter/material.dart' as m; final icon = m.Icons.add; final palette = m.Colors.purple;",
      "import 'package:flutter/material.dart' as m; Future<void> fallback(m.BuildContext c) async { await m.showDialog<void>(context:c,builder:(_)=>m.AlertDialog()); }",
      "import 'package:flutter/material.dart' as m; final construct = m.Color.new;",
      "import 'package:flutter/material.dart' as m; m.Widget surface() => m.Scrollbar(child: m.SizedBox());",
      "import 'package:flutter/material.dart' as m; m.Widget surface() => m.SearchBar();",
      "import 'package:flutter/painting.dart' as p; final style = p.TextStyle(fontFamily: 'unapproved');",
    ];
    for (var i = 0; i < forbidden.length; i++) {
      final fixture = File('${temp.path}/forbidden_$i.dart')
        ..writeAsStringSync(forbidden[i]);
      if ((await auditNativeGitSources([fixture.path])).isEmpty) {
        throw StateError('Architecture gate accepted forbidden example $i');
      }
    }
    final oldWorkspace = File('${temp.path}/workspace.dart')
      ..writeAsStringSync(
        "import 'package:busystack_git_flutter/busystack_git_flutter.dart' as git; typedef OldSwitch = git.GitChoiceBar<bool>; final legacy = OldSwitch.new;",
      );
    if ((await auditNativeGitSources([oldWorkspace.path])).isEmpty) {
      throw StateError(
        'Canonical architecture accepted the retired Commit/Log switcher',
      );
    }
    for (final glyph in ['more', 'moreHorizontal', 'actions']) {
      final fixture = File('${temp.path}/wrong_actions_$glyph.dart')
        ..writeAsStringSync(
          "import 'package:busystack_git_flutter/busystack_git_flutter.dart' as git; final wrong = git.GitIcon(git.GitGlyph.$glyph);",
        );
      if ((await auditNativeGitSources([fixture.path])).isEmpty) {
        throw StateError(
          'An arbitrary Actions icon bypassed the semantic role: $glyph',
        );
      }
    }
    final glyphCatalog = File('${temp.path}/glyph_catalog.dart')
      ..writeAsStringSync(
        "import 'package:flutter/material.dart' as m; class NativeCatalog { static const branch = m.Icons.fork_right; }",
      );
    final indirectGlyph = File('${temp.path}/indirect_glyph.dart')
      ..writeAsStringSync(
        "import 'glyph_catalog.dart' as approved; const alias = approved.NativeCatalog.branch; final gitGlyph = alias;",
      );
    if ((await auditNativeGitSources([indirectGlyph.path])).isEmpty) {
      throw StateError(
        'Material glyph hidden in an approved-looking catalog passed',
      );
    }
    // The shared fixture graph has no Yaru dependency. Test a legitimate native
    // IconData directly, without borrowing either application's implementation.
    glyphCatalog.writeAsStringSync(
      "import 'package:flutter/widgets.dart'; class NativeCatalog { static const branch = IconData(1, fontFamily: 'YaruIcons', fontPackage: 'yaru'); }",
    );
    if ((await auditNativeGitSources([indirectGlyph.path])).isNotEmpty) {
      throw StateError('Legitimate native glyph was rejected');
    }
    for (final expanded in ['true', 'false', 'variable']) {
      final metadata = File('${temp.path}/metadata_$expanded.dart')
        ..writeAsStringSync(
          "import 'package:flutter/widgets.dart'; import 'package:busystack_git_flutter/src/host.dart'; import 'package:busystack_git_flutter/src/commit_details.dart'; typedef Details = GitCommitDetails; Future<void> show(BuildContext c, GitHost host, Details content, bool variable) async { await host.present<void>(c, 'details', content, expanded: $expanded); }",
        );
      final errors = await auditNativeGitSources([metadata.path]);
      if (errors.isNotEmpty != (expanded != 'false')) {
        throw StateError(
          'Compact commit metadata enforcement failed: $expanded',
        );
      }
    }
    final design = File('${temp.path}/lib/src/app/busymark_design.dart');
    design.parent.createSync(recursive: true);
    design.writeAsStringSync('''
class BusyMarkHeaderPopupMenuButton { const BusyMarkHeaderPopupMenuButton(); const BusyMarkHeaderPopupMenuButton.native(); }
void showBusyMarkMenu() {}
class BusyMarkCompactIconButton { const BusyMarkCompactIconButton(); }
class BusyMarkHeaderIconButton { const BusyMarkHeaderIconButton(); }
class BusyMarkTypography { static const monoFontFamily = 'Native mono'; }
''');
    for (final source in [
      "import 'lib/src/app/busymark_design.dart' as host; typedef Alias = host.BusyMarkCompactIconButton; final button = Alias.new;",
      "import 'lib/src/app/busymark_design.dart' as host; final button = host.BusyMarkHeaderPopupMenuButton();",
      "import 'lib/src/app/busymark_design.dart' as host; void fallback() => host.showBusyMarkMenu();",
    ]) {
      final file = File('${temp.path}/host_fallback.dart')
        ..writeAsStringSync(source);
      if ((await auditNativeGitSources([file.path])).isEmpty)
        throw StateError('Host fallback escaped the audit');
    }
    final nativeMenu = File('${temp.path}/native_menu.dart')
      ..writeAsStringSync(
        "import 'lib/src/app/busymark_design.dart' as host; final button = host.BusyMarkHeaderPopupMenuButton.native();",
      );
    if ((await auditNativeGitSources([nativeMenu.path])).isNotEmpty)
      throw StateError('Rejected required native menu');
    final flat = File('${temp.path}/flat_action.dart')
      ..writeAsStringSync(
        "import 'lib/src/app/busymark_design.dart' as host; final button = host.BusyMarkHeaderIconButton();",
      );
    if ((await auditNativeGitSources([flat.path])).isNotEmpty)
      throw StateError('Rejected flat native action');
    final nativeFont = File('${temp.path}/native_font.dart')
      ..writeAsStringSync(
        "import 'package:flutter/painting.dart'; import 'lib/src/app/busymark_design.dart' as native; final style = TextStyle(fontFamily: native.BusyMarkTypography.monoFontFamily);",
      );
    if ((await auditNativeGitSources([nativeFont.path])).isNotEmpty)
      throw StateError('Rejected the approved native typography catalog');
    final filesDesign = File('${temp.path}/lib/src/app/busyfiles_design.dart')
      ..writeAsStringSync(
        "class BusyFilesTypography { static const monoFontFamily = 'Native mono'; }",
      );
    nativeFont.writeAsStringSync(
      "import 'package:flutter/painting.dart'; import 'lib/src/app/busyfiles_design.dart' as native; final style = TextStyle(fontFamily: native.BusyFilesTypography.monoFontFamily);",
    );
    if ((await auditNativeGitSources([nativeFont.path])).isNotEmpty) {
      throw StateError('Rejected BusyFiles native typography');
    }
    filesDesign.writeAsStringSync(
      "class UnapprovedTypography { static const monoFontFamily = 'Arbitrary'; }",
    );
    nativeFont.writeAsStringSync(
      "import 'package:flutter/painting.dart'; import 'lib/src/app/busyfiles_design.dart' as native; final style = TextStyle(fontFamily: native.UnapprovedTypography.monoFontFamily);",
    );
    if ((await auditNativeGitSources([nativeFont.path])).isEmpty) {
      throw StateError('An arbitrary BusyFiles font catalog escaped the audit');
    }
    final approved = File('${temp.path}/approved.dart')
      ..writeAsStringSync("""
import 'package:flutter/widgets.dart';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
Widget surface() => Column(children: [GitButton(onPressed: () {}, child: const Text('approved')), const GitLoading()]);
""");
    if ((await auditNativeGitSources([approved.path])).isNotEmpty)
      throw StateError('Rejected approved host-bound controls');
    final hiddenWrapper = File('${temp.path}/approved_wrapper.dart')
      ..writeAsStringSync('''
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart' as widgets;
class ApprovedLookingWrapper extends widgets.StatelessWidget {
  const ApprovedLookingWrapper({super.key});
  @override
  widgets.Widget build(widgets.BuildContext context) =>
      material.TextButton(onPressed: () {}, child: const widgets.Text('bad'));
}
class UnrelatedMaterialControl extends widgets.StatelessWidget {
  const UnrelatedMaterialControl({super.key});
  @override
  widgets.Widget build(widgets.BuildContext context) =>
      material.IconButton(onPressed: () {}, icon: const widgets.Icon(material.Icons.add));
}
''');
    final hostChain = File('${temp.path}/host_chain.dart')
      ..writeAsStringSync('''
import 'package:flutter/widgets.dart' as widgets;
import 'approved_wrapper.dart';
class GitHostAdapter {
  widgets.Widget button() => const ApprovedLookingWrapper();
}
''');
    final hiddenHostViolation = await auditFirstPartyPresentationChain(
      hostChain.path,
      ['GitHostAdapter'],
    );
    if (!hiddenHostViolation.any((error) => error.symbol == 'TextButton')) {
      throw StateError(
        'First-party Material hidden behind an approved-looking wrapper passed',
      );
    }
    if (hiddenHostViolation.any((error) => error.symbol == 'IconButton')) {
      throw StateError('Unreachable non-Git host UI polluted the Git audit');
    }
    hiddenWrapper.writeAsStringSync('''
import 'package:flutter/widgets.dart';
class NativeAction extends StatelessWidget {
  const NativeAction({super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {},
    child: const Text('approved'),
  );
}
''');
    hostChain.writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'approved_wrapper.dart';
class GitHostAdapter {
  Widget button() => const NativeAction();
}
''');
    if ((await auditFirstPartyPresentationChain(hostChain.path, [
      'GitHostAdapter',
    ])).isNotEmpty) {
      throw StateError('Legitimate first-party native implementation failed');
    }
    // A thin adapter must still inspect inherited implementations, including
    // mixins. Unreachable static helpers remain outside the rendering chain.
    for (final inheritance in ['extends Renderer', 'with Rendering']) {
      hostChain.writeAsStringSync("""
import 'package:flutter/material.dart' as material;
class Renderer {
  Object button() => material.TextButton(onPressed: () {}, child: const material.Text('bad'));
}
mixin Rendering {
  Object button() => material.TextButton(onPressed: () {}, child: const material.Text('bad'));
}
class GitHostAdapter $inheritance {}
""");
      if (!(await auditFirstPartyPresentationChain(hostChain.path, [
        'GitHostAdapter',
      ])).any((error) => error.symbol == 'TextButton')) {
        throw StateError(
          'Inherited native renderer escaped the chain audit: $inheritance',
        );
      }
    }
    final sharedFixture = Directory('${temp.path}/shared-renderer')
      ..createSync();
    final externalHost = Directory('${temp.path}/external-host')..createSync();
    Directory('${sharedFixture.path}/lib').createSync();
    Directory('${externalHost.path}/lib').createSync();
    Directory('${externalHost.path}/.dart_tool').createSync();
    for (final (directory, name) in [
      (sharedFixture, 'busystack_git_flutter'),
      (externalHost, 'external_host'),
    ]) {
      File('${directory.path}/pubspec.yaml').writeAsStringSync(
        "name: $name\nenvironment:\n  sdk: '>=3.12.1 <4.0.0'\n",
      );
    }
    final externalConfig =
        jsonDecode(jsonEncode(config)) as Map<String, dynamic>;
    for (final package in externalConfig['packages'] as List) {
      if (package['name'] == 'busystack_git_flutter') {
        package['rootUri'] = sharedFixture.uri.toString();
        package['packageUri'] = 'lib/';
      }
    }
    File(
      '${externalHost.path}/.dart_tool/package_config.json',
    ).writeAsStringSync(jsonEncode(externalConfig));
    final externalAdapter = File('${externalHost.path}/lib/adapter.dart')
      ..writeAsStringSync("""
import 'package:busystack_git_flutter/renderer.dart';
class GitHostAdapter extends SharedRenderer {}
""");
    for (final forbidden in [true, false]) {
      File('${sharedFixture.path}/lib/renderer.dart').writeAsStringSync("""
import 'package:flutter/material.dart' as material;
class SharedRenderer {
  Object button() => ${forbidden ? "material.TextButton(onPressed: () {}, child: const material.Text('bad'))" : "const material.Text('approved')"};
}
class Unreachable {
  Object button() => material.IconButton(onPressed: () {}, icon: const material.Text('unreachable'));
}
""");
      final errors = await auditFirstPartyPresentationChain(
        externalAdapter.path,
        ['GitHostAdapter'],
      );
      if (errors.any((error) => error.symbol == 'TextButton') != forbidden ||
          errors.any((error) => error.symbol == 'IconButton')) {
        throw StateError('Cross-package inherited renderer enforcement failed');
      }
    }
    // Only the canonical typed color resolver provisions literal neutral
    // tokens. A matching wrapper name elsewhere, another method, or a hidden
    // Material control never inherits that permission.
    Directory('${sharedFixture.path}/lib/src').createSync();
    Directory('${sharedFixture.path}/.dart_tool').createSync();
    File(
      '${sharedFixture.path}/.dart_tool/package_config.json',
    ).writeAsStringSync(jsonEncode(externalConfig));
    final palette = File('${sharedFixture.path}/lib/src/linux_native.dart');
    for (final (type, method, hiddenControl, allowed) in [
      ('GitPalette', 'resolve', false, true),
      ('OtherPalette', 'resolve', false, false),
      ('GitPalette', 'other', false, false),
      ('GitPalette', 'resolve', true, false),
    ]) {
      palette.writeAsStringSync("""
import 'package:flutter/material.dart';
abstract final class $type {
  static ColorScheme $method(BuildContext context) {
    ${hiddenControl ? "TextButton(onPressed: () {}, child: const Text('bad'));" : ''}
    return Theme.of(context).colorScheme.copyWith(onSurface: const Color(0xff666666));
  }
}
""");
      final errors = await auditNativeGitSources([palette.path]);
      if (errors.isEmpty != allowed) {
        throw StateError(
          'Native palette data-role enforcement failed: $type.$method hidden=$hiddenControl',
        );
      }
    }
    final comparison = File('${temp.path}/diff_view.dart');
    for (final source in [
      "import 'package:busystack_git_flutter/busystack_git_flutter.dart' as git; final mode = git.GitChoiceBar<bool>(segments: const [], selected: const {}, onSelectionChanged: null);",
      "import 'package:busystack_git_flutter/busystack_git_flutter.dart' as git; typedef Alias = git.GitChoiceBar<bool>; final mode = Alias.new;",
    ]) {
      comparison.writeAsStringSync(source);
      if ((await auditNativeGitSources([comparison.path])).isEmpty)
        throw StateError(
          'Two-way radio/aliased mode escaped the native menu rule',
        );
    }
    comparison.writeAsStringSync(
      "import 'package:busystack_git_flutter/busystack_git_flutter.dart'; final panes = GitChoiceBar<int>(segments: const [], selected: const {}, onSelectionChanged: null);",
    );
    if ((await auditNativeGitSources([comparison.path])).isNotEmpty)
      throw StateError('Rejected the existing three-way pane choice');
    final missing = File('${temp.path}/unresolved.dart')
      ..writeAsStringSync('UndefinedWidget value = UndefinedWidget();');
    var failedClosed = false;
    try {
      await auditNativeGitSources([missing.path]);
    } on StateError {
      failedClosed = true;
    }
    if (!failedClosed) throw StateError('Unresolved source bypassed the gate');
    stdout.writeln(
      'Native Git architecture tests passed: constructors, aliases, tear-offs, helpers, palette/icons, approved controls, fail-closed resolution.',
    );
  } finally {
    temp.deleteSync(recursive: true);
  }
}
