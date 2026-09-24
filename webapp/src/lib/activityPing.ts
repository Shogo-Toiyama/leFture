import { supabase } from './supabase';

/**
 * 「ユーザーがアプリを使っている」ことをSupabaseに記録する(ping)。
 *
 * ■ なぜこれが要るのか
 * アクティブユーザーを auth.users.last_sign_in_at から測ることはできない。
 * GoTrueがあれを更新するのは明示的なサインイン(パスワード/OAuth/OTP)の
 * ときだけで、リフレッシュトークンによるセッション更新では更新されないため、
 * 「毎日使っているのに最終ログインは3ヶ月前」が普通に起きる。
 * かといって lectures や review_cards の updated_at から推測すると、機能が
 * 増えるたびに集計の定義を更新し続けることになり、更新し忘れた機能は静かに
 * 計測から漏れる。だから「使っている」を明示的に1経路で記録する。
 *
 * ■ なぜ10分おきなのか
 * サーバー側(user_activity_hours)は (user_id, 時, platform) が主キーなので、
 * 10分おきに打っても同じ1時間の行にUPSERTで畳み込まれる —— つまり行数は
 * 「実際に触った時間数」しか増えない。増えるのは ping_count で、これが
 * 「その1時間をどれだけ使ったか」(最大6)を表す。行数据え置きで時間内の
 * 解像度が得られるのが狙い。起動時だけのpingでは、2時間の授業が
 * 「開始時刻の1行」に潰れてしまう。
 *
 * ■ 失敗しても何もしない
 * これは計測であって機能ではない。ネットワークが切れていようがRPCが
 * 失敗しようが、ユーザーの操作を妨げてはいけない。
 */

const PING_INTERVAL_MS = 10 * 60 * 1000;

/**
 * 直前のpingからこの時間が経っていなければ送らない。
 * タブを複数開いている場合、localStorageは同一ブラウザで共有されるので
 * この値がタブ間の重複pingも抑える。インターバルより少し短くしてあるのは、
 * setIntervalの発火が数ミリ秒遅れただけでスキップされるのを避けるため。
 */
const PING_THROTTLE_MS = 9 * 60 * 1000;

const LAST_PING_KEY = 'lefture.activityPing.lastAt';

function lastPingAt(): number {
  try {
    return Number(localStorage.getItem(LAST_PING_KEY)) || 0;
  } catch {
    // プライベートブラウジング等でlocalStorageが例外を投げることがある。
    // その場合はスロットルが効かないだけで、pingは打てる。
    return 0;
  }
}

function rememberPing(at: number): void {
  try {
    localStorage.setItem(LAST_PING_KEY, String(at));
  } catch {
    /* 上と同じ理由で握りつぶす */
  }
}

async function sendPing(): Promise<void> {
  const now = Date.now();
  if (now - lastPingAt() < PING_THROTTLE_MS) return;

  // 先に記録してから送る。RPCの応答を待つ間に別タブが同じpingを打つのを防ぐ。
  rememberPing(now);

  try {
    await supabase.rpc('touch_activity', {
      p_platform: 'web',
      // ★ getTimezoneOffset()は「UTCからどれだけ遅れているか」を正で返す
      //   (LA = +420)。サーバー側は東を正(LA = -420)で持つので符号を反転する。
      p_tz_offset_minutes: -new Date().getTimezoneOffset(),
    });
  } catch {
    /* 計測の失敗でアプリを止めない */
  }
}

/**
 * pingの送出を開始する。戻り値を呼ぶと停止する。
 *
 * タブが見えていない間はタイマーを止める —— 開きっぱなしで放置された
 * タブを「使っている」と数えると、利用時間帯の分布が意味を失うため。
 */
export function startActivityPing(): () => void {
  let timer: ReturnType<typeof setInterval> | null = null;

  const stopTimer = () => {
    if (timer !== null) {
      clearInterval(timer);
      timer = null;
    }
  };

  const startTimer = () => {
    if (timer === null) timer = setInterval(() => void sendPing(), PING_INTERVAL_MS);
  };

  const onVisibilityChange = () => {
    if (document.visibilityState === 'visible') {
      void sendPing();
      startTimer();
    } else {
      stopTimer();
    }
  };

  document.addEventListener('visibilitychange', onVisibilityChange);
  onVisibilityChange();

  return () => {
    document.removeEventListener('visibilitychange', onVisibilityChange);
    stopTimer();
  };
}
