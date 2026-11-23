import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/dev_tools/test_mode_flag.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/galaxy/galaxy_view.dart';
import 'package:lefture/application/galaxy/galaxy_data_provider.dart';
import 'package:lefture/application/galaxy/galaxy_growth.dart';
import 'package:lefture/application/galaxy/galaxy_home_preview.dart';
import 'package:lefture/application/galaxy/galaxy_state_provider.dart';

/// 銀河ページはまだ未完成なので、開発ビルド(flutter run / IS_TEST_MODE)でだけ開けるようにする。
/// 本番ビルドではHomeの銀河をタップしても遷移しない。
const bool kGalaxyPageEnabled = kDebugMode || isTestMode;

/// パラメーター調整パネルの初期値。総数とバルジの割合は defaultGalaxyConfig から計算する。
const int _defaultTotalStars = 20000;
const double _defaultBulgeShare = 0.25;

/// 成長シミュレーション: 1日を0.2秒で、2年分(730日、約2分26秒)を自動再生する。
const Duration _simTickPerDay = Duration(milliseconds: 200);
const int _simDays = 730;

class LearningGalaxyPage extends HookConsumerWidget {
  const LearningGalaxyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showOverlay = useState(false);
    final showTuner = useState(false);
    // パネルで動かしている値(ドラッグ中も更新)と、実際に銀河に反映している値。
    // 星の再生成は重いので、反映はスライダーを離した時だけ行う。
    // 前にこのページで選んだ銀河(Homeにも出している値)があれば、そこから始める
    final savedPreview = useMemoized(() => ref.read(galaxyHomePreviewProvider));
    final initialValues = useMemoized(
        () => savedPreview == null ? const _TunerValues() : _TunerValues.fromPreview(savedPreview));
    final draft = useState(initialValues);
    final applied = useState(initialValues);
    // 成長プレビューの「集めた星の数」。スライダーを動かしている間も更新し、離した時に銀河へ反映する。
    final earned = useState(savedPreview?.earned ?? galaxyStageEarnedStars[GalaxyStage.large]!);
    final playing = useState(false);
    final container = ProviderScope.containerOf(context, listen: false);

    void apply(_TunerValues next) {
      final previous = applied.value.toConfig();
      // 既定の画角が変わったら、カメラもその倍率にする(向きはそのまま)
      if ((next.zoom - applied.value.zoom).abs() > 1e-6) {
        ref.read(galaxyStateProvider.notifier).setZoom(next.zoom);
      }
      draft.value = next;
      applied.value = next;
      // 開発ビルド: ここで選んだ銀河をHomeにも出す(Homeでの見え方を確かめるため)
      ref.read(galaxyHomePreviewProvider.notifier).set(GalaxyHomePreview(
            look: next.toLook(),
            seed: next.seed,
            stableGrowth: next.stableGrowth,
            earned: earned.value,
            zoomRule: next.zoomRule,
          ));
      // galaxyDataProvider は keepAlive なので、調整中に作った銀河はキャッシュに残り続ける。
      // Homeが使う既定の銀河以外は、使わなくなった時点で捨てる。Homeの銀河も同じ値を見ているので、
      // Homeが新しい値で描き直した後(次のフレームの後)に捨てる。
      if (previous != defaultGalaxyConfig && previous != next.toConfig()) {
        WidgetsBinding.instance.addPostFrameCallback((_) => container.invalidate(galaxyDataProvider(previous)));
      }
    }

    void showEarned(int n) {
      earned.value = n;
      apply(_TunerValues.fromLook(galaxyLookForEarnedStars(n), seed: draft.value.seed, zoomRule: draft.value.zoomRule));
    }

    // 再生中は0.2秒ごとに1日進め、その日までに集めた星の数(1日55個)の銀河を描く
    useEffect(() {
      if (!playing.value) return null;
      final timer = Timer.periodic(_simTickPerDay, (_) {
        final day = (earned.value / galaxyExpectedStarsPerDay).floor() + 1;
        if (day > _simDays) {
          playing.value = false;
          return;
        }
        showEarned(day * galaxyExpectedStarsPerDay);
      });
      return timer.cancel;
    }, [playing.value]);

    // カメラの状態(galaxyStateProvider)はHomeの銀河と共有している。
    // 入った時はこのページの既定の画角にし、出る時はHomeの画角に戻す
    // (Homeに銀河を出しているならその銀河の既定の画角(ページと同じ)、出していなければ入った時の倍率)。
    useEffect(() {
      final notifier = ref.read(galaxyStateProvider.notifier);
      final zoomOnEnter = ref.read(galaxyStateProvider).zoom;
      if (savedPreview != null) Future.microtask(() => notifier.setZoom(initialValues.zoom));
      return () => Future.microtask(() {
            final preview = container.read(galaxyHomePreviewProvider);
            notifier.setZoom(preview?.zoom ?? zoomOnEnter);
          });
    }, const []);

    useEffect(() {
      // 画面遷移完了後にHUDをフェードイン
      Future.delayed(const Duration(milliseconds: 300), () {
        showOverlay.value = true;
      });
      return null;
    }, []);

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Stack(
        children: [
          // 1. 最背面: 引き継がれた3D銀河ビュー (全画面表示)
          Positioned.fill(
            child: Hero(
              tag: 'galaxy',
              child: GalaxyView(
                config: applied.value.toConfig(),
                glowScale: applied.value.glow,
                starScale: applied.value.starScale,
                minZoom: applied.value.zoomRule.minZoomFor(applied.value.radius),
                maxZoom: applied.value.zoomRule.maxZoomFor(applied.value.radius),
              ),
            ),
          ),

          // 2. 左上: SF HUD 戻るボタン ("<")
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: showOverlay.value ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 12),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0x990A0E1A),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x334FA8FF)),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            } else {
                              context.pop();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. 前面: SF HUD オーバーレイ (下部に配置)
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 下部 HUD (カメラ操作、オートオービットトグル、ロードマップ起動)
                AnimatedSlide(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  offset: showOverlay.value ? Offset.zero : const Offset(0, 0.2),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: showOverlay.value ? 1.0 : 0.0,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showTuner.value)
                            _TunerPanel(
                              values: draft.value,
                              cameraZoom: () => ref.read(galaxyStateProvider).zoom,
                              onDrag: (v) {
                                playing.value = false;
                                draft.value = v;
                              },
                              onApply: (v) {
                                playing.value = false;
                                apply(v);
                              },
                            ),
                          if (kGalaxyPageEnabled)
                            _GrowthCard(
                              earned: earned.value,
                              playing: playing.value,
                              onDrag: (n) {
                                playing.value = false;
                                earned.value = n;
                              },
                              onApply: (n) {
                                playing.value = false;
                                showEarned(n);
                              },
                              onTogglePlay: () {
                                if (playing.value) {
                                  playing.value = false;
                                  return;
                                }
                                // 2年まで再生し終わっていたら最初から
                                if (earned.value >= _simDays * galaxyExpectedStarsPerDay) showEarned(0);
                                playing.value = true;
                              },
                              onRestart: () {
                                showEarned(0);
                                playing.value = true;
                              },
                            ),
                          _buildBottomHUD(context, ref, showTuner, applied.value.zoom),
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



  // --- 下部 HUD 設計 ---
  Widget _buildBottomHUD(BuildContext context, WidgetRef ref, ValueNotifier<bool> showTuner, double defaultZoom) {
    final galaxyState = ref.watch(galaxyStateProvider);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x990A0E1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x334FA8FF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 自動回転トグル
          _HUDButton(
            icon: galaxyState.autoRotate ? Icons.sync : Icons.sync_disabled,
            label: 'AUTO ORBIT',
            isActive: galaxyState.autoRotate,
            onTap: () {
              ref.read(galaxyStateProvider.notifier).toggleAutoRotate();
            },
          ),

          // カメラリセット
          _HUDButton(
            icon: Icons.center_focus_strong,
            label: 'RESET CAM',
            isActive: false,
            onTap: () {
              ref.read(galaxyStateProvider.notifier).resetCamera(zoom: defaultZoom);
            },
          ),

          // パラメーター調整パネル
          if (kGalaxyPageEnabled)
            _HUDButton(
              icon: Icons.tune,
              label: l10n.galaxyTunerButton,
              isActive: showTuner.value,
              onTap: () => showTuner.value = !showTuner.value,
            ),
        ],
      ),
    );
  }
}

// --- HUD用 ボタンコンポーネント ---
class _HUDButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _HUDButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0x334FA8FF) // アクティブ時はネオンブルー
                  : const Color(0x1AFFFFFF),
              border: Border.all(
                color: isActive ? const Color(0xFF4FA8FF) : Colors.white24,
                width: 1.0,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF4FA8FF) : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// --- パラメーター調整 ---

/// 調整パネルの値。星は「総数」と「中心(バルジ)の割合」で持ち、GalaxyConfig に変換する。
@immutable
class _TunerValues {
  const _TunerValues({
    this.totalStars = _defaultTotalStars,
    this.bulgeShare = _defaultBulgeShare,
    this.arms = 3,
    this.radius = 1.0,
    this.thickness = 0.05,
    this.bulgeRadiusNorm = 0.2,
    this.innerDiskHoleNorm = 0.14,
    this.nebulaCount = 40,
    this.bgStarCount = 3200,
    this.glow = 1.0,
    this.starScale = 1.0,
    this.seed = 42,
    this.stableGrowth = false,
    this.zoomRule = defaultGalaxyZoomRule,
  });

  final int totalStars;
  final double bulgeShare;
  final int arms;
  final double radius;
  final double thickness;
  final double bulgeRadiusNorm;
  final double innerDiskHoleNorm;
  final int nebulaCount;
  final int bgStarCount;
  final double glow;
  final double starScale;
  final int seed;

  /// 成長プレビュー・シミュレーションでは true(星を足しても既存の星が動かない生成)。
  /// 既定の false はHomeと同じ銀河になる。
  final bool stableGrowth;

  /// 既定の画角の式。画角は半径から求める(Homeとページで同じ)。
  final GalaxyZoomRule zoomRule;

  double get zoom => zoomRule.zoomFor(radius);

  int get bulgeStars => (totalStars * bulgeShare).round();
  int get diskStars => totalStars - bulgeStars;

  factory _TunerValues.fromLook(GalaxyLook l, {required int seed, required GalaxyZoomRule zoomRule}) => _TunerValues(
        totalStars: l.totalStars,
        bulgeShare: l.bulgeShare,
        arms: l.arms,
        radius: l.radius,
        thickness: l.thickness,
        bulgeRadiusNorm: l.bulgeRadiusNorm,
        innerDiskHoleNorm: l.innerDiskHoleNorm,
        nebulaCount: l.nebulaCount,
        bgStarCount: l.bgStarCount,
        glow: l.glow,
        starScale: l.starScale,
        seed: seed,
        stableGrowth: true,
        zoomRule: zoomRule,
      );

  factory _TunerValues.fromPreview(GalaxyHomePreview p) =>
      _TunerValues.fromLook(p.look, seed: p.seed, zoomRule: p.zoomRule).copyWith(stableGrowth: p.stableGrowth);

  GalaxyLook toLook() => GalaxyLook(
        totalStars: totalStars,
        bulgeShare: bulgeShare,
        radius: radius,
        bulgeRadiusNorm: bulgeRadiusNorm,
        nebulaCount: nebulaCount,
        glow: glow,
        starScale: starScale,
        arms: arms,
        thickness: thickness,
        innerDiskHoleNorm: innerDiskHoleNorm,
        bgStarCount: bgStarCount,
      );

  GalaxyConfig toConfig() => GalaxyConfig(
        seed: seed,
        bulgeStarCount: bulgeStars,
        diskStarCount: diskStars,
        arms: arms,
        radius: radius,
        thickness: thickness,
        bulgeRadiusNorm: bulgeRadiusNorm,
        innerDiskHoleNorm: innerDiskHoleNorm,
        nebulaCount: nebulaCount,
        bgStarCount: bgStarCount,
        stableGrowth: stableGrowth,
      );

  _TunerValues copyWith({
    int? totalStars,
    double? bulgeShare,
    int? arms,
    double? radius,
    double? thickness,
    double? bulgeRadiusNorm,
    double? innerDiskHoleNorm,
    int? nebulaCount,
    int? bgStarCount,
    double? glow,
    double? starScale,
    int? seed,
    GalaxyZoomRule? zoomRule,
    bool? stableGrowth,
  }) =>
      _TunerValues(
        totalStars: totalStars ?? this.totalStars,
        bulgeShare: bulgeShare ?? this.bulgeShare,
        arms: arms ?? this.arms,
        radius: radius ?? this.radius,
        thickness: thickness ?? this.thickness,
        bulgeRadiusNorm: bulgeRadiusNorm ?? this.bulgeRadiusNorm,
        innerDiskHoleNorm: innerDiskHoleNorm ?? this.innerDiskHoleNorm,
        nebulaCount: nebulaCount ?? this.nebulaCount,
        bgStarCount: bgStarCount ?? this.bgStarCount,
        glow: glow ?? this.glow,
        starScale: starScale ?? this.starScale,
        seed: seed ?? this.seed,
        stableGrowth: stableGrowth ?? this.stableGrowth,
        zoomRule: zoomRule ?? this.zoomRule,
      );

  /// コピー用。開発者が値を控えたりClaudeに渡したりするための機械向けの文字列なので翻訳しない。
  String toCopyText(double cameraZoom) => 'zoomRule: k=${zoomRule.k.toStringAsFixed(2)}, p=${zoomRule.p.toStringAsFixed(2)} '
      '(stages ${_stageZoomsText(zoomRule)}), defaultZoom=${zoom.toStringAsFixed(2)} '
      '(camera now=${cameraZoom.toStringAsFixed(2)}), totalStars=$totalStars (bulge=$bulgeStars, disk=$diskStars), '
      'bulgeShare=${bulgeShare.toStringAsFixed(2)}, arms=$arms, radius=${radius.toStringAsFixed(2)}, '
      'thickness=${thickness.toStringAsFixed(3)}, bulgeRadiusNorm=${bulgeRadiusNorm.toStringAsFixed(2)}, '
      'innerDiskHoleNorm=${innerDiskHoleNorm.toStringAsFixed(2)}, nebulaCount=$nebulaCount, '
      'bgStarCount=$bgStarCount, glowScale=${glow.toStringAsFixed(2)}, starScale=${starScale.toStringAsFixed(2)}, seed=$seed';
}

/// 5段階それぞれの既定の画角(表示・コピー用、翻訳しない数値の並び)。
String _stageZoomsText(GalaxyZoomRule rule) => GalaxyStage.values
    .map((st) => rule.zoomFor(galaxyStageLooks[st]!.radius).toStringAsFixed(1))
    .join(' / ');

String _formatInt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

class _TunerPanel extends StatelessWidget {
  const _TunerPanel({
    required this.values,
    required this.cameraZoom,
    required this.onDrag,
    required this.onApply,
  });

  /// 今のカメラの倍率(ピンチで変えた値も含む)。
  final double Function() cameraZoom;

  final _TunerValues values;
  final ValueChanged<_TunerValues> onDrag;
  final ValueChanged<_TunerValues> onApply;

  static const _presets = [1000, 2500, 5000, 10000, 20000];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.4;
    final v = values;

    Widget slider({
      required String label,
      required String valueText,
      required double value,
      required double min,
      required double max,
      int? divisions,
      required _TunerValues Function(double) update,
    }) {
      return _TunerSlider(
        label: label,
        valueText: valueText,
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (x) => onDrag(update(x)),
        onChangeEnd: (x) => onApply(update(x)),
      );
    }

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xCC0A0E1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x334FA8FF)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.galaxyTunerTitle,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              slider(
                label: l10n.galaxyTunerTotalStars,
                valueText: _formatInt(v.totalStars),
                value: v.totalStars.toDouble(),
                min: 0,
                max: 60000,
                divisions: 120,
                update: (x) => v.copyWith(totalStars: x.round()),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in _presets)
                    _TunerChip(
                      label: _formatInt(n),
                      selected: v.totalStars == n,
                      onTap: () => onApply(v.copyWith(totalStars: n)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.galaxyTunerStarsSplit(_formatInt(v.bulgeStars), _formatInt(v.diskStars)),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              slider(
                label: l10n.galaxyTunerBulgeShare,
                valueText: '${(v.bulgeShare * 100).round()}%',
                value: v.bulgeShare,
                min: 0,
                max: 1,
                divisions: 20,
                update: (x) => v.copyWith(bulgeShare: x),
              ),
              slider(
                label: l10n.galaxyTunerArms,
                valueText: '${v.arms}',
                value: v.arms.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                update: (x) => v.copyWith(arms: x.round()),
              ),
              slider(
                label: l10n.galaxyTunerRadius,
                valueText: v.radius.toStringAsFixed(2),
                value: v.radius,
                min: 0.4,
                max: 1.6,
                divisions: 24,
                update: (x) => v.copyWith(radius: x),
              ),
              slider(
                label: l10n.galaxyTunerThickness,
                valueText: v.thickness.toStringAsFixed(3),
                value: v.thickness,
                min: 0,
                max: 0.2,
                divisions: 40,
                update: (x) => v.copyWith(thickness: x),
              ),
              slider(
                label: l10n.galaxyTunerBulgeRadius,
                valueText: v.bulgeRadiusNorm.toStringAsFixed(2),
                value: v.bulgeRadiusNorm,
                min: 0.05,
                max: 0.5,
                divisions: 45,
                update: (x) => v.copyWith(bulgeRadiusNorm: x),
              ),
              slider(
                label: l10n.galaxyTunerInnerHole,
                valueText: v.innerDiskHoleNorm.toStringAsFixed(2),
                value: v.innerDiskHoleNorm,
                min: 0,
                max: 0.4,
                divisions: 40,
                update: (x) => v.copyWith(innerDiskHoleNorm: x),
              ),
              slider(
                label: l10n.galaxyTunerNebula,
                valueText: '${v.nebulaCount}',
                value: v.nebulaCount.toDouble(),
                min: 0,
                max: 200,
                divisions: 40,
                update: (x) => v.copyWith(nebulaCount: x.round()),
              ),
              slider(
                label: l10n.galaxyTunerBgStars,
                valueText: _formatInt(v.bgStarCount),
                value: v.bgStarCount.toDouble(),
                min: 0,
                max: 6000,
                divisions: 30,
                update: (x) => v.copyWith(bgStarCount: x.round()),
              ),
              slider(
                label: l10n.galaxyTunerZoomK,
                valueText: v.zoomRule.k.toStringAsFixed(2),
                value: v.zoomRule.k,
                min: 1,
                max: 8,
                divisions: 140,
                update: (x) => v.copyWith(zoomRule: v.zoomRule.copyWith(k: x)),
              ),
              slider(
                label: l10n.galaxyTunerZoomP,
                valueText: v.zoomRule.p.toStringAsFixed(2),
                value: v.zoomRule.p,
                min: 0,
                max: 2,
                divisions: 40,
                update: (x) => v.copyWith(zoomRule: v.zoomRule.copyWith(p: x)),
              ),
              Text(
                l10n.galaxyTunerZoomStages(
                  v.zoom.toStringAsFixed(2),
                  _stageZoomsText(v.zoomRule),
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: _TunerChip(
                  label: l10n.galaxyTunerUseCurrentZoom,
                  icon: Icons.center_focus_weak,
                  onTap: () => onApply(
                      v.copyWith(zoomRule: v.zoomRule.fitTo(radius: v.radius, zoom: cameraZoom()))),
                ),
              ),
              const SizedBox(height: 8),
              slider(
                label: l10n.galaxyTunerGlow,
                valueText: v.glow.toStringAsFixed(2),
                value: v.glow,
                min: 0,
                max: 3,
                divisions: 30,
                update: (x) => v.copyWith(glow: x),
              ),
              slider(
                label: l10n.galaxyTunerStarScale,
                valueText: v.starScale.toStringAsFixed(2),
                value: v.starScale,
                min: 0.5,
                max: 6,
                divisions: 55,
                update: (x) => v.copyWith(starScale: x),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.galaxyTunerSeed('${v.seed}'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TunerChip(
                    label: l10n.galaxyTunerShuffle,
                    icon: Icons.shuffle,
                    onTap: () => onApply(v.copyWith(seed: math.Random().nextInt(1 << 31))),
                  ),
                  _TunerChip(
                    label: l10n.galaxyTunerReset,
                    icon: Icons.restart_alt,
                    onTap: () => onApply(const _TunerValues()),
                  ),
                  _TunerChip(
                    label: l10n.galaxyTunerCopy,
                    icon: Icons.copy,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: v.toCopyText(cameraZoom())));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.galaxyTunerCopied), duration: const Duration(seconds: 2)),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TunerSlider extends StatelessWidget {
  const _TunerSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
    this.divisions,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            Text(
              valueText,
              style: const TextStyle(
                color: Color(0xFF4FA8FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: const Color(0xFF4FA8FF),
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _TunerChip extends StatelessWidget {
  const _TunerChip({required this.label, required this.onTap, this.icon, this.selected = false});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0x334FA8FF) : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? const Color(0xFF4FA8FF) : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: Colors.white70),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF4FA8FF) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// --- 成長プレビュー ---

/// 集めた星の数を動かして、銀河がどう育つか(galaxyLookForEarnedStars)を確かめるカード。
/// 5段階のボタンを押すと、その段階にちょうど到達する星の数へ移動する。
class _GrowthCard extends StatelessWidget {
  const _GrowthCard({
    required this.earned,
    required this.playing,
    required this.onDrag,
    required this.onApply,
    required this.onTogglePlay,
    required this.onRestart,
  });

  final int earned;
  final bool playing;
  final ValueChanged<int> onDrag;
  final ValueChanged<int> onApply;
  final VoidCallback onTogglePlay;
  final VoidCallback onRestart;

  /// スライダーは対数目盛り(0〜巨大な銀河の星の数)。序盤の細かい変化も動かせるようにするため。
  static final double _maxLog = math.log(1 + galaxyStageEarnedStars[GalaxyStage.huge]!);
  static double _toSlider(int n) => math.log(1 + n) / _maxLog;
  static int _fromSlider(double p) => (math.exp(p * _maxLog) - 1).round();

  String _stageName(AppLocalizations l10n, GalaxyStage stage) => switch (stage) {
        GalaxyStage.newborn => l10n.galaxyStageNewborn,
        GalaxyStage.small => l10n.galaxyStageSmall,
        GalaxyStage.medium => l10n.galaxyStageMedium,
        GalaxyStage.large => l10n.galaxyStageLarge,
        GalaxyStage.huge => l10n.galaxyStageHuge,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final days = (earned / galaxyExpectedStarsPerDay).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0x990A0E1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x334FA8FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.galaxyGrowthEarned(_formatInt(earned), _formatInt(days), '$galaxyExpectedStarsPerDay'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: playing ? l10n.galaxyGrowthPause : l10n.galaxyGrowthPlay,
                visualDensity: VisualDensity.compact,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF4FA8FF)),
                onPressed: onTogglePlay,
              ),
              IconButton(
                tooltip: l10n.galaxyGrowthRestart,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.replay_rounded, color: Colors.white70, size: 20),
                onPressed: onRestart,
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: const Color(0xFF4FA8FF),
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: _toSlider(earned).clamp(0.0, 1.0),
              onChanged: (p) => onDrag(_fromSlider(p)),
              onChangeEnd: (p) => onApply(_fromSlider(p)),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final stage in GalaxyStage.values) ...[
                  _TunerChip(
                    label: _stageName(l10n, stage),
                    selected: earned == galaxyStageEarnedStars[stage],
                    onTap: () => onApply(galaxyStageEarnedStars[stage]!),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
