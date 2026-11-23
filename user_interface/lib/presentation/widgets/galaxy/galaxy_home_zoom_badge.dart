import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/galaxy/galaxy_home_preview.dart';
import 'package:lefture/application/galaxy/galaxy_state_provider.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// 開発ビルド専用: Homeの銀河の隅に出す、今の画角と「保存」ボタン。
/// ピンチで合わせた画角を、今の銀河の大きさの既定の画角として保存する(GalaxyZoomRule の k を決め直す)。
/// Learning Galaxy ページで銀河を選んだ後(galaxyHomePreviewProvider が null でない時)だけ出す。
class GalaxyHomeZoomBadge extends ConsumerWidget {
  const GalaxyHomeZoomBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(galaxyHomePreviewProvider);
    if (preview == null) return const SizedBox.shrink();
    // 倍率が変わった時だけ描き直す(自動回転では倍率は変わらない)
    final zoom = ref.watch(galaxyStateProvider.select((s) => s.zoom));
    final l10n = AppLocalizations.of(context);
    final saved = preview.zoom;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0x990A0E1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x334FA8FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.galaxyHomeZoomBadge(zoom.toStringAsFixed(2), saved.toStringAsFixed(2)),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              ref.read(galaxyHomePreviewProvider.notifier).saveZoom(zoom);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(l10n.galaxyHomeZoomSaved(zoom.toStringAsFixed(2))),
                duration: const Duration(seconds: 2),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x334FA8FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4FA8FF)),
              ),
              child: Text(
                l10n.galaxyHomeZoomSave,
                style: const TextStyle(color: Color(0xFF4FA8FF), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
