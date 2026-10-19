// lib/presentation/widgets/ai_chat/thinking_nebula.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// AIが探したり考えたりしているあいだ、回答欄に出す「星雲のかたち」。
///
/// 10の形(惑星・光芒・花・三つ葉・五芒星・八方の光・土星・連星・太陽のコロナ・彗星)を、
/// 形も色もランダムに、直前と同じものは出さずにめぐる。1つの形は2秒で、最初の0.85秒で
/// 前の形から移り変わる。表示するたびに違う順番で始まる。
/// 式の正本は docs/chatbot_motion_reference.html(webappのcanvasも同じ式を使う)。
/// 端末で「視差効果を減らす」がオンのときは4分の1の速さにする。
class ThinkingNebula extends StatefulWidget {
  const ThinkingNebula({super.key, required this.world, this.size = 40});

  final ChatWorld world;
  final double size;

  @override
  State<ThinkingNebula> createState() => _ThinkingNebulaState();
}

class _ThinkingNebulaState extends State<ThinkingNebula>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final _sequence = _NebulaSequence(math.Random());
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
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _NebulaPainter(
          time: _time,
          sequence: _sequence,
          world: widget.world,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 形と色の並び
// ---------------------------------------------------------------------------

const _segmentSeconds = 2.0;
const _transitionSeconds = 0.85;

/// 形と色の並び。前・今・次の3つだけを覚えておき、区切りが進んだら1つずらして
/// 次をランダムに引く(直前と同じものは引き直す)。
class _NebulaSequence {
  _NebulaSequence(this._random) {
    _shapes = [_pickShape(-1), 0, 0];
    _shapes[1] = _pickShape(_shapes[0]);
    _shapes[2] = _pickShape(_shapes[1]);
    _colors = [_pickColor(-1), 0, 0];
    _colors[1] = _pickColor(_colors[0]);
    _colors[2] = _pickColor(_colors[1]);
  }

  final math.Random _random;
  late final List<int> _shapes;
  late final List<int> _colors;
  int _segment = 1;

  int _pickShape(int previous) {
    int next;
    do {
      next = _random.nextInt(_nebulaShapes.length);
    } while (next == previous);
    return next;
  }

  int _pickColor(int previous) {
    int next;
    do {
      next = _random.nextInt(5);
    } while (next == previous);
    return next;
  }

  /// 時刻tの区切り。戻り値は(前の形, 今の形, 前の色, 今の色, 区切りの中の経過秒)。
  ({int fromShape, int toShape, int fromColor, int toColor, double sec}) at(
    double t,
  ) {
    final tt = math.max(0.0, t) + _segmentSeconds;
    final segment = (tt / _segmentSeconds).floor();
    while (_segment < segment) {
      _segment++;
      _shapes
        ..removeAt(0)
        ..add(_pickShape(_shapes.last));
      _colors
        ..removeAt(0)
        ..add(_pickColor(_colors.last));
    }
    return (
      fromShape: _shapes[0],
      toShape: _shapes[1],
      fromColor: _colors[0],
      toColor: _colors[1],
      sec: tt - segment * _segmentSeconds,
    );
  }
}

// ---------------------------------------------------------------------------
// 形: 角度ごとの半径(最大が1になるように正規化)
// ---------------------------------------------------------------------------

const _samples = 200;
const _tau = math.pi * 2;

Float32List _shape(double Function(double theta) fn) {
  final r = Float32List(_samples);
  var max = 0.0;
  for (var i = 0; i < _samples; i++) {
    r[i] = fn(i / _samples * _tau);
    max = math.max(max, r[i]);
  }
  for (var i = 0; i < _samples; i++) {
    r[i] /= max;
  }
  return r;
}

/// k枚の花びら・光の筋。pが大きいほど筋が鋭くなる。
double Function(double) _lobes(double base, double amp, int k, double p) =>
    (th) => base + amp * math.pow(math.cos(k * th / 2).abs(), p).toDouble();

final List<Float32List> _nebulaShapes = [
  _shape((_) => 1), // 惑星
  _shape(_lobes(.3, .7, 4, 9)), // 光芒
  _shape(_lobes(.6, .4, 6, 2.2)), // 花
  _shape(_lobes(.5, .5, 3, 1.3)), // 三つ葉
  _shape(_lobes(.42, .58, 5, 2.6)), // 五芒星
  _shape(_lobes(.28, .72, 8, 14)), // 八方の光
  _shape((th) {
    // 土星: 傾いた細い楕円(環)と、円(本体)の外側
    const phi = -.35;
    final c = math.cos(th - phi), s = math.sin(th - phi);
    return math.max(1 / math.sqrt(c * c + math.pow(s / .3, 2)), .58);
  }),
  _shape(_lobes(.55, .45, 2, 1.6)), // 連星
  _shape(_lobes(.82, .18, 12, 1.2)), // 太陽のコロナ
  _shape(
    (th) => .5 + .5 * math.pow((1 + math.cos(th)) / 2, 4).toDouble(),
  ), // 彗星
];

// ---------------------------------------------------------------------------
// 描画
// ---------------------------------------------------------------------------

double _ease(double t) =>
    t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

class _NebulaPainter extends CustomPainter {
  _NebulaPainter({
    required this.time,
    required this.sequence,
    required this.world,
  }) : super(repaint: time);

  final ValueNotifier<double> time;
  final _NebulaSequence sequence;
  final ChatWorld world;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final step = sequence.at(t);
    final m = _ease((step.sec / _transitionSeconds).clamp(0.0, 1.0));
    final m2 = _ease(((step.sec - .2) / _transitionSeconds).clamp(0.0, 1.0));
    final palette = ChatMotionPalette.of(world).colors;
    final color = Color.lerp(
      palette[step.fromColor],
      palette[step.toColor],
      m,
    )!;
    paintNebulaBlob(
      canvas,
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2,
      color: color,
      from: _nebulaShapes[step.fromShape],
      to: _nebulaShapes[step.toShape],
      morph: m,
      innerMorph: m2,
      t: t,
      paper: world == ChatWorld.paper,
    );
  }

  @override
  bool shouldRepaint(covariant _NebulaPainter oldDelegate) =>
      oldDelegate.world != world || oldDelegate.sequence != sequence;
}

Path _blobPath(
  Offset c,
  double radius,
  Float32List from,
  Float32List to,
  double m,
  double rot,
) {
  final path = Path();
  for (var i = 0; i <= _samples; i++) {
    final j = i % _samples;
    final th = j / _samples * _tau + rot;
    final r = (from[j] + (to[j] - from[j]) * m) * radius;
    final p = Offset(c.dx + math.cos(th) * r, c.dy + math.sin(th) * r);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// 星雲1つ分を描く(本体・内側の淡い形・まわりを回る3つの衛星)。
/// 宇宙では白く光る芯、紙では水彩のにじみと細い縁取りにする。
void paintNebulaBlob(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required Color color,
  required Float32List from,
  required Float32List to,
  required double morph,
  required double innerMorph,
  required double t,
  required bool paper,
}) {
  final s = radius;
  final r = s * .72 * (1 + .035 * math.sin(t * _tau / 3));
  final rot = t * .25;

  canvas.drawRect(
    Rect.fromCircle(center: center, radius: s),
    Paint()
      ..shader = ui.Gradient.radial(center, s, [
        color.withValues(alpha: paper ? .13 : .24),
        color.withValues(alpha: 0),
      ]),
  );

  final body = _blobPath(center, r, from, to, morph, rot);
  final List<Color> fillColors;
  final List<double> fillStops;
  if (paper) {
    fillColors = [
      Color.lerp(color, chatPaperColor, .78)!.withValues(alpha: .95),
      Color.lerp(color, chatPaperColor, .4)!.withValues(alpha: .9),
      color.withValues(alpha: .88),
    ];
    fillStops = [0, .55, 1];
  } else {
    fillColors = [
      Colors.white.withValues(alpha: .95),
      Color.lerp(color, Colors.white, .45)!.withValues(alpha: .92),
      color.withValues(alpha: .5),
    ];
    fillStops = [0, .35, 1];
  }
  canvas.drawPath(
    body,
    Paint()..shader = ui.Gradient.radial(center, r, fillColors, fillStops),
  );
  if (paper) {
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.7, s * .012)
        ..color = Color.lerp(color, chatInkColor, .35)!.withValues(alpha: .5),
    );
  }

  canvas.drawPath(
    _blobPath(center, r * .48, from, to, innerMorph, -rot * 1.6),
    Paint()..color = Colors.white.withValues(alpha: paper ? .5 : .3),
  );

  for (var k = 0; k < 3; k++) {
    final a = t * (.8 + k * .25) + k * _tau / 3;
    final p = Offset(
      center.dx + math.cos(a) * s * .9,
      center.dy + math.sin(a) * s * .9 * .85,
    );
    if (paper) {
      paintInkDot(
        canvas,
        p,
        s * .028,
        Color.lerp(color, chatInkColor, .25)!,
        alpha: .9,
      );
    } else {
      paintGlowDot(
        canvas,
        p,
        s * .03,
        Color.lerp(color, Colors.white, .3)!,
        alpha: .9,
      );
    }
  }
}

/// 宇宙の星: 色の光のにじみと、白に近い芯。
void paintGlowDot(
  Canvas canvas,
  Offset p,
  double r,
  Color c, {
  double alpha = 1,
}) {
  canvas.drawCircle(
    p,
    r * 3.6,
    Paint()
      ..shader = ui.Gradient.radial(
        p,
        r * 3.6,
        [
          c.withValues(alpha: alpha * .9),
          c.withValues(alpha: alpha * .35),
          c.withValues(alpha: 0),
        ],
        [0, .3, 1],
      ),
  );
  canvas.drawCircle(
    p,
    math.max(.6, r),
    Paint()..color = Color.lerp(c, Colors.white, .6)!.withValues(alpha: alpha),
  );
}

/// 紙の星: 光らせず、インクの点。明るい星には十字の光を添える(古い星図の描き方)。
void paintInkDot(
  Canvas canvas,
  Offset p,
  double r,
  Color c, {
  double alpha = 1,
  bool bright = false,
}) {
  canvas.drawCircle(
    p,
    r * 2.6,
    Paint()
      ..shader = ui.Gradient.radial(p, r * 2.6, [
        c.withValues(alpha: alpha * .22),
        c.withValues(alpha: 0),
      ]),
  );
  canvas.drawCircle(
    p,
    math.max(.7, r * 1.05),
    Paint()..color = c.withValues(alpha: alpha),
  );
  if (bright) {
    final cross = Paint()
      ..color = c.withValues(alpha: alpha * .55)
      ..strokeWidth = math.max(.6, r * .35);
    canvas
      ..drawLine(p.translate(-r * 2.8, 0), p.translate(r * 2.8, 0), cross)
      ..drawLine(p.translate(0, -r * 2.8), p.translate(0, r * 2.8), cross);
  }
}
