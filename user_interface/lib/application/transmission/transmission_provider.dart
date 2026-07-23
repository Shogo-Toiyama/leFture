import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lecture_companion_ui/domain/entities/app_transmission.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

const String _kLastReadTransmissionKey = 'last_read_transmission_time';

/// Supabaseから取得した配信中のお知らせ一覧プロバイダー
final appTransmissionsProvider = FutureProvider<List<AppTransmission>>((ref) async {
  try {
    final response = await supabase
        .from('app_transmissions')
        .select()
        .order('priority', ascending: false)
        .order('published_at', ascending: false);

    final list = (response as List<dynamic>)
        .map((item) => AppTransmission.fromMap(item as Map<String, dynamic>))
        .toList();
    return list;
  } catch (e) {
    // オフラインまたはエラー時は空リストを返す（クラッシュ防止）
    return [];
  }
});

/// ローカルに保存されている最終閲覧日時プロバイダー
final lastReadTransmissionTimeProvider = FutureProvider<DateTime?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final timeStr = prefs.getString(_kLastReadTransmissionKey);
  if (timeStr == null) return null;
  return DateTime.tryParse(timeStr);
});

/// 未読のお知らせ一覧プロバイダー
final unreadTransmissionsProvider = FutureProvider<List<AppTransmission>>((ref) async {
  final allTransmissions = await ref.watch(appTransmissionsProvider.future);
  final lastReadTime = await ref.watch(lastReadTransmissionTimeProvider.future);

  if (allTransmissions.isEmpty) return [];
  if (lastReadTime == null) {
    // 初回起動時は配信中のお知らせ全件を未読とする
    return allTransmissions;
  }

  // 最終閲覧日時よりも後に配信されたお知らせを未読として抽出
  return allTransmissions
      .where((item) => item.publishedAt.isAfter(lastReadTime))
      .toList();
});

/// お知らせをすべて既読として記録するヘルパー関数
Future<void> markTransmissionsAsRead(WidgetRef ref, List<AppTransmission> items) async {
  if (items.isEmpty) return;
  
  // 最も新しい配信日時を取得（あるいは現在時刻）
  final newestTime = items.map((e) => e.publishedAt).reduce((a, b) => a.isAfter(b) ? a : b);
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastReadTransmissionKey, newestTime.toIso8601String());
  
  // プロバイダーの再評価
  ref.invalidate(lastReadTransmissionTimeProvider);
  ref.invalidate(unreadTransmissionsProvider);
}
