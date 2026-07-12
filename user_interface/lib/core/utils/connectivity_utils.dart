import 'package:connectivity_plus/connectivity_plus.dart';

/// `connectivity_plus`のバージョン差(`ConnectivityResult`単体 or
/// `List<ConnectivityResult>`)を両方許容してオフライン判定する共通ヘルパー。
bool isConnectivityOffline(dynamic results) {
  if (results is List<ConnectivityResult>) {
    return results.isEmpty || results.contains(ConnectivityResult.none);
  }
  if (results is ConnectivityResult) {
    return results == ConnectivityResult.none;
  }
  return false;
}

/// 現在オンラインかどうかを1回だけ確認する。
Future<bool> isDeviceOnline() async {
  final result = await Connectivity().checkConnectivity();
  return !isConnectivityOffline(result);
}
