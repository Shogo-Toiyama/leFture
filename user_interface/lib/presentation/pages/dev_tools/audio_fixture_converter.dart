// presentation/pages/dev_tools/audio_fixture_converter.dart
//
// 「ファイルを選ぶ→本番のマイクストリームと同じフォーマット(PCM16/16kHz/mono
// のヘッダなしraw)に変換する」処理を、Testタブのウィジェット状態から切り離した
// 純粋な関数として実装する。
//
// 将来「別端末で録音した音声を後からアップロードする」という本番機能に
// 発展させる場合、このファイルをdev_tools/の外へ昇格させるだけで再利用できる
// ようにするための意図的な分離。

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 任意の音声ファイルをユーザーに選ばせる。拡張子を限定すると手元の録音
/// アプリのエクスポート形式(m4a/mp3/wav/caf等)を取りこぼすため、FileType.any
/// を使う。
Future<String?> pickAudioFile() async {
  final result = await FilePicker.pickFiles(type: FileType.any);
  return result?.files.single.path;
}

/// 選択された音声ファイルを、本番のマイクストリームと同じ形式
/// (s16le, 16000Hz, mono, ヘッダなしraw)に変換し、変換後ファイルの
/// 絶対パスを返す。`audio_recorder_service.dart`の`encodeMasterRawToM4a`と
/// 同じFFmpegKit.execute(...)パターンを踏襲する。
Future<String> convertToFixturePcm(String sourcePath) async {
  final tempDir = await getTemporaryDirectory();
  final baseName = p.basenameWithoutExtension(sourcePath);
  final outputPath = '${tempDir.path}/dev_tools_fixture_$baseName.pcm';

  final command = '-y -i "$sourcePath" -f s16le -ar 16000 -ac 1 "$outputPath"';
  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();

  if (!ReturnCode.isSuccess(returnCode)) {
    final logs = await session.getLogs();
    final errorMsg = logs.map((l) => l.getMessage()).join('\n');
    throw Exception('Fixture conversion failed. ReturnCode: $returnCode.\nLogs:\n$errorMsg');
  }

  return outputPath;
}
