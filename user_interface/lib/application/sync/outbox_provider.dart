// lib/application/sync/outbox_provider.dart
//
// OutboxSyncServiceを組み立てる共通provider。以前はLectureController内の
// private _outbox()にしか無かったが、RecordingControllerも「Moment追加後に
// 即座にOutboxを送る」という同じ用途でLectureController.pushOutboxNow()経由で
// これを呼んでいた。ところがLectureControllerはRecordingControllerを読む
// ため(recordingState参照)dependencies: [RecordingController]を宣言しており、
// RecordingController側もLectureControllerを読む(この用途)ので
// dependencies: [LectureController]を追加する必要が生じる——両方が互いを
// dependenciesに含める循環参照になり、riverpod_generatorの依存関係解決が
// 無限再帰に陥って生成不能になる(実際に確認済み)。
//
// 実際にはOutboxを送ること自体は録音中の状態(audioRecorderService)にも
// LectureControllerの他の責務にも依存しない独立した操作なので、ここへ
// 切り出してどちらのControllerからも(お互いを経由せず)直接読めるようにする。
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lefture/application/app_config/app_config_provider.dart';
import 'package:lefture/application/sync/announcement_outbox_push_handler.dart';
import 'package:lefture/application/sync/deep_note_outbox_push_handler.dart';
import 'package:lefture/application/sync/fun_fact_outbox_push_handler.dart';
import 'package:lefture/application/sync/keyword_outbox_push_handler.dart';
import 'package:lefture/application/sync/lecture_moment_outbox_push_handler.dart';
import 'package:lefture/application/sync/lecture_outbox_push_handler.dart';
import 'package:lefture/application/sync/outbox_sync_service.dart';
import 'package:lefture/application/sync/review_card_outbox_push_handler.dart';
import 'package:lefture/application/sync/user_profile_outbox_push_handler.dart';
import 'package:lefture/infrastructure/local_db/app_database_provider.dart';

part 'outbox_provider.g.dart';

/// entityTypeごとのPushハンドラを登録した汎用Outbox送信サービス。
/// 新しいエンティティ種別のOutbox対応を追加するときは、ハンドラ実装を
/// 足した上でここにも登録すること。
@riverpod
OutboxSyncService outboxSyncService(Ref ref) {
  final db = ref.read(appDatabaseProvider);
  final appConfig = ref.read(appConfigControllerProvider);
  return OutboxSyncService(db, {
    'lecture': LectureOutboxPushHandler(),
    'lecture_moment': LectureMomentOutboxPushHandler(),
    'fun_fact': FunFactOutboxPushHandler(),
    'announcement': AnnouncementOutboxPushHandler(),
    'review_card': ReviewCardOutboxPushHandler(),
    'deep_note': DeepNoteOutboxPushHandler(),
    'keyword': KeywordOutboxPushHandler(),
    'user_profile': UserProfileOutboxPushHandler(),
  }, syncBlocked: appConfig.isSyncBlocked);
}
