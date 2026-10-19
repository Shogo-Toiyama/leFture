import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/presentation/widgets/ai_chat/launch_gate_backdrop.dart';

void main() {
  group('流れ星', () {
    const sizes = [
      Size(430, 700),
      Size(430, 400),
      Size(430, 200),
      Size(430, 110),
      Size(900, 300),
    ];

    /// 頭から見た尾の向き(進む向きの逆)。水平から下向きの角度(度)。
    double tailAngle(MeteorPose p) {
      final d = p.head - p.tail;
      return math.atan2(d.dy, d.dx) * 180 / math.pi;
    }

    /// 少し前から今までの頭の動きの向き(度)。
    double travelAngle(Size s, double k) {
      final a = meteorPose(s, k - .02)!.head;
      final b = meteorPose(s, k)!.head;
      return math.atan2(b.dy - a.dy, b.dx - a.dx) * 180 / math.pi;
    }

    test('どの大きさでも、進む向きと尾の向きが同じで、角度も変わらない', () {
      for (final s in sizes) {
        for (final k in [.2, .4, .5, .7, .9]) {
          final p = meteorPose(s, k)!;
          expect(tailAngle(p), closeTo(24, .01), reason: '$s k=$k');
          expect(travelAngle(s, k), closeTo(24, .01), reason: '$s k=$k');
        }
      }
    });

    test('星空の帯(上から約38%)と横幅の中に収まる', () {
      for (final s in sizes) {
        for (var k = .02; k < 1; k += .02) {
          final p = meteorPose(s, k)!;
          // 頭は帯の中。尾は先ほど透明に消えるので、出だしに先が画面の上端を越えてもよいが、
          // 尾の真ん中までは画面の中に見えている
          expect(
            p.head.dy,
            inInclusiveRange(s.height * .04 - .01, s.height * .38 + .01),
            reason: '$s k=$k',
          );
          final middle = Offset.lerp(p.head, p.tail, .5)!;
          expect(middle.dy, greaterThanOrEqualTo(0), reason: '$s k=$k');
          for (final o in [p.head, p.tail]) {
            expect(o.dx, inInclusiveRange(0, s.width), reason: '$s k=$k');
            expect(o.dy, lessThanOrEqualTo(s.height * .38 + .01));
          }
        }
      }
    });

    test('低い夜空では、同じ角度のまま小さな流れ星になる', () {
      double travel(Size s) {
        final a = meteorPose(s, .001)!.head;
        final b = meteorPose(s, .999)!.head;
        return (b - a).distance;
      }

      expect(
        travel(const Size(430, 110)),
        lessThan(travel(const Size(430, 700)) * .5),
      );
      expect(
        travel(const Size(430, 700)),
        closeTo(430 * .5 / math.cos(24 * math.pi / 180), 1),
      );
    });

    test('流れていない間は見えない', () {
      expect(meteorPose(sizes.first, 1), isNull);
      expect(meteorPose(sizes.first, 3), isNull);
      expect(meteorPose(sizes.first, -.1), isNull);
    });
  });

  group('太陽の光の筋', () {
    int above(List<double> angles) =>
        angles.where((a) => math.sin(a) < -1e-9).length;

    test('全周に引く(半円だけではない)', () {
      final angles = sunRayAngles(0);
      expect(angles, hasLength(36));
      expect(angles.where((a) => math.sin(a) > 1e-9), isNotEmpty);
    });

    test('どれだけ回っても、上半分に見える筋の数はほぼ一定(消えたり半分になったりしない)', () {
      final counts = {
        for (var t = 0.0; t < 600; t += 7.3) above(sunRayAngles(t * .04)),
      };
      expect(
        counts.every((c) => c >= 17 && c <= 19),
        isTrue,
        reason: '$counts',
      );
    });
  });
}
