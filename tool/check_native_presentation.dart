import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

/// Resolve symbols in the actual built sources, including prefixes, re-exports,
/// typedefs, tear-offs and helper invocations. No feature-file exemptions.
const forbiddenMaterial = {
  'TextButton',
  'FilledButton',
  'ElevatedButton',
  'OutlinedButton',
  'IconButton',
  'SelectableText',
  'SelectionArea',
  'TextField',
  'TextFormField',
  'InputDecoration',
  'Checkbox',
  'CheckboxListTile',
  'Radio',
  'RadioListTile',
  'Switch',
  'SwitchListTile',
  'DropdownButton',
  'DropdownButtonFormField',
  'DropdownMenu',
  'DropdownMenuEntry',
  'DropdownMenuItem',
  'ListTile',
  'ExpansionTile',
  'AlertDialog',
  'Dialog',
  'SimpleDialog',
  'SimpleDialogOption',
  'Material',
  'MaterialBanner',
  'Card',
  'CircularProgressIndicator',
  'LinearProgressIndicator',
  'PopupMenuButton',
  'PopupMenuItem',
  'PopupMenuDivider',
  'PopupMenuEntry',
  'MenuAnchor',
  'MenuItemButton',
  'SubmenuButton',
  'MenuBar',
  'InputChip',
  'FilterChip',
  'ChoiceChip',
  'ActionChip',
  'Chip',
  'SegmentedButton',
  'ButtonSegment',
  'ToggleButtons',
  'Slider',
  'InkWell',
  'InkResponse',
  'Tooltip',
  'Divider',
  'VerticalDivider',
  'SnackBar',
  'BottomSheet',
  'NavigationBar',
  'NavigationRail',
  'TabBar',
  'Tab',
  'FloatingActionButton',
  'Icons',
  'Colors',
  'showGeneralDialog',
  'RawDialogRoute',
  'DialogRoute',
  'MaterialPageRoute',
  'showDialog',
  'showMenu',
  'showDatePicker',
  'showDateRangePicker',
  'showTimePicker',
  'showModalBottomSheet',
  'showBottomSheet',
  'AdaptiveTextSelectionToolbar',
  'TextSelectionToolbar',
};
const forbiddenConstructors = {'Theme', 'ThemeData', 'ColorScheme', 'Color'};

final class NativeUiViolation {
  const NativeUiViolation(this.path, this.offset, this.symbol);
  final String path, symbol;
  final int offset;
  @override
  String toString() =>
      '$path:$offset: prohibited native Git reference: $symbol';
}

final class _NativeVisitor extends RecursiveAstVisitor<void> {
  _NativeVisitor(this.path);
  final String path;
  final violations = <NativeUiViolation>[];
  final _seen = <int>{};
  void check(AstNode node, Element? element, {bool construction = false}) {
    if (element == null) return;
    final library = element.library?.uri.toString() ?? '';
    final nativeDesign = library.endsWith('/src/app/busymark_design.dart');
    if (nativeDesign && element.name == 'showBusyMarkMenu') {
      if (_seen.add(node.offset))
        violations.add(
          NativeUiViolation(path, node.offset, 'generic menu fallback'),
        );
    }
    if (nativeDesign && element is ConstructorElement) {
      final control = element.enclosingElement.name;
      if (control == 'BusyMarkCompactIconButton' ||
          control == 'BusyMarkMenuButton' ||
          control == 'BusyMarkHeaderPopupMenuButton' &&
              element.name != 'native') {
        if (_seen.add(node.offset))
          violations.add(
            NativeUiViolation(path, node.offset, 'native-required $control'),
          );
      }
    }
    if (!library.startsWith('package:flutter/') && library != 'dart:ui') return;
    final owner = element is ConstructorElement
        ? element.enclosingElement
        : element;
    final name = owner.name;
    final materialWidget =
        library.startsWith('package:flutter/src/material/') &&
        owner is InterfaceElement &&
        owner.allSupertypes.any(
          (type) =>
              type.element.name == 'Widget' &&
              type.element.library.uri.toString() ==
                  'package:flutter/src/widgets/framework.dart',
        );
    if (construction && materialWidget ||
        forbiddenMaterial.contains(name) ||
        construction && forbiddenConstructors.contains(name)) {
      if (_seen.add(node.offset))
        violations.add(NativeUiViolation(path, node.offset, name ?? '?'));
    }
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    if (const {
      'fontFamily',
      'fontFamilyFallback',
    }.contains(node.name.label.name)) {
      final token = switch (node.expression) {
        PrefixedIdentifier(:final identifier) => identifier.element,
        PropertyAccess(:final propertyName) => propertyName.element,
        SimpleIdentifier(:final element) => element,
        _ => null,
      };
      final nativeCatalog =
          token?.library?.uri.toString().endsWith(
                '/src/app/busymark_design.dart',
              ) ==
              true &&
          token?.enclosingElement?.name == 'BusyMarkTypography' &&
          const {
            'monoFontFamily',
            'monoFontFamilyFallback',
          }.contains(token?.name);
      if (!nativeCatalog)
        violations.add(
          NativeUiViolation(path, node.offset, 'feature-owned font family'),
        );
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    check(node, node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    check(node, node.element);
    super.visitNamedType(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    check(node, node.constructorName.element, construction: true);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    check(node, node.constructorName.element, construction: true);
    super.visitConstructorReference(node);
  }
}

Future<List<NativeUiViolation>> auditNativeGitSources(
  List<String> inputs,
) async {
  final paths = <String>{};
  for (final input in inputs) {
    if (Directory(input).existsSync()) {
      paths.addAll(
        Directory(input)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .map((file) => file.resolveSymbolicLinksSync()),
      );
    } else if (File(input).existsSync() && input.endsWith('.dart')) {
      paths.add(File(input).resolveSymbolicLinksSync());
    } else {
      throw ArgumentError('Missing Git production source: $input');
    }
  }
  if (paths.isEmpty)
    throw StateError('The native Git audit must examine sources.');
  final collection = AnalysisContextCollection(includedPaths: paths.toList());
  final found = <NativeUiViolation>[];
  try {
    for (final path in paths.toList()..sort()) {
      final result = await collection
          .contextFor(path)
          .currentSession
          .getResolvedUnit(path);
      if (result is! ResolvedUnitResult)
        throw StateError('Cannot resolve $path');
      final errors = result.diagnostics.where(
        (e) => e.diagnosticCode.severity == DiagnosticSeverity.ERROR,
      );
      if (errors.isNotEmpty)
        throw StateError('Unresolved Git source $path: ${errors.join('; ')}');
      final visitor = _NativeVisitor(path);
      result.unit.accept(visitor);
      found.addAll(visitor.violations);
    }
  } finally {
    await collection.dispose();
  }
  return found;
}

Future<void> main(List<String> args) async {
  final violations = await auditNativeGitSources(
    args.isEmpty ? ['lib/src'] : args,
  );
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  if (violations.isNotEmpty) {
    exitCode = 1;
  } else {
    stdout.writeln('Native Git presentation boundary passed.');
  }
}
