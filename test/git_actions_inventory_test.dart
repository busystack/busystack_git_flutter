import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

class _Inventory extends RecursiveAstVisitor<void> {
  final menus = <String>[];
  final actions = <String>[];
  final inline = <String>[];
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    record(
      node.constructorName.type.name.lexeme,
      node.constructorName.name?.name,
      node.argumentList,
    );
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    record(
      target ?? node.methodName.name,
      target == null ? null : node.methodName.name,
      node.argumentList,
    );
    super.visitMethodInvocation(node);
  }

  void record(String name, String? constructor, ArgumentList arguments) {
    if (name == 'GitMenuButton') {
      final role = arguments.arguments
          .whereType<NamedExpression>()
          .singleWhere((a) => a.name.label.name == 'role')
          .expression
          .toSource();
      menus.add(role);
      expect(
        arguments.arguments.whereType<NamedExpression>().where(
          (a) => a.name.label.name == 'glyph',
        ),
        isEmpty,
      );
    }
    if (name == 'GitIconButton' && constructor == 'actions')
      actions.add('viewActions');
    if (name == 'GitButton' && constructor == 'diffInline')
      inline.add('diffInline');
  }
}

void main() {
  test(
    'complete production menu inventory preserves semantic responsibilities',
    () {
      final actual = <String, List<String>>{};
      final actions = <String, int>{};
      for (final file
          in Directory('lib/src').listSync().whereType<File>().where(
            (f) => f.path.endsWith('.dart') && !f.path.endsWith('/host.dart'),
          )) {
        final inventory = _Inventory();
        parseString(content: file.readAsStringSync()).unit.accept(inventory);
        final name = file.uri.pathSegments.last;
        if (inventory.menus.isNotEmpty) actual[name] = inventory.menus;
        if (inventory.actions.isNotEmpty)
          actions[name] = inventory.actions.length;
        if (name == 'diff_view.dart') expect(inventory.inline, hasLength(2));
      }
      expect(actual, {
        'branch_views.dart': [
          'GitMenuRole.viewActions',
          'GitMenuRole.entryContext',
        ],
        'commit_view.dart': ['GitMenuRole.selectionOptions'],
        'diff_view.dart': [
          'GitMenuRole.selectionOptions',
          'GitMenuRole.displayOptions',
          'GitMenuRole.viewActions',
        ],
        'log_view.dart': [
          'GitMenuRole.viewActions',
          'GitMenuRole.entryContext',
        ],
        'history_actions.dart': [
          'GitMenuRole.entryContext',
          'GitMenuRole.entryContext',
        ],
        'historical_change_tree.dart': ['GitMenuRole.entryContext'],
        'organization_views.dart': [
          'GitMenuRole.entryContext',
          'GitMenuRole.entryContext',
        ],
        'network_views.dart': ['GitMenuRole.selectionOptions'],
      });
      expect(actions, {'commit_view.dart': 1, 'log_view.dart': 1});
    },
  );
}
