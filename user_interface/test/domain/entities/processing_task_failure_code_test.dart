import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/processing_task.dart';

ProcessingTask _task(String status, String? errorMessage) => ProcessingTask(
      id: 't1',
      jobId: 'j1',
      taskType: 'TRANSCRIBE_MASTER',
      status: status,
      updatedAt: DateTime.utc(2026, 11, 23),
      errorMessage: errorMessage,
    );

void main() {
  test('reads the permanent failure code written by the backend', () {
    expect(
      _task('FAILED', 'NO_SPEECH_DETECTED: No speech was detected in this recording.').failureCode,
      ProcessingTask.noSpeechDetected,
    );
    expect(
      _task('FAILED', 'AUDIO_NOT_UPLOADED: Lecture x has no uploaded audio.').failureCode,
      ProcessingTask.audioNotUploaded,
    );
  });

  test('ordinary failures and non-failed tasks have no code', () {
    expect(_task('FAILED', 'Some error\nTraceback (most recent call last): ...').failureCode, isNull);
    expect(_task('FAILED', null).failureCode, isNull);
    // 古いジョブの生のエラー文(コード無し)は従来どおりリトライ可能な失敗として扱う
    expect(_task('FAILED', 'No valid transcript lines found for Core Extraction.').failureCode, isNull);
    expect(_task('PENDING', 'NO_SPEECH_DETECTED: x').failureCode, isNull);
  });
}
