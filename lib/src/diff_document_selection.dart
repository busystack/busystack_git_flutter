import 'package:busystack_git/busystack_git.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps the aligned, virtualized diff rows while selecting one source document.
/// Flutter still owns gestures, paragraph selection, highlighting and scrolling.
final class GitDiffDocumentSelection extends StatefulWidget {
  const GitDiffDocumentSelection({
    super.key,
    required this.diff,
    required this.unified,
    required this.child,
  });
  final TextDiff diff;
  final bool unified;
  final Widget child;
  @override
  State<GitDiffDocumentSelection> createState() => _DocumentSelectionState();
}

final class _DocumentSelectionState extends State<GitDiffDocumentSelection> {
  late final _Documents documents = _Documents(widget.diff, widget.unified);
  @override
  void didUpdateWidget(GitDiffDocumentSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diff != widget.diff || oldWidget.unified != widget.unified) {
      documents.reset(widget.diff, widget.unified);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SelectionContainer(
        delegate: documents.selection,
        child: _DocumentScope(
          documents: documents,
          child: LayoutBuilder(
            builder: (context, bounds) => Listener(
              onPointerDown: (event) {
                documents.activate(
                  !widget.unified &&
                      event.localPosition.dx > bounds.maxWidth / 2,
                );
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    documents.dispose();
    super.dispose();
  }
}

/// Registers only a real source line. Gutters, padding and operation labels do
/// not participate, and the native Scrollable selection container stays intact.
final class GitDiffCopyText extends StatelessWidget {
  const GitDiffCopyText({
    super.key,
    required this.line,
    required this.right,
    required this.child,
  });
  final int? line;
  final bool right;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final documents = context
        .dependOnInheritedWidgetOfExactType<_DocumentScope>()!
        .documents;
    final parent = SelectionContainer.maybeOf(context);
    if (line == null || parent == null)
      return SelectionContainer.disabled(child: child);
    return SelectionRegistrarScope(
      registrar: documents.registrar(parent, right, line!),
      child: child,
    );
  }
}

final class _DocumentScope extends InheritedWidget {
  const _DocumentScope({required this.documents, required super.child});
  final _Documents documents;
  @override
  bool updateShouldNotify(_DocumentScope oldWidget) =>
      oldWidget.documents != documents;
}

typedef _Anchor = ({int line, int offset});

final class _Documents {
  _Documents(TextDiff diff, bool unified) {
    _sources(diff, unified);
  }
  late final selection = _DocumentSelectionDelegate(this);
  final _registrars = <(SelectionRegistrar, bool, int), _LineRegistrar>{};
  final proxies = <_DocumentSelectable>{};
  List<String> left = [], right = [];
  bool activeRight = false, all = false;
  _Anchor? start, end;
  Offset? _pendingStart;
  bool registrationPending = false, disposed = false;
  int _registrationGeneration = 0;
  void _sources(TextDiff diff, bool unified) {
    left = [
      for (final edit in diff.edits)
        if (unified || edit.oldLine != null) edit.text,
    ];
    right = [
      for (final edit in diff.edits)
        if (edit.newLine != null) edit.text,
    ];
  }

  void reset(TextDiff diff, bool unified) {
    selection.dispatchSelectionEvent(const ClearSelectionEvent());
    _registrationGeneration++;
    registrationPending = false;
    _sources(diff, unified);
  }

  void activate(bool right) {
    if (activeRight == right) return;
    selection.dispatchSelectionEvent(const ClearSelectionEvent());
    activeRight = right;
    registrationPending = true;
    final generation = ++_registrationGeneration;
    for (final proxy in proxies.toList()) {
      proxy.updateRegistration();
    }
    // Registrar additions become laid-out selectable children after this frame.
    // Retain and replay actual selection requests through the supported pending
    // result, rather than making mouse correctness depend on an event delay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (disposed || generation != _registrationGeneration) return;
      registrationPending = false;
      selection.flushPending();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    disposed = true;
    _registrationGeneration++;
    selection.dispose();
  }

  _LineRegistrar registrar(SelectionRegistrar parent, bool right, int line) =>
      _registrars.putIfAbsent((
        parent,
        right,
        line,
      ), () => _LineRegistrar(this, parent, right, line));
  void capture(SelectionEvent event) {
    if (event is ClearSelectionEvent) {
      start = end = null;
      _pendingStart = null;
      all = false;
      return;
    }
    if (event is SelectAllSelectionEvent) {
      all = true;
      return;
    }
    all = false;
    if (event is! SelectionEdgeUpdateEvent) {
      final selected = [
        for (final proxy in proxies)
          if (proxy.active && proxy.child.getSelection() != null) proxy,
      ]..sort((a, b) => a.line.compareTo(b.line));
      if (selected.isNotEmpty) {
        start = (
          line: selected.first.line,
          offset: selected.first.child.getSelection()!.startOffset,
        );
        end = (
          line: selected.last.line,
          offset: selected.last.child.getSelection()!.endOffset,
        );
      }
      return;
    }
    _Anchor? nearest(Offset position) {
      double distance = double.infinity;
      _Anchor? anchor;
      for (final proxy in proxies) {
        if (!proxy.active) continue;
        final range = proxy.child.getSelection();
        if (range == null) continue;
        final geometry = proxy.child.value;
        for (final edge in [
          (geometry.startSelectionPoint, range.startOffset),
          (geometry.endSelectionPoint, range.endOffset),
        ]) {
          if (edge.$1 == null) continue;
          final point = MatrixUtils.transformPoint(
            proxy.child.getTransformTo(null),
            edge.$1!.localPosition,
          );
          final delta = (point - position).distanceSquared;
          if (delta < distance) {
            distance = delta;
            anchor = (line: proxy.line, offset: edge.$2);
          }
        }
      }
      return anchor;
    }

    if (event.type == SelectionEventType.startEdgeUpdate) {
      _pendingStart = event.globalPosition;
      start = nearest(event.globalPosition);
    } else {
      // A collapsed mouse-down has no selected-content range yet. Resolve its
      // source anchor as soon as the drag makes the upstream selection nonempty.
      if (start == null && _pendingStart != null)
        start = nearest(_pendingStart!);
      end = nearest(event.globalPosition);
    }
  }

  SelectedContent? content() {
    final source = activeRight ? right : left;
    if (all) return SelectedContent(plainText: source.join());
    var first = start, last = end;
    if (first == null || last == null) return null;
    if (first.line > last.line ||
        first.line == last.line && first.offset > last.offset) {
      final swap = first;
      first = last;
      last = swap;
    }
    if (first.line >= source.length || last.line >= source.length) return null;
    if (first.offset > source[first.line].length ||
        last.offset > source[last.line].length)
      return null;
    if (first.line == last.line)
      return SelectedContent(
        plainText: source[first.line].substring(first.offset, last.offset),
      );
    return SelectedContent(
      plainText:
          source[first.line].substring(first.offset) +
          source.sublist(first.line + 1, last.line).join() +
          source[last.line].substring(0, last.offset),
    );
  }
}

final class _DocumentSelectionDelegate
    extends StaticSelectionContainerDelegate {
  _DocumentSelectionDelegate(this.documents);
  final _Documents documents;
  final _pending = <SelectionEvent>[];
  void flushPending() {
    final pending = List<SelectionEvent>.of(_pending);
    _pending.clear();
    for (final event in pending) {
      dispatchSelectionEvent(event);
    }
  }

  @override
  SelectionGeometry
  getSelectionGeometry() => super.getSelectionGeometry().copyWith(
    // The bounded source document remains present while its visible paragraphs
    // register for the next layout; no selection is claimed before it exists.
    hasContent:
        (documents.activeRight ? documents.right : documents.left).isNotEmpty,
  );
  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (event is ClearSelectionEvent) _pending.clear();
    if (documents.registrationPending && event is! ClearSelectionEvent) {
      _pending.removeWhere((value) => value.type == event.type);
      _pending.add(event);
      return SelectionResult.pending;
    }
    final result = super.dispatchSelectionEvent(event);
    documents.capture(event);
    return result;
  }

  @override
  SelectedContent? getSelectedContent() => documents.content();
}

final class _LineRegistrar implements SelectionRegistrar {
  _LineRegistrar(this.documents, this.parent, this.right, this.line);
  final _Documents documents;
  final SelectionRegistrar parent;
  final bool right;
  final int line;
  final _children = <Selectable, _DocumentSelectable>{};
  @override
  void add(Selectable selectable) {
    final proxy = _DocumentSelectable(
      selectable,
      documents,
      parent,
      right,
      line,
    );
    _children[selectable] = proxy;
    documents.proxies.add(proxy);
    proxy.updateRegistration();
  }

  @override
  void remove(Selectable selectable) {
    final proxy = _children.remove(selectable);
    if (proxy == null) return;
    proxy.unregister();
    documents.proxies.remove(proxy);
    proxy.dispose();
    if (_children.isEmpty) documents._registrars.remove((parent, right, line));
  }
}

// A supported Selectable adapter leaves all real paragraph operations upstream.
// It excludes the other document from selection without changing row geometry.
final class _DocumentSelectable extends ChangeNotifier with Selectable {
  _DocumentSelectable(
    this.child,
    this.documents,
    this.parent,
    this.right,
    this.line,
  ) {
    child.addListener(changed);
  }
  final Selectable child;
  final _Documents documents;
  final SelectionRegistrar parent;
  bool _registered = false;
  void updateRegistration() {
    if (_registered == active) return;
    if (active) {
      _registered = true;
      parent.add(this);
    } else {
      unregister();
    }
  }

  void unregister() {
    if (!_registered) return;
    _registered = false;
    parent.remove(this);
  }

  final bool right;
  final int line;
  bool get active => right == documents.activeRight;
  void changed() => notifyListeners();
  @override
  SelectionGeometry get value => active
      ? child.value
      : const SelectionGeometry(
          status: SelectionStatus.none,
          hasContent: false,
        );
  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      child.getTransformTo(ancestor);
  @override
  Size get size => child.size;
  @override
  List<Rect> get boundingBoxes => child.boundingBoxes;
  @override
  int get contentLength => active ? child.contentLength : 0;
  @override
  SelectedContent? getSelectedContent() =>
      active ? child.getSelectedContent() : null;
  @override
  SelectedContentRange? getSelection() => active ? child.getSelection() : null;
  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) => child
      .pushHandleLayers(active ? startHandle : null, active ? endHandle : null);
  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (active || event is ClearSelectionEvent)
      return child.dispatchSelectionEvent(event);
    if (event is SelectionEdgeUpdateEvent) {
      final bounds = MatrixUtils.transformRect(
        child.getTransformTo(null),
        Offset.zero & child.size,
      );
      if (event.globalPosition.dy < bounds.top) return SelectionResult.previous;
      if (event.globalPosition.dy > bounds.bottom) return SelectionResult.next;
      return right ? SelectionResult.previous : SelectionResult.next;
    }
    return SelectionResult.none;
  }

  @override
  void dispose() {
    child.removeListener(changed);
    super.dispose();
  }
}
