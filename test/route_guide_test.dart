import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';

import 'routing_test_helpers.dart';

void main() {
  group('OrthogonalRouter.route guide bias', () {
    test('an empty guide leaves the route unchanged', () {
      const start = Offset(0, 0);
      const end = Offset(200, 100);
      final plain = OrthogonalRouter.route(start: start, end: end, obstacles: []);
      final withEmpty =
          OrthogonalRouter.route(start: start, end: end, obstacles: [], guide: const []);
      expect(withEmpty, equals(plain));
    });

    test('guide pulls the route toward the drawn stroke', () {
      const start = Offset(0, 0);
      const end = Offset(300, 0);
      // No obstacles: the plain route is a straight horizontal line (no
      // waypoints). A guide that bows downward should make the route dip toward
      // it, producing waypoints with positive Y.
      final plain = OrthogonalRouter.route(start: start, end: end, obstacles: []);
      expect(plain, isEmpty, reason: 'straight axis-aligned route needs no bend');

      final guide = const [
        Offset(0, 0),
        Offset(150, 140),
        Offset(300, 0),
      ];
      final guided =
          OrthogonalRouter.route(start: start, end: end, obstacles: [], guide: guide);

      final fullPath = [start, ...guided, end];
      verifyAxisAligned(fullPath);
      expect(guided, isNotEmpty,
          reason: 'guide should introduce a detour toward the stroke');
      final maxY = fullPath.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
      expect(maxY, greaterThan(40),
          reason: 'route should bow toward the downward guide, got $fullPath');
    });

    test('guide never routes through an obstacle', () {
      const start = Offset(0, 0);
      const end = Offset(300, 0);
      // Obstacle squarely in the middle of the direct path.
      final obstacle = const Rect.fromLTWH(120, -40, 60, 80);
      // A guide that cuts straight through the obstacle must NOT override
      // obstacle avoidance — the path must still clear the box.
      final guide = const [Offset(0, 0), Offset(150, 0), Offset(300, 0)];
      final waypoints = OrthogonalRouter.route(
        start: start,
        end: end,
        obstacles: [obstacle],
        guide: guide,
      );
      final fullPath = [start, ...waypoints, end];
      verifyAxisAligned(fullPath);
      // No segment of the path may pass through the obstacle interior.
      for (int i = 0; i < fullPath.length - 1; i++) {
        final a = fullPath[i];
        final b = fullPath[i + 1];
        // Sample the segment and assert each sample is outside the obstacle.
        for (int s = 0; s <= 10; s++) {
          final t = s / 10;
          final p = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
          final inside = p.dx > obstacle.left &&
              p.dx < obstacle.right &&
              p.dy > obstacle.top &&
              p.dy < obstacle.bottom;
          expect(inside, isFalse,
              reason: 'guided path entered obstacle at $p (path $fullPath)');
        }
      }
    });

    test('guide that overshoots the target is still honoured', () {
      // Mirrors the real failure: the last guide vertex sits well past `end`.
      // The route must still follow the stroke's bow and arrive at end without
      // doubling back (which previously made it fall back to a plain route).
      const start = Offset(263, -350);
      const end = Offset(835, -348);
      final guide = const [
        Offset(263, -350),
        Offset(400, -540),
        Offset(750, -540),
        Offset(1291, -351), // overshoots end.x by ~456px
      ];
      final wp = OrthogonalRouter.route(
          start: start, end: end, obstacles: [], guide: guide);
      final full = [start, ...wp, end];
      verifyAxisAligned(full);
      expect(wp, isNotEmpty, reason: 'overshooting guide should still shape the route');
      // The route bows upward (negative Y) toward the stroke.
      final minY = full.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      expect(minY, lessThan(-400),
          reason: 'route should follow the upward bow, got $full');
      // No waypoint should sit past the overshoot — the path must not run out to
      // x≈1291 and back.
      final maxX = full.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
      expect(maxX, lessThanOrEqualTo(end.dx + 1),
          reason: 'route must not double back past the target, got $full');
    });

    test('short perpendicular jogs are flattened', () {
      // A guide that produces a tiny step (noise) should yield a clean route
      // without a sub-24px jog segment.
      const start = Offset(0, 0);
      const end = Offset(400, 8); // 8px vertical offset = noise
      final guide = const [
        Offset(0, 0),
        Offset(200, 120),
        Offset(400, 8),
      ];
      final wp = OrthogonalRouter.route(
          start: start, end: end, obstacles: [], guide: guide);
      final full = [start, ...wp, end];
      verifyAxisAligned(full);
      for (int i = 0; i < full.length - 1; i++) {
        final segLen = (full[i] - full[i + 1]).distance;
        // Allow the final tiny approach into `end` (8px) but no interior jog.
        final isEndApproach = i == full.length - 2;
        if (!isEndApproach) {
          expect(segLen, greaterThanOrEqualTo(20),
              reason: 'interior jog of $segLen px not flattened in $full');
        }
      }
    });
  });
}
