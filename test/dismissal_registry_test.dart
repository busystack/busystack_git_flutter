import 'dart:async';
import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one pending dismissal includes a newly attached editor', () async {
    final registry = GitDismissalRegistry();
    final answer = Completer<bool>();
    var firstRequests = 0, newerRequests = 0;
    registry.register(() {
      firstRequests++;
      return answer.future;
    });
    final first = registry.mayDismiss();
    expect(registry.mayDismiss(), same(first));
    registry.register(() async {
      newerRequests++;
      return false;
    });
    answer.complete(true);
    expect(await first, isFalse);
    expect([firstRequests, newerRequests], [1, 1]);
  });

  test(
    'a retired editor is excluded without discarding another draft',
    () async {
      final registry = GitDismissalRegistry();
      final answer = Completer<bool>();
      var retiredRequests = 0;
      final unregister = registry.register(() async {
        retiredRequests++;
        return false;
      });
      registry.register(() => answer.future);
      final request = registry.mayDismiss();
      unregister();
      answer.complete(true);
      expect(await request, isTrue);
      expect(retiredRequests, 0);
    },
  );
}
