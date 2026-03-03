import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

class OrthogonalRouter {
  static const double _padding = 25.0;
  static const double _searchInflation = 300.0;
  static const int _maxObstacles = 20;

  /// Routes an orthogonal path from [start] to [end], avoiding [obstacles].
  ///
  /// Returns a list of intermediate waypoints (excluding start and end).
  /// Every segment between consecutive points (including start/end) is
  /// guaranteed to be axis-aligned (horizontal or vertical).
  static List<Offset> route({
    required Offset start,
    required Offset end,
    required List<Rect> obstacles,
    Rect? startObjectRect,
    Rect? endObjectRect,
  }) {
    // Filter and inflate obstacles first (needed for obstacle-aware exit stubs)
    final searchArea = Rect.fromPoints(start, end).inflate(_searchInflation);
    var relevantObstacles = obstacles.where((r) => searchArea.overlaps(r)).toList();

    if (relevantObstacles.length > _maxObstacles) {
      final center = (start + end) / 2;
      relevantObstacles.sort((a, b) =>
          (a.center - center).distanceSquared.compareTo(
            (b.center - center).distanceSquared,
          ));
      relevantObstacles = relevantObstacles.sublist(0, _maxObstacles);
    }

    final inflated = relevantObstacles.map((r) => r.inflate(_padding)).toList();
    // Wider inflation for candidate waypoints — routes maintain visible gap from objects
    final candidateInflated = relevantObstacles.map((r) => r.inflate(_padding + 5.0)).toList();

    // Compute exit/entry stubs if attached to objects
    // Use obstacle-aware version to avoid landing inside another obstacle
    final startExit = startObjectRect != null
        ? _computeExitPoint(start, startObjectRect, inflated, end)
        : null;
    final endEntry = endObjectRect != null
        ? _computeExitPoint(end, endObjectRect, inflated, start)
        : null;

    final routeStart = startExit ?? start;
    final routeEnd = endEntry ?? end;

    // Try to find a clean path between routeStart and routeEnd
    List<Offset> innerWaypoints;
    if (inflated.isEmpty) {
      innerWaypoints = const [];
    } else {
      // Check if a simple L-path works, and if so, use the correct corner
      final clearCorner = _findClearLCorner(routeStart, routeEnd, inflated);
      if (clearCorner != null) {
        // clearCorner == routeStart is sentinel for "direct axis-aligned segment is clear"
        if (clearCorner == routeStart) {
          innerWaypoints = const [];
        } else {
          innerWaypoints = [clearCorner];
        }
      } else {
        final candidates = _generateCandidates(routeStart, routeEnd, candidateInflated, inflated);
        innerWaypoints = _findPath(routeStart, routeEnd, candidates, inflated);
      }
    }

    // Assemble full waypoint list: start + exitStub + inner + entryStub + end
    final fullPath = <Offset>[start];
    if (startExit != null) fullPath.add(startExit);
    for (final wp in innerWaypoints) {
      fullPath.add(wp);
    }
    if (endEntry != null) fullPath.add(endEntry);
    fullPath.add(end);

    // Ensure every consecutive pair is axis-aligned
    final aligned = _ensureAxisAligned(fullPath);

    // Build set of protected points (by value) that must not be simplified away
    final protectedPoints = <Offset>{start, end};
    if (startExit != null) protectedPoints.add(startExit);
    if (endEntry != null) protectedPoints.add(endEntry);

    bool isProtected(Offset p) {
      return protectedPoints.any((pp) =>
          (pp.dx - p.dx).abs() < 0.5 && (pp.dy - p.dy).abs() < 0.5);
    }

    // Remove collinear intermediate points, preserving protected points
    final result = <Offset>[aligned.first];
    for (int i = 1; i < aligned.length - 1; i++) {
      if (isProtected(aligned[i])) {
        result.add(aligned[i]);
        continue;
      }
      final prev = result.last;
      final curr = aligned[i];
      final next = aligned[i + 1];
      final sameX = (prev.dx - curr.dx).abs() < 0.5 &&
          (curr.dx - next.dx).abs() < 0.5;
      final sameY = (prev.dy - curr.dy).abs() < 0.5 &&
          (curr.dy - next.dy).abs() < 0.5;
      if (sameX || sameY) continue;
      result.add(aligned[i]);
    }
    result.add(aligned.last);

    // Expand U-turns (fold-backs) into visible loops with offset
    final expanded = _expandUTurns(result);

    // Return only the intermediate waypoints (strip start and end)
    if (expanded.length <= 2) return const [];
    return expanded.sublist(1, expanded.length - 1);
  }

  /// Computes optimal attachment points on two connected object rects.
  ///
  /// Returns (startPoint, endPoint) positioned on the edges of each rect
  /// that make the most sense given the relative positions of the objects.
  /// Prefers connections through clear gaps between objects.
  static (Offset, Offset) computeSmartAttachmentPoints(
      Rect sourceRect, Rect targetRect) {
    final sc = sourceRect.center;
    final tc = targetRect.center;

    // Check for clear gaps on each axis
    final verticalGapBelow = targetRect.top - sourceRect.bottom; // positive = target below with gap
    final verticalGapAbove = sourceRect.top - targetRect.bottom; // positive = target above with gap
    final horizontalGapRight = targetRect.left - sourceRect.right; // positive = target right with gap
    final horizontalGapLeft = sourceRect.left - targetRect.right; // positive = target left with gap

    final hasVerticalGap = verticalGapBelow > -_padding || verticalGapAbove > -_padding;
    final hasHorizontalGap = horizontalGapRight > -_padding || horizontalGapLeft > -_padding;

    // If there's a clear vertical gap, prefer vertical connection
    if (hasVerticalGap && (!hasHorizontalGap || (tc.dy - sc.dy).abs() >= (tc.dx - sc.dx).abs())) {
      if (tc.dy > sc.dy) {
        return (sourceRect.bottomCenter, targetRect.topCenter);
      } else {
        return (sourceRect.topCenter, targetRect.bottomCenter);
      }
    }

    // If there's a clear horizontal gap, prefer horizontal connection
    if (hasHorizontalGap) {
      if (tc.dx > sc.dx) {
        return (sourceRect.centerRight, targetRect.centerLeft);
      } else {
        return (sourceRect.centerLeft, targetRect.centerRight);
      }
    }

    // Objects overlap on both axes — use center-to-center direction
    if ((tc.dx - sc.dx).abs() > (tc.dy - sc.dy).abs()) {
      if (tc.dx > sc.dx) {
        return (sourceRect.centerRight, targetRect.centerLeft);
      } else {
        return (sourceRect.centerLeft, targetRect.centerRight);
      }
    } else {
      if (tc.dy > sc.dy) {
        return (sourceRect.bottomCenter, targetRect.topCenter);
      } else {
        return (sourceRect.topCenter, targetRect.bottomCenter);
      }
    }
  }

  /// Projects [point] outward from [objectRect], clearing the inflated zone.
  /// Determines exit direction from which edge the point is on, with fallback
  /// to target-directed exits if the natural edge exit is blocked.
  static Offset _computeExitPoint(Offset point, Rect objectRect,
      [List<Rect> inflatedObstacles = const [], Offset? target]) {
    final exitDist = _padding + 5.0;

    // Generate all 4 possible exit points (projecting outward from each edge)
    final left = Offset(objectRect.left - exitDist, point.dy);
    final right = Offset(objectRect.right + exitDist, point.dy);
    final top = Offset(point.dx, objectRect.top - exitDist);
    final bottom = Offset(point.dx, objectRect.bottom + exitDist);

    bool isClear(Offset p) {
      return !inflatedObstacles.any(
        (r) => p.dx > r.left && p.dx < r.right &&
               p.dy > r.top && p.dy < r.bottom,
      );
    }

    // Determine which edge the point is closest to — that's the natural exit
    final distToLeft = (point.dx - objectRect.left).abs();
    final distToRight = (point.dx - objectRect.right).abs();
    final distToTop = (point.dy - objectRect.top).abs();
    final distToBottom = (point.dy - objectRect.bottom).abs();
    final minEdgeDist = min(min(distToLeft, distToRight), min(distToTop, distToBottom));

    Offset naturalExit;
    if ((minEdgeDist - distToBottom).abs() < 1.0) {
      naturalExit = bottom;
    } else if ((minEdgeDist - distToTop).abs() < 1.0) {
      naturalExit = top;
    } else if ((minEdgeDist - distToRight).abs() < 1.0) {
      naturalExit = right;
    } else {
      naturalExit = left;
    }

    // Try the natural exit first
    if (isClear(naturalExit)) return naturalExit;

    // Natural exit is blocked — try target-directed fallback
    double score(Offset exitPt) {
      if (target == null) return 0;
      return (exitPt.dx - target.dx).abs() + (exitPt.dy - target.dy).abs();
    }

    final exits = [left, right, top, bottom];
    exits.sort((a, b) => score(a).compareTo(score(b)));

    for (final exit in exits) {
      if (isClear(exit)) return exit;
    }

    // All padded exits are blocked (objects too close together).
    // Use a minimal stub (just outside the object edge) in the natural
    // direction so the line can pass straight through the tight gap.
    const minStub = 2.0;
    if (naturalExit == bottom) {
      return Offset(point.dx, objectRect.bottom + minStub);
    } else if (naturalExit == top) {
      return Offset(point.dx, objectRect.top - minStub);
    } else if (naturalExit == right) {
      return Offset(objectRect.right + minStub, point.dy);
    } else {
      return Offset(objectRect.left - minStub, point.dy);
    }
  }

  /// Inserts corner points between any non-axis-aligned consecutive pairs
  /// so that every segment is purely horizontal or vertical.
  static List<Offset> _ensureAxisAligned(List<Offset> path) {
    if (path.length < 2) return path;
    final result = <Offset>[path.first];

    for (int i = 1; i < path.length; i++) {
      final a = result.last;
      final b = path[i];

      final isHorizontal = (a.dy - b.dy).abs() < 0.5;
      final isVertical = (a.dx - b.dx).abs() < 0.5;

      if (isHorizontal || isVertical) {
        result.add(b);
      } else {
        // Insert an L-corner: prefer the direction that makes sense
        // (vertical first if horizontal distance is larger, to match typical orthogonal layout)
        final dx = (b.dx - a.dx).abs();
        final dy = (b.dy - a.dy).abs();
        if (dx > dy) {
          result.add(Offset(b.dx, a.dy)); // horizontal then vertical
        } else {
          result.add(Offset(a.dx, b.dy)); // vertical then horizontal
        }
        result.add(b);
      }
    }

    return result;
  }

  /// Detects U-turns (where a segment reverses direction on the same axis)
  /// and expands them into a visible loop with perpendicular offset.
  /// e.g. A→B going left then B→C going right on the same Y becomes:
  /// A → B_offset_up → C_offset_up → C (creating a visible rectangular loop)
  static List<Offset> _expandUTurns(List<Offset> path) {
    if (path.length < 3) return path;
    const uTurnOffset = 20.0;
    final result = <Offset>[path[0]];

    for (int i = 1; i < path.length - 1; i++) {
      final prev = result.last;
      final curr = path[i];
      final next = path[i + 1];

      // Check for horizontal fold-back (same Y for all three, reverses X direction)
      final allSameY = (prev.dy - curr.dy).abs() < 0.5 &&
          (curr.dy - next.dy).abs() < 0.5;
      if (allSameY) {
        final dirIn = (curr.dx - prev.dx).sign;
        final dirOut = (next.dx - curr.dx).sign;
        if (dirIn != 0 && dirOut != 0 && dirIn == -dirOut) {
          // U-turn on horizontal axis — offset perpendicular (vertical)
          // Choose offset direction: prefer going toward the side with more room
          final offsetY = curr.dy - prev.dy >= 0 ? -uTurnOffset : uTurnOffset;
          result.add(Offset(curr.dx, curr.dy + offsetY));
          result.add(Offset(next.dx, curr.dy + offsetY));
          // next will be added normally
          continue;
        }
      }

      // Check for vertical fold-back (same X for all three, reverses Y direction)
      final allSameX = (prev.dx - curr.dx).abs() < 0.5 &&
          (curr.dx - next.dx).abs() < 0.5;
      if (allSameX) {
        final dirIn = (curr.dy - prev.dy).sign;
        final dirOut = (next.dy - curr.dy).sign;
        if (dirIn != 0 && dirOut != 0 && dirIn == -dirOut) {
          // U-turn on vertical axis — offset perpendicular (horizontal)
          final offsetX = curr.dx - prev.dx >= 0 ? -uTurnOffset : uTurnOffset;
          result.add(Offset(curr.dx + offsetX, curr.dy));
          result.add(Offset(curr.dx + offsetX, next.dy));
          continue;
        }
      }

      result.add(curr);
    }

    result.add(path.last);
    return result;
  }

  /// Returns the clear L-corner between [start] and [end], or null if both
  /// L-paths are blocked. This ensures we use the actual clear corner rather
  /// than letting _ensureAxisAligned pick one that might be blocked.
  static Offset? _findClearLCorner(Offset start, Offset end, List<Rect> obstacles) {
    // If start and end are already axis-aligned, no corner needed
    if ((start.dx - end.dx).abs() < 0.5 || (start.dy - end.dy).abs() < 0.5) {
      // Check the direct segment
      if (!_segmentHitsAny(start, end, obstacles)) return start; // sentinel: path is clear
      return null;
    }

    final corner1 = Offset(end.dx, start.dy);
    if (!_segmentHitsAny(start, corner1, obstacles) &&
        !_segmentHitsAny(corner1, end, obstacles)) {
      return corner1;
    }
    final corner2 = Offset(start.dx, end.dy);
    if (!_segmentHitsAny(start, corner2, obstacles) &&
        !_segmentHitsAny(corner2, end, obstacles)) {
      return corner2;
    }
    return null;
  }

  static bool _segmentHitsAny(Offset a, Offset b, List<Rect> obstacles) {
    for (final rect in obstacles) {
      if (_segmentIntersectsRect(a, b, rect)) return true;
    }
    return false;
  }

  static bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
    if ((a.dy - b.dy).abs() < 0.01) {
      final y = a.dy;
      final minX = min(a.dx, b.dx);
      final maxX = max(a.dx, b.dx);
      if (y >= rect.top && y <= rect.bottom &&
          maxX >= rect.left && minX <= rect.right) {
        return true;
      }
    } else {
      final x = a.dx;
      final minY = min(a.dy, b.dy);
      final maxY = max(a.dy, b.dy);
      if (x >= rect.left && x <= rect.right &&
          maxY >= rect.top && minY <= rect.bottom) {
        return true;
      }
    }
    return false;
  }

  static List<Offset> _generateCandidates(
    Offset start,
    Offset end,
    List<Rect> candidateRects,
    List<Rect> collisionRects,
  ) {
    final candidates = <Offset>{};

    // Generate corners and alignment points from the wider candidate rects
    // so that routes maintain visible padding from objects
    for (final rect in candidateRects) {
      candidates.add(rect.topLeft);
      candidates.add(rect.topRight);
      candidates.add(rect.bottomLeft);
      candidates.add(rect.bottomRight);
    }

    for (final rect in candidateRects) {
      candidates.add(Offset(rect.left, start.dy));
      candidates.add(Offset(rect.right, start.dy));
      candidates.add(Offset(start.dx, rect.top));
      candidates.add(Offset(start.dx, rect.bottom));
      candidates.add(Offset(rect.left, end.dy));
      candidates.add(Offset(rect.right, end.dy));
      candidates.add(Offset(end.dx, rect.top));
      candidates.add(Offset(end.dx, rect.bottom));
    }

    // Filter out points that land inside collision rects
    candidates.removeWhere(
      (p) => collisionRects.any(
        (r) => p.dx > r.left && p.dx < r.right &&
               p.dy > r.top && p.dy < r.bottom,
      ),
    );

    return candidates.toList();
  }

  static List<Offset> _findPath(
    Offset start,
    Offset end,
    List<Offset> candidates,
    List<Rect> inflatedObstacles,
  ) {
    final points = [start, ...candidates, end];
    final n = points.length;
    final startIdx = 0;
    final endIdx = n - 1;

    final adj = List.generate(n, (_) => <(int, double)>[]);

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final a = points[i];
        final b = points[j];

        // Direct axis-aligned connection
        if ((a.dx - b.dx).abs() < 0.01 || (a.dy - b.dy).abs() < 0.01) {
          if (!_segmentHitsAny(a, b, inflatedObstacles)) {
            final dist = (a.dx - b.dx).abs() + (a.dy - b.dy).abs();
            adj[i].add((j, dist));
            adj[j].add((i, dist));
            continue;
          }
        }

        // L-shaped via corner
        final corner1 = Offset(a.dx, b.dy);
        if (!inflatedObstacles.any((r) =>
                corner1.dx > r.left && corner1.dx < r.right &&
                corner1.dy > r.top && corner1.dy < r.bottom) &&
            !_segmentHitsAny(a, corner1, inflatedObstacles) &&
            !_segmentHitsAny(corner1, b, inflatedObstacles)) {
          final dist = (a.dx - b.dx).abs() + (a.dy - b.dy).abs();
          adj[i].add((j, dist));
          adj[j].add((i, dist));
          continue;
        }

        final corner2 = Offset(b.dx, a.dy);
        if (!inflatedObstacles.any((r) =>
                corner2.dx > r.left && corner2.dx < r.right &&
                corner2.dy > r.top && corner2.dy < r.bottom) &&
            !_segmentHitsAny(a, corner2, inflatedObstacles) &&
            !_segmentHitsAny(corner2, b, inflatedObstacles)) {
          final dist = (a.dx - b.dx).abs() + (a.dy - b.dy).abs();
          adj[i].add((j, dist));
          adj[j].add((i, dist));
        }
      }
    }

    // Dijkstra
    final dist = List.filled(n, double.infinity);
    final prev = List.filled(n, -1);
    final visited = List.filled(n, false);
    dist[startIdx] = 0;

    final pq = SplayTreeSet<(double, int)>((a, b) {
      final cmp = a.$1.compareTo(b.$1);
      if (cmp != 0) return cmp;
      return a.$2.compareTo(b.$2);
    });
    pq.add((0.0, startIdx));

    while (pq.isNotEmpty) {
      final (d, u) = pq.first;
      pq.remove(pq.first);
      if (visited[u]) continue;
      visited[u] = true;
      if (u == endIdx) break;

      for (final (v, w) in adj[u]) {
        if (visited[v]) continue;
        final newDist = d + w;
        if (newDist < dist[v]) {
          pq.remove((dist[v], v));
          dist[v] = newDist;
          prev[v] = u;
          pq.add((newDist, v));
        }
      }
    }

    if (dist[endIdx] == double.infinity) return const [];

    final path = <int>[];
    for (int at = endIdx; at != -1; at = prev[at]) {
      path.add(at);
    }
    final pathPoints = path.reversed.map((i) => points[i]).toList();

    // Expand: insert L-corners for any non-axis-aligned hops
    final expanded = _ensureAxisAligned(pathPoints);

    if (expanded.length <= 2) return const [];
    final waypoints = expanded.sublist(1, expanded.length - 1);
    return _simplify(waypoints);
  }

  static List<Offset> _simplify(List<Offset> waypoints) {
    if (waypoints.length < 2) return waypoints;
    final result = <Offset>[waypoints.first];
    for (int i = 1; i < waypoints.length; i++) {
      final prev = result.last;
      final curr = waypoints[i];
      if (i < waypoints.length - 1) {
        final next = waypoints[i + 1];
        final sameX = (prev.dx - curr.dx).abs() < 0.01 &&
            (curr.dx - next.dx).abs() < 0.01;
        final sameY = (prev.dy - curr.dy).abs() < 0.01 &&
            (curr.dy - next.dy).abs() < 0.01;
        if (sameX || sameY) continue;
      }
      result.add(curr);
    }
    return result;
  }
}
