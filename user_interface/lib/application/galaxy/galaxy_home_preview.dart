import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/galaxy/galaxy_data_provider.dart';
import 'package:lefture/application/galaxy/galaxy_growth.dart';

// ---------------------------------------------------------------------------
// 開発ビルド専用: Learning Galaxy ページで選んだ銀河(成長の段階・調整した値)を
// Homeの銀河にも出して、Homeでの見え方(特に画角)を確かめるための共有状態。
// 本番ビルドではLearning Galaxyページに入れないので、常に null(Homeは従来どおり)。
// ---------------------------------------------------------------------------

@immutable
class GalaxyHomePreview {
  const GalaxyHomePreview({
    required this.look,
    required this.seed,
    required this.stableGrowth,
    required this.earned,
    required this.zoomRule,
  });

  /// 見た目一式。
  final GalaxyLook look;

  /// 既定の画角の式(Homeとページで同じ)。
  final GalaxyZoomRule zoomRule;

  /// この銀河の既定の画角。
  double get zoom => zoomRule.zoomFor(look.radius);

  /// この銀河でピンチで引ける限界・寄れる限界(既定の画角に比例)。
  double get minZoom => zoomRule.minZoomFor(look.radius);
  double get maxZoom => zoomRule.maxZoomFor(look.radius);
  final int seed;
  final bool stableGrowth;

  /// 成長プレビューの「集めた星の数」(ページに入り直した時に復元する)。
  final int earned;

  GalaxyConfig get config => look.toConfig(seed: seed).copyWith(stableGrowth: stableGrowth);

  GalaxyHomePreview withZoomRule(GalaxyZoomRule rule) => GalaxyHomePreview(
        look: look,
        seed: seed,
        stableGrowth: stableGrowth,
        earned: earned,
        zoomRule: rule,
      );
}

class GalaxyHomePreviewNotifier extends Notifier<GalaxyHomePreview?> {
  @override
  GalaxyHomePreview? build() => null;

  void set(GalaxyHomePreview? preview) => state = preview;

  /// Homeでピンチして合わせた画角を、今の銀河の大きさの既定の画角として保存する。
  /// 式の k を決め直すので、ほかの大きさの画角も同じ比率で変わる(p はそのまま)。
  void saveZoom(double zoom) {
    final current = state;
    if (current != null) {
      state = current.withZoomRule(current.zoomRule.fitTo(radius: current.look.radius, zoom: zoom));
    }
  }
}

final galaxyHomePreviewProvider =
    NotifierProvider<GalaxyHomePreviewNotifier, GalaxyHomePreview?>(GalaxyHomePreviewNotifier.new);
