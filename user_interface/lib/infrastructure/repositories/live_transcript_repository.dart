// lib/infrastructure/repositories/live_transcript_repository.dart
import 'dart:developer' as dev;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/network_constants.dart';
import '../../domain/entities/live_transcript_sentence.dart';

class LiveTranscriptRepository {
  final SupabaseClient _supabase;

  LiveTranscriptRepository(this._supabase);

  // 録音中のライブプレビュー用途であり秒単位の追従は不要なため、
  // job_repository.dartのwatchJobと同じくポーリングにする(このアプリでは
  // Realtimeがどのテーブルにも有効化されていないため)。
  static const _pollInterval = Duration(seconds: 3);

  /// 指定講義のlecture_transcriptsをポーリングし、文単位にフラット化して
  /// 返し続ける。watchJobと違って終端条件は無く、呼び出し側が購読をやめる
  /// までポーリングし続ける(ProviderをautoDisposeにして制御する)。
  Stream<List<LiveTranscriptSentence>> watchLiveTranscript(String lectureId) async* {
    while (true) {
      List<LiveTranscriptSentence> sentences = const [];
      try {
        final rows = await _supabase
            .from('lecture_transcripts')
            .select()
            .eq('lecture_id', lectureId)
            .order('chunk_index')
            .timeout(networkTimeout);

        final all = <LiveTranscriptSentence>[];
        for (final row in rows) {
          all.addAll(_flattenRow(row));
        }
        all.sort((a, b) => a.startSec.compareTo(b.startSec));
        sentences = all;
      } catch (e, s) {
        // 通信エラー等。落とさずに次回のポーリングでリトライする。
        dev.log('🚨 watchLiveTranscript poll error: $e');
        dev.log('Stack trace: $s');
      }

      yield sentences;
      await Future.delayed(_pollInterval);
    }
  }

  /// 1チャンク行を文単位にフラット化する。サーバー側の assemble_transcript.py /
  /// sentence_review.py と同じフォールバック: segments_reviewed があれば
  /// 既に絶対秒なのでそのまま使い、無ければ segments_stt の相対秒に
  /// start_time を足した「下書き」を使う(REVIEWED後に自然に差し替わる)。
  List<LiveTranscriptSentence> _flattenRow(Map<String, dynamic> row) {
    final chunkIndex = row['chunk_index'] as int? ?? 0;
    final startTime = (row['start_time'] as num?)?.toDouble() ?? 0.0;

    final reviewed = row['segments_reviewed'] as List?;
    if (reviewed != null && reviewed.isNotEmpty) {
      return _toSentences(chunkIndex, reviewed, offset: 0.0);
    }

    final stt = row['segments_stt'] as List?;
    if (stt != null && stt.isNotEmpty) {
      return _toSentences(chunkIndex, stt, offset: startTime);
    }

    return const [];
  }

  List<LiveTranscriptSentence> _toSentences(
    int chunkIndex,
    List segments, {
    required double offset,
  }) {
    final result = <LiveTranscriptSentence>[];
    for (final raw in segments) {
      final seg = raw as Map<String, dynamic>;
      final text = (seg['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      final start = (seg['start'] as num?)?.toDouble() ?? 0.0;
      result.add(LiveTranscriptSentence(
        chunkIndex: chunkIndex,
        text: text,
        startSec: offset + start,
      ));
    }
    return result;
  }
}
