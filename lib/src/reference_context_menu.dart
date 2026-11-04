import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'context_menu_keys.dart';

// Shared mouse/keyboard context-menu ownership for branch and log references.
final class GitReferenceContextMenu extends StatefulWidget {
  const GitReferenceContextMenu({
    super.key,
    required this.open,
    required this.child,
  });
  final Future<void> Function(Offset)? open;
  final Widget child;
  @override
  State<GitReferenceContextMenu> createState() =>
      GitReferenceContextMenuState();
}

class GitReferenceContextMenuState extends State<GitReferenceContextMenu> {
  final _keys = GitContextMenuKeys();
  @override
  void dispose() {
    _keys.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (focused) {
      if (!focused) _keys.clear();
    },
    onKeyEvent: (_, event) =>
        _keys.handle(
          event,
          widget.open == null
              ? null
              : () {
                  final box = context.findRenderObject();
                  if (box is RenderBox && box.hasSize) {
                    unawaited(
                      widget.open!(
                        box.localToGlobal(
                          Offset(
                            Directionality.of(context) == TextDirection.rtl
                                ? box.size.width
                                : 0,
                            box.size.height,
                          ),
                        ),
                      ),
                    );
                  }
                },
        )
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
    child: widget.child,
  );
}

/// Keeps search-to-results navigation local, including when the toolbar wraps.
/// Composition keys continue to belong to the platform editor.
final class GitReferenceNavigation extends StatefulWidget {
  const GitReferenceNavigation({super.key, required this.builder});
  final Widget Function(FocusScopeNode results) builder;
  @override
  State<GitReferenceNavigation> createState() => _GitReferenceNavigationState();
}

class _GitReferenceNavigationState extends State<GitReferenceNavigation> {
  final results = FocusScopeNode(debugLabel: 'Git reference results');
  @override
  void dispose() {
    results.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(results);
}

Widget gitReferenceSearchNavigation({
  required TextEditingController controller,
  required FocusScopeNode results,
  required Widget child,
}) => ListenableBuilder(
  listenable: controller,
  builder: (context, _) => CallbackShortcuts(
    bindings: {
      if (!controller.value.composing.isValid ||
          controller.value.composing.isCollapsed)
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          results.requestFocus();
          if (results.focusedChild == null) results.nextFocus();
        },
    },
    child: child,
  ),
);

Widget gitReferenceResults({
  required FocusScopeNode focus,
  required Widget child,
}) => FocusScope(
  node: focus,
  child: CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowDown): focus.nextFocus,
      const SingleActivator(LogicalKeyboardKey.arrowUp): focus.previousFocus,
    },
    child: child,
  ),
);
