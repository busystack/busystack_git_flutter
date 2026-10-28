import 'dart:isolate';
import 'package:busystack_git/busystack_git.dart';

/// Immutable character correspondence for the Git revision panes. Equal text
/// maps exactly. A change maps logical lines/columns within its own block;
/// insertion/deletion boundaries map to the adjacent real content boundary.
final class GitTextCorrespondence {
  GitTextCorrespondence(TextDiff diff, this.left, this.right)
    : diff = TextDiff(List.unmodifiable(diff.edits)) {
    var a = 0, b = 0;
    int? changeA, changeB;
    void flush() {
      if (changeA == null) return;
      _spans.add(_Span(changeA!, a, changeB!, b, false, left, right));
      changeA = changeB = null;
    }

    for (final edit in diff.edits) {
      if (edit.kind == TextEditKind.equal) {
        flush();
        _spans.add(
          _Span(
            a,
            a + edit.text.length,
            b,
            b + edit.text.length,
            true,
            left,
            right,
          ),
        );
        a += edit.text.length;
        b += edit.text.length;
      } else {
        changeA ??= a;
        changeB ??= b;
        if (edit.kind == TextEditKind.remove) a += edit.text.length;
        if (edit.kind == TextEditKind.add) b += edit.text.length;
      }
    }
    flush();
    if (a != left.length || b != right.length) {
      throw ArgumentError(
        'The Git correspondence must use the exact diff sources.',
      );
    }
  }
  static Future<GitTextCorrespondence> compute(String left, String right) =>
      Isolate.run(
        () => GitTextCorrespondence(computeTextDiff(left, right), left, right),
      );
  final TextDiff diff;
  final String left, right;
  final _spans = <_Span>[];

  int forward(int offset) => _map(offset, false);
  int reverse(int offset) => _map(offset, true);

  int _map(int offset, bool reverse) {
    final length = reverse ? right.length : left.length;
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    if (offset == length) return reverse ? left.length : right.length;
    // Strictly greater chooses the following real span at a zero-length
    // insertion boundary, preserving the identity of the next equal character.
    var low = 0, high = _spans.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final end = reverse ? _spans[middle].bEnd : _spans[middle].aEnd;
      if (end <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == _spans.length) return reverse ? left.length : right.length;
    final span = _spans[low];
    final sourceStart = reverse ? span.bStart : span.aStart,
        targetStart = reverse ? span.aStart : span.bStart,
        targetEnd = reverse ? span.aEnd : span.bEnd;
    if (span.equal) return targetStart + offset - sourceStart;
    if (targetStart == targetEnd) return targetStart;
    final sourceLines = reverse ? span.bLines : span.aLines,
        targetLines = reverse ? span.aLines : span.bLines;
    var line = 0, last = sourceLines.length;
    while (line + 1 < last) {
      final middle = (line + last) ~/ 2;
      if (sourceLines[middle] <= offset) {
        line = middle;
      } else {
        last = middle;
      }
    }
    if (line >= targetLines.length) return targetEnd;
    final targetLine = line;
    final start = targetLines[targetLine];
    final end = targetLine + 1 < targetLines.length
        ? targetLines[targetLine + 1] - 1
        : targetEnd;
    final column = offset - sourceLines[line];
    return start + (column < end - start ? column : end - start);
  }
}

final class _Span {
  _Span(
    this.aStart,
    this.aEnd,
    this.bStart,
    this.bEnd,
    this.equal,
    String left,
    String right,
  ) : aLines = equal ? const [] : _lines(left, aStart, aEnd),
      bLines = equal ? const [] : _lines(right, bStart, bEnd);
  final int aStart, aEnd, bStart, bEnd;
  final bool equal;
  final List<int> aLines, bLines;
  static List<int> _lines(String text, int start, int end) {
    final result = <int>[start];
    for (var i = start; i < end; i++) {
      if (text.codeUnitAt(i) == 10 && i + 1 < end) result.add(i + 1);
    }
    return result;
  }
}
