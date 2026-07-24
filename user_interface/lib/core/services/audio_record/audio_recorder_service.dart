import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:record/record.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:lefture/core/utils/dev_log.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _disposed = false;

  // 初期化済みかどうかのフラグ
  bool _isBackgroundInitialized = false;

  // マスター生PCMファイル用の永続IOSink。マイクからのデータは高頻度で届くため、
  // 呼ばれるたびに`File.writeAsBytes(mode: append, flush: true)`で開閉すると、
  // 前回の書き込み(especially fsync)が終わる前に次の呼び出しが重なり、
  // 誰にもawaitされない例外としてチャンクが静かに欠落する(録音が「早送り」に
  // なっていく不具合の原因だった)。IOSinkは内部で書き込みをキューイング・
  // 直列化するため、これを1つだけ開いて使い続けることで欠落を防ぐ。
  IOSink? _masterSink;
  String? _masterSinkLectureId;

  Future<void> _initBackgroundService() async {
    if (_isBackgroundInitialized) return;

    // Android向けの通知設定
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: 'leFture Recording',
      notificationText: 'Recording in progress...',
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'), // アイコン
    );

    DevLog.add('[AudioRecorderService] calling FlutterBackground.initialize()...');
    // 権限と設定を初期化
    _isBackgroundInitialized = await FlutterBackground.initialize(
      androidConfig: androidConfig,
    );
    DevLog.add('[AudioRecorderService] FlutterBackground.initialize() returned: $_isBackgroundInitialized');
  }

  Future<void> start({required String outputPath}) async {
    if (_disposed) {
      throw StateError('AudioRecorderService is disposed.');
    }

    // ★録音開始前にバックグラウンド実行を有効化
    if (Platform.isAndroid) {
      await _initBackgroundService();
      // 通知を出してサービス開始
      if (_isBackgroundInitialized) {
        await FlutterBackground.enableBackgroundExecution();
      }
    }

    final f = File(outputPath);
    await f.parent.create(recursive: true);

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 48000,
      sampleRate: 24000,
      numChannels: 1,
    );

    await _recorder.start(config, path: outputPath);
  }

  Future<Stream<Uint8List>> startStream() async {
    if (_disposed) {
      throw StateError('AudioRecorderService is disposed.');
    }

    // バックグラウンド実行を有効化 (Android)
    if (Platform.isAndroid) {
      await _initBackgroundService();
      if (_isBackgroundInitialized) {
        DevLog.add('[AudioRecorderService] calling FlutterBackground.enableBackgroundExecution()...');
        await FlutterBackground.enableBackgroundExecution();
        DevLog.add('[AudioRecorderService] enableBackgroundExecution() returned');
      }
    }

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits, // 圧縮しない生データ（振幅計算に必須）
      sampleRate: 16000,               // 16kHz (Whisperの推奨サンプリングレート)
      numChannels: 1,                  // モノラル (データ量を半分にするため)
    );
    DevLog.add('[AudioRecorderService] calling _recorder.startStream(config)...');
    final stream = await _recorder.startStream(config);
    DevLog.add('[AudioRecorderService] _recorder.startStream(config) returned a stream');
    return stream;
  }

  Future<void> pause() async {
    if (_disposed) return;
    if (await _recorder.isRecording()) {
      await _recorder.pause();
    }
  }

  Future<void> resume() async {
    if (_disposed) return;
    if (await _recorder.isPaused()) {
      await _recorder.resume();
    }
  }

  Future<String?> stop() async {
    if (_disposed) return null;

    final recording = await _recorder.isRecording();
    final paused = await _recorder.isPaused();

    // ★録音停止したら、バックグラウンド実行もオフにする（通知を消す）
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }

    // マスター音声への書き込みも確実に終わらせる(encodeMasterRawToM4aが
    // rawファイルを読む前に、バッファ済みの内容を全てディスクへ反映させる)。
    await _closeMasterSink();

    if (!recording && !paused) return null;
    return _recorder.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // 念のためdispose時にもオフに
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }

    await _closeMasterSink();
    await _recorder.dispose();
  }

  /// 開いているマスター音声用IOSinkがあれば、バッファを書き出してから閉じる。
  /// すでに閉じている(null)場合は何もしない — 複数箇所(stop/dispose/
  /// encodeMasterRawToM4a/cleanUpMasterAudioFiles)から安全に呼べる。
  Future<void> _closeMasterSink() async {
    final sink = _masterSink;
    if (sink == null) return;
    _masterSink = null;
    _masterSinkLectureId = null;
    await sink.flush();
    await sink.close();
  }

  /// チャンクの生PCMデータをFFmpegでAAC(M4A)にエンコードしてローカルに保存する
  Future<String> savePcmAsM4a(Uint8List pcmData, String lectureId) async {
    final int sampleRate = 16000;
    final int channels = 1;

    final Directory dir = await getApplicationDocumentsDirectory();
    final String chunkDir = '${dir.path}/lectures/$lectureId/audio_chunks';
    await Directory(chunkDir).create(recursive: true);

    // ファイル名が被らないようにUUIDを使う
    final String uuid = const Uuid().v4();
    final String rawPath = '$chunkDir/$uuid.raw';
    final String m4aPath = '$chunkDir/$uuid.m4a';

    final File rawFile = File(rawPath);
    await rawFile.writeAsBytes(pcmData);

    final command = '-y -f s16le -ar $sampleRate -ac $channels -i "$rawPath" -c:a aac -b:a 64k "$m4aPath"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    // 一時rawファイルは成功・失敗にかかわらず不要なので削除
    try {
      if (await rawFile.exists()) await rawFile.delete();
    } catch (e) {
      debugPrint('⚠️ Failed to delete raw chunk file: $e');
    }

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogs();
      final errorMsg = logs.map((l) => l.getMessage()).join('\n');
      throw Exception('FFmpeg chunk audio encoding failed. ReturnCode: $returnCode.\nLogs:\n$errorMsg');
    }

    return m4aPath; // 保存したファイルのパスを返す
  }

  /// 指定されたレクチャーIDの一時PCMファイルパスを返す
  Future<String> _getMasterRawPath(String lectureId) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/lectures/$lectureId/master_audio.raw';
  }

  /// 指定されたレクチャーIDの圧縮M4Aファイルパスを返す
  Future<String> _getMasterM4aPath(String lectureId) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/lectures/$lectureId/master_audio.m4a';
  }

  /// 録音中の生PCMデータをローカルファイルに追記する。
  /// マイクからのコールバック頻度で呼ばれ続けるため、呼び出しごとにファイルを
  /// 開閉するのではなく、同じlectureIdの間は1つの`IOSink`を使い続けて直列に
  /// 書き込む(呼び出しが重なってもIOSink内部のキューが順序と欠落無しを保証する)。
  Future<void> appendMasterRawData(Uint8List pcmData, String lectureId) async {
    if (_masterSink == null || _masterSinkLectureId != lectureId) {
      // 別のlectureId用のsinkが開いたままだった場合に備えて、念のため閉じる。
      await _closeMasterSink();

      final String rawPath = await _getMasterRawPath(lectureId);
      final File file = File(rawPath);
      await file.parent.create(recursive: true);
      _masterSink = file.openWrite(mode: FileMode.append);
      _masterSinkLectureId = lectureId;
    }

    _masterSink!.add(pcmData);
  }

  /// ローカルに貯めたPCM生データをFFmpegでM4A(AAC)にエンコードする
  Future<String> encodeMasterRawToM4a(String lectureId) async {
    // 通常はstop()側で既に閉じられているはずだが、rawファイルを読む前に
    // バッファ済みの内容が確実にディスクへ反映されていることを保証するため、
    // 念のためここでも閉じる(既に閉じていれば何もしない)。
    await _closeMasterSink();

    final String rawPath = await _getMasterRawPath(lectureId);
    final String m4aPath = await _getMasterM4aPath(lectureId);

    final rawFile = File(rawPath);
    if (!await rawFile.exists()) {
      throw StateError('Master raw audio file does not exist at $rawPath');
    }

    // すでに出力ファイルが存在する場合は削除しておく
    final m4aFile = File(m4aPath);
    if (await m4aFile.exists()) {
      await m4aFile.delete();
    }

    // 16kHz, 16-bit signed little-endian, mono raw pcm を aac 64kbps にエンコードするコマンド
    final command = '-y -f s16le -ar 16000 -ac 1 -i "$rawPath" -c:a aac -b:a 64k "$m4aPath"';
    
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      // 成功したら元の巨大なrawファイルは削除する
      try {
        await rawFile.delete();
      } catch (e) {
        // 削除失敗は致命的ではないのでログ出力のみ
        debugPrint('⚠️ Failed to delete raw master file: $e');
      }
      return m4aPath;
    } else {
      final failStackTrace = await session.getFailStackTrace();
      final logs = await session.getLogs();
      final errorMsg = logs.map((l) => l.getMessage()).join('\n');
      throw Exception('FFmpeg master audio encoding failed. ReturnCode: $returnCode.\nLogs:\n$errorMsg\nStackTrace: $failStackTrace');
    }
  }

  /// 一時ファイル (raw, m4a) をクリーンアップする
  Future<void> cleanUpMasterAudioFiles(String lectureId) async {
    // 開いたままのIOSinkがファイルハンドルを握っていると削除に失敗しうるため、
    // 削除前に必ず閉じる。
    await _closeMasterSink();

    try {
      final String rawPath = await _getMasterRawPath(lectureId);
      final rawFile = File(rawPath);
      if (await rawFile.exists()) {
        await rawFile.delete();
      }

      final String m4aPath = await _getMasterM4aPath(lectureId);
      final m4aFile = File(m4aPath);
      if (await m4aFile.exists()) {
        await m4aFile.delete();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to clean up master audio files for lecture $lectureId: $e');
    }
  }
}