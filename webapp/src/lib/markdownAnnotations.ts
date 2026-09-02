import { isHighlightContents, NOTE_MARKER_COLOR, type Annotation } from '../types/annotation';

/**
 * アノテーションの座標系について
 * ---------------------------------------------------------------------------
 * モバイル版(annotation_text_utils.dart)は start_idx/end_idx を
 * 「Markdown記法とSID引用を取り除いたあと、全テキストリーフを区切り文字なしで
 * 連結した文字列」上のオフセットとして保存する。
 *
 * Web側でこれと同じ座標系を得るには、同じMarkdown文字列をreact-markdownで
 * レンダリングしたDOMのテキストノードを文書順に連結すればよい
 * (`Range.toString()` / `Node.textContent` はどちらもテキストノードのみを
 * 区切り文字なしで連結する)。リストの行頭記号や見出しの`#`はCSS/構文であって
 * テキストノードではないため、自然にモバイル側と一致する。
 *
 * この前提を壊さないため、ハイライト描画で挿入する要素は**テキストを一切
 * 含めてはならない**(ノートの吹き出しマークはCSSの::afterで描画している)。
 */

// ---------------------------------------------------------------------------
// DOM選択 → フラット化オフセット
// ---------------------------------------------------------------------------

export interface SelectionOffsets {
  startIdx: number;
  endIdx: number;
  text: string;
  /** ツールバーを配置するための、選択範囲の画面上の矩形。 */
  rect: DOMRect;
}

function offsetWithin(container: HTMLElement, node: Node, nodeOffset: number): number {
  const range = document.createRange();
  range.selectNodeContents(container);
  range.setEnd(node, nodeOffset);
  return range.toString().length;
}

/** 現在の選択範囲が[container]内に収まっていればフラット化オフセットを返す。 */
export function readSelectionOffsets(container: HTMLElement): SelectionOffsets | null {
  const selection = window.getSelection();
  if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null;

  const range = selection.getRangeAt(0);
  if (!container.contains(range.startContainer) || !container.contains(range.endContainer)) {
    return null;
  }

  const startIdx = offsetWithin(container, range.startContainer, range.startOffset);
  const endIdx = offsetWithin(container, range.endContainer, range.endOffset);
  if (startIdx === endIdx) return null;

  const text = range.toString();
  if (!text.trim()) return null;

  return {
    startIdx: Math.min(startIdx, endIdx),
    endIdx: Math.max(startIdx, endIdx),
    text,
    rect: range.getBoundingClientRect(),
  };
}

// ---------------------------------------------------------------------------
// アノテーション描画 (rehypeプラグイン)
// ---------------------------------------------------------------------------

interface HastText {
  type: 'text';
  value: string;
}

interface HastElement {
  type: 'element';
  tagName: string;
  properties?: Record<string, unknown>;
  children: HastNode[];
}

interface HastRoot {
  type: 'root';
  children: HastNode[];
}

type HastNode = HastText | HastElement | HastRoot | { type: string; children?: HastNode[] };

function hasChildren(node: HastNode): node is HastElement | HastRoot {
  return Array.isArray((node as { children?: unknown }).children);
}

function hexToRgba(hex: string, alpha: number): string {
  const cleaned = hex.replace('#', '');
  const value = Number.parseInt(cleaned.length === 3 ? cleaned.replace(/./g, '$&$&') : cleaned, 16);
  if (Number.isNaN(value)) return `rgba(255, 179, 0, ${alpha})`;
  const r = (value >> 16) & 0xff;
  const g = (value >> 8) & 0xff;
  const b = value & 0xff;
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/** markdown_annotation_builder.dart:_decoratedStyle と同じ見た目になるCSSを組み立てる。 */
function styleForCovering(covering: Annotation[]): string {
  const declarations: string[] = [];

  const lastHighlight = [...covering].reverse().find((a) => a.annotation_type === 'highlight');
  if (lastHighlight && isHighlightContents(lastHighlight.contents)) {
    const { type, color } = lastHighlight.contents;
    if (type === 'marker') {
      declarations.push(`background-color:${hexToRgba(color, 0.45)}`);
    } else if (type === 'line') {
      declarations.push(`text-decoration:underline solid ${color}`, 'text-decoration-thickness:2px');
    } else if (type === 'wave') {
      declarations.push(`text-decoration:underline wavy ${color}`, 'text-decoration-thickness:2px');
    }
  }

  // notesは装飾の優先度が最も高い(モバイル版と同じく破線の下線で上書きする)。
  if (covering.some((a) => a.annotation_type === 'notes')) {
    declarations.push(
      `text-decoration:underline dashed ${NOTE_MARKER_COLOR}`,
      'text-decoration-thickness:3px'
    );
  }

  return declarations.join(';');
}

function markElement(value: string, covering: Annotation[]): HastElement {
  // クリック対象は「ノート > ハイライト」の順で決める(ノートを開けることを優先)。
  const target = covering.find((a) => a.annotation_type === 'notes') ?? covering[covering.length - 1];
  return {
    type: 'element',
    tagName: 'mark',
    properties: {
      className: ['annotation-mark'],
      style: styleForCovering(covering),
      dataAnnotationId: target.id,
      dataAnnotationType: target.annotation_type,
    },
    children: [{ type: 'text', value }],
  };
}

/** ノート箇所の目印。テキストを持たない空要素にして座標系を汚さない。 */
function noteMarkerElement(annotationId: string): HastElement {
  return {
    type: 'element',
    tagName: 'span',
    properties: {
      className: ['annotation-note-marker'],
      dataAnnotationId: annotationId,
    },
    children: [],
  };
}

/**
 * react-markdownのrehypePluginsに渡すプラグイン。テキストノードを
 * アノテーション境界で分割し、該当区間を<mark>で包む。
 */
export function rehypeAnnotations(annotations: Annotation[]) {
  return () => (tree: HastNode) => {
    if (annotations.length === 0) return;

    let offset = 0;

    const walk = (node: HastNode) => {
      if (!hasChildren(node)) return;

      const nextChildren: HastNode[] = [];

      for (const child of node.children) {
        if (child.type === 'text') {
          const text = (child as HastText).value;
          const leafStart = offset;
          const leafEnd = offset + text.length;
          offset = leafEnd;

          // このリーフに掛かるアノテーションの境界で切れ目を作る。
          const cuts = new Set<number>([leafStart, leafEnd]);
          for (const a of annotations) {
            if (a.start_idx > leafStart && a.start_idx < leafEnd) cuts.add(a.start_idx);
            if (a.end_idx > leafStart && a.end_idx < leafEnd) cuts.add(a.end_idx);
          }
          const boundaries = [...cuts].sort((a, b) => a - b);

          for (let i = 0; i < boundaries.length - 1; i++) {
            const segStart = boundaries[i];
            const segEnd = boundaries[i + 1];
            const value = text.slice(segStart - leafStart, segEnd - leafStart);
            if (!value) continue;

            const covering = annotations.filter((a) => a.start_idx <= segStart && a.end_idx >= segEnd);
            if (covering.length === 0) {
              nextChildren.push({ type: 'text', value });
              continue;
            }
            nextChildren.push(markElement(value, covering));

            // 複数リーフに跨るノートでも1度だけ、終端に吹き出しマークを添える。
            for (const a of covering) {
              if (a.annotation_type === 'notes' && a.end_idx === segEnd) {
                nextChildren.push(noteMarkerElement(a.id));
              }
            }
          }
        } else {
          nextChildren.push(child);
          walk(child);
        }
      }

      node.children = nextChildren;
    };

    walk(tree);
  };
}
