// Google-Maps-style "declutter on zoom": past a certain pinch-zoom scale
// (the same point relation-type edge labels start appearing), node/edge/text
// sizes stop growing with the zoom and instead shrink back down in world
// space by the inverse of the zoom -- so their on-screen size *freezes*
// right at the threshold instead of continuing to grow, while the layout
// (positions/distances) keeps expanding as usual. Net effect: the further
// you zoom in, the more relative breathing room appears around each node,
// which is exactly what declutters a dense cluster instead of just making
// everything (including the crowding) bigger.
//
// factor(scale) = 1                        for scale <= threshold
//               = threshold / scale         for scale >  threshold
//
// Multiplying a world-space size by factor(scale) and then by the ambient
// InteractiveViewer scale gives `size * threshold` beyond the threshold --
// a constant on-screen size, however far past the threshold you zoom.

const double kDetailShrinkStartScale = 1.55;

double detailShrinkFactor(double currentScale) {
  if (currentScale <= kDetailShrinkStartScale) return 1.0;
  return kDetailShrinkStartScale / currentScale;
}

/// The opposite trick, for zooming *out*: below this scale, the big
/// centered cluster title (Cluster View) grows in world space by the
/// inverse of the zoom, so it stays legible instead of shrinking away to
/// nothing as you pull back to see the whole map. Capped at
/// [kClusterLabelMaxGrow] so it can't blow up at extreme zoom-out.
const double kClusterLabelGrowStartScale = 1.0;
const double kClusterLabelMaxGrow = 2.0;

double clusterLabelGrowFactor(double currentScale) {
  if (currentScale >= kClusterLabelGrowStartScale) return 1.0;
  return (kClusterLabelGrowStartScale / currentScale).clamp(1.0, kClusterLabelMaxGrow);
}
