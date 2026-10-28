import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

GitTextCorrespondence correspondence(String left, String right) =>
    GitTextCorrespondence(computeTextDiff(left, right), left, right);

void main() {
  test('equal Unicode CRLF and missing-final-newline offsets remain exact', () {
    const text = '一章\r\nalpha😀 prose\r\nlast';
    final map = correspondence(text, text);
    for (var offset = 0; offset <= text.length; offset++) {
      expect(map.forward(offset), offset);
      expect(map.reverse(offset), offset);
    }
  });
  test(
    'insertions preserve the next equal character and zero-length boundary',
    () {
      const left = 'a\nend\n', right = 'a\nadded😀\r\nend\n';
      final map = correspondence(left, right), boundary = left.indexOf('end');
      expect(map.forward(boundary), right.indexOf('end'));
      for (
        var offset = right.indexOf('added');
        offset < right.indexOf('end');
        offset++
      ) {
        expect(map.reverse(offset), boundary);
      }
      expect(map.forward(left.length), right.length);
    },
  );
  test('deletion maps real source lines to the surviving boundary', () {
    const left = 'a\nremoved one\nremoved two\nend', right = 'a\nend';
    final map = correspondence(left, right);
    for (
      var offset = left.indexOf('removed');
      offset < left.indexOf('end');
      offset++
    ) {
      expect(map.forward(offset), right.indexOf('end'));
    }
    expect(map.reverse(right.indexOf('end')), left.indexOf('end'));
  });
  test(
    'replacement uses logical line and column rather than a proportional offset',
    () {
      const left = 'a\nlong old first\nsecond old\nend',
          right =
              'a\nx\nnew second content with a very different length\nthird\nend';
      final map = correspondence(left, right);
      expect(
        map.forward(left.indexOf('second') + 3),
        right.indexOf('new second') + 3,
      );
      expect(map.forward(left.indexOf('first')), right.indexOf('x') + 1);
      expect(map.forward(left.indexOf('end')), right.lastIndexOf('end'));
    },
  );
  test(
    'extra changed lines map to a boundary without moving correspondence backwards',
    () {
      const left = 'a\nfirst lengthy\nsecond lengthy\nthird lengthy\nend',
          right = 'a\nx\nend';
      final map = correspondence(left, right);
      var previous = -1;
      for (var offset = 0; offset <= left.length; offset++) {
        final target = map.forward(offset);
        expect(
          target,
          greaterThanOrEqualTo(previous),
          reason: 'source offset $offset',
        );
        expect(target, inInclusiveRange(0, right.length));
        previous = target;
      }
      expect(map.forward(left.indexOf('second')), right.indexOf('end'));
    },
  );
  test('empty and complete deletions preserve real document boundaries', () {
    final added = correspondence('', 'new\n');
    expect(added.forward(0), 4);
    expect(added.reverse(2), 0);
    final deleted = correspondence('new\n', '');
    expect(deleted.forward(2), 0);
    expect(deleted.reverse(0), 4);
  });
  test('mismatched sources and invalid offsets are rejected', () {
    expect(
      () => GitTextCorrespondence(computeTextDiff('a', 'b'), 'longer', 'b'),
      throwsArgumentError,
    );
    final map = correspondence('a', 'b');
    expect(() => map.forward(2), throwsRangeError);
    expect(() => map.reverse(-1), throwsRangeError);
  });
  test(
    'worker computation returns the same immutable source correspondence',
    () async {
      const left = 'header\r\n旧文\r\nend',
          right = 'header\r\nnew text\r\nextra\r\nend';
      final map = await GitTextCorrespondence.compute(left, right);
      expect(map.forward(left.indexOf('end')), right.lastIndexOf('end'));
      expect(map.left, left);
      expect(map.right, right);
    },
  );
}
