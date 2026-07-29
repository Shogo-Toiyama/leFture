// lib/presentation/pages/introduction/introduction_page.dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/routes.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_particle_field.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_slide_cta.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_slide_hero.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_slide_magic.dart';
import 'package:lefture/presentation/pages/profile/widgets/language_selection_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/glowing_rainbow_border.dart';

/// サインアップ前、新規インストール端末に限定して一度だけ見せる
/// 3枚のイントロダクション(Hero / 3つの魔法 / CTA)。
/// 表示した時点で「見た」フラグを端末ローカルに保存するため、
/// 途中で離脱しても次回以降は再表示されない。
class IntroductionPage extends ConsumerStatefulWidget {
  const IntroductionPage({super.key});

  @override
  ConsumerState<IntroductionPage> createState() => _IntroductionPageState();
}

class _IntroductionPageState extends ConsumerState<IntroductionPage> {
  static const _slideCount = 3;
  int _index = 0;
  final _particleFieldKey = GlobalKey<IntroParticleFieldState>();

  // GlobalKeyを使う理由: ValueKeyだと「現在→去っていく」役割が変わる瞬間、
  // AnimatedBuilderの入れ物(Stackの子)が別要素とみなされることがあり、
  // 中身(HERO/MAGIC/CTA)のStateが作り直されてアニメーションが再生し直されて
  // しまう不具合があった。GlobalKeyはツリー上の位置が変わってもStateを
  // 保持したまま移動させる仕組みなので、これを使って確実にStateを守る。
  final _heroKey = GlobalKey();
  final _magicKey = GlobalKey();
  final _ctaKey = GlobalKey();

  // CTAスライドの中身(ポータル・ロゴ・文言)が出そろってから、最後の一押しと
  // して虹色の枠を「ブワッ」と出す演出用。スライドが切り替わるたびリセットし、
  // CTAに着地してから少し間を置いてから true にする。
  bool _borderBurst = false;
  Timer? _borderTimer;

  @override
  void initState() {
    super.initState();
    // 表示した瞬間に「見た」フラグを立てる。最後まで見なくても、この端末では
    // 二度と出さない(新規インストール限定の一度きりの導線として扱う)。
    RecordingPreferences().setHasSeenIntroduction(true);
  }

  @override
  void dispose() {
    _borderTimer?.cancel();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _slideCount) return;
    _borderTimer?.cancel();
    setState(() {
      _index = index;
      _borderBurst = false;
    });
    if (index == _slideCount - 1) {
      // CTAスライド内の演出(ポータル→ロゴ→リード文→サブ文)が
      // 出そろうタイミング(約1.5秒後)に合わせて枠を弾けさせる。
      _borderTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _borderBurst = true);
      });
    }
  }

  void _onPrimaryPressed() {
    if (_index < _slideCount - 1) {
      _goTo(_index + 1);
    } else {
      context.go(AppRoutes.signUp);
    }
  }

  Future<void> _openLanguageSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          const LanguageSelectionSheet(mode: LanguageSheetMode.display),
    );
  }

  Widget _buildSlide(BuildContext context, int index) {
    switch (index) {
      case 0:
        return IntroHeroSlide(
          key: _heroKey,
          particleFieldKey: _particleFieldKey,
        );
      case 1:
        return IntroMagicSlide(key: _magicKey);
      case 2:
      default:
        return IntroCtaSlide(key: _ctaKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLast = _index == _slideCount - 1;

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      // 背景は必ずGlowingRainbowBorderの外側(下のレイヤー)に置く。
      // GlowingRainbowBorderは「光る枠を描いた後、その上にchildを重ねる」
      // 仕組みなので、childの中に画面全体を覆う不透明な背景を入れてしまうと
      // 枠そのものが隠れてしまう。
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.25),
                radius: 1.3,
                colors: [
                  const Color(0xFF1B2142),
                  AppColors.universe.voidBackground,
                ],
                stops: const [0.0, 0.6],
              ),
            ),
          ),
          // GlowingRainbowBorder自体は常にここ(SafeAreaの外側 = Scaffold body
          // 直下)に置く。CTAスライド以外ではglowRadiusを0にして見た目上は
          // 消しておき、isLastで出し入れする形(ウィジェットツリーの形は
          // 変えない)にすることで、Stack配下のスライド(Hero/Magic/CTA)の
          // Stateが余計に作り直されるのを防ぐ。
          //
          // _borderBurstがtrueになった瞬間(CTAの中身が出そろった後)に
          // 0→1へ一気に育てることで、枠が最後に「ブワッ」と弾けて出てくる
          // ように見せる。easeOutBackのオーバーシュートでポップ感を出すため、
          // 幅・輝きはtをそのまま使い、alphaが必要なopacityだけ0-1にclampする。
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: (isLast && _borderBurst) ? 1.0 : 0.0),
            duration: (isLast && _borderBurst)
                ? const Duration(milliseconds: 700)
                : Duration.zero,
            curve: Curves.easeOutBack,
            builder: (context, t, child) {
              return GlowingRainbowBorder(
                borderRadius: 60,
                borderWidth: 1.0 + 1.5 * t,
                // LectureViewerPage(glowRadius: 6.0, glowOpacity: 0.4)より
                // 少し強め。
                glowRadius: 10.0 * t,
                glowOpacity: 0.55 * t.clamp(0.0, 1.0),
                animate: isLast,
                innerGlow: true,
                child: child!,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IntroParticleField(
                    key: _particleFieldKey,
                    mode: isLast
                        ? IntroParticleMode.converge
                        : IntroParticleMode.ambient,
                  ),
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 44),
                      child: _CrossFadeStage(
                        index: _index,
                        builder: _buildSlide,
                      ),
                    ),
                  ),
                ),

                // --- Top chrome (Header) ---
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 6,
                      ),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            _ChromeIconButton(
                              icon: Icons.chevron_left_rounded,
                              visible: _index > 0,
                              tooltip: l10n.introBackButton,
                              onTap: () => _goTo(_index - 1),
                            ),
                            const Spacer(),
                            _ChromeIconButton(
                              icon: Icons.language_rounded,
                              visible: true,
                              tooltip: l10n.introLanguageButton,
                              onTap: _openLanguageSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // --- Bottom chrome: dots + primary button ---
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Dots(
                            count: _slideCount,
                            index: _index,
                            onTap: _goTo,
                          ),
                          const SizedBox(height: 18),
                          _PrimaryButton(
                            label: isLast
                                ? l10n.introCtaButton
                                : l10n.introNextButton,
                            primary: isLast,
                            onPressed: _onPrimaryPressed,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.visible,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool visible;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !visible,
        child: Material(
          color: AppColors.universe.glassWhiteLow,
          shape: const CircleBorder(side: BorderSide(color: Color(0x1CFFFFFF))),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Tooltip(
              message: tooltip,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  icon,
                  size: 20,
                  color: AppColors.universe.textStarlight,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.onTap});
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final on = i == index;
        return GestureDetector(
          onTap: () => onTap(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: on ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: on
                  ? AppColors.starGold
                  : Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(5),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.starGold.withValues(alpha: 0.6),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final bool primary;
  final VoidCallback onPressed;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.primary) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.starGold,
            foregroundColor: const Color(0xFF221A00),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(widget.label),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glow = Curves.easeInOut.transform(_glowController.value);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: AppColors.starGold.withValues(alpha: 0.55 + glow * 0.35),
                blurRadius: 24 + glow * 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      },
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.starGold,
            foregroundColor: const Color(0xFF221A00),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(widget.label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// スライド切り替え時、去っていく側が縮小+ブラー+フェードしながら奥へ
/// 後退し、新しいスライドがふわっと立ち上がって重なるトランジション。
/// Welcomeのシネマティック演出と対になる「賑やかだが上品」なOUTを付与する。
class _CrossFadeStage extends StatefulWidget {
  const _CrossFadeStage({required this.index, required this.builder});
  final int index;
  final Widget Function(BuildContext, int) builder;

  @override
  State<_CrossFadeStage> createState() => _CrossFadeStageState();
}

class _CrossFadeStageState extends State<_CrossFadeStage>
    with TickerProviderStateMixin {
  late int _currentIndex = widget.index;
  int? _leavingIndex;

  // Controllerはdispose→作り直しではなく、生きたまま reset()+forward() で
  // 使い回す。まだ古いControllerを参照しているAnimatedBuilderが更新される
  // 前にdisposeすると、Flutterがその要素を別物とみなして中身(HERO等)を
  // 作り直してしまう(=アニメーションが再生し直される)不具合があったため。
  late final AnimationController _inController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final AnimationController _outController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  int _transitionToken = 0;

  @override
  void initState() {
    super.initState();
    _inController.forward();
  }

  @override
  void didUpdateWidget(covariant _CrossFadeStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _currentIndex) {
      final leaving = _currentIndex;
      _currentIndex = widget.index;
      final token = ++_transitionToken;

      _outController
        ..stop()
        ..reset();
      _outController.forward().whenCompleteOrCancel(() {
        if (mounted && token == _transitionToken) {
          setState(() => _leavingIndex = null);
        }
      });

      _inController
        ..stop()
        ..reset();
      _inController.forward();

      setState(() => _leavingIndex = leaving);
    }
  }

  @override
  void dispose() {
    _inController.dispose();
    _outController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_leavingIndex != null)
          AnimatedBuilder(
            // current->leavingへ役割が変わっても同じスライドである間はkeyを
            // 保つ(役割ではなくスライド番号でkeyを振る)。これによりcurrentから
            // leavingへ切り替わる瞬間に中身(HERO/MAGIC等)のStateが保持され、
            // 表示済みの状態のままフェードアウトできる。
            key: ValueKey('stage-slide-$_leavingIndex'),
            animation: _outController,
            builder: (context, child) {
              final t = Curves.easeIn.transform(_outController.value);
              return Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -34 * t),
                  child: Transform.scale(
                    scale: 1 - 0.1 * t,
                    // ImageFilteredを条件分岐で出し入れするとウィジェットツリーの
                    // 形が途中で変わり、Flutterが別要素と誤認識してState(HERO等)を
                    // 作り直してしまう(=アニメーションが再生し直される)ため、
                    // 常時ImageFilteredで包む(t=0近辺ではsigma=0でぼけて見えない)。
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 9 * t,
                        sigmaY: 9 * t,
                      ),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: widget.builder(context, _leavingIndex!),
          ),
        AnimatedBuilder(
          key: ValueKey('stage-slide-$_currentIndex'),
          animation: _inController,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_inController.value);
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.scale(scale: 1.035 - 0.035 * t, child: child),
            );
          },
          child: widget.builder(context, _currentIndex),
        ),
      ],
    );
  }
}
