// lib/presentation/widgets/ai_chat/launch_gate_backdrop.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';
import 'package:lefture/presentation/widgets/ai_chat/thinking_nebula.dart';

/// AIチャットのシートを開いて、まだ何も話していないときの背景「出発ゲート」。
///
/// 惑星の地平線を描き、その上に文言と質問の候補を重ねる。宇宙の画面では夜
/// (地平線から光がのぞき、流れ星が流れる)、紙の画面では夜明け(紙の色から朝焼けの空、
/// 昇りかけの太陽、地球の弧の内側に水色→黄緑のにじみ、明けの明星とインクの星4つ)。
/// 式の正本は docs/chatbot_motion_reference.html(webappのcanvasも同じ式を使う)。
/// 地平線は高さの40%の位置。文言はその下(惑星の上)に置く想定。
class LaunchGateBackdrop extends StatefulWidget {
  const LaunchGateBackdrop({super.key, required this.world});

  final ChatWorld world;

  @override
  State<LaunchGateBackdrop> createState() => _LaunchGateBackdropState();
}

class _LaunchGateBackdropState extends State<LaunchGateBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / 1e6 * _speed;
    })..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _speed = reduceMotion ? 0.25 : 1;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 惑星の円は画面より大きいので、枠の外へはみ出さないよう切り抜く
    return RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: widget.world == ChatWorld.paper
              ? _DawnGatePainter(_time)
              : _NightGatePainter(_time),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 共通
// ---------------------------------------------------------------------------

const _tau = math.pi * 2;
const _gold = Color(0xFFFFB300);
const _deepGold = Color(0xFFCC8D00);
const _blue = Color(0xFF42A5F5);

double _ease(double t) =>
    t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

class _Star {
  const _Star(this.x, this.y, this.r, this.speed, this.phase);
  final double x, y, r, speed, phase;
}

/// 背景の星(位置は固定の乱数で、開くたびに同じ並び)。
final List<_Star> _gateStars = () {
  final random = math.Random(11);
  return List.generate(
    110,
    (_) => _Star(
      random.nextDouble(),
      random.nextDouble(),
      .35 + random.nextDouble() * 1.05,
      .6 + random.nextDouble() * 1.8,
      random.nextDouble() * _tau,
    ),
  );
}();

/// 惑星の円(地平線の頂点が高さの40%)と、太陽が出る地平線上の点。
({double radius, Offset center, Offset sun}) _planet(Size size) {
  final w = size.width, h = size.height;
  final radius = w * 1.25;
  final center = Offset(w * .62, h * .4 + radius);
  final fx = w * .4;
  final fy =
      center.dy - math.sqrt(radius * radius - math.pow(fx - center.dx, 2));
  return (radius: radius, center: center, sun: Offset(fx, fy));
}

/// 同心円の放射グラデーションで、内側の半径[inner]より内は最初の色のまま、
/// [inner]〜[outer]の間で色を変えるときの止まり位置(canvasのcreateRadialGradient(r0, r1)と同じ見え方)。
List<double> _ringStops(double inner, double outer, List<double> stops) => [
  for (final s in stops) inner / outer + (1 - inner / outer) * s,
];

/// 地平線の弧(左上から右上の上半分の一部)。
void _strokeHorizon(Canvas canvas, Offset center, double radius, Paint paint) {
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: radius),
    math.pi * 1.2,
    math.pi * .6,
    false,
    paint,
  );
}

/// 流れ星の周期(秒)。このうち最初の1秒で流れる。
const _meteorCycle = 4.6;

/// 流れ星の落ちる角度(水平から下向き)。夜空の高さによらず一定。
const _meteorAngle = 24 * math.pi / 180;

/// ある瞬間の流れ星の頭と尾の位置。
typedef MeteorPose = ({Offset head, Offset tail});

/// 流れ星の位置。[k]は流れ始めてからの秒数(0〜1で流れ、1以上は見えない)。
///
/// 進む向きと尾の向きは同じ(いつも[_meteorAngle])。夜空が低いときは、角度を変えずに
/// 飛ぶ距離と尾を縮めて、星空の帯(上から約38%)に収める。つまり低いシートでは、
/// 同じ角度で落ちる小さな流れ星になる。
@visibleForTesting
MeteorPose? meteorPose(Size size, double k) {
  if (k < 0 || k >= 1) return null;
  final w = size.width, h = size.height;
  final dir = Offset(math.cos(_meteorAngle), math.sin(_meteorAngle));
  // 幅の半分だけ横へ進む道のり。ただし縦は、星空の帯(高さの34%)に収まる範囲まで
  final wide = w * .5 / dir.dx;
  final distance = math.min(wide, h * .34 / dir.dy);
  // 帯の中で左右の真ん中に寄せる
  final start = Offset(w * .25 + (w * .5 - distance * dir.dx) / 2, h * .04);
  final head = start + dir * (distance * _ease(k));
  final tail = head - dir * (distance * .36 * math.sin(math.pi * k));
  return (head: head, tail: tail);
}

/// 流れ星(4.6秒に1回、1秒かけて流れる)。
void _paintShootingStar(Canvas canvas, Size size, double t, Color color) {
  final pose = meteorPose(size, t % _meteorCycle);
  if (pose == null) return;
  canvas.drawLine(
    pose.head,
    pose.tail,
    Paint()
      ..strokeWidth = 1.6
      ..shader = ui.Gradient.linear(pose.head, pose.tail, [
        color.withValues(alpha: .95),
        color.withValues(alpha: 0),
      ]),
  );
}

// ---------------------------------------------------------------------------
// 夜(宇宙の画面)
// ---------------------------------------------------------------------------

class _NightGatePainter extends CustomPainter {
  _NightGatePainter(this.time) : super(repaint: time);

  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), const [
          Color(0xFF0B0E1C),
          Color(0xFF141936),
        ]),
    );

    final starPaint = Paint();
    for (final st in _gateStars) {
      final a = .2 + .6 * (.5 + .5 * math.sin(t * st.speed + st.phase));
      starPaint.color = const Color(0xFFECF0FF).withValues(alpha: a);
      canvas.drawCircle(Offset(st.x * w, st.y * h * .42), st.r, starPaint);
    }
    _paintShootingStar(canvas, size, t, Colors.white);

    final planet = _planet(size);
    final pulse = .72 + .28 * math.sin(t * 1.1);

    // 地平線の外側の大気(太陽の金から、離れると青)
    final atmosphereRadius = planet.radius * 1.13;
    canvas.drawCircle(
      planet.center,
      atmosphereRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          planet.center,
          atmosphereRadius,
          [
            _gold.withValues(alpha: 0),
            _gold.withValues(alpha: .3 * pulse),
            _blue.withValues(alpha: .13 * pulse),
            _blue.withValues(alpha: 0),
          ],
          _ringStops(planet.radius * .97, atmosphereRadius, const [
            0,
            .22,
            .55,
            1,
          ]),
        ),
    );

    // 惑星: 上の方が少し青みを帯びた夜の色
    canvas.drawCircle(
      planet.center,
      planet.radius,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, planet.center.dy - planet.radius),
          Offset(0, h),
          const [Color(0xFF1C2550), Color(0xFF0F1430), Color(0xFF0B0E1D)],
          const [0, .12, 1],
        ),
    );

    _strokeHorizon(
      canvas,
      planet.center,
      planet.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          [
            _blue.withValues(alpha: .2),
            _gold.withValues(alpha: .95 * pulse),
            _blue.withValues(alpha: .25),
          ],
          const [0, .42, 1],
        ),
    );

    // 地平線からのぞく光
    final flareRadius = w * .18;
    canvas.drawCircle(
      planet.sun,
      flareRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          planet.sun,
          flareRadius,
          [
            const Color(0xFFFFECBE).withValues(alpha: .9 * pulse),
            _gold.withValues(alpha: .35 * pulse),
            _gold.withValues(alpha: 0),
          ],
          const [0, .2, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _NightGatePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 夜明け(紙の画面)
// ---------------------------------------------------------------------------

const _sky = Color(0xFF5C96D6);
const _lime = Color(0xFFA8CD60);

/// 明け方に残っている星(x, y, 大きさ, 瞬きの速さ)。明けの明星は別に描く。
const _dawnStars = [
  (.14, .07, 1.5, 1.7),
  (.36, .04, 1.1, 2.3),
  (.6, .16, 1.3, 1.9),
  (.9, .24, 1.05, 2.6),
];

/// 太陽の光の筋の数(全周)。
const _sunRayCount = 36;

/// 光の筋が回る速さ(ラジアン/秒)。
const _sunRaySpeed = .04;

/// 太陽のまわりの全周に引く光の筋の角度。[rotation]だけ回った状態。
/// 筋は等間隔なので、どれだけ回っても、地平線の上に見える筋の数はほぼ一定(半分の18本ほど)。
@visibleForTesting
List<double> sunRayAngles(double rotation) => [
  for (var k = 0; k < _sunRayCount; k++) rotation + k * _tau / _sunRayCount,
];

class _DawnGatePainter extends CustomPainter {
  _DawnGatePainter(this.time) : super(repaint: time);

  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // 空: 紙の色から朝焼けへ(上に青は入れない)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h * .5),
          const [Color(0xFFFAF5E9), Color(0xFFFBF0DE), Color(0xFFFBE3C4)],
          const [0, .55, 1],
        ),
    );

    // 消えかけの淡い星(上ほど見える)
    final starPaint = Paint();
    for (final st in _gateStars) {
      final y = st.y * h * .3;
      final fade = 1 - y / (h * .3);
      final a =
          (.15 + .3 * (.5 + .5 * math.sin(t * st.speed + st.phase))) * fade;
      starPaint.color = chatInkColor.withValues(alpha: a * .6);
      canvas.drawCircle(Offset(st.x * w, y), st.r * .7, starPaint);
    }

    final planet = _planet(size);
    final sun = planet.sun;
    final pulse = .75 + .25 * math.sin(t * 1.1);
    final rise = .5 + .5 * math.sin(t * .35);

    // 太陽のまわりの金の光
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          sun,
          w * .62,
          [
            _gold.withValues(alpha: .5 * pulse),
            const Color(0xFFFFC878).withValues(alpha: .22 * pulse),
            const Color(0xFFFFDCAA).withValues(alpha: 0),
          ],
          const [0, .35, 1],
        ),
    );

    // ゆっくり回る光の筋。太陽のまわり全周に引いておき、地平線の下は、あとで描く地球が隠す
    // (半円だけだと、回るにつれて筋が地球の下へ入って、見える筋が減っていく)
    final rayPaint = Paint()
      ..color = _deepGold.withValues(alpha: .16)
      ..strokeWidth = 1;
    for (final a in sunRayAngles(t * _sunRaySpeed)) {
      canvas.drawLine(
        sun + Offset(math.cos(a), math.sin(a)) * (w * .1),
        sun + Offset(math.cos(a), math.sin(a)) * (w * .42),
        rayPaint,
      );
    }

    // 昇りかけの太陽(下半分は地球に隠れる)
    final sunRadius = w * .085;
    final sunCenter = Offset(sun.dx, sun.dy + sunRadius * (.55 - .25 * rise));
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          sunCenter,
          sunRadius,
          const [Color(0xFFFFF6DC), Color(0xFFFFCD5A), Color(0xF2FFB300)],
          const [0, .6, 1],
        ),
    );

    // 地球: 紙の色。弧に沿って、縁の内側が水色 → 黄緑 → 紙(透明)の順に溶ける
    canvas.drawCircle(
      planet.center,
      planet.radius,
      Paint()..color = chatPaperColor,
    );
    canvas.drawCircle(
      planet.center,
      planet.radius,
      Paint()
        ..shader = ui.Gradient.radial(
          planet.center,
          planet.radius,
          [
            _lime.withValues(alpha: 0),
            _lime.withValues(alpha: .13),
            Color.lerp(_lime, _sky, .5)!.withValues(alpha: .24),
            _sky.withValues(alpha: .38),
          ],
          _ringStops(planet.radius * .86, planet.radius, const [0, .38, .7, 1]),
        ),
    );

    _strokeHorizon(
      canvas,
      planet.center,
      planet.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          [
            _sky.withValues(alpha: .5),
            _deepGold.withValues(alpha: .9 * pulse),
            _sky.withValues(alpha: .55),
          ],
          const [0, .4, 1],
        ),
    );

    // 明け方に残っている星と、明けの明星(金星)
    for (final (sx, sy, sr, speed) in _dawnStars) {
      final a = .55 + .35 * (.5 + .5 * math.sin(t * speed + sx * 9));
      final r = sr * (1 + .15 * math.sin(t * speed * 1.3 + sy * 7));
      paintInkDot(
        canvas,
        Offset(sx * w, sy * h),
        r,
        chatInkColor,
        alpha: a,
        bright: sr >= 1.4,
      );
    }
    paintInkDot(
      canvas,
      Offset(w * .8, h * .12),
      2.2 * (1 + .25 * math.sin(t * 2.3)),
      _deepGold,
      bright: true,
    );
  }

  @override
  bool shouldRepaint(covariant _DawnGatePainter oldDelegate) => false;
}
