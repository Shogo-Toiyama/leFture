// lib/presentation/widgets/ai_chat/chat_sheet_handle.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lefture/domain/entities/chat.dart';

/// 開いているチャットシート1つの操作口。シートの外(「AIに聞く」など)から、開いているシートに
/// 選択を足したり、閉じたりするのに使う。シートが開いている間だけ1つ存在する。
class ChatSheetHandle {
  ChatSheetHandle();

  /// いまの高さ(使える高さに対する割合)。指で動かす間も、動きの途中も、ここが変わる。
  final fraction = ValueNotifier<double>(0);

  final _closed = Completer<void>();
  bool _finished = false;

  /// シートが閉じて、画面から消えたときに完了する。
  Future<void> get closed => _closed.future;

  bool get isOpen => !_finished;

  /// 閉じる動きの途中か(この間に開き直されたら、閉じ終わるのを待って新しく開く)。
  bool closing = false;

  // ---- シートの状態(State)が差し込む実体 ----
  void Function(double target)? _animateTo;
  void Function({bool animate})? _close;
  void Function(ChatSelection? selection, String? threadId)? _attach;
  VoidCallback? _remove;

  void bind({
    required void Function(double target) animateTo,
    required void Function({bool animate}) close,
    required void Function(ChatSelection? selection, String? threadId) attach,
    required VoidCallback remove,
  }) {
    _animateTo = animateTo;
    _close = close;
    _attach = attach;
    _remove = remove;
  }

  /// その高さへ動かす。
  void animateTo(double target) => _animateTo?.call(target);

  /// 閉じる。[animate]がfalseなら、動かさずにすぐ消す。
  void close({bool animate = true}) => _close?.call(animate: animate);

  /// 開いているシートに、選択や会話を足す(新しいシートは重ねない)。
  void attach({ChatSelection? selection, String? threadId}) =>
      _attach?.call(selection, threadId);

  /// シートを画面から外す(閉じる動きが終わったとき、シート自身が呼ぶ)。
  void finish() {
    if (_finished) return;
    _finished = true;
    _remove?.call();
    if (!_closed.isCompleted) _closed.complete();
  }
}

/// ルートの[Navigator]を見張って、チャットのシートの重なり順を保つ。
///
/// - 新しい**ページ**が開いても、チャットはずっと最上位(裏のページだけが変わる)。
/// - 出典・資料・確認などの**ポップアップ**(ダイアログ・下から出るシート)は、チャットより上に出す。
///   これを逆にすると、チャットから開いたシートがチャットの下に隠れてしまう。
class ChatSheetKeeper extends NavigatorObserver {
  OverlayEntry? _entry;
  final _popups = <Route<dynamic>>[];
  final _statusListeners = <Route<dynamic>, AnimationStatusListener>{};

  /// 開いているポップアップの数。戻る操作で、チャットより先にこれを閉じるのに使う。
  int get popupCount => _popups.length;

  void register(OverlayEntry entry) {
    _entry = entry;
    _restackSoon();
  }

  void unregister(OverlayEntry entry) {
    if (identical(_entry, entry)) _entry = null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _addPopup(route);
    _restackSoon();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _removePopup(route);
    _restackSoon();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _removePopup(route);
    _restackSoon();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _removePopup(oldRoute);
    if (newRoute is PopupRoute) _addPopup(newRoute);
    _restackSoon();
  }

  void _addPopup(PopupRoute<dynamic> route) {
    _popups.add(route);
    // 開く動きが終わると、ナビゲーターが全ルートを並べ直して、ポップアップがチャットの下に戻る。
    // その直後(同じフレームの描画より前)にもう一度、チャットの上へ動かす。
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        scheduleMicrotask(_restack);
        _restackSoon();
      }
    }

    route.animation?.addStatusListener(onStatus);
    _statusListeners[route] = onStatus;
  }

  void _removePopup(Route<dynamic> route) {
    _popups.remove(route);
    final listener = _statusListeners.remove(route);
    if (listener != null && route is TransitionRoute) {
      route.animation?.removeStatusListener(listener);
    }
  }

  void _restackSoon() {
    if (_entry == null) return;
    // 新しいルートの重なりが決まってから並べ直す
    WidgetsBinding.instance.addPostFrameCallback((_) => _restack());
  }

  void _restack() {
    final entry = _entry;
    final overlay = navigator?.overlay;
    if (entry == null || overlay == null || !entry.mounted) return;
    // チャットは最上位に挿してあり、ページが増えても、ナビゲーター自身の並べ替えでもその上に残る
    // (Overlay.rearrangeは、列挙しなかったエントリを上に残す)。直すのはポップアップがあるときだけ:
    // チャット自身を、一番下のポップアップのすぐ下へ移す。
    //
    // ポップアップの側を最上位へ動かしてはいけない。ポップアップの中で文字を選んでいると、選択の
    // つまみ・メニュー(ポップアップの文字に付いていくエントリ)がその上にあり、ポップアップだけを
    // 上へ動かすと、付いていく先より下に潜って描けなくなる(LeaderLayer/FollowerLayerのエラー)。
    OverlayEntry? lowestPopup;
    for (final route in _popups) {
      final entries = route.overlayEntries;
      if (entries.isEmpty || !entries.every((e) => e.mounted)) continue;
      lowestPopup = entries.first;
      break;
    }
    if (lowestPopup == null) return;
    // 同じフレームの中で外して挿し直すので、チャットの中身(会話・入力中の文字)は作り直されない
    entry.remove();
    overlay.insert(entry, below: lowestPopup);
  }
}

/// アプリで1つのキーパー。ルーターの`observers`に渡す。
final chatSheetKeeper = ChatSheetKeeper();
