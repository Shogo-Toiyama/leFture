import 'dart:convert';

class ProcessingJobs {
  final String id;
  final String lectureId;
  final String status;
  final String? currentStep;
  final int stepNumber;
  final Map<String, dynamic>? errorMessage;

  const ProcessingJobs({
    required this.id,
    required this.lectureId,
    required this.status,
    this.currentStep,
    this.stepNumber = 0,
    this.errorMessage,
  });

  factory ProcessingJobs.fromJson(Map<String, dynamic> json) {
    // error_message が String (JSON文字列) で来る場合と、Map で来る場合の両方に対応
    Map<String, dynamic>? parsedError;
    if (json['error_message'] != null) {
      if (json['error_message'] is String) {
        try {
          parsedError = jsonDecode(json['error_message']) as Map<String, dynamic>;
        } catch (_) {
          parsedError = {'message': json['error_message']};
        }
      } else if (json['error_message'] is Map) {
        parsedError = json['error_message'] as Map<String, dynamic>;
      }
    }

    return ProcessingJobs(
      // ★ id を String として取得 (.toString() しておくと安全)
      id: json['id']?.toString() ?? '', 
      
      lectureId: json['lecture_id'] as String,
      status: json['status'] as String,
      currentStep: json['current_step'] as String?,
      
      // step_number が null の場合のガードを入れる
      stepNumber: (json['step_number'] as num?)?.toInt() ?? 0,
      
      errorMessage: parsedError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lecture_id': lectureId,
      'status': status,
      'current_step': currentStep,
      'step_number': stepNumber,
      'error_message': errorMessage,
    };
  }

  // job_repository.dartのwatchJob()が.distinct()で「実際に内容が変わった時
  // だけ」再emitするために必要な値等価。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProcessingJobs &&
        other.id == id &&
        other.lectureId == lectureId &&
        other.status == status &&
        other.currentStep == currentStep &&
        other.stepNumber == stepNumber &&
        _mapEquals(other.errorMessage, errorMessage);
  }

  @override
  int get hashCode => Object.hash(id, lectureId, status, currentStep, stepNumber);

  static bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }
}