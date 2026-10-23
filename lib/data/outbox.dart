import 'dart:convert';
import 'dart:io';

/// A request waiting to be delivered to the backend.
class OutboxJob {
  OutboxJob({
    required this.id,
    required this.order,
    required this.method,
    required this.path,
    required this.body,
    this.attempts = 0,
  });

  factory OutboxJob.fromJson(Map<String, dynamic> json) => OutboxJob(
    id: json['id'] as String,
    order: json['order'] as int,
    method: json['method'] as String,
    path: json['path'] as String,
    body: json['body'] as Map<String, dynamic>?,
    attempts: json['attempts'] as int? ?? 0,
  );

  final String id;

  /// Monotonic sequence; jobs are delivered strictly in this order so a
  /// ride exists before its samples.
  final int order;
  final String method;
  final String path;
  final Map<String, dynamic>? body;
  int attempts;

  Map<String, dynamic> toJson() => {
    'id': id,
    'order': order,
    'method': method,
    'path': path,
    'body': body,
    'attempts': attempts,
  };
}

abstract class OutboxStore {
  Future<List<OutboxJob>> load();
  Future<void> put(OutboxJob job);
  Future<void> remove(OutboxJob job);
}

class MemoryOutboxStore implements OutboxStore {
  final Map<String, OutboxJob> _jobs = {};

  @override
  Future<List<OutboxJob>> load() async =>
      _jobs.values.toList()..sort((a, b) => a.order.compareTo(b.order));

  @override
  Future<void> put(OutboxJob job) async => _jobs[job.id] = job;

  @override
  Future<void> remove(OutboxJob job) async => _jobs.remove(job.id);
}

/// One JSON file per job, so queued ride data survives the app being
/// killed or the phone having no signal for the whole ride.
class FileOutboxStore implements OutboxStore {
  FileOutboxStore(this.directory);

  final Directory directory;

  File _file(OutboxJob job) => File(
    '${directory.path}/${job.order.toString().padLeft(20, '0')}_${job.id}.json',
  );

  @override
  Future<List<OutboxJob>> load() async {
    if (!await directory.exists()) return [];
    final jobs = <OutboxJob>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        jobs.add(
          OutboxJob.fromJson(
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>,
          ),
        );
      } on Object {
        // A half-written file from a crash; it can never be delivered.
        await entity.delete();
      }
    }
    return jobs..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<void> put(OutboxJob job) async {
    await directory.create(recursive: true);
    final file = _file(job);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(job.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> remove(OutboxJob job) async {
    final file = _file(job);
    if (await file.exists()) await file.delete();
  }
}
