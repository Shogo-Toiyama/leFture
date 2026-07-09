// Visual styling shared by the Topic Map views (Cluster View, Lecture View,
// Topic View).
//
// Color roles are kept deliberately separate so they don't compete:
//   - Cluster identity (which "chapter" a node/blob belongs to) owns color,
//     using the validated categorical palette in a fixed hue order.
//   - Edges are plain/uniform ink -- relation_type is metadata revealed as a
//     text label on zoom (see TopicMapEdge.humanizedRelationType), not a
//     line color/style, so it never competes with cluster color.
//   - Ghost nodes are a third, distinct thing again -- rendered dashed and
//     translucent, so they read as "not real yet".
//
// Reference: dataviz skill's validated default palette
// (categorical hues + chart-chrome ink), reused here for a diagram rather
// than a chart.

import 'package:flutter/material.dart';

class TopicMapPalette {
  const TopicMapPalette._();

  // Fixed 12-slot categorical palette, assigned to clusters in
  // first-appearance order (cluster N gets slot N, never a generated/HSL
  // hue). Slots 1-8 are the dataviz skill's validated reference set; slots
  // 9-12 extend it with 4 more hues chosen by a systematic OKLCH hue search
  // (maximize the worst-case CVD delta-E against the existing 8, then
  // against each other) and confirmed with the skill's validator script
  // (node validate_palette.js ... --pairs all, since this is a map where
  // any two clusters can end up spatially adjacent, not an ordered legend).
  // Both light and dark sets pass with only the expected floor-band CVD
  // warning past slot 8 -- legal per the skill's own rule because every
  // cluster/node here always carries a direct text label, never color
  // alone. If a course ever has more than 12 clusters, slot (index % 12)
  // repeats; labels remain the primary identity cue at that point too.
  static const List<Color> clusterLight = [
    Color(0xFF2A78D6), // 1 blue
    Color(0xFF1BAF7A), // 2 aqua
    Color(0xFFEDA100), // 3 yellow
    Color(0xFF008300), // 4 green
    Color(0xFF4A3AA7), // 5 violet
    Color(0xFFE34948), // 6 red
    Color(0xFFE87BA4), // 7 magenta
    Color(0xFFEB6834), // 8 orange
    Color(0xFFA84694), // 9 orchid
    Color(0xFFB54075), // 10 rose
    Color(0xFFBD404D), // 11 brick
    Color(0xFF974DAD), // 12 plum
  ];
  static const List<Color> clusterDark = [
    Color(0xFF3987E5),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFF008300),
    Color(0xFFB45CD9),
    Color(0xFFE66767),
    Color(0xFFD93E88),
    Color(0xFFD95926),
    Color(0xFFB25AA7),
    Color(0xFFC95461),
    Color(0xFF9E62C0),
    Color(0xFF499537),
  ];

  static Color clusterColor(int colorIndex, Brightness brightness) {
    final palette = brightness == Brightness.dark ? clusterDark : clusterLight;
    return palette[colorIndex % palette.length];
  }

  // Ink / chrome tokens (from the dataviz reference palette).
  static const Color surfaceLight = Color(0xFFFCFCFB);
  static const Color surfaceDark = Color(0xFF1A1A19);
  static const Color primaryInkLight = Color(0xFF0B0B0B);
  static const Color primaryInkDark = Color(0xFFFFFFFF);
  static const Color secondaryInkLight = Color(0xFF52514E);
  static const Color secondaryInkDark = Color(0xFFC3C2B7);
  static const Color mutedLight = Color(0xFF898781);
  static const Color mutedDark = Color(0xFF898781);

  static Color surface(Brightness b) => b == Brightness.dark ? surfaceDark : surfaceLight;
  static Color primaryInk(Brightness b) => b == Brightness.dark ? primaryInkDark : primaryInkLight;
  static Color secondaryInk(Brightness b) => b == Brightness.dark ? secondaryInkDark : secondaryInkLight;
  static Color mutedInk(Brightness b) => b == Brightness.dark ? mutedDark : mutedLight;
}

/// Node marker radii, shared between the marker widgets and the painter
/// (which needs them to trim edge lines/arrowheads to the node's edge
/// instead of drawing into its center).
const double kNodeRadius = 18;
const double kGhostNodeRadius = 14;
