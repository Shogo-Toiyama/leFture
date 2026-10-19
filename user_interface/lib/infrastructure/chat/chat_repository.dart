// lib/infrastructure/chat/chat_repository.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:lefture/core/config/app_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/auth/authed_http.dart';
import 'package:lefture/infrastructure/chat/chat_sse.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

part 'chat_repository.g.dart';

@Riverpod(keepAlive: true)
ChatRepository chatRepository(Ref ref) => ChatRepository(supabase);

/// 横断チャットボットのデータアクセス(webappの webapp/src/lib/chat.ts と同じ役割)。
///
/// - 読み取り(スレッド・メッセージ・資料)はSupabaseをRLS越しに直接読む(本人の行だけSELECTできる)。
/// - 書き込み(送信・停止・編集・名前変更・削除・資料の操作)は必ずバックエンド経由。ユーザーが
///   assistantの発言を偽造できないよう、テーブルにクライアント用の書き込みポリシーは無い。
/// - 端末のキャッシュ(drift)はこのクラスでは扱わない(ChatCacheDriftとChatSync)。
class ChatRepository {
  ChatRepository(this._supabase) : _http = AuthedHttpClient(_supabase);

  final SupabaseClient _supabase;
  final AuthedHttpClient _http;

  static const _baseUrl = AppConfig.backendBaseUrl;

  /// 送信の事前チェック(残高・送信頻度・資料の確認)が終わって返事のヘッダが届くまでの上限。
  static const _sendHeadersTimeout = Duration(seconds: 60);

  /// ファイルの中身の取り出し(LLMなし)。100MBのPDFでも1分程度なので余裕を持たせる。
  static const _extractTimeout = Duration(minutes: 3);

  /// 停止は、生成しているインスタンスが止めたところで締めるのを待ってから返る(ふつう1秒ほど)。
  static const _stopTimeout = Duration(seconds: 30);

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  /// ログイン中のユーザーのid(ログアウト中はnull)。端末のキャッシュを本人の行だけに絞るために使う。
  String? get currentUserId => _supabase.auth.currentUser?.id;

  // -------------------------------------------------------------------------
  // 読み取り(Supabase直)。キャッシュに行のまま保存できるよう、生の行も返せるようにしてある
  // -------------------------------------------------------------------------

  /// スレッド一覧(新しい順)の生の行。
  Future<List<Map<String, dynamic>>> fetchThreadRows({int limit = 50}) async {
    final rows = await _supabase
        .from('chat_threads')
        .select(ChatThread.columns)
        .isFilter('deleted_at', null)
        .order('last_message_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<ChatThread?> getThread(String threadId) async {
    final row = await _supabase
        .from('chat_threads')
        .select(ChatThread.columns)
        .eq('id', threadId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    return row == null ? null : ChatThread.fromMap(row);
  }

  /// スレッドのメッセージ(古い順)の生の行。
  Future<List<Map<String, dynamic>>> fetchMessageRows(String threadId) async {
    final rows = await _supabase
        .from('chat_messages')
        .select(ChatMessage.columns)
        .eq('thread_id', threadId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  /// 1件だけ読み直す(通信が切れたあと、サーバー側で生成が終わったかを見るため)。
  Future<ChatMessage?> getMessage(String messageId) async {
    final row = await _supabase
        .from('chat_messages')
        .select(ChatMessage.columns)
        .eq('id', messageId)
        .maybeSingle();
    return row == null ? null : ChatMessage.fromMap(row);
  }

  /// スレッドの資料(外したものを除く、添付順)。断った・失敗した資料も返す
  /// (送ったメッセージの横に「使えなかった」と出すため)。一覧に出すのは呼び出し側でreadyに絞る。
  Future<List<ChatAttachment>> listAttachments(String threadId) async {
    final rows = await _supabase
        .from('chat_attachments')
        .select(ChatAttachment.columns)
        .eq('thread_id', threadId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);
    return [
      for (final r in rows)
        ChatAttachment.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  // -------------------------------------------------------------------------
  // 書き込み(バックエンド経由)
  // -------------------------------------------------------------------------

  Future<void> renameThread(String threadId, String title) async {
    _ensureOk(
      await _http.patch(
        _uri('/chat/threads/$threadId'),
        payload: {'title': title},
      ),
    );
  }

  /// スレッドの削除(論理削除=ゴミ箱行き。中のメッセージも一緒に消える)。
  Future<void> deleteThread(String threadId) async {
    _ensureOk(await _http.delete(_uri('/chat/threads/$threadId')));
  }

  /// ゴミ箱のスレッド(削除が新しい順)の生の行。ゴミ箱の画面用で、端末のキャッシュには入れない。
  Future<List<Map<String, dynamic>>> fetchTrashedThreadRows() async {
    final rows = await _supabase
        .from('chat_threads')
        .select('id, title, last_message_at, deleted_at')
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  /// ゴミ箱のスレッドを復元する(スレッドと一緒に消えたメッセージ・資料が戻る)。
  Future<void> restoreThread(String threadId) async {
    _ensureOk(await _http.post(_uri('/chat/threads/$threadId/restore')));
  }

  /// ゴミ箱のスレッドを完全に削除する。404(既に消えている)は削除済みとして扱う。
  Future<void> hardDeleteThread(String threadId) async {
    final response = await _http.post(_uri('/chat/threads/$threadId/hard-delete'));
    if (response.statusCode == 404) return;
    _ensureOk(response);
  }

  /// 生成中の返答を止める。サーバーが止めたところまでで確定した行を返す
  /// (押したのと同時に完了していれば、その行)。
  Future<ChatMessage> stopMessage(String assistantMessageId) async {
    final response = await _http.post(
      _uri('/chat/messages/$assistantMessageId/stop'),
      timeout: _stopTimeout,
    );
    final body = _ensureOk(response) as Map<String, dynamic>;
    return ChatMessage.fromMap(
      Map<String, dynamic>.from(body['message'] as Map),
    );
  }

  /// 資料を全文で読ませる / やめる。上限を超える選択は ATTACHMENT_SELECTION_LIMIT /
  /// ATTACHMENT_TOO_LONG_TO_SELECT で断られる(ChatRequestException)。
  Future<void> setAttachmentSelected(String attachmentId, bool selected) async {
    _ensureOk(
      await _http.patch(
        _uri('/chat/attachments/$attachmentId'),
        payload: {'selected': selected},
      ),
    );
  }

  /// 資料を外す(以降のターンでAIに渡らなくなる)。送る前のファイル(draft)は消える。
  Future<void> removeAttachment(String attachmentId) async {
    _ensureOk(await _http.delete(_uri('/chat/attachments/$attachmentId')));
  }

  /// 添付したファイルを開くための短い署名付きURL(本人のみ)。
  Future<ChatFileLink> getAttachmentFileLink(String attachmentId) async {
    final body = _ensureOk(
      await _http.get(_uri('/chat/attachments/$attachmentId/file')),
    );
    return ChatFileLink.fromMap(Map<String, dynamic>.from(body as Map));
  }

  /// ファイルを添付する前に、アップロード先を頼む(draftの行ができる)。
  /// [fileSize]は端末で縮めた後の大きさ。
  Future<ChatUploadTarget> requestUpload({
    required String fileName,
    required int fileSize,
  }) async {
    final body = _ensureOk(
      await _http.post(
        _uri('/chat/attachments/uploads'),
        payload: {'file_name': fileName, 'file_size': fileSize},
      ),
    );
    return ChatUploadTarget.fromMap(Map<String, dynamic>.from(body as Map));
  }

  /// アップロードしたファイルの中身を取り出す(LLMなし)。文字数・ページ数などを先に知るため。
  Future<ChatFileInfo> extractAttachment(String attachmentId) async {
    final body = _ensureOk(
      await _http.post(
        _uri('/chat/attachments/$attachmentId/extract'),
        timeout: _extractTimeout,
      ),
    );
    return ChatFileInfo.fromMap(Map<String, dynamic>.from(body as Map));
  }

  /// AIの回答への報告を、お問い合わせ(/support/submit)と同じ形で送る(受付コード・確認メール・
  /// 管理者への通知もお問い合わせと同じ)。どのメッセージについてかは[report]に入れる。
  /// 戻り値は受付コード。
  Future<String> submitSupportReport({
    required String category,
    required String message,
    Map<String, dynamic>? report,
  }) async {
    final info = await PackageInfo.fromPlatform();
    final response = await _http.post(
      _uri('/support/submit'),
      payload: {
        'category': category,
        'message': message,
        'attachment_urls': const <String>[],
        'device_info': {
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'app_version': '${info.version} (${info.buildNumber})',
          'locale': Platform.localeName,
          if (report != null) 'report': report,
        },
      },
      timeout: const Duration(seconds: 30),
    );
    final body = _ensureOk(response) as Map<String, dynamic>;
    return body['ticket_code'] as String;
  }

  // -------------------------------------------------------------------------
  // 送信(SSE)
  // -------------------------------------------------------------------------

  /// POST /chat/messages を送り、届いたイベントを順に流す。
  ///
  /// - 送信前の事前チェックで弾かれたら(残高不足・送信頻度など)、ストリームはイベントを出さずに
  ///   ChatRequestException(code付き)で終わる。会話は元のまま。
  /// - 途中で通信が切れたらChatRequestException('NETWORK')。返答の生成・保存・課金はサーバー側で
  ///   最後まで走り切るので、呼び出し側はDBから該当メッセージを読み直せばよい。
  /// - 受信をやめたい(画面を閉じた等)ときはsubscriptionをcancelする。接続が閉じるだけで、
  ///   生成そのものは止まらない(止めるのはstopMessage)。
  Stream<ChatStreamEvent> sendMessage(ChatSendRequest request) async* {
    final client = http.Client();
    try {
      final http.StreamedResponse response;
      try {
        response = await _http.postStream(
          _uri('/chat/messages'),
          client: client,
          payload: await request.toJson(),
          timeout: _sendHeadersTimeout,
        );
      } on SessionExpiredException {
        rethrow;
      } catch (_) {
        throw const ChatRequestException('NETWORK', 'Network error');
      }

      if (response.statusCode != 200) {
        throw _requestError(
          response.statusCode,
          await response.stream.bytesToString(),
        );
      }

      try {
        yield* parseChatSse(response.stream);
      } catch (_) {
        throw const ChatRequestException(
          'NETWORK',
          'Connection lost while receiving the reply',
          status: 200,
        );
      }
    } finally {
      client.close();
    }
  }

  // -------------------------------------------------------------------------
  // エラー
  // -------------------------------------------------------------------------

  /// 2xxでなければChatRequestExceptionを投げる。2xxならJSONの本文を返す(空ならnull)。
  Object? _ensureOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _requestError(response.statusCode, response.body);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// バックエンドのエラー {"detail": {"error_code": ..., "message": ..., ...}} を読む。
  /// 読めなければ `HTTP_ステータス番号` にする。
  ChatRequestException _requestError(int status, String body) {
    Map<String, dynamic> detail = const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is Map) {
        detail = Map<String, dynamic>.from(decoded['detail'] as Map);
      }
    } catch (_) {}
    final code = detail['error_code'] as String? ?? 'HTTP_$status';
    final message =
        detail['message'] as String? ?? 'Request failed with status $status';
    return ChatRequestException(code, message, status: status, detail: detail);
  }
}

/// 1回の送信の中身(バックエンドのChatMessageRequest)。
class ChatSendRequest {
  ChatSendRequest({
    this.threadId,
    String? clientMessageId,
    required this.content,
    this.context = const ChatMessageContext(),
    this.newAttachments = const [],
    this.references = const [],
    this.replaceFromMessageId,
  }) : clientMessageId = clientMessageId ?? const Uuid().v4();

  /// nullなら新しい会話。最初の送信でサーバーがスレッドを作る(metaイベントでidが届く)。
  final String? threadId;

  /// 再送の重複を見分けるためのid(同じ送信を2回届けてもサーバーは1回として扱う)。
  final String clientMessageId;

  /// 資料だけを送るときは空でよい。
  final String content;
  final ChatMessageContext context;

  /// この送信で添付する資料。いつも全文で添付する。
  final List<ChatNewAttachment> newAttachments;

  /// この会話の既存の資料を指す(全文で添付 / メンション)。
  final List<ChatAttachmentRef> references;

  /// 編集・作り直し: このユーザーメッセージ自身と、それより後ろを消してから送る(一本道)。
  final String? replaceFromMessageId;

  Future<Map<String, dynamic>> toJson() async {
    String? titleOrNull(String title) =>
        title.trim().isEmpty ? null : title.trim();
    final attachments = [
      for (final a in newAttachments)
        switch (a) {
          ChatTextAttachment() => {
            'kind': 'text',
            'ref': a.localId,
            'title': titleOrNull(a.title),
            'content': a.content,
          },
          ChatFileAttachment() => {
            'kind': 'file',
            'attachment_id': a.attachmentId,
            'title': titleOrNull(a.title),
          },
        },
      for (final r in references)
        {
          'kind': 'existing',
          'attachment_id': r.attachmentId,
          'mode': r.mode.name,
        },
    ];
    return {
      'thread_id': threadId,
      'client_message_id': clientMessageId,
      'content': content,
      'context': context.toRequestJson(),
      'attachments': attachments.isEmpty ? null : attachments,
      'replace_from_message_id': replaceFromMessageId,
      // 「昨日の授業」「今学期」を端末の日付で解決するため(バックエンドは無ければUTC)
      'timezone': await deviceTimeZoneName(),
    };
  }
}

String? _cachedTimeZone;

/// 端末のIANAタイムゾーン名(例: "Asia/Tokyo")。取れなければnull(送らない)。
Future<String?> deviceTimeZoneName() async {
  if (_cachedTimeZone != null) return _cachedTimeZone;
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    final name = info.identifier;
    if (name.isNotEmpty) _cachedTimeZone = name;
    return _cachedTimeZone;
  } catch (_) {
    return null;
  }
}
