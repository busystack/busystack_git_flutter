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
