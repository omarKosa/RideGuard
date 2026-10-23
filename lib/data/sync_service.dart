import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'outbox.dart';

/// Delivers queued requests to the backend in order, persisting them first
/// so nothing is lost while offline. Every endpoint is idempotent (client
/// generated ids, sample sequence numbers) so retries never duplicate data.
class SyncService extends ChangeNotifier {
  SyncService({
    required ApiClient api,
    required OutboxStore store,
    Duration Function(int failures)? backoff,
  }) : _api = api,
       _store = store,
       _backoff = backoff ?? _defaultBackoff;

  final ApiClient _api;
  final OutboxStore _store;
  final Duration Function(int failures) _backoff;
  final List<OutboxJob> _queue = [];
  final _uuid = const Uuid();

  int _nextOrder = 0;
  int _failures = 0;
  Future<void>? _drain;
  bool _disposed = false;
  Timer? _retryTimer;

  bool? _online;
  String? _lastError;
  DateTime? _lastSuccessAt;
  int _dropped = 0;

  int get pending => _queue.length;

  /// Null until the first delivery attempt.
  bool? get online => _online;
  String? get lastError => _lastError;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Requests the server permanently rejected (validation errors).
  int get dropped => _dropped;

  static Duration _defaultBackoff(int failures) =>
      Duration(seconds: math.min(60, 2 << math.min(failures, 5)));

  Future<void> init() async {
    final jobs = await _store.load();
    _queue
      ..clear()
      ..addAll(jobs);
    _nextOrder = jobs.isEmpty
        ? DateTime.now().microsecondsSinceEpoch
        : math.max(jobs.last.order + 1, DateTime.now().microsecondsSinceEpoch);
    _notify();
    unawaited(flush());
  }

  Future<void> enqueue(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final job = OutboxJob(
      id: _uuid.v4(),
      order: _nextOrder++,
      method: method,
      path: path,
      body: body,
    );
    _queue.add(job);
    await _store.put(job);
    _notify();
    unawaited(flush());
  }

  /// Delivers as much of the queue as possible. Safe to call any time;
  /// concurrent callers share the same in-flight delivery.
  Future<void> flush() {
    if (_disposed) return Future.value();
    return _drain ??= _deliver().whenComplete(() => _drain = null);
  }

  Future<void> _deliver() async {
    _retryTimer?.cancel();
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final job = _queue.first;
        try {
          await _api.send(job.method, job.path, job.body);
          _online = true;
          _failures = 0;
          _lastError = null;
          _lastSuccessAt = DateTime.now();
          await _remove(job);
        } on ApiException catch (e) {
          job.attempts++;
          _lastError = e.toString();
          if (e.retryable) {
            _online = e.statusCode != null;
            _failures++;
            await _store.put(job);
            _scheduleRetry();
            return;
          }
          // The server will never accept this; don't block the queue.
          debugPrint('Dropping ${job.method} ${job.path}: $e');
          _dropped++;
          _online = true;
          await _remove(job);
        }
      }
    } finally {
      _notify();
    }
  }

  Future<void> _remove(OutboxJob job) async {
    _queue.remove(job);
    await _store.remove(job);
    _notify();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff(_failures), () => unawaited(flush()));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }
}
