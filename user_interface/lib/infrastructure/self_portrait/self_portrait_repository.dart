// lib/infrastructure/self_portrait/self_portrait_repository.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lefture/core/config/app_config.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/auth/authed_http.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'self_portrait_repository.g.dart';

@Riverpod(keepAlive: true)
SelfPortraitRepository selfPortraitRepository(Ref ref) =>
    SelfPortraitRepository(AuthedHttpClient(supabase));

/// 通信が失敗した(2xxではなかった)。
class SelfPortraitRequestException implements Exception {
  const SelfPortraitRequestException(this.status, [this.body = '']);

  final int status;
  final String body;

  @override
  String toString() => 'SelfPortraitRequestException($status)';
}

/// 自分像・AIのメモのデータアクセス(webappの lib/selfPortrait.ts と同じ役割)。
/// 読み出しも書き込みもバックエンドを通す(根拠のつながりや観察メモは本人向けのRLSを置いておらず、
/// バックエンドで組み立てて返すため)。表紙(いまのわたし)の編集だけは
/// UserProfileRepository.updateProfile で、これまでどおり本人が直接書く。
class SelfPortraitRepository {
  SelfPortraitRepository(this._http);

  final AuthedHttpClient _http;

  static const _baseUrl = AppConfig.backendBaseUrl;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<SelfPortrait> get() async => SelfPortrait.fromMap(
    _map(_ensureOk(await _http.get(_uri('/profile/self-portrait')))),
  );

  Future<ItemDetail> item(String id) async => ItemDetail.fromMap(
    _map(_ensureOk(await _http.get(_uri('/profile/items/$id')))),
  );

  /// AIの読み違い。同じ意味のことは、もう書かない。
  Future<void> reject(String id, {String? reason}) async {
    final r = reason?.trim();
    _ensureOk(
      await _http.post(
        _uri('/profile/items/$id/reject'),
        payload: {'reason': (r == null || r.isEmpty) ? null : r},
      ),
    );
  }

  /// 自分の言葉に書き換える。以後AIはこの文を変えない。
  Future<void> edit(String id, String content) async {
    _ensureOk(
      await _http.patch(
        _uri('/profile/items/$id'),
        payload: {'content': content},
      ),
    );
  }

  /// 合っていても残さない。項目と、その元になったメモを消す。
  Future<void> discard(String id) async {
    _ensureOk(await _http.post(_uri('/profile/items/$id/discard')));
  }

  /// 確認待ち(センシティブ)の項目を残す。
  Future<void> keep(String id) async {
    _ensureOk(await _http.post(_uri('/profile/items/$id/keep')));
  }

  /// 「新しい」印を消す。
  Future<void> markSeen(List<String> ids) async {
    _ensureOk(
      await _http.post(_uri('/profile/items/seen'), payload: {'item_ids': ids}),
    );
  }

  Future<void> decideProposal(String id, {required bool accept}) async {
    _ensureOk(
      await _http.post(
        _uri('/profile/cover-proposals/$id/${accept ? 'accept' : 'reject'}'),
      ),
    );
  }

  Future<AiMemory> aiMemory() async => AiMemory.fromMap(
    _map(_ensureOk(await _http.get(_uri('/profile/ai-memory')))),
  );

  Future<void> deleteMemo(String id) async {
    _ensureOk(await _http.delete(_uri('/profile/memos/$id')));
  }

  Future<void> deleteObservation(String id) async {
    _ensureOk(await _http.delete(_uri('/profile/observations/$id')));
  }

  Future<void> forgetAiNotes() async {
    _ensureOk(await _http.post(_uri('/profile/ai-notes/forget')));
  }

  Object? _ensureOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SelfPortraitRequestException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Map<String, dynamic> _map(Object? body) =>
      Map<String, dynamic>.from(body as Map);
}
