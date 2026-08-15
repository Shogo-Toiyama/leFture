import 'package:supabase_flutter/supabase_flutter.dart';

/// `app_config`テーブルの生データ。ここではまだ「この端末で本当に
/// アップデートが必要か」の判定はしない(それは呼び出し側がビルド番号と
/// 突き合わせて決める)。
class AppConfigRemoteData {
  const AppConfigRemoteData({
    required this.maintenance,
    this.maintenanceMessage,
    required this.minBuildNumber,
    this.updateMessage,
  });

  final bool maintenance;
  final String? maintenanceMessage;
  final int minBuildNumber;
  final String? updateMessage;
}

class AppConfigRepository {
  AppConfigRepository(this._client);

  final SupabaseClient _client;

  /// 常に単一行(id=1)だけを読む設定テーブル。取得に時間がかかりすぎる
  /// 場合(バックエンド不調など)は3秒でタイムアウトさせ、呼び出し側の
  /// フェイルオープン処理に委ねる。
  Future<AppConfigRemoteData> fetch() async {
    final row = await _client
        .from('app_config')
        .select()
        .eq('id', 1)
        .single()
        .timeout(const Duration(seconds: 3));

    return AppConfigRemoteData(
      maintenance: row['maintenance'] as bool? ?? false,
      maintenanceMessage: row['maintenance_message'] as String?,
      minBuildNumber: (row['min_build_number'] as num?)?.toInt() ?? 0,
      updateMessage: row['update_message'] as String?,
    );
  }
}
