import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/credit_summary.dart';
import '../../domain/plan_features.dart' as plan_features;

/// 最後に成功した GET /billing/summary の結果(tier_level・gating_disabled・
/// クレジット残高)を端末に保存し、次回それをまだ待たずに「楽観的に」参照
/// できるようにするための軽量キャッシュ。
///
/// ★ これは信頼境界ではない。ここに保存された値は端末上で改ざん・偽装され
/// うる前提で設計されている——実際に課金・コストが発生する操作(Whisperへの
/// チャンク送信等)の可否を、このキャッシュの値だけで最終決定してはならない。
/// 必ずバックエンドへの実際の問い合わせ(例:
/// RecordingController._resolveRealtimeEligibility)で確定させ、このキャッシュは
/// 「その結果が届くまでの間、体感を落とさないための仮の値」としてのみ使うこと。
///
/// 他の機能ゲート(DeepNotes/TopicMap/AnnouncementGeneration等)は生成の瞬間に
/// バックエンドのhas_feature()が必ずハードブロックするため、このキャッシュが
/// 偽装されても実害は無い。Realtime Transcribeだけは意図的にバックエンド側の
/// ブロックを行わない設計(録音済みの講義を一生分析できなくする方が害が
/// 大きいため — main.pyのコメント参照)なので、この値の扱いだけ特に慎重に
/// すること。
class PlanEntitlementCache {
  static const _keyTierLevel = 'plan_cache_tier_level';
  static const _keyGatingDisabled = 'plan_cache_gating_disabled';
  static const _keyCreditBalanceMicro = 'plan_cache_credit_balance_micro';

  /// 成功した/billing/summary応答を保存する。失敗(ストレージI/Oエラー等)は
  /// 無視してよい——あくまで補助的なキャッシュで、次回成功時に上書きされる。
  Future<void> save(CreditSummary summary) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyTierLevel, summary.tierLevel);
      await prefs.setBool(_keyGatingDisabled, summary.gatingDisabled);
      final balance = summary.creditBalanceMicro;
      if (balance != null) {
        await prefs.setInt(_keyCreditBalanceMicro, balance);
      } else {
        await prefs.remove(_keyCreditBalanceMicro);
      }
    } catch (_) {
      // キャッシュ書き込み失敗は無視。
    }
  }

  /// キャッシュされた値から「[featureKey]が[minCredits]クレジット以上の
  /// 残高で使えそうか」を楽観的に判定する。一度もキャッシュされたことが
  /// 無い場合、または読み取りに失敗した場合はfalse(賭けに出ない——実害の
  /// 無い機能はともかく、コストが発生しうる判定の初期値は常に安全側)。
  Future<bool> isOptimisticallyEligibleFor(
    String featureKey, {
    required int minCredits,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_keyTierLevel)) return false;
      final tierLevel = prefs.getInt(_keyTierLevel) ?? plan_features.tierFree;
      final gatingDisabled = prefs.getBool(_keyGatingDisabled) ?? false;
      if (!plan_features.hasFeature(
        tierLevel,
        featureKey,
        gatingDisabled: gatingDisabled,
      )) {
        return false;
      }
      final balanceMicro = prefs.getInt(_keyCreditBalanceMicro);
      if (balanceMicro == null) return false;
      return balanceMicro >= minCredits * CreditSummary.microCreditsPerCredit;
    } catch (_) {
      return false;
    }
  }
}
