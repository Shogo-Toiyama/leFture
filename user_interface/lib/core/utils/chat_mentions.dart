// lib/core/utils/chat_mentions.dart
import 'package:lefture/domain/entities/chat.dart';

/// 本文の中の資料の印(⟦att:id⟧)の処理。webappの webapp/src/lib/chatMentions.ts の表示側だけを移したもの
/// (入力欄で「@名前」を入れる側は、入力欄を作るときに足す)。
///
/// 保存された本文には、資料を指す場所に印 `⟦att:id⟧` が入っている。画面では、その場所に資料のチップを出す。
sealed class ChatMessagePart {
  const ChatMessagePart();
}

class ChatTextPart extends ChatMessagePart {
  const ChatTextPart(this.text);
  final String text;
}

class ChatMentionPart extends ChatMessagePart {
  const ChatMentionPart(this.attachmentId);
  final String attachmentId;
}

/// 本文を、ふつうの文字と資料の印に分ける。
List<ChatMessagePart> splitMessageText(String content) {
  final parts = <ChatMessagePart>[];
  var last = 0;
  for (final m in chatMentionPattern.allMatches(content)) {
    if (m.start > last) {
      parts.add(ChatTextPart(content.substring(last, m.start)));
    }
    parts.add(ChatMentionPart(m.group(1)!));
    last = m.end;
  }
  if (last < content.length) parts.add(ChatTextPart(content.substring(last)));
  return parts;
}

/// 本文の中で指している資料のid(重複なし、出てくる順)。
List<String> messageMentionIds(String content) => {
  for (final p in splitMessageText(content))
    if (p is ChatMentionPart) p.attachmentId,
}.toList();
