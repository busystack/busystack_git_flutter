import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'host.dart';

/// Persistent messages share one file and one stable lock across app windows.
/// Tokens, including cleared-draft tombstones, survive reopening the store.
final class FileGitDraftStore
    implements GitVersionedDraftStore, GitFlushableDraftStore {
  FileGitDraftStore({
    required Future<File> Function(String key) file,
    this.lockTimeout = const Duration(seconds: 3),
  }) : _file = file {
    if (lockTimeout <= Duration.zero) {
      throw ArgumentError.value(lockTimeout, 'lockTimeout');
    }
  }

  final Future<File> Function(String key) _file;
  final Duration lockTimeout;
  final _tails = <String, Future<void>>{};
  final _observed = <String, Future<GitStoredDraft>>{};
  final _active = <Future<Object?>>{};

  Future<T> _enqueue<T>(String key, Future<T> Function() operation) {
    final previous = _tails[key] ?? Future<void>.value();
    // A reported failure does not prevent an explicit subsequent read/review.
    final next = previous.then((_) => operation());
    _tails[key] = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return _track(next);
  }

  Future<T> _track<T>(Future<T> next) {
    _active.add(next);
    unawaited(
      next.then<void>(
        (_) => _active.remove(next),
        onError: (Object _, StackTrace _) => _active.remove(next),
      ),
    );
    return next;
  }

  void _observe(String key, Future<GitStoredDraft> observation) {
    _observed[key] = observation;
    // The same failure remains available to a later raw write. It is handled
    // here as well because callers of the versioned API consume their result.
    unawaited(
      observation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<GitDraftWriteResult> _request(
    String key,
    int operation, {
    String? expectedVersion,
    String? text,
  }) async {
    final file = await _file(key);
    return _background(
      _DraftRequest(
        file.absolute.path,
        operation,
        lockTimeout.inMicroseconds,
        expectedVersion,
        text,
      ),
    );
  }

  @override
  Future<GitStoredDraft> readVersioned(String key) {
    final read = _enqueue(key, () async => (await _request(key, 0)).current);
    _observe(key, read);
    return read;
  }

  @override
  Future<GitDraftWriteResult> compareAndWrite(
    String key, {
    required String expectedVersion,
    required String? text,
  }) {
    final write = _enqueue(
      key,
      () => _request(key, 1, expectedVersion: expectedVersion, text: text),
    );
    _observe(
      key,
      write.then((result) {
        if (!result.written) throw GitDraftConflict(key, result.current);
        return result.current;
      }),
    );
    return write;
  }

  @override
  Future<String?> read(String key) =>
      readVersioned(key).then((draft) => draft.text);

  @override
  Future<void> write(String key, String message) {
    // Capture ownership before the first await, including before file lookup.
    final expected =
        _observed[key] ??
        Future.value(
          const GitStoredDraft(
            text: null,
            version: GitStoredDraft.absentVersion,
          ),
        );
    final write = _enqueue(key, () async {
      final owner = await expected;
      final result = await _request(
        key,
        1,
        expectedVersion: owner.version,
        text: message,
      );
      if (!result.written) throw GitDraftConflict(key, result.current);
      return result.current;
    });
    _observe(key, write);
    return write.then<void>((_) {});
  }

  /// View preferences alone may intentionally use last-writer-wins behavior.
  /// Commit/amend messages must always use conditional writes.
  Future<void> writeUnconditionally(String key, String? value) {
    final write = _enqueue(
      key,
      () async => (await _request(key, 2, text: value)).current,
    );
    _observe(key, write);
    return write.then<void>((_) {});
  }

  /// Discover existing immutable amend owners independently of view preferences.
  /// This reads only the current worktree's slots; it creates no discovery index.
  Future<List<String>> recoverAmendTargets(String worktreeKey) =>
      _track(() async {
        final prototype = await _file(worktreeKey);
        return _recoverInBackground(
          prototype.absolute.parent.path,
          worktreeKey,
          lockTimeout.inMicroseconds,
        );
      }());

  @override
  Future<void> flush() async {
    while (_active.isNotEmpty) {
      await Future.wait(_active.toList());
    }
  }
}

final class _DraftRequest {
  const _DraftRequest(
    this.path,
    this.operation,
    this.timeoutMicroseconds,
    this.expectedVersion,
    this.text,
  );
  final String path;
  final int operation, timeoutMicroseconds;
  final String? expectedVersion, text;
}

Future<GitDraftWriteResult> _background(_DraftRequest request) =>
    Isolate.run(() => _transaction(request), debugName: 'Git draft storage');

Future<List<String>> _recoverInBackground(
  String directory,
  String worktreeKey,
  int timeoutMicroseconds,
) => Isolate.run(
  () => _recover(directory, worktreeKey, timeoutMicroseconds),
  debugName: 'Git amend draft recovery',
);

Future<List<String>> _recover(
  String directory,
  String worktreeKey,
  int timeoutMicroseconds,
) async {
  final timeout = Duration(microseconds: timeoutMicroseconds);
  final watch = Stopwatch()..start();
  final candidates = <(String, String)>[];
  final prefix = '$worktreeKey:amend:';
  final encodedPrefix = Uri.encodeComponent(prefix).replaceAll('*', '%2A');
  var entries = 0;
  await for (final entry in Directory(directory).list(followLinks: false)) {
    if (++entries > 4096) {
      throw FileSystemException(
        'Saved Git draft recovery exceeds 4096 directory entries',
        directory,
      );
    }
    if (watch.elapsed >= timeout) {
      throw TimeoutException('Saved Git draft recovery timed out', timeout);
    }
    // Directory URIs have a trailing empty segment; matching non-files must
    // produce an explicit failure, rather than disappear from recovery.
    final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!name.endsWith('.txt')) continue;
    var logical = name.substring(0, name.length - 4);
    if (Platform.isWindows) {
      if (!logical.startsWith(encodedPrefix)) continue;
      logical = Uri.decodeComponent(logical);
      if (Uri.encodeComponent(logical).replaceAll('*', '%2A') !=
          name.substring(0, name.length - 4))
        continue;
    }
    if (!logical.startsWith(prefix)) continue;
    final oid = logical.substring(prefix.length);
    if (!RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(oid)) continue;
    if (await FileSystemEntity.type(entry.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Saved Git amend draft is not a regular file',
        entry.path,
      );
    }
    if (candidates.length >= 256) {
      throw FileSystemException(
        'Saved Git draft recovery exceeds 256 amend slots',
        directory,
      );
    }
    candidates.add((oid, entry.path));
  }
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final recovered = <String>[];
  for (final (oid, path) in candidates) {
    final remaining = timeout - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Saved Git draft recovery timed out', timeout);
    }
    final result = await _transaction(
      _DraftRequest(path, 0, remaining.inMicroseconds, null, null),
    );
    if (result.current.version == GitStoredDraft.absentVersion) {
      throw FileSystemException(
        'Saved Git amend draft became unavailable',
        path,
      );
    }
    if (result.current.text?.isNotEmpty == true) recovered.add(oid);
  }
  return List.unmodifiable(recovered);
}

// A Git commit message cannot contain NUL. The reserved prefix distinguishes
// our record from existing plaintext messages, including ordinary JSON text.
const _prefix = '\u0000BusyStackGitDraft:1\u0000\n';
const _maximumBytes = 32 * 1024 * 1024;

String _token() {
  final random = Random.secure();
  return 'v1-${base64Url.encode(List.generate(24, (_) => random.nextInt(256)))}';
}

Future<GitDraftWriteResult> _transaction(_DraftRequest request) async {
  final target = File(request.path);
  await target.parent.create(recursive: true);
  final lock = await _DraftLock.acquire(
    '${request.path}.lock',
    Duration(microseconds: request.timeoutMicroseconds),
  );
  try {
    final current = await _read(target);
    if (request.operation == 0) {
      return GitDraftWriteResult(written: false, current: current);
    }
    if (request.operation == 1 && request.expectedVersion != current.version) {
      return GitDraftWriteResult(written: false, current: current);
    }
    final next = GitStoredDraft(text: request.text, version: _token());
    await _replace(target, next);
    return GitDraftWriteResult(written: true, current: next);
  } finally {
    await lock.release();
  }
}

Future<GitStoredDraft> _read(File target) async {
  final type = await FileSystemEntity.type(target.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return const GitStoredDraft(
      text: null,
      version: GitStoredDraft.absentVersion,
    );
  }
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('Git draft is not a regular file', target.path);
  }
  if (await target.length() > _maximumBytes) {
    throw FileSystemException(
      'Git draft exceeds the storage bound',
      target.path,
    );
  }
  final value = await target.readAsString();
  if (value.startsWith(_prefix)) {
    final record = jsonDecode(value.substring(_prefix.length));
    if (record is! Map ||
        record.length != 2 ||
        !record.containsKey('text') ||
        record['version'] is! String ||
        !RegExp(
          r'^v1-[A-Za-z0-9_-]{32}$',
        ).hasMatch(record['version'] as String) ||
        (record['text'] != null && record['text'] is! String)) {
      throw FormatException('Invalid stored Git draft', target.path);
    }
    return GitStoredDraft(
      text: record['text'] as String?,
      version: record['version'] as String,
    );
  }
  // Migration itself is serialized and atomic; every legacy byte survives the
  // UTF8 round trip, including CRLF and a missing final newline.
  final migrated = GitStoredDraft(text: value, version: _token());
  await _replace(target, migrated);
  return migrated;
}

Future<void> _replace(File target, GitStoredDraft draft) async {
  final encoded = utf8.encode(
    '$_prefix${jsonEncode({'version': draft.version, 'text': draft.text})}',
  );
  if (encoded.length > _maximumBytes) {
    throw FileSystemException(
      'Git draft exceeds the storage bound',
      target.path,
    );
  }
  final temporary = File('${target.path}.${_token()}.pending');
  try {
    if (Platform.isLinux) {
      _LinuxCalls.instance.createPrivate(temporary.path);
    } else {
      await temporary.create(exclusive: true);
    }
    await temporary.writeAsBytes(encoded, flush: true);
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

abstract interface class _DraftLock {
  static Future<_DraftLock> acquire(String path, Duration timeout) async {
    if (Platform.isLinux) return _LinuxLock.acquire(path, timeout);
    if (Platform.isWindows) return _WindowsLock.acquire(path, timeout);
    throw UnsupportedError('Persistent Git drafts need a supported file lock');
  }

  Future<void> release();
}

final class _WindowsLock implements _DraftLock {
  _WindowsLock(this.file);
  final RandomAccessFile file;
  static Future<_WindowsLock> acquire(String path, Duration timeout) async {
    final file = await File(path).open(mode: FileMode.append);
    final watch = Stopwatch()..start();
    try {
      while (true) {
        try {
          await file.lock(FileLock.exclusive, 0, 1);
          return _WindowsLock(file);
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 33 &&
              error.osError?.errorCode != 32) {
            rethrow;
          }
          if (watch.elapsed >= timeout) {
            throw TimeoutException('Git draft lock was not available', timeout);
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    } on Object {
      await file.close();
      rethrow;
    }
  }

  @override
  Future<void> release() async {
    try {
      await file.unlock(0, 1);
    } finally {
      await file.close();
    }
  }
}

final class _LinuxLock implements _DraftLock {
  _LinuxLock(this.descriptor);
  final int descriptor;
  static Future<_LinuxLock> acquire(String path, Duration timeout) async {
    final calls = _LinuxCalls.instance;
    final descriptor = calls.openPrivate(path, exclusive: false);
    final watch = Stopwatch()..start();
    try {
      while (calls.flock(descriptor, 2 | 4) != 0) {
        final code = calls.errorNumber();
        if (code != 11 && code != 4) {
          throw FileSystemException(
            'Cannot lock Git draft',
            path,
            OSError('', code),
          );
        }
        if (watch.elapsed >= timeout) {
          throw TimeoutException('Git draft lock was not available', timeout);
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return _LinuxLock(descriptor);
    } on Object {
      calls.close(descriptor);
      rethrow;
    }
  }

  @override
  Future<void> release() async {
    final calls = _LinuxCalls.instance;
    try {
      while (calls.flock(descriptor, 8) != 0) {
        final code = calls.errorNumber();
        if (code == 4) continue;
        throw FileSystemException(
          'Cannot unlock Git draft',
          '',
          OSError('', code),
        );
      }
    } finally {
      calls.close(descriptor);
    }
  }
}

/// Public Linux libc calls, executed only in the storage worker isolate.
/// Separate open descriptions make flock exclusive across same-PID isolates;
/// Dart's POSIX File.lock instead uses process-associated fcntl locks.
final class _LinuxCalls {
  _LinuxCalls() : library = DynamicLibrary.process();
  static final instance = _LinuxCalls();
  final DynamicLibrary library;
  late final open = library
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Int32, VarArgs<(Uint32,)>),
        int Function(Pointer<Uint8>, int, int)
      >('open');
  late final flock = library
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  late final close = library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final chmod = library
      .lookupFunction<Int32 Function(Int32, Uint32), int Function(int, int)>(
        'fchmod',
      );
  late final malloc = library
      .lookupFunction<
        Pointer<Void> Function(Size),
        Pointer<Void> Function(int)
      >('malloc');
  late final free = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  late final errno = library
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno_location',
      );
  int errorNumber() => errno().value;

  int openPrivate(String path, {required bool exclusive}) {
    final bytes = utf8.encode(path);
    if (bytes.contains(0)) throw ArgumentError.value(path, 'path');
    final memory = malloc(bytes.length + 1).cast<Uint8>();
    if (memory.address == 0) throw StateError('Cannot allocate Git draft path');
    try {
      memory.asTypedList(bytes.length + 1)
        ..setAll(0, bytes)
        ..[bytes.length] = 0;
      // O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW; optional O_EXCL.
      final descriptor = open(
        memory,
        2 | 64 | 0x80000 | 0x20000 | (exclusive ? 128 : 0),
        0x180,
      );
      if (descriptor < 0) {
        throw FileSystemException(
          'Cannot open Git draft lock',
          path,
          OSError('', errorNumber()),
        );
      }
      if (chmod(descriptor, 0x180) != 0) {
        final error = errorNumber();
        close(descriptor);
        throw FileSystemException(
          'Cannot protect Git draft file',
          path,
          OSError('', error),
        );
      }
      return descriptor;
    } finally {
      free(memory.cast<Void>());
    }
  }

  void createPrivate(String path) => close(openPrivate(path, exclusive: true));
}
