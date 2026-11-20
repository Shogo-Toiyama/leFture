# Flutter クライアントエラー診断の設計

2026-11-20 設計案

エラーの個別サンプルから、発生時の画面、失敗した処理、直前の状態を確認できるようにする。Flutter の画面遷移はルーターで一括計測する。操作は処理の実行箇所で計測し、初回は音声再生を対象とする。録音、アップロード、認証も同じ形式で順に追加する。ダイジェストは発生件数と代表メッセージを載せ、詳細の確認には既存の `client_error_events` を使う。

## 現状と変更箇所

本番で照合した認証エラーのサンプル16件は、すべてスタックの保存上限である4,000文字未満だった。Android 音声エラーのサンプル1件は、スタックと画面情報が空だった。`ErrorReporter` は `route` と `breadcrumbs` を送信できる。現在、ルーターから `currentRoute` を更新する処理はなく、通常の `breadcrumbs` は `DevLog` の末尾40行である。Flutter の `EventChannel` には、ネイティブの `PlatformException` を Dart スタックなしで配信する経路がある。原因を絞るには、プレーヤーの状態と操作の記録が必要になる。 [ErrorReporter](../user_interface/lib/application/errors/error_reporter.dart#L152) · [保存処理](../lefture_backend/app/main.py#L5572) · [Flutter EventChannel](https://api.flutter.dev/flutter/services/EventChannel/receiveBroadcastStream.html)

## 全画面の取得

`routerProvider` で `routerDelegate` の確定済み設定を監視する。通常の遷移は `RouteMatchList.fullPath`、`push` の場合は最前面の `ImperativeRouteMatch` の `matches.fullPath` を使う。正規化にはルーター自身の静的なルートテンプレートを使い、動的な ID やクエリ値を取り込まない。最初の遷移が確定するまでは画面未確定、照合エラーは `routing_error` とする。直前と同じテンプレートへの変更は履歴に追加しない。監視はルーターの破棄時に解除する。 [ルーター定義](../user_interface/lib/app/router.dart#L73) · [ルートテンプレートの検証](../contents_generation/test_codes/client_error_context_design/router_template_test.dart) · [go_router 17.0.1](https://pub.dev/documentation/go_router/17.0.1/go_router/RouteMatchList-class.html)

ダイアログやボトムシートでは背後の画面を `route` に残す。調査対象のシートは関連する処理に `surface` を付ける。たとえば `transcript_modal` での音声エラーは、元の画面と再生操作の両方から追える。既存の明示的な `route` 引数にはダイアログの操作名なども入るため、確定済みの画面があれば保存する `route` は画面テンプレートを優先する。既存の操作名を参照する箇所は実装時に確認し、必要な値は固定の `surface` または既存の `origin` に対応づける。 [既存のダイアログ報告](../user_interface/lib/presentation/widgets/app_error_dialog.dart#L143) · [エラーの発生元](../user_interface/lib/domain/errors/app_error.dart#L105)

## 操作の記録形式

操作名、結果、相対時刻を共通項目にする。個別の状態は各処理で型を決める。操作の開始時には処理内だけで使う連番を割り当て、要求・応答・失敗を対応づける。音声ではプレーヤー単位でも連番を持つ。ネイティブの通知に操作 ID がない場合は、同じプレーヤーの近い操作を含め、特定の操作が原因だったとは確定しない。

| 項目 | 初回の記録例 |
| --- | --- |
| `action` / `phase` | `audio.seek` / `requested`、`acknowledged`、`failed` |
| `offset_ms` / `duration_ms` | プロセス内の単調時計から計算したエラーからの相対時刻と、計測できた操作の所要時間 |
| `surface` / `trigger` | `transcript_modal` / `transcript_tap`。自動シークは別の固定値にする |
| `state` / `source` | `stopped` / `local`。状態は観測できた時点の値を使い、不明なら `unknown` |
| `native_error` | 取得できた `what=-38`、`extra=0`。エラーを受け取った箇所も固定の識別子で記録 |

初期設定は画面遷移8件、操作24件までのメモリ内履歴とする。エラー報告の入口で画面と履歴をスナップショットし、関連する操作を優先して最大8件と直前の画面遷移を最大3件添付する。追加する診断データは1サンプルあたり2 KiBを上限とする。これらは初期案の予算値で、実測値ではない。操作履歴は通常時に送信せず、別ユーザーのセッションに切り替わったら破棄する。バックグラウンド処理には処理を開始した画面と報告時の画面を区別できる情報を持たせる。

## 機能ごとの計測箇所と順番

| 段階 | 計測する処理 | 観測する状態 |
| --- | --- | --- |
| 1 | 画面遷移と音声の `set_source`、`play`、`pause`、`seek`、`stop`、`dispose` | 文字起こしページ・モーダル、講義ビューアの再生。アプリからの要求、SDK の応答、プレーヤー状態イベントを区別する |
| 2 | 録音開始・一時停止・再開・保存、アップロードの試行・再試行・完了 | 録音モード、状態、試行番号、待機時間、結果コード。OS による中断後を診断する既存の `UploadTrace` はその用途で使う |
| 3 | アプリが要求した認証更新と SDK から観測できる認証状態の変化 | 更新理由が分かる場合は期限切れか401かを記録し、成功・再試行可能・セッション失効を識別する。SDK 内部の更新開始や試行回数は観測できる範囲に限る |

音声ではプレーヤーを共有する計測処理からイベントを取り、画面側は固定の `surface` を渡す。Dart のコマンドが返った時点は `acknowledged` とし、実際の再生や準備完了は対応するプレーヤーイベントを記録する。計測で操作順や例外の伝播を変えない。録音は `RecordingController`、アップロードは `UploadManager`、アプリが発行する認証更新は `AuthedHttpClient` が計測の入口となる。 [音声プレーヤーの利用箇所](../user_interface/lib/presentation/pages/transcript/transcript_page.dart#L268) · [録音](../user_interface/lib/application/recording/recording_controller.dart#L200) · [アップロード](../user_interface/lib/application/recording/upload_manager.dart#L187) · [認証更新](../user_interface/lib/infrastructure/auth/authed_http.dart#L78) · [Supabase 認証状態イベント](https://supabase.com/docs/reference/dart/auth-onauthstatechange)

## 保存形式とプライバシー

初回は API と DB の既存フィールドを使う。正規化した画面を `route`、診断イベントをバージョン付きの固定形式に整形して `breadcrumbs` に保存する。通常エラーの最大40行の中で診断行を優先し、残りを既存のログに割り当てる。エラーの集計キーと保存件数の制限は既存値を使う。同一グループの通常サンプルは現行コードで12時間あたり最大5件、個別サンプルの保存期間は30日。専用の `UPLOAD_TRACE` の送り方も継続する。 [クライアントキュー](../user_interface/lib/application/errors/error_reporter.dart#L152) · [サンプル保存](../lefture_backend/app/main.py#L5680) · [保持期間](../lefture_backend/app/main.py#L4965)

新しい診断項目は固定ラベル、列挙値、真偽値、上限付きの数値から組み立てる。URL、クエリ、ファイルパス、ユーザーや講義の ID、入力内容、認証情報を診断項目に含めない。元のスタックは既存欄に保存する。スタックが空の場合は受信箇所の固定ラベルを残す。4,000文字の上限は、実際に切り詰められたため調査に必要な箇所が欠けた事例が出た段階で再検討する。

## 初回実装の完了条件

- 通常遷移、ネスト、`push`、戻る操作、リダイレクトで、確定済みの画面テンプレートが保存される。クエリに疑似秘密値を入れたテストで診断出力への混入がないことを確認する。
- スタックなしの音声例外をテストで注入し、画面、同じプレーヤーの直前操作、状態、ネイティブのコードを保存サンプルから読める。同時に動く別プレーヤーの操作は同じ操作系列として表示しない。
- 画面遷移がエラー報告の送信より先に起きても、添付内容は報告時点のスナップショットと一致する。バッファ上限、重複抑制、セッション切り替え時の消去、既存のダイジェストと `UPLOAD_TRACE` の経路も確認する。
- Android 実機またはエミュレータで、再生・停止・シーク・画面を閉じる操作を行い、通常の挙動を確認する。配布後はサンプルの画面記録率、スタックなしの音声エラーで操作履歴が付いた割合、通常レポートの追加バイト数を確認する。
