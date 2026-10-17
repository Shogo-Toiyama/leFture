import { createContext, useContext } from 'react';

export interface RegisteredBlock {
  element: HTMLElement;
  blockIdx: number | null;
  /** SID引用を含んだ生Markdown。"Source"アクションの引用検索に使う。 */
  rawMarkdown: string;
  /**
   * trueなら「Ask」「Copy」だけを出す(ハイライト・ノート・Sourceは付けない)。
   * コードブロックのように、Markdown上の文字位置に注釈を結べない領域用。
   */
  askOnly?: boolean;
}

export interface AnnotationContextValue {
  registerBlock: (key: string, block: RegisteredBlock) => void;
  unregisterBlock: (key: string) => void;
  openAnnotation: (annotationId: string, anchor: DOMRect) => void;
}

export const AnnotationContext = createContext<AnnotationContextValue | null>(null);

export function useAnnotationLayer(): AnnotationContextValue | null {
  return useContext(AnnotationContext);
}
