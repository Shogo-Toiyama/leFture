// lib/application/chat/chat_lifecycle_watcher.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_lifecycle_watcher.g.dart';

/// アプリが前面に戻ったとき、受信中だったチャットの返答をサーバーの内容で読み直す。
///
/// 裏に回っている間に受信の接続が切れても、iOSはエラーにせず止まったままになることがある。サーバー側の
/// 生成・保存・課金は最後まで走るので、戻ってきたとき([ChatConversation.onAppResumed])にDBから追いつく。
/// シートを閉じていても受信は続くので、シートの表示ではなくアプリ全体で見張る。
@Riverpod(keepAlive: true)
AppLifecycleListener chatLifecycleWatcher(Ref ref) {
  final listener = AppLifecycleListener(
    onResume: () =>
        unawaited(ref.read(chatConversationProvider.notifier).onAppResumed()),
  );
  ref.onDispose(listener.dispose);
  return listener;
}
