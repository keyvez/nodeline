import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';

/// A self-contained routing fixture that captures the geometry of a
/// source→target connection and can reproduce the routed path.
class RoutingFixture {
  final String name;
  final Rect sourceRect;
  final Rect targetRect;

  /// Relative position on the source rect (0,0)=topLeft, (1,1)=bottomRight.
  final Offset startRelPos;

  /// Relative position on the target rect.
  final Offset endRelPos;

  final List<Rect> obstacles;
  final double zoom;
  final double devicePixelRatio;

  const RoutingFixture({
    required this.name,
    required this.sourceRect,
    required this.targetRect,
    required this.startRelPos,
    required this.endRelPos,
    this.obstacles = const [],
    this.zoom = 1.0,
    this.devicePixelRatio = 2.0,
  });

  /// Absolute start point resolved from [startRelPos] on [sourceRect],
  /// snapped to the nearest edge.
  Offset get start {
    final raw = Offset(
      sourceRect.left + sourceRect.width * startRelPos.dx,
      sourceRect.top + sourceRect.height * startRelPos.dy,
    );
    return _snapToNearestEdge(raw, sourceRect);
  }

  /// Absolute end point resolved from [endRelPos] on [targetRect],
  /// snapped to the nearest edge.
  Offset get end {
    final raw = Offset(
      targetRect.left + targetRect.width * endRelPos.dx,
      targetRect.top + targetRect.height * endRelPos.dy,
    );
    return _snapToNearestEdge(raw, targetRect);
  }

  /// Routes and returns the full path including start and end.
  List<Offset> route() {
    final waypoints = OrthogonalRouter.route(
      start: start,
      end: end,
      obstacles: obstacles,
      startObjectRect: sourceRect,
      endObjectRect: targetRect,
      devicePixelRatio: devicePixelRatio,
      zoom: zoom,
    );
    return [start, ...waypoints, end];
  }

  /// Snaps a point to the nearest edge of [rect].
  static Offset _snapToNearestEdge(Offset point, Rect rect) {
    final distToLeft = (point.dx - rect.left).abs();
    final distToRight = (point.dx - rect.right).abs();
    final distToTop = (point.dy - rect.top).abs();
    final distToBottom = (point.dy - rect.bottom).abs();
    final minDist = [distToLeft, distToRight, distToTop, distToBottom]
        .reduce((a, b) => a < b ? a : b);

    if ((minDist - distToLeft).abs() < 0.5) {
      return Offset(rect.left, point.dy);
    } else if ((minDist - distToRight).abs() < 0.5) {
      return Offset(rect.right, point.dy);
    } else if ((minDist - distToTop).abs() < 0.5) {
      return Offset(point.dx, rect.top);
    } else {
      return Offset(point.dx, rect.bottom);
    }
  }
}

// ---------------------------------------------------------------------------
// Assertion helpers — property-based, not pixel-exact
// ---------------------------------------------------------------------------

/// All points share the same Y coordinate.
void expectStraightHorizontal(List<Offset> path) {
  final y = path.first.dy;
  for (final p in path) {
    expect((p.dy - y).abs(), lessThan(1.0),
        reason: 'Point $p deviates from horizontal at y=$y');
  }
}

/// All points share the same X coordinate.
void expectStraightVertical(List<Offset> path) {
  final x = path.first.dx;
  for (final p in path) {
    expect((p.dx - x).abs(), lessThan(1.0),
        reason: 'Point $p deviates from vertical at x=$x');
  }
}

/// No fold-back segments (no U-turns where a segment reverses direction).
void expectNoUTurn(List<Offset> path) {
  for (int i = 0; i < path.length - 2; i++) {
    final a = path[i];
    final b = path[i + 1];
    final c = path[i + 2];

    final sameY = (a.dy - b.dy).abs() < 0.5 && (b.dy - c.dy).abs() < 0.5;
    if (sameY) {
      final dirAB = (b.dx - a.dx).sign;
      final dirBC = (c.dx - b.dx).sign;
      if (dirAB != 0 && dirBC != 0) {
        expect(dirAB == dirBC, isTrue,
            reason: 'Horizontal U-turn at index $i: $a -> $b -> $c');
      }
    }

    final sameX = (a.dx - b.dx).abs() < 0.5 && (b.dx - c.dx).abs() < 0.5;
    if (sameX) {
      final dirAB = (b.dy - a.dy).sign;
      final dirBC = (c.dy - b.dy).sign;
      if (dirAB != 0 && dirBC != 0) {
        expect(dirAB == dirBC, isTrue,
            reason: 'Vertical U-turn at index $i: $a -> $b -> $c');
      }
    }
  }
}

/// Path has at most [n] segments (segments = points - 1).
void expectMaxSegments(List<Offset> path, int n) {
  final segments = path.length - 1;
  expect(segments, lessThanOrEqualTo(n),
      reason: 'Path has $segments segments, expected at most $n');
}

/// No segment of [path] crosses any of [rects].
void expectAvoidsRects(List<Offset> path, List<Rect> rects) {
  for (int i = 0; i < path.length - 1; i++) {
    for (final rect in rects) {
      expect(
        segmentIntersectsRect(path[i], path[i + 1], rect),
        isFalse,
        reason: 'Segment ${path[i]} -> ${path[i + 1]} crosses $rect',
      );
    }
  }
}

/// First segment exits the source rect in the expected [edge] direction.
/// [edge] is one of: 'left', 'right', 'top', 'bottom'.
void expectExitsFromEdge(List<Offset> path, Rect rect, String edge) {
  expect(path.length, greaterThanOrEqualTo(2));
  final start = path[0];
  final next = path[1];
  switch (edge) {
    case 'left':
      expect(next.dx, lessThan(start.dx),
          reason: 'Expected left exit but dx increased');
    case 'right':
      expect(next.dx, greaterThan(start.dx),
          reason: 'Expected right exit but dx decreased');
    case 'top':
      expect(next.dy, lessThan(start.dy),
          reason: 'Expected top exit but dy increased');
    case 'bottom':
      expect(next.dy, greaterThan(start.dy),
          reason: 'Expected bottom exit but dy decreased');
    default:
      fail('Unknown edge: $edge');
  }
}

/// Two fixtures produce paths with the same structural turn sequence
/// (same H/V pattern). E.g. both produce H-V-H or V-H-V etc.
void expectRoutesLike(RoutingFixture fixtureA, RoutingFixture fixtureB) {
  final pathA = fixtureA.route();
  final pathB = fixtureB.route();
  final patternA = _turnPattern(pathA);
  final patternB = _turnPattern(pathB);
  expect(patternA, equals(patternB),
      reason: '${fixtureA.name} pattern $patternA != ${fixtureB.name} pattern $patternB');
}

String _turnPattern(List<Offset> path) {
  final buf = StringBuffer();
  for (int i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    if ((a.dy - b.dy).abs() < 0.5) {
      buf.write('H');
    } else if ((a.dx - b.dx).abs() < 0.5) {
      buf.write('V');
    } else {
      buf.write('D'); // diagonal (shouldn't happen for orthogonal)
    }
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Shared test utility functions (moved from orthogonal_router_test.dart)
// ---------------------------------------------------------------------------

/// Verifies all consecutive points in the path are axis-aligned.
void verifyAxisAligned(List<Offset> path) {
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
void verifyNoOverlappingSegments(List<Offset> path) {
  for (int i = 0; i < path.length - 2; i++) {
    final a = path[i];
    final b = path[i + 1];
    final c = path[i + 2];
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

/// Minimum distance from a point to any edge of a rectangle.
double minDistToRect(Offset p, Rect rect) {
  if (p.dx >= rect.left && p.dx <= rect.right &&
      p.dy >= rect.top && p.dy <= rect.bottom) {
    return 0;
  }
  final clampedX = p.dx.clamp(rect.left, rect.right);
  final clampedY = p.dy.clamp(rect.top, rect.bottom);
  final dx = p.dx - clampedX;
  final dy = p.dy - clampedY;
  return (dx.abs() > dy.abs()) ? dx.abs() : dy.abs();
}

/// Simplified segment-rect intersection for test verification.
bool segmentIntersectsRect(Offset a, Offset b, Rect rect) {
  if ((a.dy - b.dy).abs() < 0.01) {
    final y = a.dy;
    final minX = a.dx < b.dx ? a.dx : b.dx;
    final maxX = a.dx > b.dx ? a.dx : b.dx;
    if (y > rect.top && y < rect.bottom && maxX > rect.left && minX < rect.right) {
      return true;
    }
  } else if ((a.dx - b.dx).abs() < 0.01) {
    final x = a.dx;
    final minY = a.dy < b.dy ? a.dy : b.dy;
    final maxY = a.dy > b.dy ? a.dy : b.dy;
    if (x > rect.left && x < rect.right && maxY > rect.top && minY < rect.bottom) {
      return true;
    }
  }
  return false;
}
