// presentation/pages/dev_tools/pipe_encode_prototype_tab.dart
//
// 部分MP3化(継続エンコード)の実現可能性を検証するための、使い捨てプロトタイプ
// (ステップ1)。RecordingController/RecordingRepositoryDrift/
// RecordingRecoveryServiceには一切触れない、完全に独立したハーネス。
//
// 検証すること:
//   1. dart:ffi経由のmkfifo()で作ったnamed pipeに、FFmpegKitが実機
//      (iOS/Android)でも安定して追従できるか
//   2. `-frag_duration` + `-flush_packets 1` を付けたfragmented MP4が、
//      録音の途中(=まだ全体の長さが確定していない状態)でも都度ディスク上で
//      有効なファイルであり続けるか
//   3. アプリを強制終了(exit(0)。実機ではロック→OSに殺されるまで待つ方がより
//      正確)しても、直前まで書かれた分は壊れずに残り、プツっという音や
//      重複無く再生できるか
//
// Macのプレーンffmpegでの事前検証(ステップ0)で固めたコマンドをそのまま
// FFmpegKit経由で使う。可聴の周波数スイープを鳴らすことで、継ぎ目のズレ
// (重複・欠落)を実際に耳で確認できるようにしている。

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:ffi/ffi.dart' as pffi;
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

const int _bytesPerSec = 32000; // 16kHz * 16bit(2byte) * mono
const int _tickMs = 200;
final int _bytesPerTick = (_bytesPerSec * _tickMs / 1000).round() ~/ 2 * 2; // 偶数(16bitサンプル境界)に揃える

typedef _MkfifoNative = ffi.Int32 Function(ffi.Pointer<pffi.Utf8> path, ffi.Uint32 mode);
typedef _MkfifoDart = int Function(ffi.Pointer<pffi.Utf8> path, int mode);

/// dart:io にmkfifo(2)相当のAPIが無いため、libcを直接叩く。
/// iOSはProcess.run自体が使えない(サンドボックスでshell実行不可)ため、
/// クロスプラットフォームで動く手段はこのFFI経由のみ。
int _mkfifo(String path) {
  final lib = ffi.DynamicLibrary.process();
  final fn = lib.lookupFunction<_MkfifoNative, _MkfifoDart>('mkfifo');
  final pathPtr = path.toNativeUtf8();
  try {
    return fn(pathPtr, 0x1B6); // 0666
  } finally {
    pffi.calloc.free(pathPtr);
  }
}

/// 5秒ごとに周波数を変える正弦波を生成する。継ぎ目で重複/欠落があれば、
/// 「同じ音程が繰り返される」「音程がいきなり飛ぶ」として耳で分かる。
Uint8List _generateSweepPcm({required int totalSeconds}) {
  const freqs = [440, 880, 220, 660, 330];
  final totalSamples = totalSeconds * 16000;
  final bytes = Uint8List(totalSamples * 2);
  final data = ByteData.sublistView(bytes);

  for (int i = 0; i < totalSamples; i++) {
    final tSec = i / 16000.0;
    final freq = freqs[(tSec ~/ 5) % freqs.length];
    final sample = (math.sin(2 * math.pi * freq * tSec) * 12000).round();
    data.setInt16(i * 2, sample, Endian.little);
  }
  return bytes;
}

class PipeEncodePrototypeTab extends StatefulWidget {
  const PipeEncodePrototypeTab({super.key});

  @override
  State<PipeEncodePrototypeTab> createState() => _PipeEncodePrototypeTabState();
}

class _PipeEncodePrototypeTabState extends State<PipeEncodePrototypeTab> {
  final List<String> _log = [];
  bool _running = false;
  String? _fixturePath;
  String? _outputPath;
  double _fedSeconds = 0;
  Timer? _sizeWatcher;
  bool _cancelled = false;

  void _addLog(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)}  $line');
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<Directory> _testDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pipe_encode_prototype');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _generateFixture() async {
    final dir = await _testDir();
    final path = '${dir.path}/sweep_fixture.pcm';
    final pcm = _generateSweepPcm(totalSeconds: 60);
    await File(path).writeAsBytes(pcm, flush: true);
    setState(() => _fixturePath = path);
    _addLog('✅ fixture生成: $path (${pcm.length} bytes, 60秒分, 440/880/220/660/330Hzを5秒毎に切替)');
  }

  Future<void> _startPipeEncode() async {
    final fixturePath = _fixturePath;
    if (fixturePath == null) return;

    final dir = await _testDir();
    final fifoPath = '${dir.path}/live.pcm.fifo';
    final outputPath = '${dir.path}/live_out.m4a';

    // 前回の残骸を掃除(fifoは特殊ファイルなので必ず作り直す)
    final fifoFile = File(fifoPath);
    if (await fifoFile.exists()) await fifoFile.delete();
    final outFile = File(outputPath);
    if (await outFile.exists()) await outFile.delete();

    final mkfifoResult = _mkfifo(fifoPath);
    if (mkfifoResult != 0) {
      _addLog('🔴 mkfifo失敗 (戻り値=$mkfifoResult) — このOS/パスでは使えない可能性');
      return;
    }
    _addLog('✅ named pipe作成: $fifoPath');

    setState(() {
      _running = true;
      _cancelled = false;
      _outputPath = outputPath;
      _fedSeconds = 0;
    });

    // Macでの検証(ステップ0)で固めたコマンド: frag_duration(2秒毎に強制的に
    // フラグメントを確定) + flush_packets 1(ffmpeg内部バッファに溜め込まず
    // 即ディスクへ書き出す)が無いと、強制終了時にファイルが壊れる。
    final command =
        '-y -f s16le -ar 16000 -ac 1 -i "$fifoPath" -c:a aac -b:a 64k '
        '-movflags +frag_keyframe+empty_moov+default_base_moof -frag_duration 2000000 '
        '-flush_packets 1 "$outputPath"';
    _addLog('▶️ FFmpegKit.executeAsync 開始: $command');

    unawaited(
      FFmpegKit.executeAsync(
        command,
        (session) async {
          final rc = await session.getReturnCode();
          _addLog('🏁 FFmpegセッション終了。ReturnCode=$rc / success=${ReturnCode.isSuccess(rc)}');
        },
        (log) => _addLog('[ffmpeg] ${log.getMessage().trim()}'),
        (stats) => _addLog('📊 statistics: time=${stats.getTime()}ms size=${stats.getSize()}bytes'),
      ),
    );

    // ディスク上のファイルサイズを定期監視(「本当に途中から逐次書かれているか」の目視確認用)
    _sizeWatcher?.cancel();
    _sizeWatcher = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (await outFile.exists()) {
        final size = await outFile.length();
        _addLog('💾 out.m4a size=$size bytes (fed=${_fedSeconds}s分)');
      }
    });

    unawaited(_feedPipe(fixturePath, fifoPath));
  }

  Future<void> _feedPipe(String fixturePath, String fifoPath) async {
    _addLog('✍️ フィード開始(1つのIOSinkを開いたまま、${_tickMs}msごとに書き込み続ける)');
    final source = await File(fixturePath).open();
    // named pipeへのopenWrite()は、読み手(ffmpeg)が既にpipeをopenして
    // 待っていないとブロックする。上でexecuteAsyncを先に呼んでいるので
    // 通常は問題ないが、タイミング次第でここが一瞬待つのは正常。
    final sink = File(fifoPath).openWrite();
    try {
      while (!_cancelled) {
        final bytes = await source.read(_bytesPerTick);
        if (bytes.isEmpty) break;
        sink.add(bytes);
        await sink.flush();
        _fedSeconds += (_tickMs / 1000);
        await Future.delayed(const Duration(milliseconds: _tickMs));
      }
      if (_cancelled) {
        _addLog('⚠️ フィードは強制中断されました(cancelledフラグ) — グレースフルクローズはしません');
        return;
      }
      _addLog('✅ フィード完了(60秒分すべて書き込み終わり)。パイプを閉じます');
    } catch (e, st) {
      _addLog('🔴 フィード中にエラー: $e');
      debugPrint('$e\n$st');
    } finally {
      await source.close();
      if (!_cancelled) {
        await sink.close();
      }
      _sizeWatcher?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  /// 「本当にOSに殺された時」に一番近い状況を作る: Dartレベルのcleanup
  /// (finally節、sink.close()等)を一切経由せず、プロセスをその場で終了する。
  /// これによりout.m4aには、その瞬間までに-flush_packets 1で実際に
  /// ディスクへ書き出されていた分だけが残る。
  void _simulateCrashNow() {
    _addLog('💥 exit(0) を呼びます。アプリはここで即座に終了します。再度開いて「前回の結果を検証」を押してください。');
    Future.delayed(const Duration(milliseconds: 300), () => exit(0));
  }

  Future<void> _probeLastResult() async {
    final dir = await _testDir();
    final outputPath = '${dir.path}/live_out.m4a';
    final file = File(outputPath);
    if (!await file.exists()) {
      _addLog('🔴 $outputPath が存在しません');
      return;
    }
    final size = await file.length();
    _addLog('📄 ファイルサイズ: $size bytes');

    final session = await FFprobeKit.getMediaInformation(outputPath);
    final info = session.getMediaInformation();
    if (info == null) {
      _addLog('🔴 ffprobeが情報を取得できませんでした(壊れている可能性)');
      return;
    }
    _addLog('✅ ffprobe成功。duration=${info.getDuration()}秒 / format=${info.getFormat()}');
    setState(() => _outputPath = outputPath);
  }

  Future<void> _play() async {
    final path = _outputPath;
    if (path == null) return;
    final player = AudioPlayer();
    await player.play(DeviceFileSource(path));
    _addLog('▶️ 再生開始。継ぎ目(5秒毎の周波数切替ポイント)で音程が飛んだり繰り返されたりしないか耳で確認してください');
  }

  @override
  void dispose() {
    _cancelled = true;
    _sizeWatcher?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ステップ1: named pipe + FFmpegKit + fragmented MP4 の実機検証。'
            'RecordingController等には一切触れない独立したテストです。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: _running ? null : _generateFixture,
                child: const Text('1. テスト用PCM生成(60秒/周波数スイープ)'),
              ),
              ElevatedButton(
                onPressed: (_fixturePath == null || _running) ? null : _startPipeEncode,
                child: const Text('2. パイプ経由で継続エンコード開始'),
              ),
              ElevatedButton(
                onPressed: _running ? _simulateCrashNow : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('3. 今すぐ強制終了(exit)して疑似クラッシュ'),
              ),
              OutlinedButton(
                onPressed: _probeLastResult,
                child: const Text('4. 前回の結果を検証(ffprobe)'),
              ),
              OutlinedButton(
                onPressed: _outputPath == null ? null : _play,
                child: const Text('5. 再生して耳で継ぎ目を確認'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, i) => Text(
                  _log[i],
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
