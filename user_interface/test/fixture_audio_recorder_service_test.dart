import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_companion_ui/presentation/pages/dev_tools/fixture_audio_recorder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // FixtureAudioRecorderService は AudioRecorderService を継承しており、
  // 親クラスのコンストラクタが実プラットフォームの `record` プラグイン
  // (MethodChannel) を生成するため、テスト実行時は最低限のモック応答を返す。
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, (call) async => null);

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fixture_audio_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('emits the fixture bytes in order and completes `done`', () async {
    // 32,000 bytes/sec の1秒分よりちょっと多いダミーPCMデータを用意する
    final expected = Uint8List.fromList(
      List.generate(32000 + 1234, (i) => i % 256),
    );
    final file = File('${tempDir.path}/fixture.pcm');
    await file.writeAsBytes(expected);

    final service = FixtureAudioRecorderService(
      fixturePcmPath: file.path,
      speedMultiplier: 1000, // テストを高速化するため大幅に加速する
    );
    addTearDown(service.dispose);

    final stream = await service.startStream();

    final received = BytesBuilder();
    await for (final chunk in stream) {
      received.add(chunk);
    }

    expect(received.toBytes(), expected);
    await expectLater(service.done, completes);
  });

  test('throws if the fixture file does not exist', () async {
    final service = FixtureAudioRecorderService(
      fixturePcmPath: '${tempDir.path}/does_not_exist.pcm',
    );
    addTearDown(service.dispose);

    expect(() => service.startStream(), throwsStateError);
  });
}
