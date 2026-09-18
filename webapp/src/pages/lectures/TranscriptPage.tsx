import React, { useCallback, useMemo } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { TranscriptView } from '../../components/transcript/TranscriptView';

/**
 * 文字起こし＆音声の全画面ページ。
 * 中身は出典シートと共通の TranscriptView。
 */
export const TranscriptPage: React.FC = () => {
  const { lectureId } = useParams<{ lectureId: string }>();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const highlightSids = useMemo(
    () => new Set((searchParams.get('sids') ?? '').split(',').filter(Boolean)),
    [searchParams]
  );

  const close = useCallback(() => navigate(`/lectures/${lectureId}`), [navigate, lectureId]);

  return (
    <div className="pv-root is-gold">
      <div className="pv-split">
        <div className="pv-column">
          <TranscriptView
            lectureId={lectureId!}
            highlightSids={highlightSids}
            onClose={close}
            variant="page"
          />
        </div>
      </div>
    </div>
  );
};
