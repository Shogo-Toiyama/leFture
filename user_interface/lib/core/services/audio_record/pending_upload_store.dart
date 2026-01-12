import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PendingUploadJob {
  PendingUploadJob({
    required this.id, // ← assetId として使う
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

  PendingUploadJob copyWith({
    String? id,
    String? userId,
    String? lectureId,
    String? localPath,
    String? fileName,
    String? createdAtIso,
    int? attempts,
  }) {
    return PendingUploadJob(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      localPath: localPath ?? this.localPath,
      fileName: fileName ?? this.fileName,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      attempts: attempts ?? this.attempts,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'lectureId': lectureId,
        'localPath': localPath,
        'fileName': fileName,
        'createdAtIso': createdAtIso,
        'attempts': attempts,
      };

  static PendingUploadJob fromJson(Map<String, dynamic> json) {
    return PendingUploadJob(
      id: json['id'] as String,
      userId: json['userId'] as String,
      lectureId: json['lectureId'] as String,
      localPath: json['localPath'] as String,
      fileName: json['fileName'] as String,
      createdAtIso: json['createdAtIso'] as String,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

class PendingUploadStore {
  static const _key = 'pending_upload_jobs_v1';

  Future<List<PendingUploadJob>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    final list = (jsonDecode(raw) as List)
        .cast<Map>()
        .map((e) => PendingUploadJob.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    list.sort((a, b) => a.createdAtIso.compareTo(b.createdAtIso));
    return list;
  }

  Future<void> save(List<PendingUploadJob> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(jobs.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> add(PendingUploadJob job) async {
    final jobs = await load();
    jobs.removeWhere((e) => e.id == job.id); // 同じassetIdは上書き
    jobs.add(job);
    await save(jobs);
  }

  Future<void> remove(String id) async {
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
