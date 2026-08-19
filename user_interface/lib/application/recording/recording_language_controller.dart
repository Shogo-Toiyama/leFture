// lib/application/recording/recording_language_controller.dart
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';

part 'recording_language_controller.g.dart';

/// 録音言語(オンデバイスASRモデル選択)の設定。永続化と状態管理のみを行う。
/// モデルのダウンロードはここでは行わない — Realtime Recordingが有効な
/// 場合のみ、呼び出し側(言語ピッカーのUI/HomePageの自動チェック)が
/// `AsrModelManager.ensureModelReady`を明示的に呼ぶ(無効なら無駄な
/// ダウンロードを避ける)。
@Riverpod(keepAlive: true)
class RecordingLanguageController extends _$RecordingLanguageController {
  @override
  String build() => RecordingPreferences().getRecordingLanguage();

  Future<void> setLanguage(String code) async {
    if (state == code) return;
    // UI表示状態を真っ先に更新して0msで反映
    state = code;

    // ディスク保存やDB/Outbox書き込みは非同期バックグラウンドで実行
    unawaited(RecordingPreferences().setRecordingLanguage(code));
    unawaited(Future(() async {
      try {
        await ref.read(userProfileRepositoryProvider).setRecordingLanguage(code);
      } catch (_) {}
    }));
  }

  /// SharedPreferences に保存されている最新の録音言語を取り込んで状態を更新する。
  /// （ログイン時のクラウドからの同期復元時などに利用）
  void syncFromPreferences() {
    final lang = RecordingPreferences().getRecordingLanguage();
    if (state != lang) {
      state = lang;
    }
  }
}
