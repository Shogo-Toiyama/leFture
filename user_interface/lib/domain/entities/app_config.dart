/// アプリ全体の稼働状態(メンテナンス中・強制アップデートが必要か)を表す。
/// Supabaseの `app_config` テーブルから取得し、[AppConfigController]が
/// アプリ起動時とバックグラウンド復帰時に更新する。取得に失敗した場合は
/// 直前の値を維持する(フェイルオープン)ため、常に「取得できた最新の
/// 状態」ではなく「最後に確認できた状態」を表す点に注意。
class AppConfig {
  const AppConfig({
    required this.maintenance,
    this.maintenanceMessage,
    required this.updateRequired,
    this.updateMessage,
    this.acknowledged = false,
  });

  /// メンテナンス中かどうか。
  final bool maintenance;

  /// メンテナンス中に表示するメッセージ(未設定ならデフォルト文言を使う)。
  final String? maintenanceMessage;

  /// この端末のビルド番号が、サーバーが要求する最低バージョンを
  /// 下回っているかどうか。
  final bool updateRequired;

  /// アップデート要求時に表示するメッセージ(未設定ならデフォルト文言を使う)。
  final String? updateMessage;

  /// ユーザーが全面オーバーレイの「このまま使う」を押して確認済みか。
  /// セッション内(アプリ再起動まで)のみ有効で、永続化はしない。
  final bool acknowledged;

  /// バックエンドとの書き込み同期(Outbox push)を止めるべきかどうか。
  /// 読み取り専用のローカル閲覧は、メンテナンス中・強制アップデート中でも
  /// 妨げない(オフラインで使える体験と同じ扱いにする)。
  bool get isSyncBlocked => maintenance || updateRequired;

  /// 全面オーバーレイを表示すべきかどうか。
  bool get shouldShowGate => (maintenance || updateRequired) && !acknowledged;

  static const unrestricted = AppConfig(
    maintenance: false,
    updateRequired: false,
  );

  AppConfig copyWith({bool? acknowledged}) {
    return AppConfig(
      maintenance: maintenance,
      maintenanceMessage: maintenanceMessage,
      updateRequired: updateRequired,
      updateMessage: updateMessage,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}
