import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

class DevicePermissionsService {
  /// アプリに必要な主要権限（マイク・通知・Androidのバッテリー最適化除外）の中で、
  /// まだ許可されていない（isGranted == false）権限が存在するかどうかを返す。
  static Future<bool> hasMissingRequiredPermissions() async {
    if (kIsWeb) return false;

    // マイク権限チェック
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) return true;

    // 通知権限チェック
    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) return true;

    // Androidの場合のバッテリー最適化除外権限チェック
    if (Platform.isAndroid) {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) return true;
    }

    return false;
  }
}
