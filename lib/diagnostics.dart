/// ZMIX diagnostics: the "صندوق أسود" behind Settings > التشخيص.
///
/// Records a redacted, timestamped event log of what the user asked the app
/// to do (intent events) and what the playback pipeline actually did
/// (outcome events), so a failure report can be exported by copy or file.
///
/// Hard rules baked in here:
/// - OFF by default; nothing is recorded until the user enables it.
/// - Redaction happens BEFORE persistence: no full signed URLs, no query
///   parameters (they carry IP/signature/session data), no playlist titles,
///   and no video ids unless the user opts in. Every line passes the URL
///   scrubber as a safety net, including raw mpv error text.
/// - Local only. There is no network code in this file and no automatic
///   sending of anything, ever.
/// - Bounded: two rotating files (~900 KB each) plus a hard-capped in-memory
///   write queue, so diagnostics can never fill the device or block the UI.
///   No loss is silent: queue drops are counted per priority class, write
///   failures are counted and retried with bounded backoff, rotations are
///   counted, and export snapshots whatever never reached disk.
/// - Crash honesty: a clean-exit marker distinguishes a normal close from
///   "ended without a clean exit (cause unknown)". The app cannot tell a
///   Dart crash, a native crash, an ANR and an OS kill apart from inside,
///   and this module says so instead of guessing.
/// - Failure containment: every public call is no-op safe before init and
///   swallows its own storage errors, so a diagnostics failure stays inside
///   this module (handled failures; not a proof it can never crash).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Snapshot of the diagnostics counters for the header and settings tile.
typedef DiagStats = ({
  int events,
  int droppedNormal,
  int droppedCritical,
  int writeFailures,
  int rotations,
  int pending,
  int bytes
});

class DiagEvent {
  const DiagEvent(this.line, {required this.critical});
  final String line;

  /// Critical events (errors, session boundaries) are dropped last under
  /// backpressure (only when the whole queue is critical); every drop of
  /// every class is counted.
  final bool critical;
}

class Diag {
  Diag._();
  static final Diag I = Diag._();

  /// Fresh instance for VM tests (restart semantics need separate objects).
  factory Diag.forTest() => Diag._();

  /// Cancels the periodic flush timer (tests and app teardown).
  void disposeForTest() {
    _flushTimer?.cancel();
  }

  static const String reportVersion = '0.3.6-diag3';

  bool _ready = false;
  bool _enabled = false;
  bool _verbose = false;
  bool _includeVideoIds = false;

  String _sessionId = '';
  int _attemptCounter = 0;

  Directory? _dir;
  File? _activeFile;
  final Queue<DiagEvent> _pending = Queue<DiagEvent>();
  Future<void> _writeChain = Future.value();
  Timer? _flushTimer;
  int _eventsWritten = 0;
  int _droppedNormal = 0;
  int _droppedCritical = 0;
  int _writeFailures = 0; // session total (header + settings)
  int _consecutiveWriteFailures = 0; // drives the retry backoff
  int _rotations = 0;
  DateTime _retryNotBefore = DateTime.fromMillisecondsSinceEpoch(0);
  List<DiagEvent> _inFlight = const []; // batch drained, write not settled
  int _requeuedPrefix = 0; // leading queue slots restored by earlier requeues

  static const int _maxPending = 300;
  static const int _maxFileBytes = 900 * 1024;
  static const String _file1 = 'events-1.log';
  static const String _file2 = 'events-2.log';

  bool get enabled => _enabled;
  bool get verbose => _verbose;
  bool get includeVideoIds => _includeVideoIds;
  String get sessionId => _sessionId;

  /// Called once from main(). Safe on web and in tests: any platform error
  /// leaves the module in its no-op state.
  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      final support = await getApplicationSupportDirectory();
      await initWithDir(Directory('${support.path}/diagnostics'));
    } catch (_) {
      _ready = false;
    }
  }

  /// Init against an explicit directory: production calls it from [init],
  /// VM tests call it with a temp dir (restart semantics need no plugin).
  Future<void> initWithDir(Directory dir) async {
    if (kIsWeb || _ready) return;
    try {
      _dir = dir;
      await _dir!.create(recursive: true);
      final flags = await _readJson('flags.json');
      _enabled = flags['enabled'] == true;
      _verbose = flags['verbose'] == true;
      _includeVideoIds = flags['includeVideoIds'] == true;
      _sessionId = _newId();
      // Clean-exit bookkeeping: if the previous session never wrote its
      // clean marker, note it (cause stays honestly unknown).
      final meta = await _readJson('meta.json');
      final prevId = meta['sessionId'] as String?;
      final prevClean = meta['endedCleanly'] == true;
      await _writeJson('meta.json', {'sessionId': _sessionId, 'endedCleanly': false});
      _ready = true;
      if (_enabled) {
        _session('بداية التطبيق');
        if (prevId != null && !prevClean) {
          _session('الجلسة السابقة انتهت من غير إنهاء نظيف',
              detail: 'سبب غير معروف (قتل نظام أو كراش أو إغلاق يدوي)');
        }
        _startTimer();
      }
    } catch (_) {
      _ready = false;
    }
  }

  // ── Public recording API (all no-op when disabled/unready) ────────────

  /// A user-intent event: a tap or gesture, logged as a REQUEST, never as
  /// an observed outcome.
  void ui(String name,
          {String? detail, String? attemptId, bool critical = false}) =>
      _event('طلب', name,
          detail: detail, attemptId: attemptId, critical: critical);

  /// An observed pipeline outcome. [stage]: extract | network | open |
  /// audio | play. [ok] false marks the line critical (never dropped).
  void outcome(String name,
          {String? stage,
          bool ok = true,
          String? detail,
          String? attemptId,
          bool critical = false}) =>
      _event('نتيجة', name,
          stage: stage,
          ok: ok,
          detail: detail,
          attemptId: attemptId,
          critical: critical);

  /// A session lifecycle event (start, background, foreground, clean end).
  void session(String name, {String? detail}) {
    if (!_ready || !_enabled) return;
    _session(name, detail: detail);
  }

  void _session(String name, {String? detail}) =>
      _event('جلسة', name, detail: detail, critical: true);

  void _event(String kind, String name,
      {String? stage,
      bool ok = true,
      String? detail,
      String? attemptId,
      bool critical = false}) {
    if (!_ready || !_enabled) return;
    final ts = DateTime.now().toIso8601String();
    final parts = StringBuffer('$ts | s:$_sessionId');
    if (attemptId != null) parts.write(' | $attemptId');
    parts.write(' | $kind | $name');
    if (stage != null) parts.write(' | stage=$stage');
    if (kind == 'نتيجة') parts.write(' ok=${ok ? 'نعم' : 'لا'}');
    if (detail != null && detail.isNotEmpty) parts.write(' | $detail');
    _enqueue(DiagEvent(redact(parts.toString()),
        critical: critical || !ok || kind == 'جلسة'));
  }

  /// A new playback-attempt id ('a1', 'a2', ...) to correlate one open's
  /// events. Session id 's-xxxxxx' is per app launch; a report id is added
  /// at export time.
  String newAttempt() {
    _attemptCounter++;
    return 'a$_attemptCounter';
  }

  // ── Toggles (persisted) ───────────────────────────────────────────────

  Future<void> setEnabled(bool value) async {
    if (!_ready) return;
    _enabled = value;
    await _saveFlags();
    if (value) {
      _session('التشخيص اتفعّل');
      _startTimer();
    } else {
      _session('التشخيص اتقفل');
      await flush();
      _flushTimer?.cancel();
    }
  }

  Future<void> setVerbose(bool value) async {
    _verbose = value;
    if (_ready) await _saveFlags();
  }

  Future<void> setIncludeVideoIds(bool value) async {
    _includeVideoIds = value;
    if (_ready) await _saveFlags();
  }

  // ── Redaction (applied BEFORE persistence) ────────────────────────────

  static final RegExp _urlRe = RegExp(r'https?://[^\s|]+');

  /// Host of a stream URL for logging; never the path or query (the query
  /// carries IP, signature and expiry data).
  static String hostOf(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isEmpty ? '[رابط]' : host;
    } catch (_) {
      return '[رابط]';
    }
  }

  /// Safety-net scrubber: any URL that slips into a log line is reduced to
  /// its host. Applied to every line before it can reach the write queue.
  static String redact(String text) =>
      text.replaceAllMapped(_urlRe, (m) => hostOf(m.group(0)!));

  /// Video label honoring the ids toggle: index in the playlist by
  /// default, the raw video id only when the user opted in.
  String videoLabel({required int index, String? videoId}) {
    if (_includeVideoIds && videoId != null) return 'id:$videoId';
    return 'فيديو رقم ${index + 1} في القائمة';
  }

  // ── Stats / export / clear ────────────────────────────────────────────

  DiagStats stats() {
    var bytes = 0;
    try {
      for (final name in const [_file1, _file2]) {
        final f = File('${_dir!.path}/$name');
        if (f.existsSync()) bytes += f.lengthSync();
      }
    } catch (_) {}
    return (
      events: _eventsWritten,
      droppedNormal: _droppedNormal,
      droppedCritical: _droppedCritical,
      writeFailures: _writeFailures,
      rotations: _rotations,
      pending: _pending.length,
      bytes: bytes,
    );
  }

  /// Full report text: header + every persisted event, oldest file first,
  /// + an in-memory snapshot of whatever had not reached disk at read time.
  Future<String> buildReport() async {
    // Time-bounded: a stalled filesystem must not hang the export itself.
    var flushTimedOut = false;
    try {
      await flush().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      flushTimedOut = true;
    } catch (_) {
      flushTimedOut = true;
    }
    final s = stats();
    final eventsLine = StringBuffer(
        'أحداث كُتبت: ${s.events} · محذوفات: ${s.droppedNormal + s.droppedCritical}');
    if (s.droppedCritical > 0) {
      eventsLine.write(' (منها حرجة: ${s.droppedCritical})');
    }
    if (s.writeFailures > 0) {
      eventsLine.write(' · كتابات فاشلة: ${s.writeFailures}');
    }
    if (s.rotations > 0) {
      eventsLine.write(' · تدويرات: ${s.rotations}');
    }
    if (s.pending > 0) {
      eventsLine.write(' · لم تُكتب عند التصدير: ${s.pending}');
    }
    final header = StringBuffer()
      ..writeln('تقرير تشخيص ZMIX')
      ..writeln('إصدار التطبيق: $reportVersion')
      ..writeln('النظام: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('الحزم (حسب pubspec): youtube_explode_dart ^3.1.0 · media_kit ^1.1.11 · media_kit_video ^1.2.5')
      ..writeln('الجلسة الحالية: $_sessionId · تقرير: ${_newId()}')
      ..writeln(eventsLine.toString())
      ..writeln('حالة الكتابة: ${_writeHealth(s, flushTimedOut)}')
      ..writeln('خصوصية: الروابط منقّحة لاسم المضيف فقط، ومعرّفات الفيديو ${_includeVideoIds ? 'مضمّنة باختيار المستخدم' : 'غير مضمّنة'}')
      ..writeln('تنبيه: نهاية غير نظيفة للجلسة لا تعني كراش مؤكد؛ السبب يفضل غير معروف من داخل التطبيق')
      ..writeln('تنبيه: السجل حد أدنى مما حدث - التدوير يحذف الأقدم، وفشل التخزين قد يفقد أحداثًا؛ الأعداد أعلاه توضّح المعروف فقط')
      ..writeln('─' * 40);
    final body = StringBuffer();
    try {
      // Oldest file first: if _file1 is the rotated-away one it holds the
      // older events; _activeFile holds the newest.
      final active = _activeFile;
      final inactive = (active != null && active.path.endsWith(_file1))
          ? File('${_dir!.path}/$_file2')
          : File('${_dir!.path}/$_file1');
      for (final f in [inactive, if (active != null) active]) {
        if (f.existsSync()) {
          body.write(await f.readAsString().timeout(const Duration(seconds: 5)));
        }
      }
    } catch (_) {}
    // Memory snapshot: events that had not reached the file at read time.
    // The flush above is serialized through _writeChain: once it settles
    // (or times out), a drained batch has either landed in the file or been
    // requeued by its catch, so _inFlight + _pending covers everything
    // unwritten. Lines here are already redacted (scrubbed before enqueue).
    final unwritten = [..._inFlight, ..._pending];
    if (unwritten.isNotEmpty) {
      body.writeln('— أحداث من الذاكرة عند التصدير (لم تكن مكتوبة للملف لحظتها) —');
      final skip = unwritten.length > 50 ? unwritten.length - 50 : 0;
      if (skip > 0) body.writeln('(و $skip أحداث أقدم لم تُعرض)');
      for (final e in unwritten.skip(skip)) {
        body.writeln(e.line);
      }
    }
    return header.toString() + body.toString();
  }

  /// Honest write-health wording: 'سليمة' only after at least one successful
  /// write with nothing pending and no unresolved failure.
  String _writeHealth(DiagStats s, bool flushTimedOut) {
    if (flushTimedOut) return 'تعذّر تأكيد الكتابة عند التصدير (مهلة)';
    if (_consecutiveWriteFailures > 0) {
      final secs =
          _retryNotBefore.difference(DateTime.now()).inSeconds.clamp(1, 60);
      return 'فشل متكرر - إعادة محاولة كل $secs ث تقريبًا';
    }
    if (s.writeFailures > 0) return 'فشلت كتابات سابقة ثم نجحت الكتابة';
    if (s.pending > 0) return 'أحداث في الانتظار لم تُكتب';
    if (s.events == 0) return 'لم تُختبر الكتابة بعد في هذه الجلسة';
    return 'سليمة';
  }

  /// Saves the report next to the app's external files dir (no storage
  /// permission needed) and returns the path for the user.
  Future<String> saveReportToFile() async {
    final report = await buildReport();
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= _dir;
    final file = File(
        '${base!.path}/zmix-diag-${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(report, flush: true);
    return file.path;
  }

  Future<void> clear() async {
    if (!_ready) return;
    await flush();
    try {
      for (final name in const [_file1, _file2]) {
        final f = File('${_dir!.path}/$name');
        if (f.existsSync()) await f.delete();
      }
    } catch (_) {}
    _activeFile = null;
    _eventsWritten = 0;
    _droppedNormal = 0;
    _droppedCritical = 0;
    _writeFailures = 0;
    _consecutiveWriteFailures = 0;
    _rotations = 0;
    _retryNotBefore = DateTime.fromMillisecondsSinceEpoch(0);
    _requeuedPrefix = 0;
    _session('سجل التشخيص اتمسح');
  }

  /// Best-effort clean-exit marker: called from the app lifecycle observer.
  /// Android does not always deliver `detached`, so a missing marker is
  /// NOT evidence of a crash — exactly what the report says.
  Future<void> markCleanExit() async {
    if (!_ready) return;
    _session('نهاية نظيفة للجلسة');
    await flush();
    try {
      await _writeJson('meta.json', {'sessionId': _sessionId, 'endedCleanly': true});
    } catch (_) {}
  }

  // ── Write queue: bounded, serialized, never blocking the UI ──────────

  void _enqueue(DiagEvent event) {
    final list = _pending.toList()..add(event);
    _enforceCap(list);
    _pending
      ..clear()
      ..addAll(list);
    if (event.critical) {
      // Deferred to a microtask so a synchronous burst of critical events
      // coalesces into ONE drain/batch instead of one disk attempt each.
      scheduleMicrotask(flush);
    }
  }

  /// Hard-cap enforcement shared by enqueue and failure requeue: drop the
  /// oldest non-critical first, the oldest critical only when nothing else
  /// remains, and count every drop in its own class. (The previous code
  /// removed from a throwaway copy of the queue: the drop was counted but
  /// the event stayed, so the cap was never actually enforced.)
  void _enforceCap(List<DiagEvent> list) {
    while (list.length > _maxPending) {
      final idx = list.indexWhere((e) => !e.critical);
      if (idx >= 0) {
        list.removeAt(idx);
        _droppedNormal++;
      } else {
        list.removeAt(0); // all critical: drop oldest, counted
        _droppedCritical++;
      }
    }
  }

  /// Returns a failed batch to the queue in chronological order: after any
  /// earlier-requeued prefix, before newer queued events. Preceded by one
  /// marker line ONLY when the batch actually touched the disk (a gated
  /// batch has no partial-write ambiguity). Never creates outcome/session
  /// events: failures feed counters only, so a dead disk cannot cause a
  /// logging feedback loop.
  void _requeueFront(List<DiagEvent> batch, {required bool attempted}) {
    final ts = DateTime.now().toIso8601String();
    final incoming = <DiagEvent>[
      if (attempted)
        DiagEvent(
            '$ts | s:$_sessionId | جلسة | قد تتكرر الأسطر التالية بعد فشل كتابة سابق',
            critical: false),
      ...batch,
    ];
    final pos = _requeuedPrefix.clamp(0, _pending.length);
    final list = _pending.toList()..insertAll(pos, incoming);
    _enforceCap(list);
    _pending
      ..clear()
      ..addAll(list);
    _requeuedPrefix = (pos + incoming.length).clamp(0, _pending.length);
  }

  /// Flushes the queue to the active file, rotating at ~900 KB. Serialized
  /// through one chain so reentrant calls cannot interleave writes.
  Future<void> flush() {
    if (!_ready || _pending.isEmpty) return _writeChain;
    // Backoff gate: after a failure, retries are spaced 2s,4s,...,60s max,
    // so neither the timer nor critical events can hammer a dead disk.
    if (DateTime.now().isBefore(_retryNotBefore)) return _writeChain;
    final batch = <DiagEvent>[];
    while (_pending.isNotEmpty) {
      batch.add(_pending.removeFirst());
    }
    _requeuedPrefix = 0; // queue fully drained: prefix bookkeeping resets
    _writeChain = _writeChain.then((_) => _writeBatch(batch)).catchError((_) {});
    return _writeChain;
  }

  Future<void> _writeBatch(List<DiagEvent> batch) async {
    // Backoff gate INSIDE the chain: batches drained before a failure was
    // discovered requeue here without touching the disk, so a burst of
    // critical events still produces at most one failed write per step.
    if (DateTime.now().isBefore(_retryNotBefore)) {
      _requeueFront(batch, attempted: false);
      return;
    }
    _inFlight = batch;
    try {
      _activeFile ??= await _pickActiveFile();
      final text = batch.map((e) => '${e.line}\n').join();
      final current = _activeFile!;
      final size = current.existsSync() ? await current.length() : 0;
      if (size > _maxFileBytes) {
        _activeFile = await _rotate(current);
      }
      await _activeFile!.writeAsString(text, mode: FileMode.append, flush: true);
      _eventsWritten += batch.length;
      _consecutiveWriteFailures = 0;
      _retryNotBefore = DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      // Storage failure: counted, backed off, and the batch returns to the
      // queue instead of vanishing; the report header and the in-memory
      // export snapshot make the loss window visible.
      _writeFailures++;
      _consecutiveWriteFailures++;
      final secs = min(2 * pow(2, _consecutiveWriteFailures - 1), 60).toInt();
      _retryNotBefore = DateTime.now().add(Duration(seconds: secs));
      _requeueFront(batch, attempted: true);
    } finally {
      _inFlight = const [];
    }
  }

  Future<File> _pickActiveFile() async {
    final f1 = File('${_dir!.path}/$_file1');
    final f2 = File('${_dir!.path}/$_file2');
    final f1Exists = f1.existsSync();
    final f2Exists = f2.existsSync();
    if (!f1Exists && !f2Exists) return f1;
    if (f1Exists && !f2Exists) return f1;
    if (!f1Exists && f2Exists) return f2;
    final s1 = await f1.stat();
    final s2 = await f2.stat();
    return s1.modified.isAfter(s2.modified) ? f1 : f2;
  }

  Future<File> _rotate(File current) async {
    _rotations++;
    // The other file becomes active; old content of the new one is wiped,
    // keeping total size bounded at ~2x the per-file cap.
    final other = current.path.endsWith(_file1)
        ? File('${_dir!.path}/$_file2')
        : File('${_dir!.path}/$_file1');
    if (other.existsSync()) await other.delete();
    return other;
  }

  void _startTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 2), (_) => flush());
  }

  Future<Map<String, dynamic>> _readJson(String name) async {
    try {
      final f = File('${_dir!.path}/$name');
      if (!f.existsSync()) return {};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeJson(String name, Map<String, dynamic> data) async {
    await File('${_dir!.path}/$name')
        .writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> _saveFlags() async {
    try {
      await _writeJson('flags.json', {
        'enabled': _enabled,
        'verbose': _verbose,
        'includeVideoIds': _includeVideoIds,
      });
    } catch (_) {}
  }

  static String _newId() {
    final r = Random();
    const hex = '0123456789abcdef';
    return List.generate(6, (_) => hex[r.nextInt(16)]).join();
  }
}
