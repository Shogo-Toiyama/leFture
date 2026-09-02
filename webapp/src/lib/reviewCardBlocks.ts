import { stripSidCitations } from './sidCitation';
import type { ReviewCardBlock } from '../types/content';

/**
 * annotation_text_utils.dart の reviewCardBlockMarkdownSource / ...RawMarkdownSource と
 * 同じ文字列を組み立てる。アノテーションの座標系はここで作るMarkdownを
 * フラット化したものが基準になるため、モバイル版と一字一句揃える必要がある。
 */
export function blockMarkdownSource(block: ReviewCardBlock): string {
  if (block.type === 'list') {
    return (block.items ?? []).map((item) => `- ${stripSidCitations(item)}`).join('\n');
  }
  return stripSidCitations(block.text ?? '');
}

export function blockRawMarkdownSource(block: ReviewCardBlock): string {
  if (block.type === 'list') {
    return (block.items ?? []).map((item) => `- ${item}`).join('\n');
  }
  return block.text ?? '';
}

/** コードブロックはモバイル側でも注釈対象になっていない(本文がcode_string側にあるため)。 */
export function isAnnotatableBlock(block: ReviewCardBlock): boolean {
  return block.type !== 'code' && blockMarkdownSource(block).trim().length > 0;
}
