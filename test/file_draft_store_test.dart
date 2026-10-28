import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:busystack_git_flutter/busystack_git_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File target;
  FileGitDraftStore store({Duration? timeout}) => FileGitDraftStore(
    file: (_) async => target,
    lockTimeout: timeout ?? const Duration(seconds: 3),
  );
  File namedFile(String key) {
    final name = Platform.isWindows
        ? Uri.encodeComponent(key).replaceAll('*', '%2A')
        : key;
    return File('${directory.path}/$name.txt');
  }

  FileGitDraftStore namedStore() =>
      FileGitDraftStore(file: (key) async => namedFile(key));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('git-draft-store-');
    target = File('${directory.path}/worktree.txt');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'an absent draft is distinguished from an empty persisted draft',
    () async {
      final a = store();
      final missing = await a.readVersioned('worktree');
      expect(missing.text, isNull);
      expect(missing.version, GitStoredDraft.absentVersion);
      final empty = await a.compareAndWrite(
        'worktree',
        expectedVersion: missing.version,
        text: '',
      );
      expect(empty.written, isTrue);
      expect(empty.current.text, '');
      expect(empty.current.version, isNot(missing.version));
      expect(
        (await store().readVersioned('worktree')).version,
        empty.current.version,
      );
    },
  );

  test(
    'legacy Unicode CRLF and missing final newline survive migration',
    () async {
      const text = 'Subject 日本語\r\n\r\nArabic العربية and emoji 🐙\r\nlast';
      await target.writeAsString(text);
      final migrated = await store().readVersioned('worktree');
      expect(migrated.text, text);
      expect(migrated.version, isNot(GitStoredDraft.absentVersion));
      final reopened = await store().readVersioned('worktree');
      expect(reopened.text, text);
      expect(reopened.version, migrated.version);
    },
  );

  test(
    'ordinary JSON plaintext and empty legacy text remain messages',
    () async {
      for (final text in ['{"text":null,"version":"v1-example"}', '']) {
        final file = File(
          '${directory.path}/${text.isEmpty ? 'empty' : 'json'}.txt',
        );
        await file.writeAsString(text);
        final a = FileGitDraftStore(file: (_) async => file);
        expect(await a.read('legacy'), text);
        expect(
          await FileGitDraftStore(file: (_) async => file).read('legacy'),
          text,
        );
      }
    },
  );

  test('independent stores cannot clear a newer second-window draft', () async {
    final a = store(), b = store();
    await a.write('worktree', 'submitted B');
    final submitted = await a.readVersioned('worktree');
    final other = await b.readVersioned('worktree');
    final newer = await b.compareAndWrite(
      'worktree',
      expectedVersion: other.version,
      text: 'newer C',
    );
    final cleared = await a.compareAndWrite(
      'worktree',
      expectedVersion: submitted.version,
      text: null,
    );
    expect(newer.written, isTrue);
    expect(cleared.written, isFalse);
    expect(cleared.current.text, 'newer C');
    expect(cleared.current.version, newer.current.version);
    expect(await store().read('worktree'), 'newer C');
  });

  test(
    'same-text ABA and clear/reopen never restore an old owner token',
    () async {
      final a = store();
      await a.write('worktree', 'B');
      final initial = await a.readVersioned('worktree');
      final b = store();
      var current = await b.readVersioned('worktree');
      for (final text in ['C', 'B']) {
        final result = await b.compareAndWrite(
          'worktree',
          expectedVersion: current.version,
          text: text,
        );
        expect(result.written, isTrue);
        current = result.current;
      }
      expect(current.text, initial.text);
      expect(current.version, isNot(initial.version));
      final stale = await a.compareAndWrite(
        'worktree',
        expectedVersion: initial.version,
        text: null,
      );
      expect(stale.written, isFalse);
      final cleared = await b.compareAndWrite(
        'worktree',
        expectedVersion: current.version,
        text: null,
      );
      expect(cleared.written, isTrue);
      expect(cleared.current.text, isNull);
      expect(cleared.current.version, isNot(GitStoredDraft.absentVersion));
      expect(
        (await store().readVersioned('worktree')).version,
        cleared.current.version,
      );
      expect(
        (await store().compareAndWrite(
          'worktree',
          expectedVersion: GitStoredDraft.absentVersion,
          text: 'old',
        )).written,
        isFalse,
      );
    },
  );

  test(
    'raw late first write captures absent before delayed file resolution',
    () async {
      final lookup = Completer<File>();
      final delayed = FileGitDraftStore(file: (_) => lookup.future);
      final pending = delayed.write('worktree', 'older B');
      await store().write('worktree', 'newer C');
      lookup.complete(target);
      await expectLater(
        pending,
        throwsA(
          isA<GitDraftConflict>().having(
            (error) => error.current.text,
            'current text',
            'newer C',
          ),
        ),
      );
      expect(await store().read('worktree'), 'newer C');
    },
  );

  test(
    'raw observed write and raw clear reject another store revision',
    () async {
      final a = store(), b = store();
      await a.write('worktree', 'B');
      await b.read('worktree');
      await b.write('worktree', 'C');
      await expectLater(
        a.write('worktree', ''),
        throwsA(isA<GitDraftConflict>()),
      );
      await expectLater(
        a.write('worktree', 'late B'),
        throwsA(isA<GitDraftConflict>()),
      );
      expect(await store().read('worktree'), 'C');
      // Deliberate re-review supplies the actual token for a subsequent edit.
      expect(await a.read('worktree'), 'C');
      await a.write('worktree', 'reviewed D');
      expect(await store().read('worktree'), 'reviewed D');
    },
  );

  test(
    'rapid own raw writes chain only their own successful revisions',
    () async {
      final a = store();
      await Future.wait(
        List.generate(16, (i) => a.write('worktree', 'draft $i')),
      );
      await a.flush();
      expect(await store().read('worktree'), 'draft 15');
    },
  );

  test(
    'reads inspect disk instead of returning a store-local memory draft',
    () async {
      final a = store(), b = store();
      await a.write('worktree', 'B');
      expect(await a.read('worktree'), 'B');
      await b.read('worktree');
      await b.write('worktree', 'C');
      expect(await a.read('worktree'), 'C');
    },
  );

  test('flush waits for a pending read and its delayed resolver', () async {
    final lookup = Completer<File>();
    final a = FileGitDraftStore(file: (_) => lookup.future);
    final reading = a.readVersioned('worktree');
    var flushed = false;
    final flushing = a.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    lookup.complete(target);
    await reading;
    await flushing;
    expect(flushed, isTrue);
  });

  test('flush includes pending conditional and preference writes', () async {
    final lookup = Completer<void>();
    final a = FileGitDraftStore(
      file: (key) async {
        await lookup.future;
        return namedFile(key);
      },
    );
    final writing = a.compareAndWrite(
      'worktree',
      expectedVersion: GitStoredDraft.absentVersion,
      text: 'C',
    );
    final preferences = a.writeUnconditionally('view', '{"split":0.6}');
    var flushed = false;
    final flushing = a.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    lookup.complete();
    expect((await writing).written, isTrue);
    await preferences;
    await flushing;
    expect(flushed, isTrue);
    expect(await namedStore().read('view'), '{"split":0.6}');
    expect(await namedStore().read('worktree'), 'C');
  });

  test(
    'only explicit preference writes have unconditional replacement',
    () async {
      final a = store(), b = store();
      await a.writeUnconditionally('view', '{"split":0.3}');
      await b.writeUnconditionally('view', '{"split":0.7}');
      expect(await store().read('view'), '{"split":0.7}');
      await expectLater(
        store().write('view', 'unreviewed'),
        throwsA(isA<GitDraftConflict>()),
      );
    },
  );

  test('invalid UTF8 is reported without replacing original bytes', () async {
    final bytes = [0xc3, 0x28];
    await target.writeAsBytes(bytes);
    await expectLater(
      store().readVersioned('worktree'),
      throwsA(isA<Exception>()),
    );
    expect(await target.readAsBytes(), bytes);
    expect(await File('${target.path}.lock').exists(), isTrue);
    await target.writeAsString('recoverable original');
    expect(await store().read('worktree'), 'recoverable original');
  });

  test(
    'malformed stored metadata fails explicitly and preserves the file',
    () async {
      const value = '\u0000BusyStackGitDraft:1\u0000\n{"version":"v1-bad"}';
      await target.writeAsString(value);
      await expectLater(
        store().readVersioned('worktree'),
        throwsA(isA<FormatException>()),
      );
      expect(await target.readAsString(), value);
    },
  );

  test(
    'simultaneous separate isolates have one CAS winner and atomic text',
    () async {
      const writers = 8;
      final responses = ReceivePort();
      final ready = <SendPort>[];
      final results = <List<Object?>>[];
      final done = Completer<void>();
      final subscription = responses.listen((message) {
        final row = message as List;
        if (row.first == 'ready') {
          expect(row[2], pid);
          ready.add(row[1] as SendPort);
          if (ready.length == writers) {
            for (final port in ready) port.send('go');
          }
        } else {
          results.add(row.cast<Object?>());
          if (results.length == writers) done.complete();
        }
      });
      try {
        for (var i = 0; i < writers; i++) {
          await Isolate.spawn(_raceWriter, (
            responses.sendPort,
            target.path,
            i,
          ));
        }
        await done.future.timeout(const Duration(seconds: 15));
        expect(results.where((row) => row[1] == true), hasLength(1));
        final winner = results.singleWhere((row) => row[1] == true)[2] as int;
        expect(await store().read('worktree'), 'writer $winner 日本語\r\nno EOF');
        expect(
          await directory
              .list()
              .where((p) => p.path.endsWith('.pending'))
              .length,
          0,
        );
      } finally {
        await subscription.cancel();
        responses.close();
      }
    },
  );

  test(
    'reopen discovers durable amend owners after another window clears view metadata',
    () async {
      final a = namedStore(), b = namedStore();
      final old = 'a' * 40, current = 'b' * 64;
      final oldKey = 'worktree:amend:$old',
          currentKey = 'worktree:amend:$current';
      await a.write('worktree', 'normal A');
      await a.write(oldKey, 'submitted B');
      final submitted = await a.readVersioned(oldKey);
      await b.readVersioned(oldKey);
      await b.write(oldKey, 'newer C');
      await b.write(currentKey, 'independent D');
      final consumed = await a.compareAndWrite(
        oldKey,
        expectedVersion: submitted.version,
        text: null,
      );
      expect(consumed.written, isFalse);
      // View state intentionally remains last-writer-wins and may be obsolete.
      await a.writeUnconditionally(
        'worktree-view',
        jsonEncode({'commitAmendDraftTargets': <String>[], 'split': .35}),
      );
      final reopened = namedStore();
      expect(
        jsonDecode(
          (await reopened.read('worktree-view'))!,
        )['commitAmendDraftTargets'],
        isEmpty,
      );
      expect(await reopened.recoverAmendTargets('worktree'), [old, current]);
      expect(await reopened.read(oldKey), 'newer C');
      expect(await reopened.read(currentKey), 'independent D');
      expect(await reopened.read('worktree'), 'normal A');
      expect(jsonDecode((await reopened.read('worktree-view'))!)['split'], .35);
    },
  );

  test(
    'recovery includes exact worktree valid OIDs and excludes empty tombstones',
    () async {
      final a = namedStore();
      final keep = '1' * 40, empty = '2' * 64, cleared = '3' * 40;
      final whitespace = '4' * 64;
      await a.write('worktree:amend:$keep', 'keep Unicode 日本語\r\nno EOF');
      await a.write('worktree:amend:$empty', '');
      await a.write('worktree:amend:$whitespace', ' ');
      await a.write('worktree:amend:$cleared', 'will clear');
      final owner = await a.readVersioned('worktree:amend:$cleared');
      await a.compareAndWrite(
        'worktree:amend:$cleared',
        expectedVersion: owner.version,
        text: null,
      );
      await a.write('other-worktree:amend:$keep', 'another repository');
      await namedFile('worktree:amend:short').writeAsString('invalid target');
      await namedFile(
        'worktree:amend:${'g' * 40}',
      ).writeAsString('invalid hex');
      expect(await namedStore().recoverAmendTargets('worktree'), [
        keep,
        whitespace,
      ]);
      expect(
        (await a.readVersioned('worktree:amend:$cleared')).version,
        isNot(GitStoredDraft.absentVersion),
      );
    },
  );

  test(
    'recovery migrates existing legacy amend text without relying on view state',
    () async {
      final oid = '5' * 40;
      const text = 'legacy C 日本語\r\nno EOF';
      final file = namedFile('worktree:amend:$oid');
      await file.writeAsString(text);
      final priorPending = File('${file.path}.pending');
      await priorPending.writeAsString('prior recoverable pending bytes');
      expect(await namedStore().recoverAmendTargets('worktree'), [oid]);
      final recovered = await namedStore().readVersioned('worktree:amend:$oid');
      expect(recovered.text, text);
      expect(
        await priorPending.readAsString(),
        'prior recoverable pending bytes',
      );
      expect(
        (await namedStore().readVersioned('worktree:amend:$oid')).version,
        recovered.version,
      );
    },
  );

  test(
    'recovery reports unreadable content instead of returning empty results',
    () async {
      final file = namedFile('worktree:amend:${'6' * 40}');
      await file.writeAsBytes([0xc3, 0x28]);
      await expectLater(
        namedStore().recoverAmendTargets('worktree'),
        throwsA(isA<Exception>()),
      );
      expect(await file.readAsBytes(), [0xc3, 0x28]);
    },
  );

  test(
    'recovery reports a matching directory instead of silently hiding it',
    () async {
      await Directory(namedFile('worktree:amend:${'9' * 40}').path).create();
      await expectLater(
        namedStore().recoverAmendTargets('worktree'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'recovery bounds metadata rather than silently returning a partial list',
    () async {
      for (var start = 0; start < 4097; start += 32) {
        await Future.wait([
          for (var i = start; i < start + 32 && i < 4097; i++)
            File('${directory.path}/unrelated-$i').create(exclusive: true),
        ]);
      }
      await expectLater(
        namedStore().recoverAmendTargets('worktree'),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'bound',
            contains('4096'),
          ),
        ),
      );
    },
  );

  test(
    'flush includes an in-flight recovery and its delayed directory resolver',
    () async {
      final lookup = Completer<File>();
      final oid = '7' * 40;
      await namedFile('worktree:amend:$oid').writeAsString('C');
      final a = FileGitDraftStore(file: (_) => lookup.future);
      final recovering = a.recoverAmendTargets('worktree');
      var flushed = false;
      final flushing = a.flush().then((_) => flushed = true);
      await Future<void>.delayed(Duration.zero);
      expect(flushed, isFalse);
      lookup.complete(namedFile('worktree'));
      expect(await recovering, [oid]);
      await flushing;
      expect(flushed, isTrue);
    },
  );

  if (Platform.isLinux) {
    test(
      'recovery rejects matching symlinks without reading another file',
      () async {
        final sentinel = File('${directory.path}/sentinel');
        await sentinel.writeAsString('untouched');
        await Link(
          namedFile('worktree:amend:${'8' * 40}').path,
        ).create(sentinel.path);
        await expectLater(
          namedStore().recoverAmendTargets('worktree'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await sentinel.readAsString(), 'untouched');
      },
    );
    test(
      'same-PID independent flock descriptor blocks until timeout and releases',
      () async {
        final responses = ReceivePort();
        final messages = StreamIterator<dynamic>(responses);
        final isolate = await Isolate.spawn(_holdLinuxLock, (
          responses.sendPort,
          '${target.path}.lock',
        ));
        try {
          expect(await messages.moveNext(), isTrue);
          final ready = messages.current as List;
          expect(ready[1], pid);
          final release = ready[0] as SendPort;
          final a = store(timeout: const Duration(milliseconds: 100));
          await expectLater(
            a.readVersioned('worktree'),
            throwsA(isA<TimeoutException>()),
          );
          release.send('release');
          expect(await messages.moveNext(), isTrue);
          expect(messages.current, 'released');
          expect(
            (await a.readVersioned('worktree')).version,
            GitStoredDraft.absentVersion,
          );
          await a.write('worktree', 'after release');
          expect(await store().read('worktree'), 'after release');
          expect(
            (await File('${target.path}.lock').stat()).mode & 0x1ff,
            0x180,
          );
          expect((await target.stat()).mode & 0x1ff, 0x180);
          for (final entry in Directory('/proc/self/fd').listSync()) {
            try {
              expect(
                Link(entry.path).targetSync(),
                isNot('${target.path}.lock'),
              );
            } on FileSystemException {
              // The directory iterator can close its own descriptor meanwhile.
            }
          }
        } finally {
          isolate.kill(priority: Isolate.immediate);
          await messages.cancel();
          responses.close();
        }
      },
    );

    test(
      'symlink lock fails safely without changing the linked file',
      () async {
        final sentinel = File('${directory.path}/sentinel');
        await sentinel.writeAsString('untouched');
        await Link('${target.path}.lock').create(sentinel.path);
        await expectLater(
          store().readVersioned('worktree'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await sentinel.readAsString(), 'untouched');
        expect(await target.exists(), isFalse);
      },
    );
  }
}

Future<void> _raceWriter((SendPort, String, int) arguments) async {
  final (parent, path, id) = arguments;
  final start = ReceivePort();
  parent.send(['ready', start.sendPort, pid]);
  await start.first;
  start.close();
  try {
    final store = FileGitDraftStore(file: (_) async => File(path));
    final result = await store.compareAndWrite(
      'worktree',
      expectedVersion: GitStoredDraft.absentVersion,
      text: 'writer $id 日本語\r\nno EOF',
    );
    parent.send(['result', result.written, id]);
  } on Object catch (error) {
    parent.send(['error', error.toString(), id]);
  }
}

/// Independent test holder uses libc's FILE API, not the store's lock wrapper.
Future<void> _holdLinuxLock((SendPort, String) arguments) async {
  final (parent, path) = arguments;
  final libc = DynamicLibrary.process();
  final malloc = libc
      .lookupFunction<
        Pointer<Void> Function(Size),
        Pointer<Void> Function(int)
      >('malloc');
  final free = libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  Pointer<Uint8> string(String value) {
    final bytes = utf8.encode(value);
    final result = malloc(bytes.length + 1).cast<Uint8>();
    result.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return result;
  }

  final fopen = libc
      .lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>),
        Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>)
      >('fopen');
  final fileno = libc
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('fileno');
  final flock = libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  final fclose = libc
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('fclose');
  final nativePath = string(path), nativeMode = string('a+');
  final file = fopen(nativePath, nativeMode);
  free(nativePath.cast<Void>());
  free(nativeMode.cast<Void>());
  if (file.address == 0 || flock(fileno(file), 2) != 0) {
    throw StateError('Cannot hold independent test lock');
  }
  final commands = ReceivePort();
  parent.send([commands.sendPort, pid]);
  try {
    await commands.first;
  } finally {
    fclose(file);
    commands.close();
  }
  parent.send('released');
}
