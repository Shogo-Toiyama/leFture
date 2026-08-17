// lib/app/navigation_utils.dart
//
// 「階層をひとつ上がる」ナビゲーションのための小さなヘルパー。
//
// このアプリはHomeの講義タイルから Home > Courses > Course > LectureViewer の
// 2階層を飛ばして入れる。そのため「戻る」には2つの意味が混在する:
//
// - Back(時間軸): 直前に見ていた画面へ戻る。端末の戻るボタン/スワイプ、pop。
// - Up(階層軸)  : その画面が所属する親へ上がる。画面内のリンク。
//
// 以前はHomeからの遷移に`go`を使っていた。go_routerはネストしたルートに`go`
// すると祖先ルートごとにページを積んだスタックを組み直すため、
// 「Homeから講義を開いたのに、戻るとCoursePageに出る」という挙動になっていた
// (アプリ外からのディープリンク向けの考え方を、アプリ内のショートカットに
// 適用してしまっていた)。今はBackを常に時間軸に統一し、階層へは画面内の
// リンクから移動する。
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// [location] が現在の画面のひとつ下(＝直前に見ていた画面)かどうか。
///
/// `push`で積まれた分(ImperativeRouteMatch)も`go`で組まれた分も、
/// `matchedLocation`は解決済みのパス文字列を返すので同じ比較で判定できる。
bool isDirectlyBehind(BuildContext context, String location) {
  final matches =
      GoRouter.of(context).routerDelegate.currentConfiguration.matches;
  if (matches.length < 2) return false;
  return matches[matches.length - 2].matchedLocation == location;
}

/// 階層をひとつ上がる。
///
/// 直前に見ていた画面がまさにその親なら`pop`する — 同じページを二重に積まず、
/// 遷移アニメーションも「戻る」向きになる。そうでなければ(Homeから飛び込んだ
/// 場合など)`push`する。ここで`go`を使うと、今読んでいたページがスタックから
/// 消えて戻れなくなるため使わない。
void navigateUpTo(BuildContext context, String location) {
  if (context.canPop() && isDirectlyBehind(context, location)) {
    context.pop();
    return;
  }
  context.push(location);
}
