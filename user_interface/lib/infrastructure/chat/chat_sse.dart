// lib/infrastructure/chat/chat_sse.dart
import 'dart:convert';

import 'package:lefture/domain/entities/chat.dart';

/// POST /chat/messages の返事(text/event-stream)を、ChatStreamEventに変換する。
///
/// EventSourceのようにPOSTとAuthorizationヘッダを扱える標準の受け口が無いので、
/// バイト列を自前で区切る(webappのsendChatMessageと同じ考え方)。イベントは空行で区切られた
/// "event: xxx\ndata: {...}" の塊。知らないイベント・読めないJSONは読み飛ばす。
/// utf8.decoderを通すので、日本語の1文字が通信の区切りで2つに割れても正しく読める。
Stream<ChatStreamEvent> parseChatSse(Stream<List<int>> bytes) async* {
  var pending = '';
  await for (final chunk in bytes.transform(utf8.decoder)) {
    pending += chunk;
    var separator = pending.indexOf('\n\n');
    while (separator != -1) {
      final event = parseChatSseBlock(pending.substring(0, separator));
      pending = pending.substring(separator + 2);
      if (event != null) yield event;
      separator = pending.indexOf('\n\n');
    }
  }
  final tail = parseChatSseBlock(pending);
  if (tail != null) yield tail;
}

/// "event: xxx\ndata: {...}" 1件を変換する。読めなければnull。
ChatStreamEvent? parseChatSseBlock(String raw) {
  var name = '';
  final dataLines = <String>[];
  for (var line in raw.split('\n')) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.startsWith('event:')) {
      name = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
  }
  if (name.isEmpty || dataLines.isEmpty) return null;
  try {
    final data = jsonDecode(dataLines.join('\n'));
    if (data is! Map) return null;
    return ChatStreamEvent.fromSse(name, Map<String, dynamic>.from(data));
  } catch (_) {
    return null;
  }
}
