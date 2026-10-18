// lib/application/chat/chat_attachment_files.dart
import 'dart:async';

import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_attachment_files.g.dart';

/// 送った資料の元のファイルを開く署名付きURL(画像の見本・PDFの表示・元のファイルを開く)。
///
/// 署名付きURLは10分で切れるので、9分だけ使い回す(webappの useAttachmentImageUrl と同じ)。
/// 同じ資料を同時に頼んでも、問い合わせは1回。失敗は覚えず、次に頼んだときにやり直す。
@riverpod
Future<ChatFileLink> chatAttachmentFileLink(Ref ref, String attachmentId) async {
  final keep = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 9), keep.close);
  ref.onDispose(timer.cancel);
  try {
    return await ref
        .watch(chatRepositoryProvider)
        .getAttachmentFileLink(attachmentId);
  } catch (_) {
    keep.close();
    rethrow;
  }
}
