// lib/core/utils/chat_selection.dart
import 'package:lefture/domain/entities/chat.dart';

/// 選択の前後として添える文字数。同じ文言がページに何度も出るときに、どれを選んだかを見分けるだけに使う。
const chatSelectionContextChars = 200;

/// 「Ask」で送る選択(webappの buildChatSelection と同じ)。[flattenedText]は選択の位置
/// ([startIdx]〜[endIdx])の座標系の本文。バックエンドは選択テキストと前後の文字でページ本文の中の位置を
/// 探し、そこに印を付ける。範囲が本文の外に出ていても落ちない。
ChatSelection buildChatSelection(
  String flattenedText,
  int startIdx,
  int endIdx,
  String text, {
  ChatScreenRef? screen,
}) {
  final start = startIdx.clamp(0, flattenedText.length);
  final end = endIdx.clamp(start, flattenedText.length);
  final beforeFrom = (start - chatSelectionContextChars).clamp(0, start);
  final afterTo = (end + chatSelectionContextChars).clamp(
    end,
    flattenedText.length,
  );
  return ChatSelection(
    text: text,
    before: flattenedText.substring(beforeFrom, start),
    after: flattenedText.substring(end, afterTo),
    screen: screen,
  );
}
