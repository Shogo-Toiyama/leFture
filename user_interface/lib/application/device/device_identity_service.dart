import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

/// 端末のKeychain / KeyStoreを活用し、アプリ再インストール後も永続化される
/// 端末一意IDおよびFreeプラン利用済みフラグを管理するサービス。
class DeviceIdentityService {
  DeviceIdentityService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _deviceIdKey = 'device_install_id';
  static const _hasClaimedFreeKey = 'has_claimed_device_free';

  /// 端末に永続化された一意なUUIDを取得する。
  /// 初回呼び出し時は新規生成してKeychainに書き込む。
  Future<String> getOrCreateDeviceId() async {
    try {
      final existingId = await _storage.read(key: _deviceIdKey);
      if (existingId != null && existingId.isNotEmpty) {
        return existingId;
      }
      final newId = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: newId);
      return newId;
    } catch (_) {
      // 万が一Keychainアクセスに失敗した場合のフォールバック
      return const Uuid().v4();
    }
  }

  /// この端末で過去にFreeプラン（無料クレジット）がClaimされたか判定する。
  Future<bool> hasClaimedDeviceFree() async {
    try {
      final val = await _storage.read(key: _hasClaimedFreeKey);
      return val == 'true';
    } catch (_) {
      return false;
    }
  }

  /// この端末でFreeプランがClaimされたことをKeychainに永続記録する。
  Future<void> markDeviceFreeClaimed() async {
    try {
      await _storage.write(key: _hasClaimedFreeKey, value: 'true');
    } catch (_) {
      // ログ等の処理
    }
  }
}

final deviceIdentityServiceProvider = Provider<DeviceIdentityService>((ref) {
  return DeviceIdentityService();
});
