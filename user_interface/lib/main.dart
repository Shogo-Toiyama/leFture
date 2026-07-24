import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';

const supabaseUrl = 'https://lvbpuywjxmmeecftinkb.supabase.co';
const supabaseAnonKey = 'sb_publishable_LUfg9T2f-zvargd7GgR7Cw_KAl86N8c';

void _logUncaughtError(Object error, StackTrace stack) {
  DevLog.add('🔴 [UNCAUGHT ERROR] $error\n$stack');
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Flutterフレームワーク内のエラー(widget build中の例外など)を確実にログへ出す。
    // これが無いと、非同期コールバック内の例外が画面に何も表示されないまま
    // 握りつぶされることがある。
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _logUncaughtError(details.exception, details.stack ?? StackTrace.current);
    };
    // Flutterフレームワーク外(プラットフォームチャンネル・Isolateなど)のエラー。
    PlatformDispatcher.instance.onError = (error, stack) {
      _logUncaughtError(error, stack);
      return true;
    };

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    // 設定の永続化を初期化
    await RecordingPreferences().init();

    runApp(
      ProviderScope(
        child: MyApp(),
      ),
    );
  }, _logUncaughtError);
}