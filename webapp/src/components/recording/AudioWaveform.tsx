import React, { useEffect, useRef } from 'react';

/**
 * 録音中の音量を、25本のバーの波形で見せる。
 * Flutter版(presentation/pages/recording/widgets/audio_waveform_visualizer.dart)の移植:
 * 新しい音量を右端に足して左へ流す / 中央ほど高くなる包絡線 / 大きい音はゴールドに光る /
 * 録音中の無音は低いゴールドのバー、一時停止中は灰色の点。
 */
const BAR_COUNT = 25;
const HEIGHT = 72;
const SAMPLE_MS = 100;
/** 横長のパネルでもバーが太りすぎないよう上限を設ける(Flutterのスマホ幅だと約8px) */
const MAX_BAR_WIDTH = 12;
/** 大きい音のときのぼかし(blur 6px)が上下で切れないための余白 */
const GLOW_PAD = 7;

interface AudioWaveformProps {
  /** 現在の音量(0〜1)を返す。録音中だけ一定間隔で呼ばれる */
  getLevel: () => number;
  isRecording: boolean;
}

export const AudioWaveform: React.FC<AudioWaveformProps> = ({ getLevel, isRecording }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const historyRef = useRef<number[]>(Array(BAR_COUNT).fill(0));

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const draw = () => {
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      const dpr = window.devicePixelRatio || 1;
      const width = canvas.clientWidth;
      if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(HEIGHT * dpr)) {
        canvas.width = Math.round(width * dpr);
        canvas.height = Math.round(HEIGHT * dpr);
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, HEIGHT);

      const levels = historyRef.current;
      const barWidth = Math.min(MAX_BAR_WIDTH, (width * 0.6) / BAR_COUNT);
      const spacing = (width - barWidth * BAR_COUNT) / (BAR_COUNT - 1);
      const centerY = HEIGHT / 2;
      const minBarHeight = isRecording ? 7 : 3.5;
      // 線の端は丸く描くので、端がバーの太さの半分ずつ上下にはみ出す。その分とぼかしの分を引いた高さが上限
      const maxBarHeight = HEIGHT - barWidth - GLOW_PAD * 2;
      ctx.lineCap = 'round';

      for (let i = 0; i < BAR_COUNT; i++) {
        const x = i * (barWidth + spacing) + barWidth / 2;
        const normalizedIndex = Math.abs(i - BAR_COUNT / 2) / (BAR_COUNT / 2);
        const envelope = Math.sin(((1 - normalizedIndex) * Math.PI) / 2);
        const level = levels[i];
        const barHeight = minBarHeight + (maxBarHeight - minBarHeight) * level * envelope;
        const y1 = centerY - barHeight / 2;
        const y2 = centerY + barHeight / 2;

        let color: string;
        if (isRecording) {
          color =
            level > 0.04
              ? `hsla(${42 + level * 10}, 90%, 60%, ${Math.min(1, 0.5 + level * 0.5)})`
              : 'rgba(255, 179, 0, 0.35)';
        } else {
          color = 'rgba(142, 153, 166, 0.25)';
        }

        // 大きな音の時だけ外側にぼかした光を重ねる
        if (isRecording && level > 0.3) {
          ctx.save();
          ctx.strokeStyle = `rgba(255, 179, 0, ${Math.min(0.4, level * 0.25)})`;
          ctx.lineWidth = barWidth * 1.5;
          ctx.filter = 'blur(6px)';
          ctx.beginPath();
          ctx.moveTo(x, y1);
          ctx.lineTo(x, y2);
          ctx.stroke();
          ctx.restore();
        }

        ctx.strokeStyle = color;
        ctx.lineWidth = barWidth;
        ctx.beginPath();
        ctx.moveTo(x, y1);
        ctx.lineTo(x, y2);
        ctx.stroke();
      }
    };

    if (!isRecording) {
      // 停止・一時停止中は完全にフラット
      historyRef.current = Array(BAR_COUNT).fill(0);
      draw();
      return;
    }

    const timer = window.setInterval(() => {
      // 小さな声でも見やすく立ち上がる感度カーブ(Flutter版と同じ)
      const boosted = Math.min(1, Math.max(0, Math.pow(getLevel(), 0.6) * 1.1));
      historyRef.current = [...historyRef.current.slice(1), boosted];
      draw();
    }, SAMPLE_MS);
    draw();

    const onResize = () => draw();
    window.addEventListener('resize', onResize);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener('resize', onResize);
    };
  }, [getLevel, isRecording]);

  return <canvas ref={canvasRef} className="rec-waveform" style={{ height: HEIGHT }} aria-hidden="true" />;
};
