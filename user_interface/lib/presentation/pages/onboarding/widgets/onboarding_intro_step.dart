// lib/presentation/pages/onboarding/widgets/onboarding_intro_step.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_particle_field.dart';
import 'package:lefture/presentation/pages/introduction/widgets/intro_reveal.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// Bridge slide shown right after sign-up, before the setup wizard proper
/// begins (Language → Profile → Permissions → Plan). Lays the four upcoming
/// steps out as a lit-up "constellation" roadmap so the wizard doesn't feel
/// abrupt after the atmospheric Introduction flow — reuses the same
/// starfield/RiseIn vocabulary as `IntroductionPage`, just toned down since
/// this is a single step rather than a full-screen slide.
class OnboardingIntroStep extends HookWidget {
  const OnboardingIntroStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final headerVisible = useState(false);
    final nodesVisible = useState(false);
    final ctaVisible = useState(false);

    useEffect(() {
      final timers = [
        Timer(const Duration(milliseconds: 80), () => headerVisible.value = true),
        Timer(const Duration(milliseconds: 360), () => nodesVisible.value = true),
        Timer(const Duration(milliseconds: 1320), () => ctaVisible.value = true),
      ];
      return () {
        for (final t in timers) {
          t.cancel();
        }
      };
    }, const []);

    final steps = [
      _IntroStepSpec(
        color: AppColors.cosmicBlue,
        icon: Icons.language_rounded,
        title: l10n.onboardingIntroStep1Title,
        desc: l10n.onboardingIntroStep1Desc,
        delayMs: 0,
      ),
      _IntroStepSpec(
        color: AppColors.growthGreen,
        icon: Icons.person_outline_rounded,
        title: l10n.onboardingIntroStep2Title,
        desc: l10n.onboardingIntroStep2Desc,
        delayMs: 260,
      ),
      _IntroStepSpec(
        color: AppColors.alertAmber,
        icon: Icons.lock_outline_rounded,
        title: l10n.onboardingIntroStep3Title,
        desc: l10n.onboardingIntroStep3Desc,
        delayMs: 520,
      ),
      _IntroStepSpec(
        color: AppColors.starGold,
        icon: Icons.card_giftcard_rounded,
        title: l10n.onboardingIntroStep4Title,
        desc: l10n.onboardingIntroStep4Desc,
        delayMs: 780,
      ),
    ];

    return Stack(
      children: [
        // 控えめな瞬く星空。IntroParticleFieldをそのまま使うが、単体ステップの
        // 主役はあくまでロードマップ側なので不透明度を落として背景に徹させる。
        const Positioned.fill(
          child: IntroParticleField(
            mode: IntroParticleMode.ambient,
            enableShootingStars: true,
          ),
        ),
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RiseIn(
                visible: headerVisible.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 18, height: 1.5, color: AppColors.starGold),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.onboardingIntroEyebrow.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.starGold,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              RiseIn(
                visible: headerVisible.value,
                duration: const Duration(milliseconds: 700),
                child: Text(
                  l10n.onboardingIntroTitle,
                  style: TextStyle(
                    color: AppColors.universe.textStarlight,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.28,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              RiseIn(
                visible: headerVisible.value,
                duration: const Duration(milliseconds: 750),
                child: Text(
                  l10n.onboardingIntroSubtitle,
                  style: TextStyle(
                    color: AppColors.universe.textComet,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              for (var i = 0; i < steps.length; i++)
                _Waypoint(
                  visible: nodesVisible.value,
                  spec: steps[i],
                  nextColor: i < steps.length - 1 ? steps[i + 1].color : steps[i].color,
                  stepNumber: i + 1,
                  showConnector: i < steps.length - 1,
                ),
              const SizedBox(height: 26),
              RiseIn(
                visible: ctaVisible.value,
                duration: const Duration(milliseconds: 700),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.starGold,
                          foregroundColor: const Color(0xFF221A00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: onNext,
                        child: Text(
                          l10n.onboardingGetStartedButton,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.onboardingIntroHint,
                      style: TextStyle(
                        color: AppColors.universe.textComet.withValues(alpha: 0.8),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IntroStepSpec {
  const _IntroStepSpec({
    required this.color,
    required this.icon,
    required this.title,
    required this.desc,
    required this.delayMs,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String desc;
  final int delayMs;
}

/// 1つの「星」ノード。[visible]がtrueになった[spec.delayMs]後に点灯し、次の
/// ノードへの軌道ライン(connector)も続けて伸びる。Magicスライドの
/// `_ValueCard`と同じ「親のvisibleフラグ+子自身のTimerで個別遅延」パターン。
class _Waypoint extends StatefulWidget {
  const _Waypoint({
    required this.visible,
    required this.spec,
    required this.nextColor,
    required this.stepNumber,
    required this.showConnector,
  });

  final bool visible;
  final _IntroStepSpec spec;
  final Color nextColor;
  final int stepNumber;
  final bool showConnector;

  @override
  State<_Waypoint> createState() => _WaypointState();
}

class _WaypointState extends State<_Waypoint> {
  bool _shown = false;
  Timer? _timer;

  @override
  void didUpdateWidget(covariant _Waypoint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: widget.spec.delayMs), () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.spec.color;

    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.12),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 600),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 46,
                child: Column(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.3, -0.3),
                          colors: [
                            Color.lerp(color, Colors.white, 0.25)!,
                            color,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: _shown ? 0.55 : 0),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ],
                        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Icon(widget.spec.icon, color: Colors.white, size: 19),
                    ),
                    if (widget.showConnector)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: AnimatedScale(
                            scale: _shown ? 1 : 0,
                            alignment: Alignment.topCenter,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            child: Container(
                              width: 2,
                              constraints: const BoxConstraints(minHeight: 22),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [color, widget.nextColor],
                                ),
                                boxShadow: [
                                  BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withValues(alpha: 0.38)),
                        ),
                        child: Text(
                          'STEP ${widget.stepNumber}',
                          style: TextStyle(
                            color: color,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.spec.title,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.spec.desc,
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
