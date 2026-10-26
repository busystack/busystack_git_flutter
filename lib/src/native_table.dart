import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'host.dart';

/// Presentation metadata for the two Git tables. No paths here grant access
/// to repository content: actions return an opaque row ID to the owning view.
final class GitNativeRow {
  const GitNativeRow({
    required this.id,
    required this.cells,
    this.description = '',
    this.parent = -1,
    this.depth = 0,
    this.expanded = -1,
    this.actions = const {},
    this.textInsets = const [],
  });
  final String id, description;
  final List<String> cells;
  final int parent, depth, expanded;
  final Map<String, String> actions;
  final List<double> textInsets;

  Map<String, Object> packet(int index) => {
    'index': index,
    'id': id,
    'cells': cells,
    'description': description,
    'parent': parent,
    'depth': depth,
    'expanded': expanded,
    'textInsets': textInsets,
    'actions': [
      for (final action in actions.entries)
        {'id': action.key, 'label': action.value},
    ],
  };
}

final class GitNativeTableRequest {
  const GitNativeTableRequest(this.action, this.row, this.column);
  final String action;
  final int row, column;
}

/// Bridges only Git Log and Commit rows to Linux ATK. The application owns
/// the GTK content overlay. All pixels, keyboard handling and Git actions stay
/// in these shared Flutter views; other platforms retain Flutter semantics.
///
/// A view/repository generation and opaque row identity bind every callback.
/// Only visible metadata is sent initially; AT can request bounded row pages
/// without a Git query or materializing every accessible row.
final class GitNativeTable extends StatefulWidget {
  const GitNativeTable({
    super.key,
    required this.name,
    required this.revision,
    required this.rowCount,
    required this.rowAt,
    required this.columns,
    required this.widths,
    required this.rowHeight,
    required this.scroll,
    required this.focus,
    required this.selected,
    required this.focusedRow,
    required this.onRequest,
    required this.builder,
    this.description = '',
    this.tree = false,
    this.headers = true,
    this.busy = false,
    this.active = true,
    this.headerInsets = const [],
  });
  final String name, description;
  final Object revision;
  final int rowCount, focusedRow;
  final GitNativeRow Function(int) rowAt;
  final List<String> columns;
  final List<double> widths;
  final List<double> headerInsets;
  final double rowHeight;
  final ScrollController scroll;
  final FocusNode focus;
  final List<int> selected;
  final bool tree, headers, busy, active;
  final ValueChanged<GitNativeTableRequest> onRequest;
  final Widget Function(bool nativeReady) builder;

  @override
  State<GitNativeTable> createState() => _GitNativeTableState();
}

final class _GitNativeTableState extends State<GitNativeTable>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('busystack_git_flutter/accessibility');
  // This registry routes native notifications to their original view. It has
  // no current repository and cannot redirect an outstanding action to a tab.
  static final _views = <String, _GitNativeTableState>{};
  static int _nextId = 0;
  late final String _id = 'git-table-${++_nextId}';
  final _geometry = GlobalKey();
  int _generation = 1, _serial = 0, _submitted = -1;
  Rect? _lastRect;
  bool _scheduled = false, _registered = false, _ready = false;
  bool _routeVisible = true, _applicationVisible = true;
  bool _sending = false;
  bool _changedDuringSend = false;
  String? _failure;

  bool get _linux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  bool get _visible => widget.active && _routeVisible && _applicationVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.scroll.addListener(_changed);
    widget.focus.addListener(_changed);
    if (_linux) {
      _views[_id] = this;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'request') throw MissingPluginException();
        final args = call.arguments;
        if (args is! Map) return false;
        return _views[args['id']]?._request(args) ?? false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _changed();
  }

  @override
  void didUpdateWidget(GitNativeTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision ||
        widget.rowCount != oldWidget.rowCount ||
        !listEquals(widget.columns, oldWidget.columns)) {
      _generation++;
    }
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll.removeListener(_changed);
      widget.scroll.addListener(_changed);
    }
    if (oldWidget.focus != widget.focus) {
      oldWidget.focus.removeListener(_changed);
      widget.focus.addListener(_changed);
    }
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationVisible =
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    _changed();
  }

  void _changed() {
    _serial++;
    _schedule();
  }

  void _schedule({bool wake = true}) {
    if (!_linux || _scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_synchronize());
    });
    if (wake) WidgetsBinding.instance.ensureVisualUpdate();
  }

  List<Map<String, Object>> _rows(int start, int count) => [
    for (var i = start; i < math.min(widget.rowCount, start + count); i++)
      widget.rowAt(i).packet(i),
  ];

  Future<bool> _request(Map args) async {
    if (!mounted ||
        !_visible ||
        !_registered ||
        args['generation'] != _generation)
      return false;
    final action = args['action'], row = args['row'], column = args['column'];
    if (action is! String || row is! int || column is! int) return false;
    if (action == 'rows') {
      final count = args['count'];
      if (count is! int ||
          count < 1 ||
          count > 128 ||
          row < 0 ||
          row >= widget.rowCount)
        return false;
      try {
        await _channel.invokeMethod<bool>('rows', {
          'id': _id,
          'generation': _generation,
          'rows': _rows(row, count),
        });
      } on PlatformException catch (error) {
        // A refresh/removal can overtake this optional row-page response.
        if (error.code != 'stale') _failed();
      } on MissingPluginException {
        _failed();
      }
      return true;
    }
    if (row < -1 ||
        row >= widget.rowCount ||
        column < -1 ||
        column >= widget.columns.length)
      return false;
    // An unloaded native row can be revealed by generation/index. Selection,
    // focus and context actions retain the full row-identity requirement.
    if (row >= 0 &&
        widget.rowAt(row).id != args['rowId'] &&
        !(action == 'scroll' && args['rowId'] == ''))
      return false;
    if (row < 0 && !const {'clearSelection', 'selectAll'}.contains(action)) {
      return false;
    }
    const ordinary = {
      'select',
      'focus',
      'scroll',
      'context',
      'addSelection',
      'removeSelection',
      'clearSelection',
      'selectAll',
    };
    if (!ordinary.contains(action) &&
        (row < 0 || !widget.rowAt(row).actions.containsKey(action)))
      return false;
    widget.onRequest(GitNativeTableRequest(action, row, column));
    return true;
  }

  void _failed() {
    if (!mounted) return;
    setState(() {
      _ready = false;
      _failure =
          'Native Git table accessibility is unavailable. Retry after reconnecting the application.';
    });
    unawaited(_remove());
  }

  Future<void> _remove() async {
    if (!_registered) return;
    _registered = false;
    try {
      await _channel.invokeMethod<bool>('remove', {'id': _id});
    } on MissingPluginException {
      // An engine disconnect destroys its application-owned GTK children.
    } on PlatformException {
      // The native view's destroy handler also releases all of its tables.
    }
  }

  Future<void> _synchronize() async {
    if (_sending) {
      _changedDuringSend = true;
      return;
    }
    if (_failure != null) return;
    if (!_visible) {
      await _remove();
      if (mounted && _ready) setState(() => _ready = false);
      _submitted = -1;
      return;
    }
    final box = _geometry.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (_submitted == _serial && _lastRect == rect) return;
    final serial = _serial, generation = _generation;
    final offset = widget.scroll.hasClients ? widget.scroll.offset : 0.0;
    final first = math.max(
      0,
      (offset / widget.rowHeight).floor() - (widget.headers ? 1 : 0),
    );
    final count = math.min(512, (rect.height / widget.rowHeight).ceil() + 2);
    final style = Theme.of(context).textTheme.bodyMedium;
    final args = <String, Object>{
      'id': _id,
      'generation': generation,
      'name': widget.name,
      'description': widget.description,
      'tree': widget.tree,
      'busy': widget.busy,
      'focused': widget.focus.hasPrimaryFocus,
      'focusedRow': widget.focusedRow,
      'rowCount': widget.rowCount,
      'columns': widget.columns,
      'widths': widget.widths,
      'headerInsets': widget.headerInsets,
      'selected': widget.selected,
      'rowHeight': widget.rowHeight,
      'scroll': offset,
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
      'fontFamily': style?.fontFamily ?? 'Sans',
      'fontSize': MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14),
      'rtl': Directionality.of(context) == TextDirection.rtl,
      'headers': widget.headers,
      'actionLabels': [
        gitString(context, 'Select'),
        gitString(context, 'Context menu'),
        gitString(context, 'Copy text'),
      ],
      'loadingLabel': gitString(context, 'Loading row'),
      'rows': _rows(first, count),
    };
    _sending = true;
    try {
      _registered = true;
      final ready = await _channel.invokeMethod<bool>('update', args);
      if (!mounted) {
        await _remove();
        return;
      }
      if (ready != true) {
        _failed();
        return;
      }
      _submitted = serial;
      _lastRect = rect;
      if (!_ready && generation == _generation && _visible) {
        setState(() => _ready = true);
      }
    } on MissingPluginException {
      _failed();
    } on PlatformException {
      _failed();
    } finally {
      _sending = false;
      if (mounted &&
          _failure == null &&
          (_serial != serial || !_visible || _changedDuringSend)) {
        _changedDuringSend = false;
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    _views.remove(_id);
    _generation++;
    widget.scroll.removeListener(_changed);
    widget.focus.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_remove());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _GitTableGeometry(
      key: _geometry,
      onPaint: () => _schedule(wake: false),
      child: widget.builder(_ready && _visible),
    );
    if (_failure == null) return child;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: GitLabel(_failure!)),
            TextButton(
              onPressed: () {
                setState(() {
                  _failure = null;
                  _submitted = -1;
                });
                _changed();
              },
              child: const GitLabel('Retry'),
            ),
          ],
        ),
        Expanded(child: child),
      ],
    );
  }
}

final class _GitTableGeometry extends SingleChildRenderObjectWidget {
  const _GitTableGeometry({
    super.key,
    required this.onPaint,
    required super.child,
  });
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _GitTableRender(onPaint);
  @override
  void updateRenderObject(BuildContext context, _GitTableRender renderObject) {
    renderObject.onPaint = onPaint;
  }
}

final class _GitTableRender extends RenderProxyBox {
  _GitTableRender(this.onPaint);
  VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
