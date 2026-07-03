import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:lecture_companion_ui/core/utils/dev_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    final prefs = await SharedPreferences.getInstance();

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    runApp(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: MyApp(),
      ),
    );
  }, _logUncaughtError);
}