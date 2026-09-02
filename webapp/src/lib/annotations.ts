import { supabase } from './supabase';
import { createAnnotationId, type Annotation, type AnnotationContents } from '../types/annotation';
import type { ContentMetadata } from '../types/content';

export type AnnotatableTable = 'review_cards' | 'deep_notes';

export function readAnnotations(metadata: ContentMetadata | null): Annotation[] {
  const raw = metadata?.annotations;
  return Array.isArray(raw) ? raw : [];
}

/** 指定ブロック(DeepNotesはnull)のアノテーションだけを取り出す。 */
export function annotationsForBlock(annotations: Annotation[], blockIdx: number | null): Annotation[] {
  return annotations.filter((a) => (a.block_idx ?? null) === blockIdx);
}

async function persist(
  table: AnnotatableTable,
  rowId: string,
  currentMetadata: ContentMetadata | null,
  annotations: Annotation[]
): Promise<ContentMetadata> {
  const nextMetadata: ContentMetadata = { ...currentMetadata, annotations };
  const { error } = await supabase.from(table).update({ metadata: nextMetadata }).eq('id', rowId);
  if (error) throw error;
  return nextMetadata;
}

export interface NewAnnotationInput {
  blockIdx: number | null;
  startIdx: number;
  endIdx: number;
  annotatedWords: string;
  annotationType: Annotation['annotation_type'];
  contents: AnnotationContents;
}

export async function addAnnotation(
  table: AnnotatableTable,
  rowId: string,
  currentMetadata: ContentMetadata | null,
  input: NewAnnotationInput
): Promise<ContentMetadata> {
  const existing = readAnnotations(currentMetadata);

  const annotation: Annotation = {
    id: createAnnotationId(),
    ...(input.blockIdx !== null ? { block_idx: input.blockIdx } : {}),
    start_idx: input.startIdx,
    end_idx: input.endIdx,
    annotation_type: input.annotationType,
    annotated_words: input.annotatedWords,
    contents: input.contents,
  };

  // 同じ種類のアノテーションが同じ範囲に重なっている場合は積み重ねず置き換える
  // (同じ箇所を2回ハイライトしても濃くならないようにするため)。
  const survivors = existing.filter(
    (a) =>
      a.annotation_type !== input.annotationType ||
      (a.block_idx ?? null) !== input.blockIdx ||
      a.end_idx <= input.startIdx ||
      a.start_idx >= input.endIdx
  );

  return persist(table, rowId, currentMetadata, [...survivors, annotation]);
}

export async function removeAnnotation(
  table: AnnotatableTable,
  rowId: string,
  currentMetadata: ContentMetadata | null,
  annotationId: string
): Promise<ContentMetadata> {
  const next = readAnnotations(currentMetadata).filter((a) => a.id !== annotationId);
  return persist(table, rowId, currentMetadata, next);
}

/** 消しゴム: 指定範囲に少しでも重なるアノテーションを削除する。 */
export async function eraseAnnotationsInRange(
  table: AnnotatableTable,
  rowId: string,
  currentMetadata: ContentMetadata | null,
  blockIdx: number | null,
  startIdx: number,
  endIdx: number
): Promise<ContentMetadata> {
  const next = readAnnotations(currentMetadata).filter(
    (a) =>
      (a.block_idx ?? null) !== blockIdx || a.end_idx <= startIdx || a.start_idx >= endIdx
  );
  return persist(table, rowId, currentMetadata, next);
}

export async function updateNoteContents(
  table: AnnotatableTable,
  rowId: string,
  currentMetadata: ContentMetadata | null,
  annotationId: string,
  text: string
): Promise<ContentMetadata> {
  const next = readAnnotations(currentMetadata).map((a) =>
    a.id === annotationId ? { ...a, contents: text } : a
  );
  return persist(table, rowId, currentMetadata, next);
}

export async function toggleSaved(
  table: AnnotatableTable | 'fun_facts',
  rowId: string,
  currentMetadata: ContentMetadata | null
): Promise<ContentMetadata> {
  const nextMetadata: ContentMetadata = { ...currentMetadata, saved: !currentMetadata?.saved };
  const { error } = await supabase.from(table).update({ metadata: nextMetadata }).eq('id', rowId);
  if (error) throw error;
  return nextMetadata;
}
