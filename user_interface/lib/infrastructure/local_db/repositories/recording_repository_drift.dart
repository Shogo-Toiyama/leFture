import 'package:drift/drift.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../app_database_provider.dart';

part 'recording_repository_drift.g.dart';

@Riverpod(keepAlive: true)
RecordingRepositoryDrift recordingRepositoryDrift(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return RecordingRepositoryDrift(db: db);
}

/// Drift（ローカルDB）だけを触る層。
/// Supabase auth / UI 依存を持たない。
class RecordingRepositoryDrift {
  RecordingRepositoryDrift({required this.db});

  final AppDatabase db;

  static const String audioBucket = 'lecture_assets';

  Future<String> createDraftLecture({
    required String userId,
    String? presetLectureId,
    String? presetCourseId,
    String? presetTitle,
    DateTime? lectureDateTime,
    bool autoStartAnalysis = true,
    bool isRealtime = true,
    String? recordingLanguage,
    String? displayLanguage,
  }) async {
    final lectureId = presetLectureId ?? const Uuid().v4();
    final now = DateTime.now().toUtc();
    final dt = (lectureDateTime ?? now).toUtc();

    await db.transaction(() async {
      await db.into(db.localLectures).insertOnConflictUpdate(
            LocalLecturesCompanion(
              id: Value(lectureId),
              userId: Value(userId),
              courseId: Value(presetCourseId),
              title: Value(presetTitle ?? ''),
              createdAt: Value(now),
              updatedAt: Value(now),
              lectureDatetime: Value(dt),
              sortOrder: const Value(0),
              autoStartAnalysis: Value(autoStartAnalysis),
              isRealtime: Value(isRealtime),
              recordingLanguage: Value(recordingLanguage),
              displayLanguage: Value(displayLanguage),
            ),
          );

      // ★ 講義の「新規作成」をOutboxに積む。
      // 以前はここが抜けており、Outboxに`lecture`が積まれるのは削除
      // (softDeleteLecture)と編集(updateLectureTitleAndCourse)の時だけだった。
      // その穴を塞ぐために`upsertLecture`がUploadManagerのアップロードジョブの
      // 前処理として差し込まれていたため、「音声アップロードジョブが動かない限り
      // 講義そのものがSupabaseへ届かない」という状態になっていた。実際、保存処理が
      // 途中で止まってジョブが1件も作られなかった講義は、ローカルにだけ存在する
      // まま丸1日サーバーに現れなかった。
      //
      // 作成時点でOutboxに乗せておけば、音声パイプラインの成否とは無関係に
      // 講義行がサーバーへ届く。Discardで物理削除された場合は
      // [LectureOutboxPushHandler]がローカル行の不在を見て何も送らずに畳む。
      await db.enqueueOutbox(
        entityType: 'lecture',
        entityId: lectureId,
        op: 'create',
      );
    });

    return lectureId;
  }

  Future<void> updateLectureTitle({
    required String userId,
    required String lectureId,
    required String title,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      title: Value(title),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateLectureCourse({
    required String userId,
    required String lectureId,
    required String? courseId,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      courseId: Value(courseId),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateLectureAutoStartAnalysis({
    required String userId,
    required String lectureId,
    required bool autoStartAnalysis,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      autoStartAnalysis: Value(autoStartAnalysis),
      updatedAt: Value(now),
    ));
  }

  Future<void> updateLectureIsRealtime({
    required String userId,
    required String lectureId,
    required bool isRealtime,
  }) async {
    final now = DateTime.now().toUtc();
    await (db.update(db.localLectures)
          ..where((t) => t.id.equals(lectureId))
          ..where((t) => t.userId.equals(userId)))
        .write(LocalLecturesCompanion(
      isRealtime: Value(isRealtime),
      updatedAt: Value(now),
    ));
  }

  /// 録音停止後に、asset + upload job を「同一トランザクション」で作る。
  /// ここが壊れないことが最重要なので transaction で囲む。
  Future<String> attachAudioAndEnqueueUpload({
    required String userId,
    required String lectureId,
    required String localPath,
    required double startTime,
    // このチャンクがカバーする音声の絶対終端秒(startTime + 実データ長/32000)。
    // Recording Recoveryがクラッシュ後にテールを正しい位置で切り出すために
    // 使う唯一の情報源。呼び出し側(RecordingController)が渡さない(既存の
    // 呼び出し箇所)場合はnullのままで、その場合はテール回収が自動的に
    // スキップされるだけで他の挙動に影響しない。
    double? endTime,
    String? presetAssetId,
    int sequenceIndex = 0,
  }) async {
    final now = DateTime.now().toUtc();

    final assetId = presetAssetId ?? const Uuid().v4();
    final fileName = p.basename(localPath);
    final storagePath = '$userId/$lectureId/$fileName';
    final jobId = const Uuid().v4();

    await db.transaction(() async {
      // lecture updatedAt 更新（lecture row が存在しない可能性もあるので upsert にしたいならここを調整）
      await (db.update(db.localLectures)
            ..where((t) => t.id.equals(lectureId))
            ..where((t) => t.userId.equals(userId)))
          .write(LocalLecturesCompanion(updatedAt: Value(now)));

      // asset upsert
      await db.into(db.localLectureAssets).insertOnConflictUpdate(
            LocalLectureAssetsCompanion(
              id: Value(assetId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              type: const Value('audio'),
              sequenceIndex: Value(sequenceIndex),
              localPath: Value(localPath),
              storageBucket: const Value(audioBucket),
              storagePath: Value(storagePath),
              startTime: Value(startTime),
              endTime: Value(endTime),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // upload job upsert
      await db.into(db.localUploadJobs).insertOnConflictUpdate(
            LocalUploadJobsCompanion(
              id: Value(jobId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              assetId: Value(assetId),

              status: const Value('queued'),
              attemptCount: const Value(0),
              lastError: const Value(null),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });

    return jobId;
  }

  Stream<LocalLecture?> watchLecture(String lectureId) {
    return (db.select(db.localLectures)..where((t) => t.id.equals(lectureId)))
        .watchSingleOrNull();
  }

  /// 講義の録音言語(recordingLanguage)をローカルDBで更新する。
  /// [languageCode]がnullなら「自動判定」(未設定)として保存する。
  Future<void> updateLectureRecordingLanguage(String lectureId, String? languageCode) async {
    await (db.update(db.localLectures)..where((t) => t.id.equals(lectureId))).write(
      LocalLecturesCompanion(
        recordingLanguage: Value(languageCode),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<LocalLectureAsset>> watchLectureAssets(String lectureId) {
    return (db.select(db.localLectureAssets)
          ..where((t) => t.lectureId.equals(lectureId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  /// Discard時に、アップロードジョブと紐づくアセット行(ローカルのみの付随データ)
  /// を消す。Lecture本体はここでは消さない — Discard時点で既にバックグラウンドの
  /// チャンクアップロードがSupabaseへ`lectures`行を作ってしまっている可能性があり
  /// (レース)、その場合は`LectureRepositoryDrift.softDeleteLecture`で論理削除
  /// してOutbox経由で`deleted_at`をpushする必要があるため、そちらが読み出せる
  /// ようローカルの`localLectures`行はあえて残す(30日後に自動退避される)。
  Future<void> deleteLectureJobsAndAssets(String lectureId) async {
    await db.transaction(() async {
      // 1. Jobがあれば消す(これ以上チャンクがアップロードされないようにする)
      await (db.delete(db.localUploadJobs)
            ..where((t) => t.lectureId.equals(lectureId)))
          .go();

      // 2. Assetがあれば消す
      await (db.delete(db.localLectureAssets)
            ..where((t) => t.lectureId.equals(lectureId)))
          .go();
    });
  }

  /// [deleteLectureJobsAndAssets]でアセット行を消す前に、実体ファイルを掃除する
  /// ための一覧。行を消してしまうとlocalPathが辿れなくなり、圧縮済みM4Aが
  /// 端末に残り続けてしまう。
  Future<List<String>> getLectureAssetLocalPaths(String lectureId) async {
    final assets = await (db.select(db.localLectureAssets)
          ..where((t) => t.lectureId.equals(lectureId)))
        .get();
    return assets
        .map((a) => a.localPath)
        .whereType<String>()
        .toList();
  }

  // ついでに UploadManager が使う「ジョブ取得」機能もここに定義しておくと綺麗です
  Stream<List<LocalUploadJob>> watchPendingJobs() {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.status.isIn(['queued', 'retry_wait']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  // Jobの状態更新用
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
    String? lastError,
    DateTime? nextRetryAt,
    int? attemptCount,
  }) async {
    await (db.update(db.localUploadJobs)..where((t) => t.id.equals(jobId)))
        .write(LocalUploadJobsCompanion(
      status: Value(status),
      lastError: Value(lastError),
      nextRetryAt: Value(nextRetryAt),
      attemptCount: attemptCount != null ? Value(attemptCount) : const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }
  
  // Assetの状態更新用 (Upload完了時に storagePath を入れ、
  // 既に削除済みのローカルファイルへの参照(localPath)もクリアするため)
  Future<void> updateAssetUploaded({
    required String assetId,
    required String remotePath,
  }) async {
    await (db.update(db.localLectureAssets)..where((t) => t.id.equals(assetId)))
        .write(LocalLectureAssetsCompanion(
       uploadStatus: const Value('uploaded'),
       storagePath: Value(remotePath),
       localPath: const Value(null),
       updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<List<LocalUploadJob>> getPendingJobs() {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.status.isIn(['queued', 'retry_wait']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
  
  // Lecture本体のデータ取得（Upload時にSupabaseへ送るため）
  Future<LocalLecture?> getLecture(String lectureId) {
     return (db.select(db.localLectures)..where((t) => t.id.equals(lectureId))).getSingleOrNull();
  }
  
  // Assetのデータ取得（ファイルパスを知るため）
  Future<LocalLectureAsset?> getAsset(String assetId) {
     return (db.select(db.localLectureAssets)..where((t) => t.id.equals(assetId))).getSingleOrNull();
  }

  Future<void> saveWhisperContext({
    required String lectureId,
    required String whisperContext,
  }) async {
    await (db.update(db.localLectures)..where((t) => t.id.equals(lectureId)))
        .write(LocalLecturesCompanion(
      whisperContext: Value(whisperContext),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  // 録音終了時(Done)に、総チャンク数をローカルDBに保存する
  Future<void> finishLectureRecording({
    required String lectureId,
    required int expectedChunks,
  }) async {
    await (db.update(db.localLectures)..where((t) => t.id.equals(lectureId)))
        .write(LocalLecturesCompanion(
      expectedChunks: Value(expectedChunks),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }
  
  // UploadManager用：特定の授業の「未送信ジョブ」をすべて取得する
  Future<List<LocalUploadJob>> getPendingJobsForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
        .get();
  }

  // UploadManager用：start-analysisのトリガー判定に使う。
  // マスター音声(kind: 'master_audio_upload')は分析パイプラインの入力ではなく
  // 再生用途でしかないため、これが失敗・保留中でも分析開始をブロックしない。
  // ここでは音声チャンク(kind: 'audio_upload')のみを対象にする。
  Future<List<LocalUploadJob>> getPendingChunkJobsForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.equals('audio_upload'))
          ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
        .get();
  }

  // Recording Recovery用: この講義の音声チャンク資産(master_audioは除く、
  // sequenceIndex順)を取得する。テール回収の可否判定(全チャンクのendTimeが
  // 揃っているか)と、次に採番すべきsequenceIndexの算出の両方に使う。
  Future<List<LocalLectureAsset>> getChunkAssetsForLecture(String lectureId) {
    return (db.select(db.localLectureAssets)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.type.equals('audio'))
          ..orderBy([(t) => OrderingTerm(expression: t.sequenceIndex)]))
        .get();
  }

  // マスターオーディオ用のアップロードジョブをエンキューする
  Future<String> enqueueMasterAudioUpload({
    required String userId,
    required String lectureId,
    required String localPath,
  }) async {
    final now = DateTime.now().toUtc();
    final assetId = const Uuid().v4();
    final jobId = const Uuid().v4();
    final fileName = p.basename(localPath);
    final storagePath = '$userId/$lectureId/$fileName';

    await db.transaction(() async {
      // 1. lecture updatedAt 更新
      await (db.update(db.localLectures)
            ..where((t) => t.id.equals(lectureId))
            ..where((t) => t.userId.equals(userId)))
          .write(LocalLecturesCompanion(updatedAt: Value(now)));

      // 2. asset 登録 (type: 'master_audio', sequenceIndex: -1)
      await db.into(db.localLectureAssets).insertOnConflictUpdate(
            LocalLectureAssetsCompanion(
              id: Value(assetId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              type: const Value('master_audio'),
              sequenceIndex: const Value(-1),
              localPath: Value(localPath),
              storageBucket: const Value(audioBucket),
              storagePath: Value(storagePath),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // 3. upload job 登録 (kind: 'master_audio_upload')
      await db.into(db.localUploadJobs).insertOnConflictUpdate(
            LocalUploadJobsCompanion(
              id: Value(jobId),
              userId: Value(userId),
              lectureId: Value(lectureId),
              assetId: Value(assetId),
              kind: const Value('master_audio_upload'),
              status: const Value('queued'),
              attemptCount: const Value(0),
              lastError: const Value(null),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });

    return jobId;
  }

  // 分析開始(StartAnalysis)呼び出し専用のジョブをエンキューする。
  // アップロード完了直後の"号砲"だった_triggerStartAnalysisは、失敗してもDevLogに
  // 書くだけで誰にも気づかれず消えていた。他のアップロードジョブと同じ
  // queued/retry_wait/lastError/attemptCountの仕組みに乗せることで、失敗時に
  // 自動リトライされ、かつUI側からlastErrorを参照して表示できるようにする。
  // assetIdは実体を持たない(参照用の列が必須なので、直前に完了したアップロード
  // ジョブのassetIdをそのまま流用する)。
  Future<String> enqueueStartAnalysis({
    required String userId,
    required String lectureId,
    required String assetId,
  }) async {
    final now = DateTime.now().toUtc();
    final jobId = const Uuid().v4();

    await db.into(db.localUploadJobs).insertOnConflictUpdate(
          LocalUploadJobsCompanion(
            id: Value(jobId),
            userId: Value(userId),
            lectureId: Value(lectureId),
            assetId: Value(assetId),
            kind: const Value('start_analysis'),
            status: const Value('queued'),
            attemptCount: const Value(0),
            lastError: const Value(null),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    return jobId;
  }

  // start_analysisジョブはassetIdカラムが必須だが、実体ファイルは一切参照しない
  // (UploadManager._performUploadはkind=='start_analysis'ならasset取得より前に
  // 分岐して抜ける)。号砲を鳴らす側がassetIdを持っていない場合に、この講義の
  // 任意のアセットIDを流用するためのヘルパー。
  Future<String?> getAnyAssetIdForLecture(String lectureId) async {
    final row = await (db.select(db.localLectureAssets)
          ..where((t) => t.lectureId.equals(lectureId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  // 自動発火の二重登録ガード。保存時(RecordingController.upload)と
  // 最終チャンク完了時(UploadManager)の両方が号砲を鳴らしうるため、
  // 既に号砲ジョブがあるかを発火前に確認する。完了済み('done')も含めて
  // 見るのが重要 —— 完了済みを除外すると、一度analysisを開始した後に
  // もう一度発火してしまう。
  Future<bool> hasStartAnalysisJobForLecture(String lectureId) async {
    final rows = await (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.equals('start_analysis'))
          ..where((t) => t.status.isNotValue('cancelled'))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  // Recording Recovery用: この講義に指定kindのアップロードジョブが
  // (ステータス問わず)1件でも存在するかを判定する。「master_audio_uploadが
  // 存在する = 通常の保存/確定フローを一度でも通過した」という判定に使う
  // (孤児検出は「このジョブが無い」ことそのものが条件なので、statusで
  // 絞り込まない — doneでもcancelledでも「一度は通した」事実に変わりはない)。
  Future<bool> hasAnyUploadJobOfKindForLecture(String lectureId, String kind) async {
    final rows = await (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.equals(kind))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  // UI側(NotStartedView)が「まだ音声のアップロードが終わっていないので
  // Start Analysisを押させてはいけない」を判定するためのwatch。
  // start_analysisジョブ(実ファイルを持たない号砲)は対象外 —— これ自体は
  // 音声の到達とは無関係で、含めるとボタンが永久に押せなくなる。
  Stream<List<LocalUploadJob>> watchPendingAudioUploadJobsForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.isIn(['audio_upload', 'master_audio_upload']))
          ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
        .watch();
  }

  // UI側(NotStartedView)が「アップロードをユーザーが自分で止めた」ことを
  // 表示するためのwatch。cancelPendingUploadsForLectureで'cancelled'に
  // なったジョブがここに現れる。
  Stream<List<LocalUploadJob>> watchCancelledAudioUploadJobsForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.isIn(['audio_upload', 'master_audio_upload']))
          ..where((t) => t.status.equals('cancelled')))
        .watch();
  }

  // UploadManager用: 自動Start Analysis発火の直前ガード。この講義に
  // 'cancelled'な音声アップロードジョブが1件でも残っている間は、たとえ
  // 別のジョブ(例: 既に送信済みのチャンク)が今まさに成功しても、自動発火
  // すべきではない(ユーザーが明示的に「止めた」意思表示をしているため)。
  Future<bool> hasCancelledUploadJobsForLecture(String lectureId) async {
    final rows = await (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.isIn(['audio_upload', 'master_audio_upload']))
          ..where((t) => t.status.equals('cancelled'))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  // 音声アップロードを「止める」。★ ファイル本体・アセット行には一切触れない
  // (deleteLectureJobsAndAssetsとの決定的な違い) —— ユーザーが後で再開したい
  // 場合に備え、いつでもresumePendingUploadsForLectureで元に戻せるようにする。
  // 対象は未完了(queued/retry_wait)のチャンク/マスター音声ジョブと、
  // それに連動して待機しているstart_analysisジョブ(アップロードを止めたのに
  // 解析だけ勝手に始まっては困るため)。
  Future<void> cancelPendingUploadsForLecture(String lectureId) async {
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      final cancelledUploads = await (db.update(db.localUploadJobs)
            ..where((t) => t.lectureId.equals(lectureId))
            ..where((t) => t.kind.isIn(['audio_upload', 'master_audio_upload']))
            ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
          .write(LocalUploadJobsCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(now),
      ));

      final cancelledStartAnalysis = await (db.update(db.localUploadJobs)
            ..where((t) => t.lectureId.equals(lectureId))
            ..where((t) => t.kind.equals('start_analysis'))
            ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
          .write(LocalUploadJobsCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(now),
      ));

      // 検証用: 行数が両方0だと「押したのに何も変わっていない」バグの
      // 可能性が高い(例: 既に'done'になっていた、lectureIdが違う等)ので、
      // 押した側にすぐ気づけるようにログを残す。
      DevLog.add(
        '🛑 [RecordingRepo] cancelPendingUploadsForLecture($lectureId): '
        '$cancelledUploads upload job(s), $cancelledStartAnalysis start_analysis job(s) → cancelled',
      );
    });
  }

  // 止めていたアップロードを再開する。ファイルはcancelPendingUploadsForLecture
  // が一度も触っていないのでそのまま残っており、ステータスをqueuedへ戻すだけで
  // UploadManagerの通常のリトライ経路に自然に乗る。attemptCount等は0から
  // やり直す(止めていた理由は「失敗し続けていたから」とは限らないため)。
  Future<void> resumePendingUploadsForLecture(String lectureId) async {
    final resumed = await (db.update(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.isIn(['audio_upload', 'master_audio_upload']))
          ..where((t) => t.status.equals('cancelled')))
        .write(LocalUploadJobsCompanion(
      status: const Value('queued'),
      attemptCount: const Value(0),
      nextRetryAt: const Value(null),
      lastError: const Value(null),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    DevLog.add('▶️ [RecordingRepo] resumePendingUploadsForLecture($lectureId): $resumed job(s) → queued');
  }

  /// 録音を確定した(保存 or 復旧からの確定)瞬間に、リアルタイム収録の
  /// 自動分析(start_analysis号砲)を予約する。呼び出し元はRecordingController.
  /// upload()とRecording Recoveryの確定フローの両方(元は前者にだけ存在した
  /// private methodだったが、両方から同じ判定を使うためrepo層へ移動した)。
  /// 未送信チャンクが残っている場合はここでは鳴らさず、UploadManagerが
  /// 最後のチャンク完了時に鳴らす方に任せる(この時点でexpectedChunksは
  /// 既に確定済みなので、そちらの判定も正しく通るようになっている)。
  Future<void> maybeEnqueueStartAnalysisForRealtimeLecture(String lectureId) async {
    // 呼び出し元が保持している講義データは古い可能性があるため、DBから読み直す。
    final fresh = await getLecture(lectureId);
    if (fresh == null) return;

    if (fresh.isRealtime != true) {
      // プレレコーデッドはマスター音声の送信完了時にUploadManagerが発火する。
      return;
    }
    if (fresh.autoStartAnalysis == false) {
      DevLog.add('⏸️ [Upload] 自動分析がOFFのため、号砲は鳴らしません（手動でStart Analysisが必要）。');
      return;
    }
    if (fresh.courseId == null) {
      DevLog.add('⏸️ [Upload] コース未選択のため、自動分析はスキップします（手動でStart Analysisが必要）。');
      return;
    }

    // 二重発火ガード。保存時(ここ)と最終チャンク完了時(UploadManager)の
    // 両方が候補になるため、既に号砲があるなら何もしない。
    if (await hasStartAnalysisJobForLecture(lectureId)) {
      DevLog.add('⏭️ [Upload] start_analysisジョブが既に存在するため、二重発火を回避します。');
      return;
    }

    final pendingChunks = await getPendingChunkJobsForLecture(lectureId);
    if (pendingChunks.isNotEmpty) {
      DevLog.add(
        '⏳ [Upload] 未送信チャンクが${pendingChunks.length}件残っています。全て完了した時点でUploadManagerが分析を開始します。',
      );
      return;
    }

    final assetId = await getAnyAssetIdForLecture(lectureId);
    if (assetId == null) {
      DevLog.add('⚠️ [Upload] アセットが1件も見つからないため、号砲を鳴らせませんでした。');
      return;
    }

    DevLog.add('🎉 [Upload] 全チャンク送信済み。保存と同時に分析開始の号砲を鳴らします！');
    await enqueueStartAnalysis(
      userId: fresh.userId,
      lectureId: lectureId,
      assetId: assetId,
    );
  }

  // UI側(NotStartedView等)がstart_analysisジョブの失敗状況を表示するためのwatch。
  Stream<List<LocalUploadJob>> watchStartAnalysisJobsForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.equals('start_analysis'))
          ..where((t) => t.status.isIn(['queued', 'retry_wait'])))
        .watch();
  }

  // UI側(NotStartedView/LectureOverlayCard)が「分析開始の号砲は既に鳴らして
  // ある(サーバー側のジョブ作成をポーリングで検知するまでの数秒の隙間)」を
  // 判定するためのwatch。上のwatchStartAnalysisJobsForLectureと違い'done'も
  // 含める — 号砲が成功してサーバーにprocessing_jobsが作られた直後は、
  // watchJob(3秒ポーリング)がそれを拾うまでの間job==nullのままになり、
  // その隙間だけStart Analysisボタンが再び表示される「ちらつき」の原因に
  // なっていた。'done'を含めることで、その隙間もこのwatchが埋める。
  // hasStartAnalysisJobForLectureが'done'を含めているのと同じ理由。
  Stream<List<LocalUploadJob>> watchStartAnalysisJobsIncludingDoneForLecture(String lectureId) {
    return (db.select(db.localUploadJobs)
          ..where((t) => t.lectureId.equals(lectureId))
          ..where((t) => t.kind.equals('start_analysis'))
          ..where((t) => t.status.isNotValue('cancelled')))
        .watch();
  }
}
