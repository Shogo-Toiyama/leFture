import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:lefture/application/audio/diagnostic_audio_player.dart';
import 'package:lefture/application/errors/client_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final directory = await Directory.systemTemp.createTemp('audio_smoke');
  final player = DiagnosticAudioPlayer(
    ClientDiagnostics(),
    surface: DiagnosticSurface.transcript,
  );
  try {
    final file = await File('${directory.path}/silence.wav')
        .writeAsBytes(_wav());
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(DeviceFileSource(file.path));
    await _state(player, PlayerState.playing, player.resume);
    await _state(player, PlayerState.paused, player.pause);
    await player.seek(const Duration(milliseconds: 500));
    await _state(player, PlayerState.playing, player.resume);
    await _state(player, PlayerState.stopped, player.stop);
    await player.dispose();
    debugPrint('DIAGNOSTIC_AUDIO_SMOKE passed');
  } catch (error) {
    debugPrint('DIAGNOSTIC_AUDIO_SMOKE failed ${error.runtimeType}');
    rethrow;
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> _state(
  DiagnosticAudioPlayer player,
  PlayerState expected,
  Future<void> Function() command,
) async {
  final observed = player.onPlayerStateChanged
      .firstWhere((state) => state == expected)
      .timeout(const Duration(seconds: 5));
  await Future.wait([command(), observed]);
}

Uint8List _wav() {
  const sampleRate = 16000;
  const dataLength = sampleRate * 2 * 4;
  final wav = ByteData(44 + dataLength)
    ..setUint32(0, 0x52494646)
    ..setUint32(4, dataLength + 36, Endian.little)
    ..setUint32(8, 0x57415645)
    ..setUint32(12, 0x666d7420)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461)
    ..setUint32(40, dataLength, Endian.little);
  return wav.buffer.asUint8List();
}
