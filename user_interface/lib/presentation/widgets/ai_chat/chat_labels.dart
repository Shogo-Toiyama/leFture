// lib/presentation/widgets/ai_chat/chat_labels.dart
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// 生成中の段階の文言(webappのAssistantMessageのstageLabelと同じ分岐)。
/// 探しているものが複数なら、添付資料 → Web → 過去のチャット → 講義の順に1つだけ出す。
String chatStageLabel(AppLocalizations l, LocalChatMessage message) {
  final detail = message.searchDetail;
  final rawQuery = message.searchQuery?.trim();
  final query = rawQuery == null || rawQuery.isEmpty
      ? null
      : (rawQuery.length > 25 ? '${rawQuery.substring(0, 24)}…' : rawQuery);

  switch (message.stage) {
    case ChatStage.readingAttachments:
      return l.aiChatStageReadingAttachments;
    case ChatStage.indexingAttachments:
      return l.aiChatStageIndexingAttachments;
    case ChatStage.searching:
      if (detail.contains('organizing')) {
        return l.aiChatStageOrganizingMaterials;
      }
      if (message.searchTarget == 'attachments' ||
          detail.contains('attachments')) {
        return l.aiChatStageReadingAttachment;
      }
      if (message.searchTarget == 'web' || detail.contains('web')) {
        return query == null
            ? l.aiChatStageSearchingWeb
            : l.aiChatStageSearchingWebWithQuery(query);
      }
      if (message.searchTarget == 'chats' || detail.contains('chats')) {
        return query == null
            ? l.aiChatStageSearchingChats
            : l.aiChatStageSearchingChatsWithQuery(query);
      }
      if (message.searchLayer == 'transcript') {
        return query == null
            ? l.aiChatStageReadingTranscript
            : l.aiChatStageSearchingTranscriptWithQuery(query);
      }
      if (query != null) return l.aiChatStageSearchingNotesWithQuery(query);
      final handle = message.searchHandle;
      if (handle != null && handle.isNotEmpty) {
        return handle.contains('/s')
            ? l.aiChatStageReadingTranscript
            : l.aiChatStageReadingNotes;
      }
      return l.aiChatStageSearching;
    case ChatStage.reasoning:
      return l.aiChatStageReasoning;
    case ChatStage.writing:
      return l.aiChatStageWriting;
    case ChatStage.thinking:
    case null:
      return l.aiChatStageThinking;
  }
}

/// 経過秒数(5秒をすぎたら出す)。1分を超えたら「1分05秒」の形。
String chatElapsedLabel(AppLocalizations l, int seconds) {
  if (seconds < 60) return l.aiChatElapsedSeconds('$seconds');
  return l.aiChatElapsedMinutesSeconds(
    '${seconds ~/ 60}',
    (seconds % 60).toString().padLeft(2, '0'),
  );
}

/// 出典の種類の短い名前(出典のチップに出す)。
String chatSourceKindLabel(AppLocalizations l, String sourceType) =>
    switch (sourceType) {
      'course' => l.aiChatSourceCourse,
      'chat_turn' => l.aiChatSourceChat,
      'web' => l.aiChatSourceWeb,
      'chat_attachment' => l.aiChatSourceAttachment,
      'deep_note' => l.aiChatSourceDeepNote,
      'review_card' => l.aiChatSourceReviewCard,
      'keyword' => l.aiChatSourceKeyword,
      'announcement' => l.aiChatSourceAnnouncement,
      'transcript_topic' => l.aiChatSourceTranscript,
      'topic_summary' => l.aiChatSourceTopic,
      'fun_fact' => l.aiChatSourceFunFact,
      'lecture_summary' => l.aiChatSourceLectureSummary,
      'lecture_moment' => l.aiChatSourceMoment,
      _ => '',
    };

/// 出典ラベル "CS 161 / Lecture 7 / Deep Note: Heaps" から、チップに出す短い名前を作る。
/// 先頭のコース名は一覧で重複しがちなので、講義名以降を使う(webappのcitationShortLabelと同じ)。
String chatCitationShortLabel(ChatCitation c) {
  if (c.sourceType == 'web') {
    final domain = c.metadata['domain'];
    return domain is String && domain.isNotEmpty ? domain : c.label;
  }
  final parts = c.label.split(' / ').where((p) => p.isNotEmpty).toList();
  if (parts.length >= 3) {
    final detail = parts[2].trim();
    // チップの種別バッジですでに表示される "Transcript: " などのプレフィックスを取り除く
    final cleaned = detail.replaceFirst(
      RegExp(
        r'^(Transcript|Deep Note|Topic Summary|Review Cards?|Announcement):\s*',
        caseSensitive: false,
      ),
      '',
    );
    final range = c.metadata['sentence_range'];
    final suffix = range is String ? ' ($range)' : '';
    return '${cleaned.isEmpty ? detail : cleaned}$suffix';
  }
  if (parts.length == 2) return parts[1].trim();
  return parts.join(' · ');
}

/// 送る前に止められたときの文言と、次にとれる行動(webappのfailureCopyと同じ)。
class ChatFailureCopy {
  const ChatFailureCopy(
    this.text, {
    this.buyCredits = false,
    this.canRetry = true,
  });

  final String text;

  /// クレジットが足りない: 「クレジットを購入」への導線を出す。
  final bool buyCredits;

  /// 同じ内容で送り直せる(待っても直らない理由のときは出さない)。
  final bool canRetry;
}

ChatFailureCopy chatFailureCopy(
  AppLocalizations l,
  String code,
  Map<String, dynamic> detail,
) {
  switch (code) {
    case 'INSUFFICIENT_CREDITS':
      final min = detail['min_credits'];
      return ChatFailureCopy(
        l.aiChatErrorInsufficientCredits(min is num ? '$min' : '5'),
        buyCredits: true,
      );
    case 'CHAT_RATE_LIMITED':
      return ChatFailureCopy(l.aiChatErrorRateLimited);
    case 'CHAT_BLOCKED_COOLDOWN':
      return ChatFailureCopy(l.aiChatErrorBlockedCooldown, canRetry: false);
    case 'MESSAGE_TOO_LONG':
      return ChatFailureCopy(l.aiChatErrorTooLong('$chatMaxMessageChars'));
    case 'SELECTED_TEXT_TOO_LONG':
      return ChatFailureCopy(
        l.aiChatErrorSelectedTooLong('$chatMaxSelectedTextChars'),
      );
    case 'EMPTY_ATTACHMENT':
      return ChatFailureCopy(l.aiChatErrorEmptyAttachment);
    case 'ATTACHMENT_TOO_LONG':
      return ChatFailureCopy(
        l.aiChatErrorAttachmentTooLong('$chatMaxAttachmentChars'),
      );
    case 'TOO_MANY_ATTACHMENTS':
      return ChatFailureCopy(
        l.aiChatErrorTooManyAttachments('$chatMaxAttachmentsPerMessage'),
      );
    case 'THREAD_ATTACHMENT_LIMIT':
      return ChatFailureCopy(
        l.aiChatErrorThreadAttachmentLimit('$chatMaxAttachmentsPerThread'),
      );
    case 'ATTACHMENT_NOT_FOUND':
    case 'ATTACHMENT_NOT_READY':
      return ChatFailureCopy(l.aiChatErrorAttachmentNotReady);
    case 'TOO_MANY_MENTIONS':
      return ChatFailureCopy(
        l.aiChatErrorTooManyMentions('$chatMaxMentionsPerMessage'),
      );
    case 'THREAD_BUSY':
      return ChatFailureCopy(l.aiChatErrorThreadBusy);
    case 'THREAD_NOT_FOUND':
      return ChatFailureCopy(l.aiChatErrorThreadNotFound, canRetry: false);
    case 'ACCOUNT_SUSPENDED':
      return ChatFailureCopy(l.aiChatErrorSuspended, canRetry: false);
    case 'NETWORK':
      return ChatFailureCopy(l.aiChatErrorNetwork);
    default:
      return ChatFailureCopy(l.aiChatErrorGeneric);
  }
}

/// ファイルを準備できなかった理由の文言(webappの fileErrorCopy と同じ分け方)。
String chatFileErrorCopy(
  AppLocalizations l,
  String? code,
  Map<String, dynamic> detail,
) {
  String mb(Object? bytes) =>
      '${bytes is num ? (bytes / (1024 * 1024)).round() : 30}';
  String count(Object? n, int fallback) => '${n is num ? n.toInt() : fallback}';
  switch (code) {
    case 'UNSUPPORTED_FILE_TYPE':
      return l.aiChatFileErrorUnsupported;
    case 'FILE_TOO_LARGE':
      return l.aiChatFileErrorTooLarge(mb(detail['max_bytes']));
    case 'FILE_TOO_LARGE_MEDIA':
      return l.aiChatFileErrorTooLargeMedia(mb(detail['max_bytes']));
    case 'PDF_ENCRYPTED':
      return l.aiChatFileErrorEncrypted;
    case 'FILE_EMPTY':
      return l.aiChatFileErrorEmpty;
    case 'TOO_MANY_PAGES':
      return l.aiChatFileErrorTooManyPages(count(detail['max_pages'], 500));
    case 'TOO_MANY_IMAGES':
      return l.aiChatFileErrorTooManyImages(count(detail['max_images'], 60));
    case 'ATTACHMENT_TOO_LONG':
      return l.aiChatFileErrorTooLong(
        count(detail['max_chars'], chatMaxAttachmentChars),
      );
    case 'FILE_TOO_COMPLEX':
      return l.aiChatFileErrorTooComplex;
    case 'TOO_MANY_DRAFTS':
      return l.aiChatFileErrorTooManyDrafts;
    case 'IMAGE_DECODE_FAILED':
      return l.aiChatFileErrorDecode;
    case 'FILE_CORRUPT':
      return l.aiChatFileErrorCorrupt;
    case 'ACCOUNT_SUSPENDED':
      return l.aiChatErrorSuspended;
    case 'UPLOAD_FAILED':
      // 状態コード(0は通信の切断。それ以外はR2の返事)を出して、原因を追えるようにする
      final status = detail['status'];
      return l.aiChatFileErrorUpload(status is num ? '${status.toInt()}' : '-');
    default:
      return l.aiChatFileErrorGeneric;
  }
}
