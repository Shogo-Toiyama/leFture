import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/device/device_identity_service.dart';

class _MockFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _map[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _map[key] = value;
    } else {
      _map.remove(key);
    }
  }
}

void main() {
  group('DeviceIdentityService', () {
    late _MockFlutterSecureStorage mockStorage;
    late DeviceIdentityService service;

    setUp(() {
      mockStorage = _MockFlutterSecureStorage();
      service = DeviceIdentityService(storage: mockStorage);
    });

    test('getOrCreateDeviceId returns new UUID on first call and persists it', () async {
      final id1 = await service.getOrCreateDeviceId();
      expect(id1, isNotEmpty);

      // 2回目以降は同じIDが返る
      final id2 = await service.getOrCreateDeviceId();
      expect(id2, equals(id1));
    });

    test('hasClaimedDeviceFree returns false initially, then true after markDeviceFreeClaimed', () async {
      expect(await service.hasClaimedDeviceFree(), isFalse);

      await service.markDeviceFreeClaimed();
      expect(await service.hasClaimedDeviceFree(), isTrue);
    });
  });
}
