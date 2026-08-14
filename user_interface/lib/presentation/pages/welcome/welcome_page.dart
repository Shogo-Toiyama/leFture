// lib/presentation/pages/welcome/welcome_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/application/lecture/lecture_list_provider.dart';
import 'package:lefture/domain/entities/lecture.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

import 'package:lefture/application/sync/sync_progress.dart';

/// サインアウト直後・起動直後の一瞬だけ表示するタイトル画面。
///
/// 「lecture for the future」というタグラインが光とともに浮かび上がり、
/// "le" / "f" / "ture" だけを残して他の文字が消え、"f"に向かって収束、
/// 着弾で星が弾けて金色の「leFture」へ着地するアニメーションを再生してから
/// ホームへ遷移する（裏でホーム用データをプレロードし、完了してから遷移する）。
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, this.revealTiming = WelcomeRevealTiming.short});

  /// タイトル演出の尺。既定は短縮版([WelcomeRevealTiming.short])。
  /// じっくり見せたい表示箇所があれば[WelcomeRevealTiming.full]を渡す。
  final WelcomeRevealTiming revealTiming;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  late final Future<void> _preloadFuture;
  Timer? _progressDisplayTimer;
  bool _showProgressBar = false;

  @override
  void initState() {
    super.initState();
    // WelcomePage 表示（アニメーション再生）と同時に、裏でホーム画面用データを先行取得
    _preloadFuture = _startPreload();

    // インパクト演出が終わり「leFture」が着弾完了してから約1秒後に、
    // まだデータ同期中だった場合のみプログレスバーをフェードイン表示する。
    _progressDisplayTimer = Timer(
      Duration(milliseconds: widget.revealTiming.impactEndMs + 1000),
      () {
        if (mounted) {
          setState(() => _showProgressBar = true);
        }
      },
    );
  }

  @override
  void dispose() {
    _progressDisplayTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPreload() async {
    try {
      // 1. Supabase 同期(ローカルDBへ講義データを書き込む処理)完了を待つ。
      //    ここをawaitしないと、下のallLecturesStreamProviderが
      //    「同期前のローカルDBの中身」で即座に解決してしまい、
      //    プリロードの意味がなくなる。
      //    bootstrapIfNeeded()自体は複数エンティティのPullを逐次実行し、
      //    それぞれ独立してnetworkTimeout(15秒)を持つため、「オフライン」
      //    ではなく「繋がってはいるが不安定」な回線だと合計で数十秒〜
      //    それ以上かかりうる。ここに8秒のタイムアウトを設けることで、
      //    そのケースでもWelcome画面に不定に長く留まらないようにする
      //    (タイムアウトしても裏側のPull自体は継続し、完了次第ローカルDB/
      //    SyncCursorへ反映される。ここで打ち切るのは「待つのをやめる」
      //    だけで、Pullそのものをキャンセルするわけではない)。
      await ref
          .read(lectureControllerProvider.notifier)
          .bootstrapIfNeeded()
          .timeout(const Duration(seconds: 8), onTimeout: () {});

      // 2. コース一覧(Supabase直参照) & レクチャー一覧(ローカルDB参照、
      //    同期後なので最新)の先行ロード完了を待機。
      //    ref.read(provider.future)はkeepAlive化したStreamProviderに対しては
      //    購読を確実に開始しない場合があった(Homeでの購読が始まるまで
      //    ストリームの初回値が永遠に来ないことがあった)ため、ref.listenで
      //    明示的に購読して初回値/エラーを待つ方式にする。preload全体にも
      //    タイムアウトを設け、万が一今後また同様の問題が起きても
      //    ホームへの遷移自体は止めない。
      final lecturesCompleter = Completer<void>();
      // fireImmediately:true の場合、Providerに既に値がキャッシュされていると
      // (keepAlive化後の2回目以降のWelcome表示など)、コールバックは
      // listenManual呼び出しの「最中」に同期的に発火する。そのためlate final
      // で受け取って直後にcloseしようとすると、まだ代入が終わっておらず
      // LateInitializationErrorになる。nullable変数+フラグで、同期発火時は
      // closeを後回しにする。
      ProviderSubscription<AsyncValue<List<Lecture>>>? lecturesSubscription;
      var lecturesReady = false;
      void onLecturesValue() {
        if (!lecturesCompleter.isCompleted) lecturesCompleter.complete();
        lecturesReady = true;
        lecturesSubscription?.close();
      }

      lecturesSubscription = ref.listenManual<AsyncValue<List<Lecture>>>(
        allLecturesStreamProvider,
        (previous, next) {
          if (next.hasValue || next.hasError) onLecturesValue();
        },
        fireImmediately: true,
      );
      if (lecturesReady) lecturesSubscription.close();

      await Future.wait<void>([
        ref.read(courseListProvider.future).then((_) {}),
        lecturesCompleter.future,
      ]).timeout(const Duration(seconds: 8), onTimeout: () => const []);
    } catch (_) {
      // 万が一のネットワークエラー時でもアニメーション完了後の遷移を阻害しない
    }
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Scaffold(
        backgroundColor: AppColors.universe.voidBackground,
        body: Stack(
          children: [
            _TitleRevealAnimation(
              revealTiming: widget.revealTiming,
              onFinished: () async {
                // アニメーション完了時に、裏でのデータロード完了を待ってからホームへ遷移！
                await _preloadFuture;
                if (!context.mounted) return;
                context.go(AppRoutes.home);
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 36,
              child: AnimatedOpacity(
                opacity: _showProgressBar ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: StardustProgressBar(visible: _showProgressBar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1文字ずつではなく単語の断片単位で扱うチャンク。
/// [keep] が true のものだけが最終的な "leFture" を構成する。
class _Chunk {
  const _Chunk(this.text, {required this.keep});
  final String text;
  final bool keep;
}

const _kChunks = [
  _Chunk('le', keep: true),
  _Chunk('cture ', keep: false),
  _Chunk('f', keep: true),
  _Chunk('or the fu', keep: false),
  _Chunk('ture', keep: true),
];

const _kPhraseStyle = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.1,
  height: 1.0,
);

const _kGapLe = 0.5; // 着地後、le と F の間に残すすき間（詰め気味でバランス最適化）
const _kGapTure = 0.2; // 着地後、F と ture の間に残すすき間

/// タイトル演出の各フェーズの所要時間(ms)のプリセット。
///
/// [full]が元々の尺（このコード上に定数として書き留めてあるので、将来
/// 「ここではじっくり見せたい」という表示箇所が出てきたら
/// `WelcomePage(revealTiming: WelcomeRevealTiming.full)` のように指定
/// すれば使える）。[short]がWelcomePageの既定値で、現状すべての呼び出し
/// 箇所（起動時・サインアウト後・アカウント削除後）はこちらを使う。
class WelcomeRevealTiming {
  const WelcomeRevealTiming({
    required this.blackMs,
    required this.lightMs,
    required this.holdMs,
    required this.rushMs,
    required this.impactMs,
    required this.finalHoldMs,
  });

  /// 何も出ない暗転(スタート直前の溜め)
  final int blackMs;
  /// 光が灯り、フレーズが浮かび上がる
  final int lightMs;
  /// 「lecture for the future」を静止して見せる
  final int holdMs;
  /// le / ture が f へ突進
  final int rushMs;
  /// 着弾・星の爆発・金色化・センタリング
  final int impactMs;
  /// 「leFture」が完成した状態を見せてから遷移
  final int finalHoldMs;

  int get totalMs =>
      blackMs + lightMs + holdMs + rushMs + impactMs + finalHoldMs;

  /// インパクト（着弾・星の爆発）が完了する時点までの総ミリ秒数
  int get impactEndMs => blackMs + lightMs + holdMs + rushMs + impactMs;

  double get p0 => blackMs / totalMs;
  double get p1 => (blackMs + lightMs) / totalMs;
  double get p2 => (blackMs + lightMs + holdMs) / totalMs;
  double get p3 => (blackMs + lightMs + holdMs + rushMs) / totalMs;
  double get p4 => (blackMs + lightMs + holdMs + rushMs + impactMs) / totalMs;

  /// 元々のフルの尺(合計3,400ms)。
  static const full = WelcomeRevealTiming(
    blackMs: 300,
    lightMs: 640,
    holdMs: 650,
    rushMs: 260,
    impactMs: 800,
    finalHoldMs: 750,
  );

  /// 短縮版(合計2,220ms、フルの約35%減)。静止区間(black/hold/finalHold)を
  /// 大きく削り、動きのある区間(light/rush/impact)も少しだけ詰めている。
  static const short = WelcomeRevealTiming(
    blackMs: 150,
    lightMs: 550,
    holdMs: 300,
    rushMs: 220,
    impactMs: 650,
    finalHoldMs: 350,
  );
}

// 光る演出のうち、最初は光だけ・文字は一切見せない区間の割合。
// この後、中央に近い文字から外側へ向かって少しずつ浮かび上がる。
const _kRevealDelayFrac = 0.35;
// 中央から一番遠い文字が、中央の文字よりどれだけ遅れて浮かび上がり始めるか
// （光る区間の残り時間に対する割合）。
const _kRevealStagger = 0.6;

/// 各チャンクの幅・自然な位置・着地位置・クラスター中心などを
/// TextPainter で一度だけ計算しておくためのメトリクス。
class _Metrics {
  _Metrics._({
    required this.chunkWidths,
    required this.naturalLeft,
    required this.targetLeft,
    required this.totalWidth,
    required this.lineHeight,
    required this.originX,
    required this.fCenterShiftDx,
    required this.finalClusterShiftDx,
    required this.charDistNorm,
  });

  final List<double> chunkWidths;
  final List<double> naturalLeft;
  final Map<int, double> targetLeft; // keep-chunk index -> Rush完了時のleft
  final double totalWidth;
  final double lineHeight;
  final double originX; // 着地後のleFtureクラスタ中心のローカルX座標
  final double fCenterShiftDx; // f の中心をボックス中央に合わせるシフト量
  final double finalClusterShiftDx; // 着地後のleFtureクラスタ全体をボックス中央に合わせる最終シフト量

  /// チャンクごと・文字ごとの「フレーズ中央からの距離」(0=中央, 1=端)。
  /// 光る演出で中央の文字から順に浮かび上がらせるために使う。
  final List<List<double>> charDistNorm;

  static _Metrics compute(TextStyle style) {
    final widths = <double>[];
    var cursor = 0.0;
    final naturalLeft = <double>[];
    final charLocalCenters = <List<double>>[];
    double lineHeight = 0;

    for (final chunk in _kChunks) {
      final painter = TextPainter(
        text: TextSpan(text: chunk.text, style: style),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      widths.add(painter.width);
      naturalLeft.add(cursor);
      cursor += painter.width;
      lineHeight = math.max(lineHeight, painter.height);

      final centers = <double>[];
      var localCursor = 0.0;
      for (final char in chunk.text.split('')) {
        final charPainter = TextPainter(
          text: TextSpan(text: char, style: style),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        centers.add(localCursor + charPainter.width / 2);
        localCursor += charPainter.width;
      }
      charLocalCenters.add(centers);
    }

    final totalWidth = cursor;
    final halfWidth = totalWidth / 2;
    final charDistNorm = <List<double>>[
      for (var i = 0; i < _kChunks.length; i++)
        [
          for (final centerLocal in charLocalCenters[i])
            ((naturalLeft[i] + centerLocal - halfWidth).abs() / halfWidth)
                .clamp(0.0, 1.0),
        ],
    ];
    final fIndex = _kChunks.indexWhere((c) => c.text == 'f');
    final leIndex = _kChunks.indexWhere((c) => c.text == 'le');
    final tureIndex = _kChunks.indexWhere((c) => c.text == 'ture');

    final fLeft = naturalLeft[fIndex];
    final fWidth = widths[fIndex];
    final leWidth = widths[leIndex];
    final tureWidth = widths[tureIndex];

    // 大文字 F の幅を正確に計測
    final fUpperPainter = TextPainter(
      text: TextSpan(text: 'F', style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final fUpperWidth = fUpperPainter.width;

    // 1. 小文字 f の中心をボックス中央 (totalWidth / 2) に合わせるシフト量
    final fCenterLocal = fLeft + fWidth / 2;
    final fCenterShiftDx = totalWidth / 2 - fCenterLocal;

    // 2. 突進完了時 (Rush終了時) の各チャンクの到達目標 Left 座標
    final fRushTargetLeft = fLeft + fCenterShiftDx;
    final leRushTargetLeft = fRushTargetLeft - leWidth - _kGapLe;
    final tureRushTargetLeft = fRushTargetLeft + fUpperWidth + _kGapTure;

    // 3. 着弾後に大文字 F に変わった leFture クラスタ全体の中心座標
    final clusterLeft = leRushTargetLeft;
    final clusterRight =
        (fRushTargetLeft + fUpperWidth + _kGapTure) + tureWidth;
    final originX = (clusterLeft + clusterRight) / 2;
    final finalClusterShiftDx = totalWidth / 2 - originX;

    return _Metrics._(
      chunkWidths: widths,
      naturalLeft: naturalLeft,
      charDistNorm: charDistNorm,
      targetLeft: {
        leIndex: leRushTargetLeft,
        fIndex: fRushTargetLeft,
        tureIndex: tureRushTargetLeft,
      },
      totalWidth: totalWidth,
      lineHeight: lineHeight,
      originX: originX,
      fCenterShiftDx: fCenterShiftDx,
      finalClusterShiftDx: finalClusterShiftDx,
    );
  }
}

class _TitleRevealAnimation extends StatefulWidget {
  const _TitleRevealAnimation({
    required this.revealTiming,
    required this.onFinished,
  });
  final WelcomeRevealTiming revealTiming;
  final VoidCallback onFinished;

  @override
  State<_TitleRevealAnimation> createState() => _TitleRevealAnimationState();
}

class _TitleRevealAnimationState extends State<_TitleRevealAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final _Metrics _metrics;
  late final List<_Particle> _particles;
  bool _burstFired = false;
  bool _reduceMotion = false;

  WelcomeRevealTiming get _timing => widget.revealTiming;

  @override
  void initState() {
    super.initState();
    _metrics = _Metrics.compute(_kPhraseStyle);
    _particles = _generateParticles();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _timing.totalMs),
    )..addListener(_onTick);

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _controller.value = 1.0;
    }
  }

  void _onTick() {
    if (!_burstFired && _controller.value >= _timing.p3) {
      _burstFired = true;
      // 着弾の瞬間の演出はビルド内で controller.value を直接参照するので
      // ここでは再描画のトリガーのみ（副作用なし）。
    }
    setState(() {});
  }

  List<_Particle> _generateParticles() {
    final rand = math.Random();
    const count = 90;
    return List.generate(count, (i) {
      final angle = rand.nextDouble() * math.pi * 2;
      final isBig = rand.nextDouble() < 0.2;
      final distance = 70 + rand.nextDouble() * 260;
      final size = isBig
          ? 3.2 + rand.nextDouble() * 2.4
          : 1.2 + rand.nextDouble() * 2.0;
      final delay = rand.nextDouble() * 0.08;
      final duration = 0.55 + rand.nextDouble() * 0.4;
      final colorIndex = rand.nextInt(_particleColors.length);
      return _Particle(
        angle: angle,
        distance: distance,
        size: size,
        delay: delay,
        duration: duration,
        color: _particleColors[colorIndex],
      );
    });
  }

  static const _particleColors = [
    AppColors.starGold,
    Color(0xFFFFD166),
    Colors.white,
    Color(0xFFFFE8B0),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return Center(
        child: _StaticWordmark(chunks: _kChunks, metrics: _metrics),
      );
    }

    final t = _controller.value;

    return Center(
      child: SizedBox(
        width: _metrics.totalWidth,
        height: _metrics.lineHeight + 40,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 着弾エフェクト(フラッシュ・衝撃波・星)は常に画面中央基準
            if (t >= _timing.p3)
              Positioned.fill(
                child: CustomPaint(
                  painter: _BurstPainter(
                    progress: _impactLocal(t),
                    particles: _particles,
                  ),
                ),
              ),
            _buildPhrase(t),
          ],
        ),
      ),
    );
  }

  double _impactLocal(double t) {
    if (t <= _timing.p3) return 0;
    return ((t - _timing.p3) / (_timing.p4 - _timing.p3)).clamp(0.0, 1.0);
  }

  /// 光る演出の間、中央に近い文字ほど早く・外側の文字ほど遅れて
  /// 浮かび上がるための、文字ごとの不透明度(0..1)。
  /// [distNorm] はその文字のフレーズ中央からの距離(0=中央,1=端)。
  double _charAlpha(double t, double distNorm) {
    final p0 = _timing.p0;
    final p1 = _timing.p1;
    final revealStart = p0 + (p1 - p0) * _kRevealDelayFrac;
    final revealSpan = p1 - revealStart;
    final charStart = revealStart + distNorm * _kRevealStagger * revealSpan;
    final duration = revealSpan * (1 - distNorm * _kRevealStagger);
    if (t <= charStart) return 0.0;
    final raw = ((t - charStart) / duration).clamp(0.0, 1.0);
    return Curves.easeOut.transform(raw);
  }

  Widget _buildPhrase(double t) {
    final impactT = _impactLocal(t);

    // --- カメラ演出(拡大+センタリング) ---
    double scale = 1.0;
    double dx = 0.0;
    if (t > _timing.p3) {
      final camCurve = Curves.easeOutBack.transform(impactT);
      scale = ui.lerpDouble(1.0, 2.3, camCurve.clamp(0.0, 1.4))!;
      dx = _metrics.finalClusterShiftDx * camCurve.clamp(0.0, 1.0);
    }
    final origin = _metrics.originX;
    final matrix = Matrix4.identity()
      ..translateByDouble(dx + origin, 0.0, 0.0, 1.0)
      ..scaleByDouble(scale, scale, scale, 1.0)
      ..translateByDouble(-origin, 0.0, 0.0, 1.0);

    // --- フレーズ全体の光の演出(フェーズA) ---
    // 個々の文字の見え方(不透明度)は _charAlpha が中央からの距離で
    // 個別に決める。ここではブラー・グロー・色温度だけを共通で扱う。
    double blurSigma = 0.0;
    double glowStrength = 0.0;
    Color baseTextColor = AppColors.universe.textStarlight;
    if (t <= _timing.p1) {
      final lt = ((t - _timing.p0) / (_timing.p1 - _timing.p0)).clamp(0.0, 1.0);
      blurSigma = ui.lerpDouble(9, 0, Curves.easeOut.transform(lt))!;
      glowStrength = ui.lerpDouble(1.25, 0.0, Curves.easeIn.transform(lt))!;
      baseTextColor = Color.lerp(
        const Color(0xFFFFFFFF),
        AppColors.universe.textStarlight,
        Curves.easeOut.transform(lt),
      )!;
    }

    // --- 金色化(フェーズD後半) ---
    final goldT = t > _timing.p3
        ? Curves.easeOut.transform(impactT.clamp(0.0, 1.0))
        : 0.0;
    final keepColor = Color.lerp(baseTextColor, AppColors.starGold, goldT)!;

    Widget phrase = Transform(
      transform: matrix,
      child: SizedBox(
        width: _metrics.totalWidth,
        height: _metrics.lineHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: _buildChunks(t, keepColor, glowStrength),
        ),
      ),
    );

    if (blurSigma > 0.01) {
      phrase = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: phrase,
      );
    }

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (t <= _timing.p1)
          _Glint(
            progress: ((t - _timing.p0) / (_timing.p1 - _timing.p0))
                .clamp(0.0, 1.0),
          ),
        phrase,
      ],
    );
  }

  List<Widget> _buildChunks(double t, Color keepColor, double glowStrength) {
    final widgets = <Widget>[];

    for (var i = 0; i < _kChunks.length; i++) {
      final chunk = _kChunks[i];
      final natural = _metrics.naturalLeft[i];

      // 光る演出の間は、位置は動かさず文字ごとに中央から浮かび上がらせる。
      if (t <= _timing.p1) {
        final color = chunk.keep ? keepColor : AppColors.universe.textComet;
        widgets.add(
          Positioned(
            left: natural,
            top: 0,
            child: _revealText(
              chunk.text,
              _metrics.charDistNorm[i],
              t,
              color,
              chunk.keep ? glowStrength : 0.0,
            ),
          ),
        );
        continue;
      }

      if (chunk.keep) {
        double left = natural;
        double opacity = 1.0;
        double scaleX = 1.0;

        if (t > _timing.p2) {
          final target = _metrics.targetLeft[i] ?? natural;
          final rt = ((t - _timing.p2) / (_timing.p3 - _timing.p2)).clamp(0.0, 1.0);
          final eased = const Cubic(0.55, 0.06, 0.68, 0.19).transform(rt);
          left = ui.lerpDouble(natural, target, eased)!;
        }

        final isF = chunk.text == 'f';
        final displayText = isF && t > _timing.p3 ? 'F' : chunk.text;

        Widget textWidget = Text(
          displayText,
          style: _kPhraseStyle.copyWith(
            color: isF && t > _timing.p3 ? AppColors.starGold : keepColor,
            shadows: isF && t > _timing.p3
                ? [
                    Shadow(
                      color: AppColors.starGold.withValues(alpha: 0.85),
                      blurRadius: 18,
                    ),
                    Shadow(
                      color: AppColors.starGold.withValues(alpha: 0.5),
                      blurRadius: 40,
                    ),
                  ]
                : glowStrength > 0.01
                ? [
                    Shadow(
                      color: const Color(
                        0xFFFFFFFF,
                      ).withValues(alpha: 0.9 * glowStrength),
                      blurRadius: 18 * glowStrength + 4,
                    ),
                    Shadow(
                      color: const Color(
                        0xCCE0ECFF,
                      ).withValues(alpha: 0.5 * glowStrength),
                      blurRadius: 36 * glowStrength + 4,
                    ),
                  ]
                : null,
          ),
        );

        if (isF && t > _timing.p3) {
          final popT =
              ((t - _timing.p3) / ((_timing.impactMs * 0.4) / _timing.totalMs))
                  .clamp(0.0, 1.0);
          final popScale = _fPopScale(popT);
          textWidget = Transform.scale(scale: popScale, child: textWidget);
        }

        widgets.add(
          Positioned(
            left: left,
            top: 0,
            child: Opacity(
              opacity: opacity,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scaleByDouble(scaleX, 1.0, 1.0, 1.0),
                child: textWidget,
              ),
            ),
          ),
        );
      } else {
        // drop chunk: rush 開始と同時に縮小してフェードアウト
        double opacity = 1.0;
        double scale = 1.0;
        double blur = 0.0;
        if (t > _timing.p2) {
          final vt =
              ((t - _timing.p2) / ((_timing.rushMs * 0.75) / _timing.totalMs))
                  .clamp(0.0, 1.0);
          final eased = Curves.easeIn.transform(vt);
          opacity = 1.0 - eased;
          scale = ui.lerpDouble(1.0, 0.4, eased)!;
          blur = 3.0 * eased;
        }
        Widget child = Text(
          chunk.text,
          style: _kPhraseStyle.copyWith(color: AppColors.universe.textComet),
        );
        if (blur > 0.01) {
          child = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: child,
          );
        }
        widgets.add(
          Positioned(
            left: natural,
            top: 0,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  /// 光る演出の間だけ使う、文字ごとに不透明度をずらして描くテキスト。
  Widget _revealText(
    String text,
    List<double> distNorms,
    double t,
    Color color,
    double glowStrength,
  ) {
    final spans = <TextSpan>[];
    for (var j = 0; j < text.length; j++) {
      final alpha = _charAlpha(t, distNorms[j]);
      spans.add(
        TextSpan(
          text: text[j],
          style: _kPhraseStyle.copyWith(
            color: color.withValues(alpha: alpha),
            shadows: glowStrength > 0.01 && alpha > 0.02
                ? [
                    Shadow(
                      color: const Color(
                        0xFFFFFFFF,
                      ).withValues(alpha: 0.9 * glowStrength * alpha),
                      blurRadius: 18 * glowStrength + 4,
                    ),
                    Shadow(
                      color: const Color(
                        0xCCE0ECFF,
                      ).withValues(alpha: 0.5 * glowStrength * alpha),
                      blurRadius: 36 * glowStrength + 4,
                    ),
                  ]
                : null,
          ),
        ),
      );
    }
    return Text.rich(TextSpan(children: spans));
  }

  double _fPopScale(double t) {
    if (t <= 0.28) {
      return ui.lerpDouble(1.0, 1.6, Curves.easeOut.transform(t / 0.28))!;
    } else if (t <= 0.6) {
      return ui.lerpDouble(1.6, 0.9, (t - 0.28) / 0.32)!;
    }
    return ui.lerpDouble(0.9, 1.0, ((t - 0.6) / 0.4).clamp(0.0, 1.0))!;
  }
}

/// reduce-motion時にそのまま出す最終形。
class _StaticWordmark extends StatelessWidget {
  const _StaticWordmark({required this.chunks, required this.metrics});
  final List<_Chunk> chunks;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final text = chunks.where((c) => c.keep).map((c) {
      return c.text == 'f' ? 'F' : c.text;
    }).join();
    return Text(
      text,
      style: _kPhraseStyle.copyWith(fontSize: 34, color: AppColors.starGold),
    );
  }
}

class _Glint extends StatelessWidget {
  const _Glint({required this.progress});
  final double progress; // 0..1 (ライトフェーズ内)

  @override
  Widget build(BuildContext context) {
    // コアの明滅: 控えめで自然な拡大率
    double coreOpacity;
    double coreScale;
    if (progress < 0.22) {
      final lt = progress / 0.22;
      coreOpacity = lt;
      coreScale = ui.lerpDouble(0.25, 2.0, lt)!;
    } else if (progress < 0.55) {
      final lt = (progress - 0.22) / 0.33;
      coreOpacity = ui.lerpDouble(1.0, 0.75, lt)!;
      coreScale = ui.lerpDouble(2.0, 4.2, lt)!;
    } else {
      final lt = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);
      coreOpacity = ui.lerpDouble(0.75, 0.0, lt)!;
      coreScale = ui.lerpDouble(4.2, 7.5, lt)!;
    }

    double beamOpacity;
    double beamScale;
    if (progress < 0.18) {
      final lt = progress / 0.18;
      beamOpacity = lt;
      beamScale = ui.lerpDouble(0.25, 1.25, lt)!;
    } else {
      final lt = ((progress - 0.18) / 0.82).clamp(0.0, 1.0);
      beamOpacity = ui.lerpDouble(1.0, 0.0, lt)!;
      beamScale = ui.lerpDouble(1.25, 1.55, lt)!;
    }

    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. ふわっと広がる背景のエレガントな白銀オーラ (Halo Glow)
          Opacity(
            opacity: (coreOpacity * 0.65).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: coreScale * 0.85,
              child: Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xB3F0F4FF),
                      Color(0x35D0E0FF),
                      Color(0x00B5C8FF),
                    ],
                    stops: [0.0, 0.3, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 2. 水平ビーム (透明感のある美しい純白グラデーション / 幅270px)
          Opacity(
            opacity: (beamOpacity * 0.9).clamp(0.0, 1.0),
            child: Transform.scale(
              scaleX: beamScale,
              child: Container(
                width: 270,
                height: 2.5,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Color(0x35E0E8FF),
                      Color(0xCCFFFFFF),
                      Colors.white,
                      Color(0xCCFFFFFF),
                      Color(0x35E0E8FF),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.25, 0.45, 0.5, 0.55, 0.75, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 3. 垂直ビーム (高さ150px)
          Opacity(
            opacity: (beamOpacity * 0.85).clamp(0.0, 1.0),
            child: Transform.scale(
              scaleY: beamScale,
              child: Container(
                width: 2.5,
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x35E0E8FF),
                      Color(0xCCFFFFFF),
                      Colors.white,
                      Color(0xCCFFFFFF),
                      Color(0x35E0E8FF),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.25, 0.45, 0.5, 0.55, 0.75, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 4. 斜め45度の静かなダイヤモンド光条 (控えめで上品)
          Opacity(
            opacity: (beamOpacity * 0.4).clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Transform.scale(
                scale: beamScale * 0.6,
                child: Container(
                  width: 140,
                  height: 1.5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0x77FFFFFF),
                        Colors.white,
                        Color(0x77FFFFFF),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.35, 0.5, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 5. 中央コアのシルキーホワイトな閃光 (10px)
          Opacity(
            opacity: coreOpacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: coreScale,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white,
                      Color(0xEEF5F8FF),
                      Color(0x55C8D8FF),
                      Color(0x00B0C4FF),
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
    required this.duration,
    required this.color,
  });
  final double angle;
  final double distance;
  final double size;
  final double delay; // 0..1 (impactフェーズ内)
  final double duration; // 0..1 (impactフェーズ内)
  final Color color;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.particles});
  final double progress; // 0..1 (impactフェーズ内)
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    _paintFlash(canvas, center);
    _paintShockwaves(canvas, center);
    _paintParticles(canvas, center);
  }

  void _paintFlash(Canvas canvas, Offset center) {
    final t = (progress / 0.35).clamp(0.0, 1.0);
    if (t >= 1.0) return;
    final opacity = t < 0.25 ? t / 0.25 : 1 - ((t - 0.25) / 0.75);
    final scale = ui.lerpDouble(0.2, 22, Curves.easeOut.transform(t))!;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.95 * opacity.clamp(0.0, 1.0)),
          AppColors.starGold.withValues(alpha: 0.55 * opacity.clamp(0.0, 1.0)),
          AppColors.starGold.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.32, 0.7],
      ).createShader(Rect.fromCircle(center: center, radius: 12 * scale));
    canvas.drawCircle(center, 12 * scale, paint);
  }

  void _paintShockwaves(Canvas canvas, Offset center) {
    for (final delay in [0.0, 0.08]) {
      final t = ((progress - delay) / 0.5).clamp(0.0, 1.0);
      if (progress < delay || t >= 1.0) continue;
      final eased = Curves.easeOut.transform(t);
      final radius = ui.lerpDouble(6, 150, eased)!;
      final opacity = 1 - eased;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ui.lerpDouble(3, 0.5, eased)!
        ..color = const Color(0xFFFFC45A).withValues(alpha: 0.85 * opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintParticles(Canvas canvas, Offset center) {
    for (final p in particles) {
      final local = ((progress - p.delay) / p.duration).clamp(0.0, 1.0);
      if (progress < p.delay) continue;
      final eased = Curves.easeOut.transform(local);
      final dist = p.distance * eased;
      final opacity = local < 0.12 ? local / 0.12 : 1 - ((local - 0.12) / 0.88);
      if (opacity <= 0) continue;
      final offset =
          center + Offset(math.cos(p.angle) * dist, math.sin(p.angle) * dist);
      final scale = ui.lerpDouble(1.0, 0.5, local)!;
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.6);
      canvas.drawCircle(offset, (p.size * scale) / 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 宇宙のゴールドグラデーションと先端の光粒（グロー）で滑らかに進捗を描画する極細スリムバー
class StardustProgressBar extends ConsumerWidget {
  const StardustProgressBar({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncProgress = ref.watch(syncProgressProvider);
    // 出現前（visible == false）は常に0.0。出現した瞬間に0.0から現在の進捗値へスムーズにアニメーション開始
    final targetFraction = visible ? syncProgress.fraction : 0.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: targetFraction),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth;
                final fillWidth = (barWidth * value).clamp(0.0, barWidth);

                return Container(
                  height: 3,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 進行ゴールドグラデーションバー
                      Container(
                        width: fillWidth,
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFE5A93C),
                              AppColors.starGold,
                              Color(0xFFFFE8B0),
                            ],
                          ),
                        ),
                      ),
                      // 先端のグロー（輝く星の光粒）
                      if (fillWidth > 2)
                        Positioned(
                          left: fillWidth - 3,
                          top: -1.5,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFF6D6),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.starGold.withValues(alpha: 0.9),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
