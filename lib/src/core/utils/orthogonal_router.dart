import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

class OrthogonalRouter {
  static const double _padding = 20.0;
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
    // Compute exit/entry stubs if attached to objects
    final startExit = startObjectRect != null
        ? _computeExitPoint(start, startObjectRect)
        : null;
    final endEntry = endObjectRect != null
        ? _computeExitPoint(end, endObjectRect)
        : null;

    final routeStart = startExit ?? start;
    final routeEnd = endEntry ?? end;

    // Filter and inflate obstacles
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

    // Try to find a clean path between routeStart and routeEnd
    List<Offset> innerWaypoints;
    if (inflated.isEmpty || _isLPathClear(routeStart, routeEnd, inflated)) {
      innerWaypoints = const [];
    } else {
      final candidates = _generateCandidates(routeStart, routeEnd, inflated);
      innerWaypoints = _findPath(routeStart, routeEnd, candidates, inflated);
    }

    // Assemble full waypoint list: startExit + inner + endEntry
    // Then ensure all segments are axis-aligned by inserting L-corners
    final fullPath = <Offset>[start];
    if (startExit != null) fullPath.add(startExit);
    for (final wp in innerWaypoints) {
      fullPath.add(wp);
    }
    if (endEntry != null) fullPath.add(endEntry);
    fullPath.add(end);

    // Ensure every consecutive pair is axis-aligned
    final aligned = _ensureAxisAligned(fullPath);

    // Return only the intermediate waypoints (strip start and end)
    if (aligned.length <= 2) return const [];
    return aligned.sublist(1, aligned.length - 1);
  }

  /// Projects [point] outward from the nearest edge of [objectRect] by [_padding].
  static Offset _computeExitPoint(Offset point, Rect objectRect) {
    final distLeft = (point.dx - objectRect.left).abs();
    final distRight = (point.dx - objectRect.right).abs();
    final distTop = (point.dy - objectRect.top).abs();
    final distBottom = (point.dy - objectRect.bottom).abs();
    final minDist = [distLeft, distRight, distTop, distBottom].reduce(min);

    if (minDist == distLeft) {
      return Offset(objectRect.left - _padding, point.dy);
    } else if (minDist == distRight) {
      return Offset(objectRect.right + _padding, point.dy);
    } else if (minDist == distTop) {
      return Offset(point.dx, objectRect.top - _padding);
    } else {
      return Offset(point.dx, objectRect.bottom + _padding);
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

  static bool _isLPathClear(Offset start, Offset end, List<Rect> obstacles) {
    final corner1 = Offset(end.dx, start.dy);
    if (!_segmentHitsAny(start, corner1, obstacles) &&
        !_segmentHitsAny(corner1, end, obstacles)) {
      return true;
    }
    final corner2 = Offset(start.dx, end.dy);
    if (!_segmentHitsAny(start, corner2, obstacles) &&
        !_segmentHitsAny(corner2, end, obstacles)) {
      return true;
    }
    return false;
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
    List<Rect> inflatedObstacles,
  ) {
    final candidates = <Offset>{};

    for (final rect in inflatedObstacles) {
      candidates.add(rect.topLeft);
      candidates.add(rect.topRight);
      candidates.add(rect.bottomLeft);
      candidates.add(rect.bottomRight);
    }

    for (final rect in inflatedObstacles) {
      candidates.add(Offset(rect.left, start.dy));
      candidates.add(Offset(rect.right, start.dy));
      candidates.add(Offset(start.dx, rect.top));
      candidates.add(Offset(start.dx, rect.bottom));
      candidates.add(Offset(rect.left, end.dy));
      candidates.add(Offset(rect.right, end.dy));
      candidates.add(Offset(end.dx, rect.top));
      candidates.add(Offset(end.dx, rect.bottom));
    }

    candidates.removeWhere(
      (p) => inflatedObstacles.any(
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
