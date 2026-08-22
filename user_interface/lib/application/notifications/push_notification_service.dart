import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lefture/app/router.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/repositories/push_notification_repository.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';

part 'push_notification_service.g.dart';

const _androidChannel = AndroidNotificationChannel(
  'job_completed',
  '分析完了通知',
  description: '講義の分析が完了した時の通知',
  importance: Importance.high,
);

/// アプリ起動中ずっとFCMのトークン登録・受信・タップ遷移を監視するサービス。
/// AppLifecycleSyncWatcherと同じく、MyApp.buildでref.watchされることで
/// 初めて生成・起動する(誰も参照しなければ何もリスナー登録されない)。
@Riverpod(keepAlive: true)
PushNotificationService pushNotificationService(Ref ref) {
  final service = PushNotificationService(ref);
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
}

class PushNotificationService {
  PushNotificationService(this._ref)
    : _repository = PushNotificationRepository(supabase);

  final Ref _ref;
  final PushNotificationRepository _repository;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  String? _lastKnownToken;

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> initialize() async {
    if (kIsWeb) return; // Web版は非対応(google-services設定なし)

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    // フォアグラウンド中もOSバナーで自然に見せたいので、
    // ここではlocal_notificationsで自前表示する(下のonMessage参照)。
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    _foregroundSub = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
    );
    _tokenRefreshSub = messaging.onTokenRefresh.listen(_registerToken);

    // アプリが通知タップで(バックグラウンド/終了状態から)起動された場合
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // ログイン/ログアウトに合わせてトークンの登録・解除を行う
    _authSub = supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        _fetchAndRegisterToken();
      } else if (state.event == AuthChangeEvent.signedOut) {
        _unregisterCurrentToken();
      }
    });

    if (supabase.auth.currentSession != null) {
      await _fetchAndRegisterToken();
    }
  }

  Future<void> _fetchAndRegisterToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      DevLog.add('⚠️ Failed to fetch FCM token: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    _lastKnownToken = token;
    if (supabase.auth.currentSession == null) return;
    try {
      await _repository.registerDevice(
        deviceToken: token,
        platform: _platform,
      );
    } catch (e) {
      DevLog.add('⚠️ Failed to register device token: $e');
    }
  }

  Future<void> _unregisterCurrentToken() async {
    final token = _lastKnownToken;
    if (token == null) return;
    try {
      await _repository.unregisterDevice(
        deviceToken: token,
        platform: _platform,
      );
    } catch (e) {
      DevLog.add('⚠️ Failed to unregister device token: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['lecture_id'] as String?,
    );
  }

  Future<void> _handleNotificationTap(RemoteMessage message) async {
    final lectureId = message.data['lecture_id'] as String?;
    if (lectureId == null) return;

    try {
      final row = await supabase
          .from('lectures')
          .select('course_id')
          .eq('id', lectureId)
          .maybeSingle();
      final courseId = row?['course_id'] as String?;
      if (courseId == null) return;

      _ref
          .read(routerProvider)
          .push('${AppRoutes.coursesRootPath}/c/$courseId/v/$lectureId');
    } catch (e) {
      DevLog.add('⚠️ Failed to navigate from notification tap: $e');
    }
  }

  void dispose() {
    _authSub?.cancel();
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}
