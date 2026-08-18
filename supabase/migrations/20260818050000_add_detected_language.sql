-- 「録音言語 自動判定」機能のための、Whisperが実際に検出した言語の保存先。
--
-- 背景: lectures.recording_language はユーザーが明示的に選んだ(または
-- 自動判定を選んで未設定のままにした)値でしかなく、実際にWhisperが
-- 文字起こしした言語と一致する保証がない(ユーザーの選択ミスや、日英混在の
-- 授業などで特に)。Core Extraction/Review Cards向けの言語解決
-- (_get_content_language_context)がこれまでrecording_languageだけを見て
-- いたため、未設定(自動判定)の講義では常に"English"にフォールバックし、
-- 原語併記(is_bilingual)機能も常に無効化されていた。
--
-- 検出言語を実際に保存し、それを元に解決することで、この問題を解消する。
-- 保存先を2つに分けているのは、リアルタイム録音とプレレコで文字起こしの
-- 単位が違うため:
--   - リアルタイム: チャンクごとに文字起こしされるので、チャンクごとに
--     lecture_transcripts.detected_languageへ保存する
--     (講義全体の言語は、後で複数チャンクの多数決から解決する)。
--   - プレレコ: マスター音声を1回で文字起こしするため、講義1件につき
--     1値をlectures.detected_recording_languageへ保存する
--     (プレレコはlecture_transcriptsに行を作らないため)。

ALTER TABLE public.lecture_transcripts
  ADD COLUMN detected_language text;

COMMENT ON COLUMN public.lecture_transcripts.detected_language IS
  'Whisperがこのチャンクの音声から実際に検出した言語コード(ISO-639-1)。ユーザーが選んだrecording_languageとは独立。';

ALTER TABLE public.lectures
  ADD COLUMN detected_recording_language text;

COMMENT ON COLUMN public.lectures.detected_recording_language IS
  'プレレコ講義でWhisperが実際に検出した言語コード(ISO-639-1)。マスター音声1本につき1値。リアルタイム講義ではlecture_transcripts.detected_languageの多数決を都度計算するため使わない。';
