import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/core/utils/path_layout.dart';

void main() {
  group('PathLayout.distribute', () {
    test('spreads boxes evenly along an open straight path, endpoints inclusive',
        () {
      // Three boxes in a vertical line, guide is a horizontal segment 0..300.
      final boxes = {
        'a': const Offset(10, 5),
        'b': const Offset(10, 10),
        'c': const Offset(10, 15),
      };
      final result = PathLayout.distribute(
        boxes: boxes,
        polyline: const [Offset(0, 0), Offset(300, 0)],
        closed: false,
      );
      // n=3 open path → arc lengths 0, 150, 300.
      // Boxes all project near x≈10 so order is preserved (a,b,c by insertion).
      final xs = result.values.map((o) => o.dx).toList()..sort();
      expect(xs[0], closeTo(0, 0.001));
      expect(xs[1], closeTo(150, 0.001));
      expect(xs[2], closeTo(300, 0.001));
      // All land on the guide line (y=0).
      for (final o in result.values) {
        expect(o.dy, closeTo(0, 0.001));
      }
    });

    test('orders boxes by their projection onto the path', () {
      // Boxes given out of order; guide runs left→right. The box currently
      // furthest right should end up at the path end.
      final boxes = {
        'right': const Offset(250, 50),
        'left': const Offset(20, 50),
        'mid': const Offset(140, 50),
      };
      final result = PathLayout.distribute(
        boxes: boxes,
        polyline: const [Offset(0, 0), Offset(300, 0)],
        closed: false,
      );
      expect(result['left']!.dx, closeTo(0, 0.001));
      expect(result['mid']!.dx, closeTo(150, 0.001));
      expect(result['right']!.dx, closeTo(300, 0.001));
    });

    test('distributes around a closed loop without piling at the seam', () {
      // 4 boxes around a circle approximated by a square polyline.
      final boxes = {
        'a': const Offset(0, -10),
        'b': const Offset(10, 0),
        'c': const Offset(0, 10),
        'd': const Offset(-10, 0),
      };
      // Closed square loop, perimeter 800, centred at origin.
      final result = PathLayout.distribute(
        boxes: boxes,
        polyline: const [
          Offset(-100, -100),
          Offset(100, -100),
          Offset(100, 100),
          Offset(-100, 100),
        ],
        closed: true,
      );
      expect(result.length, 4);
      // The 4 placements must be 4 distinct points (no seam pile-up).
      final unique = result.values.toSet();
      expect(unique.length, 4);
      // Evenly spaced → consecutive arc gaps all equal (200 each on an 800 loop).
      // Verify all placements lie on the square's boundary.
      for (final o in result.values) {
        final onBoundary = (o.dx.abs() == 100 && o.dy.abs() <= 100) ||
            (o.dy.abs() == 100 && o.dx.abs() <= 100);
        expect(onBoundary, isTrue, reason: '$o not on boundary');
      }
    });

    test('single box on an open path lands at the midpoint', () {
      final result = PathLayout.distribute(
        boxes: {'only': const Offset(0, 99)},
        polyline: const [Offset(0, 0), Offset(100, 0)],
        closed: false,
      );
      expect(result['only']!.dx, closeTo(50, 0.001));
    });

    test('degenerate guide (single point) yields no placements', () {
      final result = PathLayout.distribute(
        boxes: {'a': Offset.zero},
        polyline: const [Offset(5, 5), Offset(5, 5)],
        closed: false,
      );
      expect(result, isEmpty);
    });

    test('handles a curved (multi-segment) open polyline', () {
      // L-shaped guide: right 100 then down 100, total length 200.
      final boxes = {
        'a': const Offset(0, 0),
        'b': const Offset(100, 100),
      };
      final result = PathLayout.distribute(
        boxes: boxes,
        polyline: const [Offset(0, 0), Offset(100, 0), Offset(100, 100)],
        closed: false,
      );
      // Endpoints of the L.
      final placements = result.values.toList();
      // One at the corner-start (0,0), one at the far end (100,100).
      final hasStart =
          placements.any((o) => (o - const Offset(0, 0)).distance < 0.01);
      final hasEnd =
          placements.any((o) => (o - const Offset(100, 100)).distance < 0.01);
      expect(hasStart, isTrue);
      expect(hasEnd, isTrue);
    });

    test('places many boxes evenly on a sampled circle', () {
      // 8 boxes, circle of radius 100 sampled finely.
      const segments = 360;
      final polyline = [
        for (int i = 0; i < segments; i++)
          Offset(100 * cos(2 * pi * i / segments),
              100 * sin(2 * pi * i / segments)),
      ];
      final boxes = {
        for (int i = 0; i < 8; i++)
          'n$i': Offset(
              100 * cos(2 * pi * i / 8), 100 * sin(2 * pi * i / 8)),
      };
      final result =
          PathLayout.distribute(boxes: boxes, polyline: polyline, closed: true);
      expect(result.length, 8);
      // All ~radius 100 from origin.
      for (final o in result.values) {
        expect(o.distance, closeTo(100, 1.0));
      }
    });
  });
}
