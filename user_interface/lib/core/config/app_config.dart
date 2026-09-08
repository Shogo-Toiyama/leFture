// lib/core/config/app_config.dart
//
// バックエンド(Cloud Run)のベースURL。既定は本番URLで、ローカルの
// バックエンド(`uvicorn app.main:app`)に向けてテストしたい時だけ
// 起動時に上書きする:
//
//   flutter run --dart-define=BACKEND_URL=http://192.168.1.23:8080
//
// (実機はPCと同じWi-Fiに繋いだ上で、PCのLAN IPを指定する。
//  `localhost`/`127.0.0.1`は実機からは繋がらないので使えない。
//  Android実機ではPCのファイアウォールでポート8080への着信を許可すること)
class AppConfig {
  AppConfig._();

  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://lefture-511705914929.us-west1.run.app',
  );
}
