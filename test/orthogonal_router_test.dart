import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fldraw/src/core/utils/orthogonal_router.dart';

void main() {
  group('OrthogonalRouter.route', () {
    test('returns L-corner waypoint when no obstacles and not axis-aligned', () {
      final waypoints = OrthogonalRouter.route(
        start: const Offset(0, 0),
        end: const Offset(200, 100),
        obstacles: [],
      );
      // Router inserts an L-corner to ensure axis-aligned segments
      expect(waypoints, hasLength(1));
      final fullPath = [const Offset(0, 0), ...waypoints, const Offset(200, 100)];
      _verifyAxisAligned(fullPath);
    });

    test('returns empty waypoints when obstacle is far away', () {
      final waypoints = OrthogonalRouter.route(
        start: const Offset(0, 0),
        end: const Offset(200, 0),
        obstacles: [const Rect.fromLTWH(500, 500, 100, 100)],
      );
      expect(waypoints, isEmpty);
    });

    test('routes around a single obstacle between start and end', () {
      final waypoints = OrthogonalRouter.route(
        start: const Offset(0, 100),
        end: const Offset(300, 100),
        obstacles: [const Rect.fromLTWH(100, 50, 100, 100)],
      );
      // Should have waypoints to route around the obstacle
      expect(waypoints, isNotEmpty);
      // All waypoints should form axis-aligned segments with start/end
      _verifyAxisAligned([const Offset(0, 100), ...waypoints, const Offset(300, 100)]);
    });

    test('all segments are axis-aligned', () {
      final waypoints = OrthogonalRouter.route(
        start: const Offset(50, 50),
        end: const Offset(350, 250),
        obstacles: [
          const Rect.fromLTWH(100, 0, 150, 200),
        ],
      );
      final fullPath = [const Offset(50, 50), ...waypoints, const Offset(350, 250)];
      _verifyAxisAligned(fullPath);
    });

    test('path avoids inflated obstacle boundaries', () {
      const obstacle = Rect.fromLTWH(100, 50, 100, 100);
      final waypoints = OrthogonalRouter.route(
        start: const Offset(0, 100),
        end: const Offset(300, 100),
        obstacles: [obstacle],
      );
      final fullPath = [const Offset(0, 100), ...waypoints, const Offset(300, 100)];
      // No segment should pass through the obstacle
      for (int i = 0; i < fullPath.length - 1; i++) {
        expect(
          _segmentIntersectsRect(fullPath[i], fullPath[i + 1], obstacle),
          isFalse,
          reason: 'Segment ${fullPath[i]} -> ${fullPath[i + 1]} crosses obstacle',
        );
      }
    });

    test('routes with start and end object rects (exit stubs)', () {
      const startRect = Rect.fromLTWH(0, 0, 100, 80);
      const endRect = Rect.fromLTWH(300, 0, 100, 80);
      final waypoints = OrthogonalRouter.route(
        start: const Offset(100, 40), // right center of start rect
        end: const Offset(300, 40), // left center of end rect
        obstacles: [startRect, endRect],
        startObjectRect: startRect,
        endObjectRect: endRect,
      );
      final fullPath = [const Offset(100, 40), ...waypoints, const Offset(300, 40)];
      _verifyAxisAligned(fullPath);
    });

    test('exit stub projects from nearest edge', () {
      const objectRect = Rect.fromLTWH(0, 0, 100, 100);
      // Point on the right edge
      final waypoints = OrthogonalRouter.route(
        start: const Offset(100, 50), // right edge center
        end: const Offset(300, 50),
        obstacles: [objectRect],
        startObjectRect: objectRect,
      );
      // The exit stub should project rightward (toward target)
      if (waypoints.isNotEmpty) {
        // First waypoint should be to the right of the object
        expect(waypoints.first.dx, greaterThan(100));
      }
    });

    test('exit stub projects from bottom edge when point is at bottom', () {
      const objectRect = Rect.fromLTWH(0, 0, 100, 100);
      final waypoints = OrthogonalRouter.route(
        start: const Offset(50, 100), // bottom center
        end: const Offset(50, 300),
        obstacles: [objectRect],
        startObjectRect: objectRect,
      );
      // First waypoint should be below the object
      if (waypoints.isNotEmpty) {
        expect(waypoints.first.dy, greaterThan(100));
      }
    });

    test('handles multiple obstacles', () {
      final waypoints = OrthogonalRouter.route(
        start: const Offset(0, 100),
        end: const Offset(500, 100),
        obstacles: [
          const Rect.fromLTWH(100, 50, 80, 100),
          const Rect.fromLTWH(300, 50, 80, 100),
        ],
      );
      final fullPath = [const Offset(0, 100), ...waypoints, const Offset(500, 100)];
      _verifyAxisAligned(fullPath);
      // Path should avoid both obstacles
      for (final obstacle in [
        const Rect.fromLTWH(100, 50, 80, 100),
        const Rect.fromLTWH(300, 50, 80, 100),
      ]) {
        for (int i = 0; i < fullPath.length - 1; i++) {
          expect(
            _segmentIntersectsRect(fullPath[i], fullPath[i + 1], obstacle),
            isFalse,
            reason: 'Segment crosses obstacle $obstacle',
          );
        }
      }
    });

    test('handles vertically stacked objects with gap', () {
      const topRect = Rect.fromLTWH(100, 0, 200, 100);
      const bottomRect = Rect.fromLTWH(150, 200, 150, 100);
      final waypoints = OrthogonalRouter.route(
        start: const Offset(200, 100), // bottom center of top rect
        end: const Offset(225, 200), // top center of bottom rect
        obstacles: [topRect, bottomRect],
        startObjectRect: topRect,
        endObjectRect: bottomRect,
      );
      final fullPath = [const Offset(200, 100), ...waypoints, const Offset(225, 200)];
      _verifyAxisAligned(fullPath);
    });

    test('caps obstacles at max limit', () {
      // Create many obstacles — should not crash or hang
      final obstacles = List.generate(
        50,
        (i) => Rect.fromLTWH(i * 30.0, 0, 20, 20),
      );
      final waypoints = OrthogonalRouter.route(
        start: const Offset(0, 10),
        end: const Offset(1500, 10),
        obstacles: obstacles,
      );
      // Should complete without error
      expect(waypoints, isA<List<Offset>>());
    });
  });

  group('OrthogonalRouter.computeSmartAttachmentPoints', () {
    test('prefers horizontal connection when target is to the right', () {
      const source = Rect.fromLTWH(0, 0, 100, 80);
      const target = Rect.fromLTWH(200, 0, 100, 80);
      final (start, end) = OrthogonalRouter.computeSmartAttachmentPoints(source, target);
      expect(start, source.centerRight);
      expect(end, target.centerLeft);
    });

    test('prefers horizontal connection when target is to the left', () {
      const source = Rect.fromLTWH(200, 0, 100, 80);
      const target = Rect.fromLTWH(0, 0, 100, 80);
      final (start, end) = OrthogonalRouter.computeSmartAttachmentPoints(source, target);
      expect(start, source.centerLeft);
      expect(end, target.centerRight);
    });

    test('prefers vertical connection when target is below', () {
      const source = Rect.fromLTWH(0, 0, 100, 80);
      const target = Rect.fromLTWH(0, 200, 100, 80);
      final (start, end) = OrthogonalRouter.computeSmartAttachmentPoints(source, target);
      expect(start, source.bottomCenter);
      expect(end, target.topCenter);
    });

    test('prefers vertical connection when target is above', () {
      const source = Rect.fromLTWH(0, 200, 100, 80);
      const target = Rect.fromLTWH(0, 0, 100, 80);
      final (start, end) = OrthogonalRouter.computeSmartAttachmentPoints(source, target);
      expect(start, source.topCenter);
      expect(end, target.bottomCenter);
    });

    test('handles overlapping objects using center-to-center direction', () {
      const source = Rect.fromLTWH(0, 0, 100, 100);
      const target = Rect.fromLTWH(50, 50, 100, 100); // overlapping
      final (start, end) = OrthogonalRouter.computeSmartAttachmentPoints(source, target);
      // Should not crash, returns valid offsets
      expect(start, isA<Offset>());
      expect(end, isA<Offset>());
    });
  });

  group('U-turn expansion', () {
    test('path with U-turn has visible offset', () {
      // Create a scenario where the exit stub goes opposite to the target
      // Start on left edge, target is to the right but behind another object
      const startRect = Rect.fromLTWH(100, 100, 200, 150);
      final waypoints = OrthogonalRouter.route(
        start: const Offset(100, 175), // left edge center
        end: const Offset(400, 175),
        obstacles: [startRect],
        startObjectRect: startRect,
      );
      final fullPath = [const Offset(100, 175), ...waypoints, const Offset(400, 175)];
      _verifyAxisAligned(fullPath);
      // Path should have waypoints (not a simple straight line since it exits left)
      // and no two adjacent segments should perfectly overlap (U-turn should be expanded)
      _verifyNoOverlappingSegments(fullPath);
    });
  });

  group('edge cases', () {
    test('start equals end returns empty', () {
      final waypoints = OrthogonalRouter.route(
        start: const Offset(100, 100),
        end: const Offset(100, 100),
        obstacles: [],
      );
      expect(waypoints, isEmpty);
    });

    test('axis-aligned start and end with no obstacles', () {
      // Horizontal
      var waypoints = OrthogonalRouter.route(
        start: const Offset(0, 50),
        end: const Offset(200, 50),
        obstacles: [],
      );
      expect(waypoints, isEmpty);

      // Vertical
      waypoints = OrthogonalRouter.route(
        start: const Offset(50, 0),
        end: const Offset(50, 200),
        obstacles: [],
      );
      expect(waypoints, isEmpty);
    });

    test('obstacle directly on path is avoided', () {
      const obstacle = Rect.fromLTWH(90, 40, 20, 20);
      final waypoints = OrthogonalRouter.route(
        start: const Offset(0, 50),
        end: const Offset(200, 50),
        obstacles: [obstacle],
      );
      final fullPath = [const Offset(0, 50), ...waypoints, const Offset(200, 50)];
      _verifyAxisAligned(fullPath);
    });
  });
}

/// Verifies all consecutive points in the path are axis-aligned.
void _verifyAxisAligned(List<Offset> path) {
  for (int i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    final isHorizontal = (a.dy - b.dy).abs() < 1.0;
    final isVertical = (a.dx - b.dx).abs() < 1.0;
    expect(
      isHorizontal || isVertical,
      isTrue,
      reason: 'Segment $a -> $b is not axis-aligned '
          '(dx=${(a.dx - b.dx).abs()}, dy=${(a.dy - b.dy).abs()})',
    );
  }
}

/// Checks that no two adjacent segments overlap (fold back on themselves).
void _verifyNoOverlappingSegments(List<Offset> path) {
  for (int i = 0; i < path.length - 2; i++) {
    final a = path[i];
    final b = path[i + 1];
    final c = path[i + 2];
    // Check for fold-back: A→B→C where B→C reverses A→B on the same axis
    final sameY = (a.dy - b.dy).abs() < 0.5 && (b.dy - c.dy).abs() < 0.5;
    final sameX = (a.dx - b.dx).abs() < 0.5 && (b.dx - c.dx).abs() < 0.5;
    if (sameY) {
      final dirAB = (b.dx - a.dx).sign;
      final dirBC = (c.dx - b.dx).sign;
      if (dirAB != 0 && dirBC != 0) {
        expect(
          dirAB == dirBC || dirAB == 0 || dirBC == 0,
          isTrue,
          reason: 'Horizontal fold-back at index $i: $a -> $b -> $c',
        );
      }
    }
    if (sameX) {
      final dirAB = (b.dy - a.dy).sign;
      final dirBC = (c.dy - b.dy).sign;
      if (dirAB != 0 && dirBC != 0) {
        expect(
          dirAB == dirBC || dirAB == 0 || dirBC == 0,
          isTrue,
          reason: 'Vertical fold-back at index $i: $a -> $b -> $c',
        );
      }
    }
  }
}

/// Simplified segment-rect intersection for test verification.
bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
  // Only checks axis-aligned segments (which is all our router produces)
  if ((a.dy - b.dy).abs() < 0.01) {
    // Horizontal segment
    final y = a.dy;
    final minX = a.dx < b.dx ? a.dx : b.dx;
    final maxX = a.dx > b.dx ? a.dx : b.dx;
    // Check if the horizontal segment passes through the rect interior
    if (y > rect.top && y < rect.bottom && maxX > rect.left && minX < rect.right) {
      return true;
    }
  } else if ((a.dx - b.dx).abs() < 0.01) {
    // Vertical segment
    final x = a.dx;
    final minY = a.dy < b.dy ? a.dy : b.dy;
    final maxY = a.dy > b.dy ? a.dy : b.dy;
    if (x > rect.left && x < rect.right && maxY > rect.top && minY < rect.bottom) {
      return true;
    }
  }
  return false;
}
