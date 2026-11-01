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
