import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  addAnnotation,
  eraseAnnotationsInRange,
  readAnnotations,
  removeAnnotation,
  updateNoteContents,
  type AnnotatableTable,
} from '../../lib/annotations';
import { readSelectionOffsets } from '../../lib/markdownAnnotations';
import { findSourceForSelection } from '../../lib/sourceCitation';
import { HIGHLIGHT_PRESET_COLORS, noteText, type Annotation } from '../../types/annotation';
import type { ContentMetadata } from '../../types/content';
import { AnnotationContext, type RegisteredBlock } from './AnnotationContext';

type HighlightStyle = 'marker' | 'line' | 'wave';

interface PendingSelection {
  blockIdx: number | null;
  startIdx: number;
  endIdx: number;
  text: string;
  rawMarkdown: string;
  /** 描画済みブロックのtextContent。選択オフセットの座標系そのもの。 */
  flattenedText: string;
  rect: DOMRect;
}

interface NoteEditorState {
  annotation?: Annotation;
  blockIdx: number | null;
  startIdx: number;
  endIdx: number;
  annotatedWords: string;
  draft: string;
  rect: DOMRect;
}

interface AnnotationLayerProps {
  table: AnnotatableTable;
  rowId: string;
  metadata: ContentMetadata | null;
  onMetadataChange: (metadata: ContentMetadata) => void;
  lectureId: string;
  /**
   * "Source" を押したときの出口。渡されていればトランスクリプトのシートを
   * 開き、無ければ文字起こしページへ遷移する。
   */
  onOpenSource?: (sidStrings: string[]) => void;
  children: React.ReactNode;
}

const STYLE_KEY = 'lefture.highlightStyle';
const COLOR_KEY = 'lefture.highlightColor';

function readStored(key: string, fallback: string): string {
  try {
    return localStorage.getItem(key) ?? fallback;
  } catch {
    return fallback;
  }
}

function store(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* プライベートウィンドウ等では黙って諦める */
  }
}

/** ビューポートからはみ出さないよう、選択範囲の上に浮かせる座標を求める。 */
function floatingStyle(rect: DOMRect, width: number): React.CSSProperties {
  const margin = 12;
  const centered = rect.left + rect.width / 2;
  const clamped = Math.min(Math.max(centered, width / 2 + margin), window.innerWidth - width / 2 - margin);
  const above = rect.top > 160;
  return {
    position: 'fixed',
    left: clamped,
    top: above ? rect.top - 10 : rect.bottom + 10,
    transform: above ? 'translate(-50%, -100%)' : 'translate(-50%, 0)',
  };
}

export const AnnotationLayer: React.FC<AnnotationLayerProps> = ({
  table,
  rowId,
  metadata,
  onMetadataChange,
  lectureId,
  onOpenSource,
  children,
}) => {
  const navigate = useNavigate();
  const blocksRef = useRef(new Map<string, RegisteredBlock>());
  // ノート編集中かどうか。選択の追従はドキュメント購読なので、編集中に
  // 走って編集中のノートを閉じてしまわないよう ref で見張る。
  const noteEditorOpenRef = useRef(false);

  const [selection, setSelection] = useState<PendingSelection | null>(null);
  const [showHighlightRow, setShowHighlightRow] = useState(false);
  const [showColors, setShowColors] = useState(false);
  const [noteEditor, setNoteEditor] = useState<NoteEditorState | null>(null);
  const [busy, setBusy] = useState(false);
  const [style, setStyle] = useState<HighlightStyle>(() => readStored(STYLE_KEY, 'marker') as HighlightStyle);
  const [color, setColor] = useState(() => readStored(COLOR_KEY, HIGHLIGHT_PRESET_COLORS[0]));

  const annotations = useMemo(() => readAnnotations(metadata), [metadata]);

  const registerBlock = useCallback((key: string, block: RegisteredBlock) => {
    blocksRef.current.set(key, block);
  }, []);

  const unregisterBlock = useCallback((key: string) => {
    blocksRef.current.delete(key);
  }, []);

  const dismiss = useCallback(() => {
    setSelection(null);
    setShowHighlightRow(false);
    setShowColors(false);
    window.getSelection()?.removeAllRanges();
  }, []);

  const openAnnotation = useCallback(
    (annotationId: string, anchor: DOMRect) => {
      const annotation = annotations.find((a) => a.id === annotationId);
      if (!annotation || annotation.annotation_type !== 'notes') return;
      // stateの反映を待たずに立てる(選択追従はrAFで走るため)。
      noteEditorOpenRef.current = true;
      setSelection(null);
      setNoteEditor({
        annotation,
        blockIdx: annotation.block_idx ?? null,
        startIdx: annotation.start_idx,
        endIdx: annotation.end_idx,
        annotatedWords: annotation.annotated_words,
        draft: noteText(annotation),
        rect: anchor,
      });
    },
    [annotations]
  );

  /**
   * 選択の追従。
   *
   * mouseupだけを見ていると、(1)クリックによる選択解除がmouseupの後に反映される
   * ブラウザでメニューが消えない、(2)キーボード選択やダブルクリックを取りこぼす、
   * という二つの取りこぼしが起きる。そこでselectionchangeを主、ポインタの上下を
   * 「ドラッグ確定の合図」として併用する。
   *   - 選択が空になったら即座に閉じる
   *   - ドラッグ中(ポインタ押下中)は確定しない
   *   - ツールバー自身の上での操作では何も動かさない
   */
  useEffect(() => {
    let pointerDown = false;
    let onOwnUi = false;
    let frame = 0;

    const evaluate = () => {
      // ノート編集中は選択UIを一切動かさない(閉じるのは Cancel / Save / Esc)。
      if (noteEditorOpenRef.current) return;

      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
        setSelection(null);
        setShowHighlightRow(false);
        setShowColors(false);
        return;
      }

      // ノート編集中のtextarea内の選択には反応しない。
      const anchor = sel.anchorNode;
      const anchorElement =
        anchor instanceof HTMLElement ? anchor : (anchor?.parentElement ?? null);
      if (anchorElement?.closest('[data-annotation-ui]')) return;

      // まずブロック内に収まっている選択、無ければブロックにクリップして拾う。
      const blocks = [...blocksRef.current.values()];
      for (const pass of [false, true]) {
        for (const block of blocks) {
          const offsets = readSelectionOffsets(block.element, { clip: pass });
          if (!offsets) continue;
          setShowHighlightRow(false);
          setShowColors(false);
          setSelection({
            blockIdx: block.blockIdx,
            startIdx: offsets.startIdx,
            endIdx: offsets.endIdx,
            text: offsets.text,
            rawMarkdown: block.rawMarkdown,
            flattenedText: block.element.textContent ?? '',
            rect: offsets.rect,
          });
          return;
        }
      }
      setSelection(null);
    };

    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(evaluate);
    };

    const isOwnUi = (target: EventTarget | null) =>
      target instanceof Element && Boolean(target.closest('[data-annotation-ui]'));

    const onPointerDown = (event: PointerEvent) => {
      onOwnUi = isOwnUi(event.target);
      pointerDown = !onOwnUi;
    };

    const onPointerUp = (event: PointerEvent) => {
      const ownUi = onOwnUi || isOwnUi(event.target);
      pointerDown = false;
      onOwnUi = false;
      if (!ownUi) schedule();
    };

    const onSelectionChange = () => {
      if (onOwnUi) return;
      const sel = window.getSelection();
      // 解除はドラッグ中でも即座に反映する(掴み直しで古いメニューが残らない)。
      if (!sel || sel.isCollapsed) {
        schedule();
        return;
      }
      if (!pointerDown) schedule();
    };

    document.addEventListener('selectionchange', onSelectionChange);
    document.addEventListener('pointerdown', onPointerDown, true);
    document.addEventListener('pointerup', onPointerUp, true);
    document.addEventListener('pointercancel', onPointerUp, true);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener('selectionchange', onSelectionChange);
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('pointerup', onPointerUp, true);
      document.removeEventListener('pointercancel', onPointerUp, true);
    };
  }, []);

  useEffect(() => {
    noteEditorOpenRef.current = noteEditor !== null;
  }, [noteEditor]);

  // カード内をスクロールしてもメニューが選択範囲に貼りついたままになるよう、
  // 位置だけ追従させる(fixed配置なのでスクロールでは自動的にはずれる)。
  const hasSelection = selection !== null;
  useEffect(() => {
    if (!hasSelection) return;
    let frame = 0;
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
        const rect = sel.getRangeAt(0).getBoundingClientRect();
        setSelection((prev) => (prev ? { ...prev, rect } : prev));
      });
    };
    window.addEventListener('scroll', onScroll, true);
    window.addEventListener('resize', onScroll);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener('scroll', onScroll, true);
      window.removeEventListener('resize', onScroll);
    };
  }, [hasSelection]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      dismiss();
      setNoteEditor(null);
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [dismiss]);

  const runWrite = async (write: () => Promise<ContentMetadata>) => {
    setBusy(true);
    try {
      onMetadataChange(await write());
    } finally {
      setBusy(false);
    }
  };

  const applyHighlight = async (nextStyle: HighlightStyle) => {
    if (!selection) return;
    setStyle(nextStyle);
    store(STYLE_KEY, nextStyle);
    store(COLOR_KEY, color);
    await runWrite(() =>
      addAnnotation(table, rowId, metadata, {
        blockIdx: selection.blockIdx,
        startIdx: selection.startIdx,
        endIdx: selection.endIdx,
        annotatedWords: selection.text,
        annotationType: 'highlight',
        contents: { type: nextStyle, color },
      })
    );
    dismiss();
  };

  const erase = async () => {
    if (!selection) return;
    await runWrite(() =>
      eraseAnnotationsInRange(
        table,
        rowId,
        metadata,
        selection.blockIdx,
        selection.startIdx,
        selection.endIdx
      )
    );
    dismiss();
  };

  const startNote = () => {
    if (!selection) return;
    noteEditorOpenRef.current = true;
    setNoteEditor({
      blockIdx: selection.blockIdx,
      startIdx: selection.startIdx,
      endIdx: selection.endIdx,
      annotatedWords: selection.text,
      draft: '',
      rect: selection.rect,
    });
    setSelection(null);
  };

  const saveNote = async () => {
    if (!noteEditor) return;
    const draft = noteEditor.draft.trim();
    if (!draft) return;

    if (noteEditor.annotation) {
      const id = noteEditor.annotation.id;
      await runWrite(() => updateNoteContents(table, rowId, metadata, id, draft));
    } else {
      await runWrite(() =>
        addAnnotation(table, rowId, metadata, {
          blockIdx: noteEditor.blockIdx,
          startIdx: noteEditor.startIdx,
          endIdx: noteEditor.endIdx,
          annotatedWords: noteEditor.annotatedWords,
          annotationType: 'notes',
          contents: draft,
        })
      );
    }
    setNoteEditor(null);
    window.getSelection()?.removeAllRanges();
  };

  const deleteNote = async () => {
    if (!noteEditor?.annotation) return;
    const id = noteEditor.annotation.id;
    await runWrite(() => removeAnnotation(table, rowId, metadata, id));
    setNoteEditor(null);
  };

  const copySelection = async () => {
    if (!selection) return;
    try {
      await navigator.clipboard.writeText(selection.text);
    } catch {
      /* クリップボード権限がない場合は黙って無視 */
    }
    dismiss();
  };

  const source = useMemo(
    () =>
      selection
        ? findSourceForSelection(
            selection.rawMarkdown,
            selection.flattenedText,
            selection.startIdx,
            selection.endIdx
          )
        : null,
    [selection]
  );

  const jumpToSource = () => {
    const sids = source?.sidStrings ?? [];
    dismiss();
    if (sids.length === 0) return;
    if (onOpenSource) onOpenSource(sids);
    else navigate(`/lectures/${lectureId}/transcript?sids=${sids.join(',')}`);
  };

  const hasSource = (source?.sidStrings.length ?? 0) > 0;

  const contextValue = useMemo(
    () => ({ registerBlock, unregisterBlock, openAnnotation }),
    [registerBlock, unregisterBlock, openAnnotation]
  );

  return (
    <AnnotationContext.Provider value={contextValue}>
      {children}

      {selection && (
        <div
          data-annotation-ui
          className="annotation-toolbar"
          style={floatingStyle(selection.rect, 320)}
          onMouseDown={(e) => e.preventDefault()}
        >
          <div className="annotation-toolbar-row">
            <button
              type="button"
              className={showHighlightRow ? 'is-active' : ''}
              onClick={() => setShowHighlightRow((v) => !v)}
            >
              <span className="annotation-swatch" style={{ background: color }} />
              Highlight
            </button>
            <button type="button" onClick={startNote}>
              Note
            </button>
            {hasSource && (
              <button type="button" onClick={jumpToSource}>
                Source
              </button>
            )}
            <button type="button" onClick={copySelection}>
              Copy
            </button>
          </div>

          {showHighlightRow && (
            <div className="annotation-toolbar-row annotation-toolbar-sub">
              <button
                type="button"
                className={style === 'line' ? 'is-active' : ''}
                onClick={() => applyHighlight('line')}
                disabled={busy}
                title="Underline"
              >
                <span className="hl-preview hl-preview-line" style={{ ['--hl' as string]: color }}>
                  Aa
                </span>
              </button>
              <button
                type="button"
                className={style === 'wave' ? 'is-active' : ''}
                onClick={() => applyHighlight('wave')}
                disabled={busy}
                title="Wavy underline"
              >
                <span className="hl-preview hl-preview-wave" style={{ ['--hl' as string]: color }}>
                  Aa
                </span>
              </button>
              <button
                type="button"
                className={style === 'marker' ? 'is-active' : ''}
                onClick={() => applyHighlight('marker')}
                disabled={busy}
                title="Marker"
              >
                <span className="hl-preview hl-preview-marker" style={{ ['--hl' as string]: color }}>
                  Aa
                </span>
              </button>
              <button type="button" onClick={erase} disabled={busy} title="Erase annotations here">
                Erase
              </button>
              <span className="annotation-toolbar-divider" />
              <button
                type="button"
                className={showColors ? 'is-active' : ''}
                onClick={() => setShowColors((v) => !v)}
                title="Colour"
              >
                <span className="annotation-swatch" style={{ background: color }} />
              </button>
            </div>
          )}

          {showHighlightRow && showColors && (
            <div className="annotation-color-grid">
              {HIGHLIGHT_PRESET_COLORS.map((preset) => (
                <button
                  key={preset}
                  type="button"
                  className={preset === color ? 'is-active' : ''}
                  style={{ background: preset }}
                  onClick={() => {
                    setColor(preset);
                    store(COLOR_KEY, preset);
                  }}
                  aria-label={preset}
                />
              ))}
            </div>
          )}
        </div>
      )}

      {noteEditor && (
        <div
          data-annotation-ui
          className="annotation-note-editor"
          style={floatingStyle(noteEditor.rect, 320)}
          onMouseDown={(e) => e.stopPropagation()}
        >
          <p className="annotation-note-anchor">“{noteEditor.annotatedWords}”</p>
          <textarea
            autoFocus
            rows={4}
            value={noteEditor.draft}
            placeholder="Write a note…"
            onChange={(e) => setNoteEditor((prev) => (prev ? { ...prev, draft: e.target.value } : prev))}
          />
          <div className="annotation-note-actions">
            {noteEditor.annotation && (
              <button type="button" className="danger" onClick={deleteNote} disabled={busy}>
                Delete
              </button>
            )}
            <button type="button" className="ghost" onClick={() => setNoteEditor(null)}>
              Cancel
            </button>
            <button type="button" onClick={saveNote} disabled={busy || !noteEditor.draft.trim()}>
              Save
            </button>
          </div>
        </div>
      )}
    </AnnotationContext.Provider>
  );
};
