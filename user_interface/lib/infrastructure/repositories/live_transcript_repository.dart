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
  ///
  /// `status == 'REVIEWED'`はサーバー側で一方向・終端の状態(戻ることは無い)
  /// なので、一度REVIEWEDと確認できた行は内容をローカルにキャッシュし、
  /// 以降のポーリングでは`.not('id', 'in', ...)`で除外して二度と取得しない。
  /// これが無いと、2時間・200チャンク超の講義では、既に確定して二度と
  /// 変わらない行のJSONペイロードまで毎回(3秒ごとに)丸ごと再取得する
  /// ことになり、講義が長くなるほどポーリングのコストが際限なく増えていく。
  Stream<LiveTranscriptSnapshot> watchLiveTranscript(String lectureId) async* {
    // 行id → フラット化済み文。REVIEWEDと確認できた行だけをここに残す。
    final finalized = <String, List<LiveTranscriptSentence>>{};
    // 行id → その行が実際にカバーしている音声の終端(絶対秒)。無音チャンク等で
    // 文が1つも無いREVIEWED行でも、audio_durationが確定していればここに残す
    // (節電ラベルの判定が「サーバーがどこまで文字起こしを終えたか」を
    // 文の有無に関係なく知れるようにするため)。
    final finalizedCoverageEnd = <String, double>{};

    while (true) {
      List<LiveTranscriptSentence> sentences = const [];
      double? coverageEndSec = _maxOrNull(finalizedCoverageEnd.values);
      try {
        var query = _supabase.from('lecture_transcripts').select().eq('lecture_id', lectureId);
        if (finalized.isNotEmpty) {
          query = query.not('id', 'in', finalized.keys.toList());
        }
        final rows = await query.order('chunk_index').timeout(networkTimeout);

        final pending = <LiveTranscriptSentence>[];
        for (final row in rows) {
          final id = row['id'] as String?;
          final flattened = _flattenRow(row);
          final rowCoverageEnd = _coverageEndOf(row);
          if (rowCoverageEnd != null &&
              (coverageEndSec == null || rowCoverageEnd > coverageEndSec)) {
            coverageEndSec = rowCoverageEnd;
          }
          if (id != null && row['status'] == 'REVIEWED') {
            // 無音チャンク等でsegmentsが空のREVIEWED行も、二度と内容が
            // 変わらない点は同じなのでキャッシュして除外対象にする。
            finalized[id] = flattened;
            if (rowCoverageEnd != null) finalizedCoverageEnd[id] = rowCoverageEnd;
          } else {
            pending.addAll(flattened);
          }
        }

        final all = [
          for (final s in finalized.values) ...s,
          ...pending,
        ];
        all.sort((a, b) => a.startSec.compareTo(b.startSec));
        sentences = all;
      } catch (e, s) {
        // 通信エラー等。落とさずに次回のポーリングでリトライする。
        dev.log('🚨 watchLiveTranscript poll error: $e');
        dev.log('Stack trace: $s');
      }

      yield (sentences: sentences, coverageEndSec: coverageEndSec);
      await Future.delayed(_pollInterval);
    }
  }

  double? _maxOrNull(Iterable<double> values) {
    double? result;
    for (final v in values) {
      if (result == null || v > result) result = v;
    }
    return result;
  }

  /// この行(チャンク)が実際にカバーしている音声の終端(絶対秒)。
  /// audio_durationはSTTが完了した時点でstart_timeと同時に書き込まれる
  /// ので、まだ文字起こしが終わっていない行(PROCESSING/TRANSCRIBING)では
  /// nullを返す — 「サーバーが追い越した」とは言えないため。
  double? _coverageEndOf(Map<String, dynamic> row) {
    final duration = (row['audio_duration'] as num?)?.toDouble();
    if (duration == null) return null;
    final startTime = (row['start_time'] as num?)?.toDouble() ?? 0.0;
    return startTime + duration;
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
