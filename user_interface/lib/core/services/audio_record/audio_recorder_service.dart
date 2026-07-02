import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:record/record.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _disposed = false;
  
  // 初期化済みかどうかのフラグ
  bool _isBackgroundInitialized = false;

  Future<void> _initBackgroundService() async {
    if (_isBackgroundInitialized) return;

    // Android向けの通知設定
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: 'leFture Recording',
      notificationText: 'Recording in progress...',
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'), // アイコン
    );

    // 権限と設定を初期化
    _isBackgroundInitialized = await FlutterBackground.initialize(
      androidConfig: androidConfig,
    );
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
        await FlutterBackground.enableBackgroundExecution();
      }
    }

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits, // 圧縮しない生データ（振幅計算に必須）
      sampleRate: 16000,               // 16kHz (Whisperの推奨サンプリングレート)
      numChannels: 1,                  // モノラル (データ量を半分にするため)
    );
    // print("Audio Stream呼び出します！");
    return await _recorder.startStream(config);
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
    
    await _recorder.dispose();
  }

  Future<String> savePcmAsWav(Uint8List pcmData, String lectureId) async {
    // 1. WAVヘッダー（44バイト）を作成する
    final int sampleRate = 16000;
    final int channels = 1;
    final int byteRate = sampleRate * channels * 2; // 16-bit = 2 bytes
    final int dataSize = pcmData.length;
    final int fileSize = 36 + dataSize;

    final ByteData header = ByteData(44);
    
    // "RIFF" (リトルエンディアンで書き込み)
    header.setUint8(0, 82); header.setUint8(1, 73); header.setUint8(2, 70); header.setUint8(3, 70);
    header.setUint32(4, fileSize, Endian.little);
    // "WAVE"
    header.setUint8(8, 87); header.setUint8(9, 65); header.setUint8(10, 86); header.setUint8(11, 69);
    // "fmt "
    header.setUint8(12, 102); header.setUint8(13, 109); header.setUint8(14, 116); header.setUint8(15, 32);
    header.setUint32(16, 16, Endian.little); // Subchunk1Size
    header.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    header.setUint16(22, channels, Endian.little); // NumChannels
    header.setUint32(24, sampleRate, Endian.little); // SampleRate
    header.setUint32(28, byteRate, Endian.little); // ByteRate
    header.setUint16(32, channels * 2, Endian.little); // BlockAlign
    header.setUint16(34, 16, Endian.little); // BitsPerSample
    // "data"
    header.setUint8(36, 100); header.setUint8(37, 97); header.setUint8(38, 116); header.setUint8(39, 97);
    header.setUint32(40, dataSize, Endian.little);

    // 2. ヘッダーとPCMデータを結合
    final BytesBuilder wavBuilder = BytesBuilder();
    wavBuilder.add(header.buffer.asUint8List());
    wavBuilder.add(pcmData);
    final Uint8List finalWavData = wavBuilder.toBytes();

    // 3. ローカルディレクトリに保存
    final Directory dir = await getApplicationDocumentsDirectory();
    // ファイル名が被らないようにUUIDを使う
    final String chunkFileName = '${const Uuid().v4()}.wav';
    // leFture用のディレクトリ構成に合わせて保存パスを作成
    final String filePath = '${dir.path}/lectures/$lectureId/audio_chunks/$chunkFileName';

    final File wavFile = File(filePath);
    await wavFile.parent.create(recursive: true); // フォルダがなければ作る
    await wavFile.writeAsBytes(finalWavData);

    return filePath; // 保存したファイルのパスを返す
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

  /// 録音中の生PCMデータをローカルファイルに追記する
  Future<void> appendMasterRawData(Uint8List pcmData, String lectureId) async {
    final String rawPath = await _getMasterRawPath(lectureId);
    final File file = File(rawPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pcmData, mode: FileMode.append, flush: true);
  }

  /// ローカルに貯めたPCM生データをFFmpegでM4A(AAC)にエンコードする
  Future<String> encodeMasterRawToM4a(String lectureId) async {
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
        print('⚠️ Failed to delete raw master file: $e');
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
      print('⚠️ Failed to clean up master audio files for lecture $lectureId: $e');
    }
  }
}