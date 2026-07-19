import 'package:shared_preferences/shared_preferences.dart';

/// メール確認/OAuthのdeep linkコールバックには、それがどの操作の結果かを示す
/// マーカーが含まれないケースがある(例: プロバイダー連携 vs 通常サインイン)。
/// そのため、操作を開始する直前にアプリ側で「今何を待っているか」を
/// SharedPreferencesへ永続化しておく(メールのリンクをタップする間に
/// OSがアプリプロセスを終了させる可能性があるため、メモリ上の状態では不十分)。
///
/// 消費し忘れて残り続けると後々おかしな挙動を招くため、[consume] は
/// 読み取りと同時に必ず削除する(読みっぱなしで残さない)。さらに、
/// 何らかの理由で消費されないまま放置された場合に備えて有効期限を設け、
/// 期限切れのマーカーは無かったものとして扱う。
enum PendingAuthActionKind { emailChange, providerLink }

class PendingAuthAction {
  const PendingAuthAction(this.kind, this.detail);

  final PendingAuthActionKind kind;
  final String detail;
}

const _prefsKey = 'pending_auth_action';
const _staleAfter = Duration(minutes: 30);

Future<void> setPendingAuthAction(
  PendingAuthActionKind kind, {
  String detail = '',
}) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch;
  await prefs.setString(_prefsKey, '${kind.name}|$now|$detail');
}

/// 読み取りと同時に必ずクリアする。期限切れの場合は null を返す(かつクリア済み)。
Future<PendingAuthAction?> consumePendingAuthAction() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsKey);
  if (raw == null) return null;
  await prefs.remove(_prefsKey);

  final parts = raw.split('|');
  if (parts.length < 2) return null;

  final kind = PendingAuthActionKind.values
      .where((k) => k.name == parts[0])
      .firstOrNull;
  final sentAtMs = int.tryParse(parts[1]);
  if (kind == null || sentAtMs == null) return null;

  final sentAt = DateTime.fromMillisecondsSinceEpoch(sentAtMs);
  if (DateTime.now().difference(sentAt) > _staleAfter) return null;

  final detail = parts.length > 2 ? parts.sublist(2).join('|') : '';
  return PendingAuthAction(kind, detail);
}
