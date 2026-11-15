import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/recording/upload_trace.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('upload_trace_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await UploadTrace.init();
  });

  tearDown(() async {
    DevLog.tap = null;
    await tmp.delete(recursive: true);
  });

  test('records DevLog lines after begin, skipping timer ticks', () async {
    await UploadTrace.begin('lec-1', preamble: ['10:00:00 [Chunker] Chunk 3 ready', '10:00:01 [Timer] Tick: 5']);
    DevLog.add('[Timer] Tick: 6');
    DevLog.add('🔄 [UploadManager] Attempting master_audio_upload#abc');
    final lines = await File('${tmp.path}/upload_traces/lec-1.log').readAsLines();
    expect(lines.first, startsWith('# started='));
    expect(lines.any((l) => l.contains('Chunk 3 ready')), isTrue);
    expect(lines.any((l) => l.contains('[Timer] Tick')), isFalse);
    expect(lines.any((l) => l.contains('Attempting master_audio_upload')), isTrue);
    expect(lines.contains('--- stop pressed, upload phase begins ---'), isTrue);
  });

  test('finish removes the trace file (no reporter installed: send is a no-op)', () async {
    await UploadTrace.begin('lec-2');
    await UploadTrace.finish('lec-2');
    expect(File('${tmp.path}/upload_traces/lec-2.log').existsSync(), isFalse);
  });
}
