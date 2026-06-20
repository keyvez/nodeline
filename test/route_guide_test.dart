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
  });
}
