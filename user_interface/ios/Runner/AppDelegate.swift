import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Dart側から開始された`beginBackgroundTask`の管理表。
  ///
  /// ★ なぜこれが必要か:
  /// 録音の保存処理は `stop()` → FFmpegでM4Aへエンコード → アップロードジョブ登録、
  /// という順で進む。`stop()`でオーディオセッションが終わった時点で
  /// `UIBackgroundModes: audio` による保護が切れるため、その直後の
  /// エンコード中に画面ロック・アプリ切替が起きるとiOSは数秒でアプリを
  /// サスペンドしてしまう。するとジョブ登録に到達せず、録音は端末に残ったまま
  /// サーバーへ一切送られない(実際にテスターの講義3件がこれで丸1日
  /// 取り残された)。
  ///
  /// マイクを回し続ければ保護は維持できるが、それだとステータスバーの
  /// 録音インジケータが出続け「保存したのにまだ録音されている」状態になる。
  /// 代わりにここで明示的に実行猶予(概ね30秒)をもらう。実測では90分の講義でも
  /// エンコードは10秒前後なので、通常はこれで十分収まる。
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]
  private var nextTaskId: Int = 1

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "lefture/background_task",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }
        switch call.method {
        case "begin":
          let args = call.arguments as? [String: Any]
          let name = args?["name"] as? String ?? "lefture.task"
          result(self.beginTask(name: name))

        case "end":
          if let id = (call.arguments as? [String: Any])?["id"] as? Int {
            self.endTask(id: id)
          }
          result(nil)

        case "remainingSeconds":
          // フォアグラウンドでは非常に大きな値(greatestFiniteMagnitude)が返る。
          // 「事実上無制限」の意味なので、Dart側でそのまま扱えるよう素通しする。
          result(UIApplication.shared.backgroundTimeRemaining)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 実行猶予を要求する。成功したらDart側が`end`で返すためのIDを返す。
  /// 取得できなかった場合は-1(Dart側はnull扱いにして、保護なしで続行する)。
  private func beginTask(name: String) -> Int {
    let id = nextTaskId
    nextTaskId += 1

    let identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      // ★ 猶予が尽きた時のハンドラ。ここで確実にendBackgroundTaskを呼ばないと
      // iOSはアプリを「約束を守らなかった」として強制終了する。
      // 処理そのものは中断されるが、その場合はRecordingRecovery/サルベージが
      // 次回起動で拾い直す。
      self?.endTask(id: id)
    }

    if identifier == .invalid {
      return -1
    }
    backgroundTasks[id] = identifier
    return id
  }

  /// 猶予を返上する。既に返上済み(期限切れハンドラが先に走った場合など)なら何もしない。
  private func endTask(id: Int) {
    guard let identifier = backgroundTasks.removeValue(forKey: id) else { return }
    UIApplication.shared.endBackgroundTask(identifier)
  }
}
