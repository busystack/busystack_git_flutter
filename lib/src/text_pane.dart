import 'messages.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'host.dart';
import 'text_undo.dart';

enum GitHighlightKind { staged, unstaged, conflict }

final class GitTextHighlight {
  const GitTextHighlight(this.start, this.end, this.kind);
  final int start, end;
  final GitHighlightKind kind;
}

/// Paint reviewed regions without replacing the text field or its undo stack.
final class GitHighlightedTextController extends TextEditingController {
  GitHighlightedTextController({super.text});
  List<GitTextHighlight> _highlights = const [];
  List<GitTextHighlight> get highlights => _highlights;

  void setHighlights(List<GitTextHighlight> ranges) {
    _highlights = ranges;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final content = text;
    final boundaries = <int>{0, content.length};
    for (final range in _highlights) {
      boundaries.add(range.start.clamp(0, content.length));
      boundaries.add(range.end.clamp(0, content.length));
    }
    final composing = value.composing;
    if (withComposing && composing.isValid && composing.end <= content.length) {
      boundaries.add(composing.start);
      boundaries.add(composing.end);
    }
    final offsets = boundaries.toList()..sort();
    final colors = Theme.of(context).colorScheme;
    Color? background(int start, int end) {
      GitHighlightKind? kind;
      for (final range in _highlights) {
        if (range.start >= end || range.end <= start) continue;
        kind = kind == null || kind == range.kind
            ? range.kind
            : GitHighlightKind.conflict;
      }
      return switch (kind) {
        GitHighlightKind.staged => colors.primaryContainer.withValues(
          alpha: .55,
        ),
        GitHighlightKind.unstaged => colors.tertiaryContainer.withValues(
          alpha: .55,
        ),
        GitHighlightKind.conflict => colors.errorContainer.withValues(
          alpha: .65,
        ),
        null => null,
      };
    }

    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i + 1 < offsets.length; i++)
          TextSpan(
            text: content.substring(offsets[i], offsets[i + 1]),
            style: TextStyle(
              backgroundColor: background(offsets[i], offsets[i + 1]),
              decoration:
                  withComposing &&
                      composing.isValid &&
                      offsets[i] < composing.end &&
                      offsets[i + 1] > composing.start
                  ? TextDecoration.underline
                  : null,
            ),
          ),
      ],
    );
  }
}

/// A revision pane with a real native text field and logical line numbers.
/// The gutter measures the editable's actual caret geometry, including wrapping
/// and text scaling, instead of assuming a fixed line height.
final class GitTextPane extends StatefulWidget {
  const GitTextPane({
    super.key,
    required this.label,
    this.text,
    this.controller,
    this.undoController,
    this.scrollController,
    this.focusNode,
    this.semanticLabel,
    this.onChanged,
    this.readOnly = false,
    this.revealOffset,
    this.revealRevision = 0,
  });
  final String label;
  final String? text, semanticLabel;
  final TextEditingController? controller;
  final UndoHistoryController? undoController;
  final ScrollController? scrollController;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final int? revealOffset;
  final int revealRevision;
  @override
  State<GitTextPane> createState() => _TextPaneState();
}

final class _TextPaneState extends State<GitTextPane> {
  final _fieldKey = GlobalKey(), _rowKey = GlobalKey();
  final _geometry = ValueNotifier<int>(0);
  TextEditingController? _ownedText;
  ScrollController? _ownedScroll;
  TextEditingController get _text => widget.controller ?? _ownedText!;
  ScrollController get _scroll => widget.scrollController ?? _ownedScroll!;
  String? _lineText;
  List<int> _lineStarts = [0];

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedText = TextEditingController(text: widget.text ?? '');
    }
    if (widget.scrollController == null) _ownedScroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didUpdateWidget(covariant GitTextPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _ownedText?.dispose();
      _ownedText = widget.controller == null
          ? TextEditingController(text: widget.text ?? '')
          : null;
    } else if (widget.controller == null && widget.text != oldWidget.text) {
      _ownedText!.text = widget.text ?? '';
    }
    if (widget.scrollController != oldWidget.scrollController) {
      _ownedScroll?.dispose();
      _ownedScroll = widget.scrollController == null
          ? ScrollController()
          : null;
    }
    if (widget.revealOffset != oldWidget.revealOffset ||
        widget.revealRevision != oldWidget.revealRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  RenderEditable? _editable() {
    RenderEditable? result;
    void visit(RenderObject node) {
      if (node is RenderEditable) {
        result = node;
      } else if (result == null) {
        node.visitChildren(visit);
      }
    }

    final render = _fieldKey.currentContext?.findRenderObject();
    if (render != null) visit(render);
    return result;
  }

  void _reveal() {
    if (!mounted) return;
    final editable = _editable(), offset = widget.revealOffset;
    if (editable != null && offset != null && _scroll.hasClients) {
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: offset.clamp(0, _text.text.length)),
      );
      _scroll.jumpTo(
        (_scroll.offset + caret.top - 24).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
    _geometry.value++;
  }

  @override
  void dispose() {
    _ownedText?.dispose();
    _ownedScroll?.dispose();
    _geometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontFamily: 'monospace');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: GitLabel(widget.label, maxLines: 2),
        ),
        const Divider(height: 1),
        Expanded(
          child: AnimatedBuilder(
            animation: _text,
            builder: (context, _) {
              if (_lineText != _text.text) {
                _lineText = _text.text;
                _lineStarts = [0];
                for (var i = 0; i < _lineText!.length; i++) {
                  if (_lineText!.codeUnitAt(i) == 10) _lineStarts.add(i + 1);
                }
              }
              final digits = _lineStarts.length.toString().length;
              final measure = TextPainter(
                text: TextSpan(text: '9' * digits, style: style),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final gutter = measure.width + 16;
              measure.dispose();
              return Row(
                key: _rowKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: SizedBox(
                      width: gutter,
                      child: ClipRect(
                        child: CustomPaint(
                          painter: _LineGutter(
                            starts: _lineStarts,
                            editable: _editable,
                            row: () =>
                                _rowKey.currentContext?.findRenderObject()
                                    as RenderBox?,
                            style: style.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            textScaler: MediaQuery.textScalerOf(context),
                            highlights: _text is GitHighlightedTextController
                                ? (_text as GitHighlightedTextController)
                                      .highlights
                                : const [],
                            stagedColor: Theme.of(context).colorScheme.primary,
                            unstagedColor: Theme.of(
                              context,
                            ).colorScheme.tertiary,
                            conflictColor: Theme.of(context).colorScheme.error,
                            repaint: Listenable.merge([
                              _text,
                              _scroll,
                              _geometry,
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: GitTextUndo(
                      controller: _text,
                      history: widget.undoController,
                      enabled: widget.controller != null && !widget.readOnly,
                      child: TextField(
                        key: _fieldKey,
                        controller: _text,
                        readOnly: widget.controller == null || widget.readOnly,
                        scrollController: _scroll,
                        focusNode: widget.focusNode,
                        expands: true,
                        maxLines: null,
                        onChanged: widget.onChanged,
                        textAlignVertical: TextAlignVertical.top,
                        style: style,
                        decoration: InputDecoration(
                          labelText: gitString(
                            context,
                            widget.semanticLabel ??
                                (widget.controller == null
                                    ? GitMessages.readOnlyRevisionContent
                                    : GitMessages.editableIndexContent),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _LineGutter extends CustomPainter {
  _LineGutter({
    required this.starts,
    required this.editable,
    required this.row,
    required this.style,
    required this.textScaler,
    required this.highlights,
    required this.stagedColor,
    required this.unstagedColor,
    required this.conflictColor,
    required super.repaint,
  });
  final List<int> starts;
  final RenderEditable? Function() editable;
  final RenderBox? Function() row;
  final TextStyle style;
  final TextScaler textScaler;
  final List<GitTextHighlight> highlights;
  final Color stagedColor, unstagedColor, conflictColor;

  @override
  void paint(Canvas canvas, Size size) {
    final field = editable(), ancestor = row();
    if (field == null ||
        !field.attached ||
        !field.hasSize ||
        ancestor == null ||
        !ancestor.hasSize)
      return;
    Rect caret(int line) {
      final rect = field.getLocalRectForCaret(
        TextPosition(offset: starts[line]),
      );
      return rect.shift(field.localToGlobal(Offset.zero, ancestor: ancestor));
    }

    var low = 0, high = starts.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (caret(middle).bottom < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var i = low; i < starts.length; i++) {
      final rect = caret(i);
      if (rect.top > size.height) break;
      final number = TextPainter(
        text: TextSpan(text: '${i + 1}', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      number.paint(
        canvas,
        Offset(
          math.max(0, size.width - number.width - 6),
          rect.top + (rect.height - number.height) / 2,
        ),
      );
      number.dispose();
    }
    final contentLength = field.text?.toPlainText().length ?? 0;
    for (final highlight in highlights) {
      final start = highlight.start.clamp(0, contentLength);
      final end = highlight.end.clamp(start, contentLength);
      final startRect = field
          .getLocalRectForCaret(TextPosition(offset: start))
          .shift(field.localToGlobal(Offset.zero, ancestor: ancestor));
      final endRect = field
          .getLocalRectForCaret(TextPosition(offset: end))
          .shift(field.localToGlobal(Offset.zero, ancestor: ancestor));
      if (startRect.top > size.height || endRect.bottom < 0) continue;
      final color = switch (highlight.kind) {
        GitHighlightKind.staged => stagedColor,
        GitHighlightKind.unstaged => unstagedColor,
        GitHighlightKind.conflict => conflictColor,
      };
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          startRect.top.clamp(0, size.height).toDouble(),
          3,
          math
              .max(4, endRect.bottom - startRect.top)
              .clamp(0, size.height - startRect.top.clamp(0, size.height))
              .toDouble(),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineGutter oldDelegate) => true;
}
