import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/galaxy/galaxy_data_provider.dart';
import 'package:lefture/application/galaxy/galaxy_state_provider.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

// 定数はクラスの外に出しておくとコンパイル時定数として扱われやすい
const double _minZoom = 1.0;
const double _maxZoom = 8.0;

// 慣性(フリック後の減衰回転)関連の定数
const double _inertiaSmoothing = 0.35; // ドラッグ中の角速度を追跡する指数移動平均の重み
const double _inertiaDecay = 0.94; // 1フレームごとの減衰率
const double _inertiaStopThresholdSq = 2.5e-7; // これ未満の角速度になったら慣性を止める

class GalaxyView extends ConsumerStatefulWidget {
  const GalaxyView({
    super.key,
    this.config = defaultGalaxyConfig,
    this.glowScale = 1.0,
  });

  /// 銀河生成パラメーター。省略時はこれまで通りの標準的な銀河になる。
  /// 例: `defaultGalaxyConfig.copyWith(diskStarCount: 0, nebulaCount: 0)` で
  /// 「まだ星が少ないユーザー向けの、中心核だけの銀河」になる。
  final GalaxyConfig config;

  /// 中心に重ねて光らせている2枚の楕円（Outer Glow / Inner Core）の
  /// 半径にかける倍率。星の生成データとは無関係の純粋な見た目調整用なので
  /// [GalaxyConfig] ではなくこちらのパラメーターで持つ。
  /// 例: バルジだけの小さな銀河では 0.4〜0.5 程度に絞ると馴染む。
  final double glowScale;

  @override
  ConsumerState<GalaxyView> createState() => GalaxyViewState();
}

class GalaxyViewState extends ConsumerState<GalaxyView> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  double t = 0.0;
  int _frame = 0; // フレームカウンタをフィールドに移動

  // Camera / controls
  bool userInteracting = false;



  // トラックボール操作用: 現在のウィジェットサイズ（buildのLayoutBuilderで更新）
  Size _viewSize = Size.zero;

  // 慣性回転用: 直近のドラッグの「角速度」を軸*角度のベクトルとして保持する。
  // 指を離した瞬間、この値を引き継いで減衰させながら回転を続ける。
  v.Vector3 _spinVector = v.Vector3.zero();

  @override
  void initState() {
    super.initState();

    _ticker = AnimationController(vsync: this, duration: const Duration(days: 99))
      ..addListener(_onTick) // リスナーメソッドを分けるとスッキリする
      ..forward();
  }

  void _onTick() {
    if (!mounted) return;
    if ((_frame++ & 1) == 1) return; // 30FPS制限
    t += 1 / 30;

    final state = ref.read(galaxyStateProvider);
    if (!userInteracting) {
      if (_spinVector.length2 > _inertiaStopThresholdSq) {
        // 慣性: 指を離した時点の角速度を減衰させながら回転を続ける
        final angle = _spinVector.length;
        final axis = _spinVector.clone()..normalize();
        final q = v.Quaternion.axisAngle(axis, angle);
        final newCamRot = (q * state.camRot)..normalize();

        ref.read(galaxyStateProvider.notifier).updateState(
          camRot: newCamRot,
          zoom: state.zoom,
        );

        _spinVector = _spinVector * _inertiaDecay;
      } else {
        _spinVector = v.Vector3.zero();

        if (state.autoRotate) {
          const spin = 0.002;
          final worldUp = v.Vector3(0, 1, 0);
          final q = v.Quaternion.axisAngle(worldUp, spin);
          final newCamRot = q * state.camRot;
          newCamRot.normalize();

          ref.read(galaxyStateProvider.notifier).updateState(
            camRot: newCamRot,
            zoom: state.zoom,
          );
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // --- 外部からジェスチャーを流し込むための公開メソッド ---
  void handleScaleStart(ScaleStartDetails details) {
    // 新しいドラッグを始めたら、前回の慣性の勢いは打ち消す
    _spinVector = v.Vector3.zero();
    setState(() => userInteracting = true);
  }

  void handleScaleUpdate(ScaleUpdateDetails d) {
    final state = ref.read(galaxyStateProvider);
    var newZoom = state.zoom;
    var newCamRot = state.camRot.clone();

    // Zoom
    const zoomSensitivity = 0.05;
    final s = math.pow(d.scale, zoomSensitivity).toDouble();
    newZoom = (newZoom * s).clamp(_minZoom, _maxZoom);

    // Rotation (トラックボール/アークボール方式)
    // 画面上のドラッグ前後の点を仮想球面上の3D点に投影し、その2点間の回転を
    // そのままカメラに適用する。ヨー・ピッチを別軸として毎フレーム積み上げないため、
    // ロール(傾き)が蓄積してドリフトすることがなく、常に「指の動き＝見た目の動き」が一致する。
    if (_viewSize.width > 0 && _viewSize.height > 0) {
      const sensitivity = 0.5; // 感度調整用の係数
      final current = d.localFocalPoint;
      final previous = current - d.focalPointDelta;

      final pCurr = _projectToSphere(current, _viewSize);
      final pPrev = _projectToSphere(previous, _viewSize);

      final dot = pPrev.dot(pCurr).clamp(-1.0, 1.0);
      final angle = math.acos(dot) * sensitivity;

      if (angle > 1e-6) {
        final axis = pPrev.cross(pCurr);
        if (axis.length2 > 1e-12) {
          axis.normalize();
          final qDelta = v.Quaternion.axisAngle(axis, angle);
          // スクリーン空間で求めた回転をそのままカメラ姿勢に左から掛ける
          newCamRot = (qDelta * newCamRot)..normalize();

          // 慣性用に、直近の角速度(軸*角度)を指数移動平均で追跡しておく。
          // 指を離した瞬間、最後の1フレームだけを見ると急停止のノイズを
          // 拾いやすいため、直近の勢いを滑らかにならしておく。
          final instant = axis * angle;
          _spinVector = _spinVector * (1 - _inertiaSmoothing) + instant * _inertiaSmoothing;
        }
      }
    }

    ref.read(galaxyStateProvider.notifier).updateState(
      camRot: newCamRot,
      zoom: newZoom,
    );
    setState(() {});
  }

  /// 画面ローカル座標を、ウィジェット中心を原点とする仮想楕円体面上の
  /// 3D点(x: 右, y: 上, z: 手前)に投影する。中心から外側にはみ出した場合は
  /// 楕円の縁（z=0）にクランプする。
  ///
  /// x/yそれぞれをウィジェットの半幅・半高で正規化するため、横長/縦長どちらの
  /// ウィジェットでも「見た目の範囲いっぱい＝操作できる範囲」になる
  /// （min(width,height)を使う円の場合、横長ウィジェットではボールが
  /// 実際の見た目よりかなり小さくなってしまう）。
  v.Vector3 _projectToSphere(Offset point, Size size) {
    final halfWidth = size.width * 0.5;
    final halfHeight = size.height * 0.5;

    // この投影結果はワールド空間ではなく、camRotがそのまま出力に使うview空間
    final nx = -(point.dx - halfWidth) / halfWidth;
    final ny = -(point.dy - halfHeight) / halfHeight;

    final lenSq = nx * nx + ny * ny;
    if (lenSq <= 1.0) {
      final nz = math.sqrt(1.0 - lenSq);
      return v.Vector3(nx, ny, nz);
    } else {
      final invLen = 1.0 / math.sqrt(lenSq);
      return v.Vector3(nx * invLen, ny * invLen, 0);
    }
  }

  void handleScaleEnd(ScaleEndDetails details) {
    setState(() => userInteracting = false);
  }

  @override
  Widget build(BuildContext context) {
    // 星field・スプライトテクスチャはgalaxyDataProviderでconfigごとにキャッシュされている。
    // watchすることで、初回のみローディングを表示し、以降同じconfigである限り
    // どのGalaxyViewインスタンスも再生成なしに即座に描画できる。
    final galaxyDataAsync = ref.watch(galaxyDataProvider(widget.config));

    return galaxyDataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Icon(Icons.error_outline, color: Colors.white.withValues(alpha: 0.5)),
      ),
      data: (galaxyData) {
        // プロバイダーから状態を直接読み取る（watchしないことでリビルドを防ぐ）
        final state = ref.read(galaxyStateProvider);

        return LayoutBuilder(
          builder: (context, constraints) {
            _viewSize = constraints.biggest;
            return Stack(
              children: [
                GestureDetector(
                  onScaleStart: handleScaleStart,
                  onScaleEnd: handleScaleEnd,
                  onScaleUpdate: handleScaleUpdate,
                  child: RepaintBoundary(
                    // 2. ClipRect: 画用紙からはみ出したインク（drawColor）をカットする
                    child: ClipRect(
                      child: CustomPaint(
                        painter: _GalaxyPainter(
                          stars: galaxyData.stars,
                          nebula: galaxyData.nebula,
                          bgStars: galaxyData.bgStars,
                          time: t,
                          camRot: state.camRot,
                          zoom: state.zoom,
                          onProjected: (_) {},
                          sprite: galaxyData.sprite,
                          glowScale: widget.glowScale,
                        ),
                        isComplex: true,
                        willChange: true,
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Data Classes (Immutable & Simple)
// ---------------------------------------------------------------------------

class _ProjectedStar {
  const _ProjectedStar({required this.star, required this.screen, required this.depth});
  final GalaxyStar star;
  final Offset screen;
  final double depth;
}

typedef _ProjectedCallback = void Function(List<_ProjectedStar> list);


// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _GalaxyPainter extends CustomPainter {
  _GalaxyPainter({
    required this.stars,
    required this.nebula,
    required this.bgStars,
    required this.time,
    required this.camRot,
    required this.zoom,
    required this.onProjected,
    required this.sprite,
    this.glowScale = 1.0,
  });

  final List<GalaxyStar> stars;
  final List<GalaxyNebulaPuff> nebula;
  final List<GalaxyBgStar> bgStars;
  final double time;
  final v.Quaternion camRot;
  final double zoom;
  final _ProjectedCallback onProjected;
  final ui.Image sprite;
  final double glowScale;

  // 定数を外に出して再利用可能に
  static final _bgColor = AppColors.universe.voidBackground;
  static const _nebulaPalette = [
    Color(0xFFFF5FA2), Color(0xFFFF9A3D), Color(0xFFB86BFF), Color(0xFF4FA8FF),
  ];
  static const _starPalette = [
    Color(0xFFFFFFFF), Color(0xFFB7D8FF), Color(0xFFFFE7B0), Color(0xFFFFB7B7),
  ];
  static const _glowGradientColors = [Color(0xE6D8F3FF), Color(0x7A6BCBFF), Color(0x001E1B2E)];
  static const _coreGradientColors = [Color(0x66FFB26B), Color(0x33FF4FA2), Color(0x00FF4FA2)];

  @override
  void paint(Canvas canvas, Size size) {
    // -------------------------------------------------------
    // Pre-calculation
    // -------------------------------------------------------
    canvas.drawColor(_bgColor, BlendMode.src);

    final center = Offset(size.width * 0.5, size.height * 0.52);
    final screenMin = math.min(size.width, size.height);

    // Density Fix: iPad等で星がスカスカになるのを防ぐ
    final densityScale = screenMin / 380.0;

    final fov = 1.2;
    final scale = screenMin * 0.38 * zoom;
    final z01 = ((zoom - _minZoom) / (_maxZoom - _minZoom)).clamp(0.0, 1.0).toDouble();

    // Matrix manual expansion
    final rotMatrix = v.Matrix4.identity()..setRotation(camRot.asRotationMatrix());
    final m = rotMatrix.storage;
    final m00 = m[0], m01 = m[4], m02 = m[8],  m03 = m[12];
    final m10 = m[1], m11 = m[5], m12 = m[9],  m13 = m[13];
    final m20 = m[2], m21 = m[6], m22 = m[10], m23 = m[14];

    // Sprite info
    final spriteW = sprite.width.toDouble();
    final spriteRect = Rect.fromLTWH(0, 0, spriteW, sprite.height.toDouble());
    final anchorX = spriteW / 2;
    final anchorY = sprite.height.toDouble() / 2;

    // -------------------------------------------------------
    // 1. Background Stars
    // -------------------------------------------------------
    final bgTransforms = <RSTransform>[];
    final bgRects = <Rect>[];
    final bgColors = <Color>[];
    final avoidR = screenMin * 0.14;
    final avoidRSq = avoidR * avoidR;

    for (final s in bgStars) {
      final x = s.x01 * size.width;
      final y = s.y01 * size.height;

      // Avoid center galaxy
      final dx = x - center.dx;
      final dy = y - center.dy;
      final dist2 = dx * dx + dy * dy;
      final avoid = (dist2 / avoidRSq).clamp(0.55, 1.0);

      final a = (s.baseA * avoid).clamp(0.01, 0.5);
      final sScale = (s.r * 2.5) * densityScale / spriteW;

      bgTransforms.add(RSTransform.fromComponents(
        rotation: 0,
        scale: sScale,
        anchorX: anchorX,
        anchorY: anchorY,
        translateX: x,
        translateY: y,
      ));
      bgRects.add(spriteRect);
      bgColors.add(Colors.white.withValues(alpha: a));
    }

    if (bgTransforms.isNotEmpty) {
      canvas.drawAtlas(
        sprite, bgTransforms, bgRects, bgColors,
        BlendMode.modulate, null, Paint()
      );
    }

    // -------------------------------------------------------
    // 2. Center Glow (Deformed by view angle)
    // -------------------------------------------------------
    final normalX = m01;
    final normalY = m11;
    final normalZ = m21;
    final tilt = normalZ.abs();
    final angle = math.atan2(normalY, normalX);

    final haze = 1.35 - 0.55 * z01;
    final coreRadius = screenMin * 0.18 * zoom * haze * glowScale;

    // Outer Glow
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(0.35 + 0.65 * tilt, 1.0); // Flatten

    final glowPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = ui.Gradient.radial(
        Offset.zero, coreRadius, _glowGradientColors, const [0.0, 0.3, 0.8]
      );
    canvas.drawCircle(Offset.zero, coreRadius, glowPaint);
    canvas.restore();

    // Inner Core
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(0.75 + 0.25 * tilt, 1.0); // Less flattened

    final corePaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = ui.Gradient.radial(
        Offset.zero, coreRadius * 0.55, _coreGradientColors, const [0.0, 0.5, 1.0]
      );
    canvas.drawCircle(Offset.zero, coreRadius * 0.55, corePaint);
    canvas.restore();

    // -------------------------------------------------------
    // 3. Nebula Layer
    // -------------------------------------------------------
    final nebulaTransforms = <RSTransform>[];
    final nebulaRects = <Rect>[];
    final nebulaColors = <Color>[];
    final zoomFade = math.log(20 * z01 + 0.8) / 2;

    for (final puff in nebula) {
      final px = puff.pos.x;
      final py = puff.pos.y;
      final pz = puff.pos.z;

      final rotX = m00 * px + m01 * py + m02 * pz + m03;
      final rotY = m10 * px + m11 * py + m12 * pz + m13;
      final rotZ = m20 * px + m21 * py + m22 * pz + m23;

      final z = rotZ + 2.5;
      if (z <= 0.2) continue;

      final x2 = (rotX / (z * fov)) * scale + center.dx;
      final y2 = (rotY / (z * fov)) * scale + center.dy;

      // Culling
      if (x2 < -150 || x2 > size.width + 150 || y2 < -150 || y2 > size.height + 150) continue;

      final sizeFade = (0.35 + 0.65 * z01);
      final rPx = ((puff.radius / z) * 2.4 * sizeFade * densityScale);
      final sScale = (rPx * 2) / spriteW;

      final alpha = (puff.alpha * zoomFade).clamp(0.0, 1.0) * 0.7;
      if (alpha < 0.01) continue;

      nebulaTransforms.add(RSTransform.fromComponents(
        rotation: 0, scale: sScale, anchorX: anchorX, anchorY: anchorY,
        translateX: x2, translateY: y2
      ));
      nebulaRects.add(spriteRect);
      nebulaColors.add(_nebulaPalette[puff.colorIndex].withValues(alpha: alpha));
    }

    if (nebulaTransforms.isNotEmpty) {
      canvas.drawAtlas(
        sprite, nebulaTransforms, nebulaRects, nebulaColors,
        BlendMode.modulate, null, Paint()..blendMode = BlendMode.screen
      );
    }

    // -------------------------------------------------------
    // 4. Stars Layer
    // -------------------------------------------------------
    final starTransforms = <RSTransform>[];
    final starRects = <Rect>[];
    final starColors = <Color>[];
    final projList = <_ProjectedStar>[];

    final zoomT = ((zoom - 0.6) / 2.4).clamp(0.0, 1.0); // 3.0 - 0.6 = 2.4
    final zoomBoost = 0.55 + 0.9 * math.pow(zoomT, 2.2);

    // Zoom Alpha Logic
    final baseAlphaFactor = 0.3 + 0.5 * z01;

    for (final s in stars) {
      final px = s.pos.x;
      final py = s.pos.y;
      final pz = s.pos.z;

      final rotX = m00 * px + m01 * py + m02 * pz + m03;
      final rotY = m10 * px + m11 * py + m12 * pz + m13;
      final rotZ = m20 * px + m21 * py + m22 * pz + m23;

      final z = rotZ + 2.5;
      if (z <= 0.2) continue;

      final x2 = (rotX / (z * fov)) * scale + center.dx;
      final y2 = (rotY / (z * fov)) * scale + center.dy;

      // Culling (tight)
      if (x2 < -20 || x2 > size.width + 20 || y2 < -20 || y2 > size.height + 20) continue;

      projList.add(_ProjectedStar(star: s, screen: Offset(x2, y2), depth: z));

      final sizePx = (s.size / z) * zoomBoost * densityScale;
      if (sizePx < 0.2) continue;

      // Alpha calc
      final alpha = (s.bright / math.pow(z, 0.8) * baseAlphaFactor).clamp(0.3, 1.0);
      if (alpha < 0.01) continue;

      final visualScale = 1.2;
      final sScale = (sizePx * 2 * visualScale) / spriteW;

      starTransforms.add(RSTransform.fromComponents(
        rotation: 0, scale: sScale, anchorX: anchorX, anchorY: anchorY,
        translateX: x2, translateY: y2
      ));
      starRects.add(spriteRect);
      starColors.add(_starPalette[s.type].withValues(alpha: alpha));
    }

    onProjected(projList);

    if (starTransforms.isNotEmpty) {
      canvas.drawAtlas(
        sprite, starTransforms, starRects, starColors,
        BlendMode.modulate, null, Paint()..blendMode = BlendMode.screen
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) {
    return oldDelegate.camRot != camRot ||
           oldDelegate.zoom != zoom ||
           oldDelegate.time != time ||
           oldDelegate.glowScale != glowScale;
  }
}
