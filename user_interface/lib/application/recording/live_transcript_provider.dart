// lib/application/recording/live_transcript_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lefture/domain/entities/live_transcript_sentence.dart';
import 'package:lefture/infrastructure/repositories/live_transcript_repository.dart';

part 'live_transcript_provider.g.dart';

@riverpod
LiveTranscriptRepository liveTranscriptRepository(Ref ref) {
  return LiveTranscriptRepository(Supabase.instance.client);
}

// @riverpod(既定でautoDispose)にすることで、Liveタブを離れる/Realtimeを
// offにするとポーリングが止まる(UploadManagerのようなapp全体スコープにはしない)。
@riverpod
Stream<LiveTranscriptSnapshot> liveTranscript(Ref ref, String lectureId) {
  return ref.watch(liveTranscriptRepositoryProvider).watchLiveTranscript(lectureId);
}
