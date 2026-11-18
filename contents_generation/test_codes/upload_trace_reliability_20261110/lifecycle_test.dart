import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/recording/upload_trace.dart';
import 'package:lefture/core/utils/dev_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('trace-lifecycle');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => tmp.path);
    await UploadTrace.init();
  });
  tearDown(() async {
    DevLog.tap = null;
    await tmp.delete(recursive: true);
  });
  test('failed persistence preserves the source trace', () async {
    await UploadTrace.begin('lecture');
    await UploadTrace.finish('lecture');
    expect(File('${tmp.path}/upload_traces/lecture.log').existsSync(), isTrue);
  });
}
