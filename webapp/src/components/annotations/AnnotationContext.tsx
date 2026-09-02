import { createContext, useContext } from 'react';

export interface RegisteredBlock {
  element: HTMLElement;
  blockIdx: number | null;
  /** SID引用を含んだ生Markdown。"Source"アクションの引用検索に使う。 */
  rawMarkdown: string;
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
