import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PendingUploadJob {
  PendingUploadJob({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.localPath,
    required this.fileName,
    required this.createdAtIso,
    this.attempts = 0,
  });

  final String id;
  final String userId;
  final String lectureId;
  final String localPath;
  final String fileName;
  final String createdAtIso;
  final int attempts;

  PendingUploadJob copyWith({int? attempts}) => PendingUploadJob(
        id: id,
        userId: userId,
        lectureId: lectureId,
        localPath: localPath,
        fileName: fileName,
        createdAtIso: createdAtIso,
        attempts: attempts ?? this.attempts,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'lectureId': lectureId,
        'localPath': localPath,
        'fileName': fileName,
        'createdAtIso': createdAtIso,
        'attempts': attempts,
      };

  static PendingUploadJob fromJson(Map<String, dynamic> j) => PendingUploadJob(
        id: j['id'] as String,
        userId: j['userId'] as String,
        lectureId: j['lectureId'] as String,
        localPath: j['localPath'] as String,
        fileName: j['fileName'] as String,
        createdAtIso: j['createdAtIso'] as String,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );
}

class PendingUploadStore {
  static const _key = 'pending_upload_jobs_v1';

  Future<List<PendingUploadJob>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(PendingUploadJob.fromJson).toList();
  }

  Future<void> save(List<PendingUploadJob> jobs) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(jobs.map((e) => e.toJson()).toList());
    await sp.setString(_key, raw);
  }

  Future<void> add(PendingUploadJob job) async {
    final jobs = await load();
    jobs.add(job);
    await save(jobs);
  }

  Future<void> removeById(String id) async {
    final jobs = await load();
    jobs.removeWhere((e) => e.id == id);
    await save(jobs);
  }

  Future<void> update(PendingUploadJob job) async {
    final jobs = await load();
    final idx = jobs.indexWhere((e) => e.id == job.id);
    if (idx >= 0) {
      jobs[idx] = job;
      await save(jobs);
    }
  }
}
