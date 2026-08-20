import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';

const supabaseUrl = 'https://lvbpuywjxmmeecftinkb.supabase.co';
const supabaseAnonKey = 'sb_publishable_LUfg9T2f-zvargd7GgR7Cw_KAl86N8c';

// Google Cloud Console で作成した2種類のOAuthクライアントID。
// - googleIosClientId: iOSアプリ用クライアント(ネイティブSDKがこのIDで認証する)
// - googleWebServerClientId: Web用クライアント(SupabaseのGoogleプロバイダー設定と
//   同じものを使う。signInWithIdTokenのトークン検証はこちらのIDを対象に行われる)
const googleIosClientId =
    '511705914929-omh4h6phcvvldef0ssc6jb6o1ep8ijke.apps.googleusercontent.com';
const googleWebServerClientId =
    '511705914929-t0vvqbco2e60rh8gjhpb3qusbvbbrp2o.apps.googleusercontent.com';

void _logUncaughtError(Object error, StackTrace stack) {
  DevLog.add('🔴 [UNCAUGHT ERROR] $error\n$stack');
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 画面の向きを縦向き（Portrait）に固定
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

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

    // GoogleSignIn.instance はこの初期化が完了するまで他のメソッドを
    // 呼んではいけない(公式ドキュメントの制約)ため、起動時に一度だけ実行する。
    await GoogleSignIn.instance.initialize(
      clientId: googleIosClientId,
      serverClientId: googleWebServerClientId,
      nonce: googleSignInHashedNonce,
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