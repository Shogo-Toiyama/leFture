// lib/presentation/widgets/ai_chat/chat_sheet_physics.dart

/// チャットのシートの高さの決まり(使える高さに対する割合 0〜1)。
/// 指で上下に動かすとその位置で止まり、離したときの勢いで 100% / 閉じる に動く。
/// 画面に依存しない計算だけをここに置く(テストしやすいように)。
class ChatSheetPhysics {
  const ChatSheetPhysics._();

  /// 開いた直後の高さ。
  static const opening = .8;

  /// これを超えると、後ろのメイン画面は暗くなって触れなくなる。
  /// 以下のときは、メイン画面をそのまま触れる。
  static const blockAbove = .8;

  /// つまみをタップしたときに小さくする先の高さ。
  static const collapsed = .3;

  /// 全画面。
  static const full = 1.0;

  /// これより低い位置で離したら閉じる。
  static const closeBelow = .15;

  /// 指を離す直前の速さ(px/秒)がこれ以上なら「素早いスワイプ」。
  static const flingVelocity = 1000.0;

  /// 指で動かしている間の高さの範囲。
  static double clampWhileDragging(double fraction) =>
      fraction.clamp(0.0, full).toDouble();

  /// つまみのタップ: 50%以下なら80%に開き、それより高ければ30%に下げる。
  static double afterTap(double fraction) =>
      fraction <= .5 ? opening : collapsed;

  /// 後ろの暗い幕(と、メイン画面を触れなくする壁)が出る高さか。
  static bool blocksMain(double fraction) => fraction > blockAbove + 1e-6;

  /// 幕の濃さ(0〜1)。80%から100%にかけて濃くなる。
  static double scrimStrength(double fraction) =>
      ((fraction - blockAbove) / (full - blockAbove)).clamp(0.0, 1.0);
}

/// 指を離したときに、シートをどうするか。
sealed class ChatSheetRelease {
  const ChatSheetRelease();
}

/// その高さで止める。
class ChatSheetStay extends ChatSheetRelease {
  const ChatSheetStay();
}

/// その高さへ動かす。
class ChatSheetMoveTo extends ChatSheetRelease {
  const ChatSheetMoveTo(this.fraction);

  final double fraction;
}

/// 閉じる。
class ChatSheetClose extends ChatSheetRelease {
  const ChatSheetClose();
}

/// 指を離した時の高さ[fraction]と、上下の速さ[velocityY](px/秒。下向きが正)から決める。
/// 素早く上 → 100%、素早く下 → 閉じる(100%からでも)。ゆっくりなら、その位置で止める。
/// 低すぎる位置で離したら閉じる。
ChatSheetRelease releaseChatSheet(double fraction, double velocityY) {
  if (velocityY <= -ChatSheetPhysics.flingVelocity) {
    return const ChatSheetMoveTo(ChatSheetPhysics.full);
  }
  if (velocityY >= ChatSheetPhysics.flingVelocity) {
    return const ChatSheetClose();
  }
  if (fraction < ChatSheetPhysics.closeBelow) {
    return const ChatSheetClose();
  }
  return const ChatSheetStay();
}
