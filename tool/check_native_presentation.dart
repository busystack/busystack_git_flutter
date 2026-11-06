import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
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

class _NativeVisitor extends RecursiveAstVisitor<void> {
  _NativeVisitor(this.path);
  final String path;
  final violations = <NativeUiViolation>[];
  final _seen = <int>{};
  void checkNativeHostBoundary(AstNode node, Element element) {
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
  }

  void check(AstNode node, Element? element, {bool construction = false}) {
    if (element == null) return;
    // Follow resolved constants through the host glyph catalog and aliases.
    // Being declared in a permitted design file cannot authorize Material artwork.
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element is VariableElement
        ? element
        : null;
    final type = variable?.type;
    if (type is InterfaceType && type.element.name == 'IconData') {
      final icon = variable?.computeConstantValue();
      if (icon?.getField('fontFamily')?.toStringValue() == 'MaterialIcons' &&
          _seen.add(node.offset)) {
        violations.add(
          NativeUiViolation(
            path,
            node.offset,
            'Material Git glyph through host mapping',
          ),
        );
      }
    }
    final library = element.library?.uri.toString() ?? '';
    checkNativeHostBoundary(node, element);
    // Feature authors cannot select an arbitrary overflow glyph for Actions.
    // Catalog keys are mappings; actual controls request the semantic role.
    if (library.endsWith('/src/host.dart') &&
        element.enclosingElement?.name == 'GitGlyph' &&
        const {'more', 'moreHorizontal', 'actions'}.contains(element.name) &&
        !path.endsWith('/host.dart')) {
      final mapping = node.thisOrAncestorOfType<MapLiteralEntry>();
      if (mapping == null || node.offset >= mapping.value.offset) {
        violations.add(
          NativeUiViolation(
            path,
            node.offset,
            'Git menus require semantic Actions/context roles',
          ),
        );
      }
    }
    if (!library.startsWith('package:flutter/') && library != 'dart:ui') return;
    final owner = element is ConstructorElement
        ? element.enclosingElement
        : element;
    final name = owner.name;
    // Literal colors belong only to the typed shared native palette resolver.
    // This is a data-role boundary: controls and all other constructors remain
    // audited, including a Material widget hidden inside this same resolver.
    if (construction && name == 'Color' && library == 'dart:ui') {
      final declaration = node.thisOrAncestorOfType<ClassDeclaration>();
      final method = node.thisOrAncestorOfType<MethodDeclaration>();
      final palette = declaration?.declaredFragment?.element;
      final result = method?.declaredFragment?.element.returnType;
      if (palette?.name == 'GitPalette' &&
          palette?.library.uri.toString() ==
              'package:busystack_git_flutter/src/linux_native.dart' &&
          method?.name.lexeme == 'resolve' &&
          method?.isStatic == true &&
          result is InterfaceType &&
          result.element.name == 'ColorScheme' &&
          result.element.library.uri.toString() ==
              'package:flutter/src/material/color_scheme.dart')
        return;
    }
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
          (token?.library?.uri.toString() ==
                  'package:busystack_git_flutter/src/linux_native.dart' &&
              token?.enclosingElement?.name == 'GitTypography' &&
              const {
                'monoFontFamily',
                'monoFontFamilyFallback',
              }.contains(token?.name)) ||
          ((token?.library?.uri.toString().endsWith(
                            '/src/app/busymark_design.dart',
                          ) ==
                          true &&
                      token?.enclosingElement?.name == 'BusyMarkTypography') ||
                  (token?.library?.uri.toString().endsWith(
                            '/src/app/busyfiles_design.dart',
                          ) ==
                          true &&
                      token?.enclosingElement?.name ==
                          'BusyFilesTypography')) &&
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

  void checkComparisonChoice(AstNode node, DartType? type) {
    if (!path.endsWith('/diff_view.dart') && !path.endsWith('/workspace.dart'))
      return;
    if (type is FunctionType) type = type.returnType;
    if (type is InterfaceType &&
        type.element.name == 'GitChoiceBar' &&
        type.element.library.uri.toString().endsWith(
          '/src/presentation.dart',
        ) &&
        type.typeArguments.length == 1 &&
        type.typeArguments.single.isDartCoreBool &&
        _seen.add(node.offset)) {
      violations.add(
        NativeUiViolation(
          path,
          node.offset,
          'two-way comparison requires the native mode menu',
        ),
      );
    }
  }

  @override
  void visitNamedType(NamedType node) {
    checkComparisonChoice(node, node.type);
    check(node, node.element);
    super.visitNamedType(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    checkComparisonChoice(node, node.staticType);
    check(node, node.constructorName.element, construction: true);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    checkComparisonChoice(node, node.staticType);
    check(node, node.constructorName.element, construction: true);
    super.visitConstructorReference(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.staticType;
    if (node.methodName.name == 'present' &&
        target is InterfaceType &&
        target.element.name == 'GitHost' &&
        target.element.library.uri.toString().endsWith('/src/host.dart')) {
      final arguments = node.argumentList.arguments;
      final details = arguments.where((a) => a is! NamedExpression).any((a) {
        final type = a.staticType;
        return type is InterfaceType &&
            type.element.name == 'GitCommitDetails' &&
            type.element.library.uri.toString().endsWith(
              '/src/commit_details.dart',
            );
      });
      if (details) {
        for (final argument in arguments.whereType<NamedExpression>()) {
          if (argument.name.label.name == 'expanded' &&
              !(argument.expression is BooleanLiteral &&
                  !(argument.expression as BooleanLiteral).value)) {
            violations.add(
              NativeUiViolation(
                path,
                argument.offset,
                'commit metadata requires compact host presentation',
              ),
            );
          }
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// Audits the first-party implementation behind a host presentation adapter.
///
/// Feature-source checks stop at the required [GitPresentation] boundary. This
/// second pass starts at concrete host roots and follows resolved references to
/// declarations in the host package and the resolved first-party shared Git UI
/// package, including inherited renderers and mixins. Consequently, a BusyStack wrapper
/// cannot conceal a prohibited Flutter Material construction merely by having
/// an approved-looking name. Upstream packages remain outside this construction
/// boundary: their supported public widgets may have implementation details of
/// their own and are not modified or reclassified here.
Future<List<NativeUiViolation>> auditFirstPartyPresentationChain(
  String input,
  List<String> rootClasses,
) async {
  final file = File(input);
  if (!file.existsSync() || !input.endsWith('.dart')) {
    throw ArgumentError('Missing host presentation source: $input');
  }
  if (rootClasses.isEmpty) {
    throw ArgumentError('At least one host presentation root is required.');
  }
  final path = file.resolveSymbolicLinksSync();
  final packageRoot = _findPackageRoot(file);
  final packageLibrary = Directory(
    '${packageRoot.path}${Platform.pathSeparator}lib',
  );
  final includedPaths = packageLibrary.existsSync()
      ? [packageLibrary.resolveSymbolicLinksSync()]
      : packageRoot
            .listSync(followLinks: false)
            .whereType<File>()
            .where((entry) => entry.path.endsWith('.dart'))
            .map((entry) => entry.resolveSymbolicLinksSync())
            .toList();
  if (!includedPaths.contains(path)) includedPaths.add(path);
  final collection = AnalysisContextCollection(includedPaths: includedPaths);
  try {
    final index = _FirstPartyIndex(collection, packageRoot, path);
    final declarations = await index.declarationsFor(path);
    final roots = <AstNode>[];
    for (final selector in rootClasses) {
      final separator = selector.indexOf('.');
      final className = separator < 0
          ? selector
          : selector.substring(0, separator);
      final memberName = separator < 0
          ? null
          : selector.substring(separator + 1);
      final root = declarations.classesByName[className];
      if (root == null) {
        throw StateError(
          'Host presentation root $selector moved; update the required audit.',
        );
      }
      if (memberName == null) {
        roots.add(root);
        continue;
      }
      final members = root.body.members
          .whereType<MethodDeclaration>()
          .where((member) => member.name.lexeme == memberName)
          .toList();
      if (members.length != 1) {
        throw StateError(
          'Host presentation root $selector moved; update the required audit.',
        );
      }
      roots.add(members.single);
    }

    final pending = <_PendingFirstPartyDeclaration>[
      for (final root in roots)
        _PendingFirstPartyDeclaration(path: path, node: root),
    ];
    return await _auditFirstPartyDeclarations(index, pending);
  } finally {
    await collection.dispose();
  }
}

Future<List<NativeUiViolation>> _auditFirstPartyDeclarations(
  _FirstPartyIndex index,
  List<_PendingFirstPartyDeclaration> pending, {
  bool notificationBridge = false,
}) async {
  final visited = <String>{};
  final violations = <NativeUiViolation>[];
  while (pending.isNotEmpty) {
    final declaration = pending.removeLast();
    final node = declaration.node;
    final visitKey = '${declaration.path}:${node.offset}:${node.runtimeType}';
    if (!visited.add(visitKey)) continue;
    final visitor = _FirstPartyChainVisitor(
      declaration.path,
      hostNotification: notificationBridge && !declaration.sharedOrigin,
    );
    node.accept(visitor);
    violations.addAll(visitor.violations);
    for (final element in visitor.followedElements) {
      final target = await index.declarationFor(element);
      if (target != null) pending.add(target);
    }
  }
  return violations;
}

Directory _findPackageRoot(File source) {
  var directory = source.absolute.parent;
  while (true) {
    if (File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    ).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return source.absolute.parent;
    directory = parent;
  }
}

final class _PendingFirstPartyDeclaration {
  const _PendingFirstPartyDeclaration({
    required this.path,
    required this.node,
    this.sharedOrigin = false,
  });
  final String path;
  final AstNode node;
  final bool sharedOrigin;
}

final class _FirstPartyIndex {
  _FirstPartyIndex(this.collection, this.packageRoot, this.hostPath);

  final AnalysisContextCollection collection;
  final Directory packageRoot;
  final String hostPath;
  final Map<String, _FirstPartyDeclarations> _units = {};

  bool _contains(String path, Element element) {
    final root = packageRoot.resolveSymbolicLinksSync();
    final candidate = File(path).resolveSymbolicLinksSync();
    return candidate == root ||
        candidate.startsWith('$root${Platform.pathSeparator}') ||
        // This resolved first-party package owns the Linux renderer used by
        // both hosts. Third-party packages remain outside the audit boundary.
        element.library?.uri.toString().startsWith(
              'package:busystack_git_flutter/',
            ) ==
            true;
  }

  Future<_FirstPartyDeclarations> declarationsFor(String path) async {
    final resolvedPath = File(path).resolveSymbolicLinksSync();
    final cached = _units[resolvedPath];
    if (cached != null) return cached;
    final result = await collection
        .contextFor(hostPath)
        .currentSession
        .getResolvedUnit(resolvedPath);
    if (result is! ResolvedUnitResult) {
      throw StateError(
        'Cannot resolve host presentation source: $resolvedPath',
      );
    }
    final errors = result.diagnostics.where(
      (error) => error.diagnosticCode.severity == DiagnosticSeverity.ERROR,
    );
    if (errors.isNotEmpty) {
      throw StateError(
        'Unresolved host presentation source $resolvedPath: ${errors.join('; ')}',
      );
    }
    final declarations = _FirstPartyDeclarations();
    result.unit.accept(declarations);
    _units[resolvedPath] = declarations;
    return declarations;
  }

  Future<_PendingFirstPartyDeclaration?> declarationFor(Element element) async {
    final base = element.baseElement;
    final source = base.firstFragment.libraryFragment?.source.fullName;
    if (source == null || !_contains(source, base)) return null;
    final declarations = await declarationsFor(source);
    AstNode? declaration;
    if (base is ConstructorElement) {
      declaration =
          declarations.classesByElement[base.enclosingElement.baseElement.id];
    } else {
      declaration = declarations.byElement[base.id];
      if (declaration == null && base is PropertyAccessorElement) {
        declaration = declarations.byElement[base.variable.baseElement.id];
      }
    }
    if (declaration == null) return null;
    return _PendingFirstPartyDeclaration(
      path: File(source).resolveSymbolicLinksSync(),
      node: declaration,
      sharedOrigin:
          base.library?.uri.toString().startsWith(
            'package:busystack_git_flutter/',
          ) ==
          true,
    );
  }
}

final class _FirstPartyDeclarations extends RecursiveAstVisitor<void> {
  final Map<int, AstNode> byElement = {};
  final Map<int, ClassDeclaration> classesByElement = {};
  final Map<String, ClassDeclaration> classesByName = {};

  void _record(Element? element, AstNode node) {
    if (element == null) return;
    byElement[element.baseElement.id] = node;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    _record(element, node);
    if (element != null) {
      classesByElement[element.baseElement.id] = node;
      classesByName[node.namePart.typeName.lexeme] = node;
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _record(node.declaredFragment?.element, node);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _record(node.declaredFragment?.element, node);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _record(node.declaredFragment?.element, node);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _record(node.declaredFragment?.element, node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    _record(
      element,
      node.parent is VariableDeclarationList ? node.parent! : node,
    );
    if (element is PropertyInducingElement) {
      _record(
        element.getter,
        node.parent is VariableDeclarationList ? node.parent! : node,
      );
      _record(
        element.setter,
        node.parent is VariableDeclarationList ? node.parent! : node,
      );
    }
    super.visitVariableDeclaration(node);
  }
}

final class _FirstPartyChainVisitor extends _NativeVisitor {
  _FirstPartyChainVisitor(super.path, {this.hostNotification = false});
  final bool hostNotification;

  final _hostSeen = <int>{};
  final followedElements = <Element>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element?.supertype case final parent?) {
      followedElements.add(parent.element);
    }
    if (element != null) {
      followedElements.addAll(element.mixins.map((type) => type.element));
    }
    super.visitClassDeclaration(node);
  }

  @override
  void check(AstNode node, Element? element, {bool construction = false}) {
    if (element == null) return;
    checkNativeHostBoundary(node, element);
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element is VariableElement
        ? element
        : null;
    final type = variable?.type;
    if (type is InterfaceType && type.element.name == 'IconData') {
      final icon = variable?.computeConstantValue();
      if (icon?.getField('fontFamily')?.toStringValue() == 'MaterialIcons' &&
          _hostSeen.add(node.offset)) {
        violations.add(
          NativeUiViolation(
            path,
            node.offset,
            'Material Git glyph through host mapping',
          ),
        );
      }
    }
    if (construction && hostNotification && element is ConstructorElement) {
      final owner = element.enclosingElement;
      if (owner.allSupertypes.any(
            (type) =>
                type.element.name == 'Widget' &&
                type.element.library.uri.toString() ==
                    'package:flutter/src/widgets/framework.dart',
          ) &&
          _hostSeen.add(node.offset)) {
        violations.add(
          NativeUiViolation(
            path,
            node.offset,
            'host-owned Git notification rendering',
          ),
        );
      }
    }
    final library = element.library?.uri.toString() ?? '';
    if (!library.startsWith('package:flutter/src/material/')) return;
    final owner = element is ConstructorElement
        ? element.enclosingElement
        : element;
    final name = owner.name;
    final materialWidget =
        owner is InterfaceElement &&
        owner.allSupertypes.any(
          (type) =>
              type.element.name == 'Widget' &&
              type.element.library.uri.toString() ==
                  'package:flutter/src/widgets/framework.dart',
        );
    if ((construction && materialWidget ||
            (construction || element is ExecutableElement) &&
                forbiddenMaterial.contains(name)) &&
        _hostSeen.add(node.offset)) {
      violations.add(NativeUiViolation(path, node.offset, name ?? '?'));
    }
  }

  void _follow(Element? element) {
    if (element == null) return;
    // A class name used as a static namespace or type annotation does not
    // execute the whole class. Constructors are followed separately below,
    // and the referenced static member has its own resolved identifier.
    if (element.baseElement is InterfaceElement) return;
    followedElements.add(element);
    // Calling State.enqueue can schedule build without referring to its widget
    // constructor. Include that supported rendering lifecycle, not unrelated
    // classes merely used as namespaces or annotations.
    if (element is MethodElement) {
      final owner = element.enclosingElement;
      if (owner is InterfaceElement &&
          owner.allSupertypes.any(
            (type) =>
                type.element.name == 'State' &&
                type.element.library.uri.toString() ==
                    'package:flutter/src/widgets/framework.dart',
          )) {
        followedElements.add(owner);
      }
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _follow(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _follow(node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    _follow(node.constructorName.element);
    super.visitConstructorReference(node);
  }
}

/// Locate the semantic service callback through resolved constructor identity.
/// Other host callbacks can legitimately open host documents or platform UI.
final class _GitNotificationRoots extends RecursiveAstVisitor<void> {
  final roots = <AstNode>[];
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final owner = node.constructorName.element?.enclosingElement;
    if (owner?.name == 'GitHost' &&
        owner?.library.uri.toString() ==
            'package:busystack_git_flutter/src/host.dart') {
      for (final argument
          in node.argumentList.arguments.whereType<NamedExpression>()) {
        if (argument.name.label.name == 'notify')
          roots.add(argument.expression);
      }
    }
    super.visitInstanceCreationExpression(node);
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
      final notifications = _GitNotificationRoots();
      result.unit.accept(notifications);
      if (notifications.roots.isNotEmpty) {
        final index = _FirstPartyIndex(
          collection,
          _findPackageRoot(File(path)),
          path,
        );
        found.addAll(
          await _auditFirstPartyDeclarations(index, [
            for (final root in notifications.roots)
              _PendingFirstPartyDeclaration(path: path, node: root),
          ], notificationBridge: true),
        );
      }
    }
  } finally {
    await collection.dispose();
  }
  return found;
}

Future<void> main(List<String> args) async {
  String? hostSource;
  final hostRoots = <String>[];
  final featureInputs = <String>[];
  var hostOnly = false;
  for (var index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--host-only':
        hostOnly = true;
      case '--host-source':
        if (++index >= args.length) {
          throw ArgumentError('--host-source requires a Dart file.');
        }
        hostSource = args[index];
      case '--host-root':
        if (++index >= args.length) {
          throw ArgumentError('--host-root requires a class name.');
        }
        hostRoots.add(args[index]);
      default:
        featureInputs.add(args[index]);
    }
  }
  final violations = hostOnly
      ? <NativeUiViolation>[]
      : await auditNativeGitSources(
          featureInputs.isEmpty ? ['lib/src'] : featureInputs,
        );
  if (hostSource != null) {
    violations.addAll(
      await auditFirstPartyPresentationChain(hostSource, hostRoots),
    );
  } else if (hostRoots.isNotEmpty) {
    throw ArgumentError('--host-root requires --host-source.');
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  if (violations.isNotEmpty) {
    exitCode = 1;
  } else {
    stdout.writeln('Native Git presentation boundary passed.');
  }
}
