import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lecture_companion_ui/core/utils/connectivity_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_status_provider.g.dart';

/// アプリ全体で共有するオンライン/オフライン状態。
/// オフラインバナー表示や、ネットワーク処理を開始する前のガードに使う。
@Riverpod(keepAlive: true)
Stream<bool> isOnline(Ref ref) async* {
  yield await isDeviceOnline();
  yield* Connectivity()
      .onConnectivityChanged
      .map((results) => !isConnectivityOffline(results));
}
