import type { ChatScreenRef, ChatSelection } from '../types/chat';

/** 選択の前後として添える文字数。同じ文言がページに何度も出るときに、どれを選んだかを見分けるだけに使う。 */
const SELECTION_CONTEXT_CHARS = 200;

/**
 * 「Ask」で送る選択。flattenedTextは選択オフセットの座標系(ブロックのtextContent)。
 * バックエンドは選択テキストと前後の文字でページ本文の中の位置を探し、そこに印を付ける。
 */
export function buildChatSelection(
  flattenedText: string,
  startIdx: number,
  endIdx: number,
  text: string,
  /** 選択したページ。無ければ(会話の中の選択など)今いる画面のページが使われる。 */
  screen?: ChatScreenRef
): ChatSelection {
  return {
    text,
    before: flattenedText.slice(Math.max(0, startIdx - SELECTION_CONTEXT_CHARS), startIdx),
    after: flattenedText.slice(endIdx, endIdx + SELECTION_CONTEXT_CHARS),
    screen,
  };
}
