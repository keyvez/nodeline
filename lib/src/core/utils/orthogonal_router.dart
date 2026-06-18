import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

/// Orthogonal (axis-aligned) router using a visibility-graph approach.
///
/// All constants are in world-space — no zoom or DPR scaling. Paths are
/// stable regardless of zoom level.
class OrthogonalRouter {
  /// Debug: total number of route() calls since process start. Lets the
  /// profiler overlay show how often routing actually runs during gestures.
  static int routeCallCountTotal = 0;

  // ── Constants (world-space, no scaling) ──────────────────────────────────
  static const double _padding = 40.0;
  static const double _stubDistance = 45.0;
  static const double _bendPenalty = 20.0;
  // Penalty per unit length of overlap with an existing path segment.
  static const double _overlapPenalty = 8.0;

  /// Routes an orthogonal path from [start] to [end], avoiding [obstacles].
  ///
  /// Returns a list of intermediate waypoints (excluding start and end).
  /// Every segment between consecutive points (including start/end) is
  /// guaranteed to be axis-aligned (horizontal or vertical).
  ///
  /// [existingSegments] is an optional list of (a, b) pairs representing
  /// already-routed paths that this route should try to avoid overlapping.
  ///
  /// [devicePixelRatio] and [zoom] are kept for API compatibility but ignored.
  static List<Offset> route({
    required Offset start,
    required Offset end,
    required List<Rect> obstacles,
    Rect? startObjectRect,
    Rect? endObjectRect,
    List<(Offset, Offset)> existingSegments = const [],
    double devicePixelRatio = 1.0,
    double zoom = 1.0,
  }) {
    routeCallCountTotal++;
    // ── Phase 1: Setup ──────────────────────────────────────────────────
    // Use all obstacles — no distance-based truncation. The search area
    // still filters to relevant ones, but we inflate generously.
    final searchArea = Rect.fromPoints(start, end).inflate(
      max(600.0, (end - start).distance * 1.5),
    );
    final relevant = obstacles.where((r) => searchArea.overlaps(r)).toList();

    final inflated = relevant.map((r) => r.inflate(_padding)).toList();

    // Add source/target as routing obstacles (inflated).
    if (startObjectRect != null) inflated.add(startObjectRect.inflate(_padding));
    if (endObjectRect != null) inflated.add(endObjectRect.inflate(_padding));

    // Inner obstacles: actual shapes with tiny inflation so the path doesn't
    // pass through objects but stubs can still exit cleanly.
    final innerInflated = relevant.map((r) => r.inflate(2.0)).toList();
    if (startObjectRect != null) innerInflated.add(startObjectRect.inflate(2.0));
    if (endObjectRect != null) innerInflated.add(endObjectRect.inflate(2.0));

    // Compute exit/entry stubs.
    final exitStub = startObjectRect != null
        ? _computeExitStub(start, startObjectRect,
            _excludeRect(relevant, inflated, startObjectRect), end)
        : null;
    final entryStub = endObjectRect != null
        ? _computeExitStub(end, endObjectRect,
            _excludeRect(relevant, inflated, endObjectRect), start)
        : null;

    final routeStart = exitStub ?? start;
    final routeEnd = entryStub ?? end;

    // ── Phase 2: Fast paths ─────────────────────────────────────────────
    // Straight line (only if no existing-segment overlap either).
    if (_isAxisAligned(routeStart, routeEnd) &&
        !_segmentHitsAny(routeStart, routeEnd, innerInflated) &&
        _overlapLength(routeStart, routeEnd, existingSegments) < 1.0) {
      return _assemble(start, exitStub, const [], entryStub, end, innerInflated);
    }

    // L-corner — pick the option with less existing-segment overlap.
    final lCorner = _findClearLCorner(routeStart, routeEnd, innerInflated,
        exitDir: exitStub != null ? routeStart - start : null,
        existingSegments: existingSegments);
    if (lCorner != null) {
      final inner = lCorner == routeStart ? const <Offset>[] : [lCorner];
      return _assemble(start, exitStub, inner, entryStub, end, innerInflated);
    }

    // ── Phase 3: U-turn detection ───────────────────────────────────────
    if (exitStub != null && _isUTurn(start, exitStub, end)) {
      final inner = _buildUTurnWaypoints(
          routeStart, routeEnd, exitStub - start, startObjectRect, endObjectRect);
      return _assemble(start, exitStub, inner, entryStub, end, innerInflated);
    }

    // ── Phase 4: Visibility graph + A* ──────────────────────────────────
    final candidates =
        _generateCandidates(routeStart, routeEnd, inflated, innerInflated);
    final astarPath = _astar(
      routeStart,
      routeEnd,
      candidates,
      innerInflated,
      existingSegments: existingSegments,
    );

    return _assemble(start, exitStub, astarPath, entryStub, end, innerInflated);
  }

  // ── Public: Smart attachment points ─────────────────────────────────────

  static (Offset, Offset) computeSmartAttachmentPoints(
      Rect sourceRect, Rect targetRect) {
    final sc = sourceRect.center;
    final tc = targetRect.center;

    final verticalGapBelow = targetRect.top - sourceRect.bottom;
    final verticalGapAbove = sourceRect.top - targetRect.bottom;
    final horizontalGapRight = targetRect.left - sourceRect.right;
    final horizontalGapLeft = sourceRect.left - targetRect.right;

    final hasVerticalGap =
        verticalGapBelow > -_padding || verticalGapAbove > -_padding;
    final hasHorizontalGap =
        horizontalGapRight > -_padding || horizontalGapLeft > -_padding;

    if (hasVerticalGap &&
        (!hasHorizontalGap ||
            (tc.dy - sc.dy).abs() >= (tc.dx - sc.dx).abs())) {
      if (tc.dy > sc.dy) {
        return (sourceRect.bottomCenter, targetRect.topCenter);
      } else {
        return (sourceRect.topCenter, targetRect.bottomCenter);
      }
    }

    if (hasHorizontalGap) {
      if (tc.dx > sc.dx) {
        return (sourceRect.centerRight, targetRect.centerLeft);
      } else {
        return (sourceRect.centerLeft, targetRect.centerRight);
      }
    }

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

  // ── Exit stub computation ───────────────────────────────────────────────

  static Offset _computeExitStub(Offset point, Rect objectRect,
      [List<Rect> obstacles = const [], Offset? target]) {
    final exits = <Offset>[
      Offset(objectRect.left - _stubDistance, point.dy), // left
      Offset(objectRect.right + _stubDistance, point.dy), // right
      Offset(point.dx, objectRect.top - _stubDistance), // top
      Offset(point.dx, objectRect.bottom + _stubDistance), // bottom
    ];

    bool isClear(Offset p) => !obstacles.any((r) =>
        p.dx > r.left && p.dx < r.right && p.dy > r.top && p.dy < r.bottom);

    final natural = _naturalExitIndex(point, objectRect);
    if (isClear(exits[natural])) return exits[natural];

    double score(Offset p) =>
        target == null ? 0 : (p.dx - target.dx).abs() + (p.dy - target.dy).abs();

    final sorted = List.generate(4, (i) => i)
      ..sort((a, b) => score(exits[a]).compareTo(score(exits[b])));
    for (final i in sorted) {
      if (isClear(exits[i])) return exits[i];
    }

    const minStub = 2.0;
    final minExits = [
      Offset(objectRect.left - minStub, point.dy),
      Offset(objectRect.right + minStub, point.dy),
      Offset(point.dx, objectRect.top - minStub),
      Offset(point.dx, objectRect.bottom + minStub),
    ];
    for (final i in sorted) {
      if (isClear(minExits[i])) return minExits[i];
    }
    return minExits[natural];
  }

  static int _naturalExitIndex(Offset point, Rect rect) {
    final dists = [
      (point.dx - rect.left).abs(),
      (point.dx - rect.right).abs(),
      (point.dy - rect.top).abs(),
      (point.dy - rect.bottom).abs(),
    ];
    final minD = dists.reduce(min);
    if ((minD - dists[3]).abs() < 1.0) return 3; // bottom
    if ((minD - dists[2]).abs() < 1.0) return 2; // top
    if ((minD - dists[1]).abs() < 1.0) return 1; // right
    return 0; // left
  }

  // ── U-turn detection & waypoints ────────────────────────────────────────

  static bool _isUTurn(Offset start, Offset exitStub, Offset end) {
    final exitDir = exitStub - start;
    final toTarget = end - start;

    if (exitDir.dx.abs() > exitDir.dy.abs()) {
      if (toTarget.dx.abs() >= toTarget.dy.abs() && toTarget.dx.abs() > 0.5) {
        return exitDir.dx.sign != toTarget.dx.sign;
      }
    }
    if (exitDir.dy.abs() > exitDir.dx.abs()) {
      if (toTarget.dy.abs() >= toTarget.dx.abs() && toTarget.dy.abs() > 0.5) {
        return exitDir.dy.sign != toTarget.dy.sign;
      }
    }
    return false;
  }

  static List<Offset> _buildUTurnWaypoints(Offset routeStart, Offset routeEnd,
      Offset exitDir, Rect? startRect, Rect? endRect) {
    final clearance = _padding + 5;
    final isHoriz = exitDir.dx.abs() > exitDir.dy.abs();

    if (isHoriz) {
      final detourSign = (routeEnd.dy - routeStart.dy).abs() > 0.5
          ? (routeEnd.dy - routeStart.dy).sign
          : 1.0;
      double detourY = routeStart.dy + detourSign * clearance;
      if (startRect != null) {
        final edge = detourSign > 0 ? startRect.bottom : startRect.top;
        detourY = detourSign > 0
            ? max(detourY, edge + clearance)
            : min(detourY, edge - clearance);
      }
      if (endRect != null) {
        final edge = detourSign > 0 ? endRect.bottom : endRect.top;
        detourY = detourSign > 0
            ? max(detourY, edge + clearance)
            : min(detourY, edge - clearance);
      }
      return [
        Offset(routeStart.dx, detourY),
        Offset(routeEnd.dx, detourY),
      ];
    } else {
      final detourSign = (routeEnd.dx - routeStart.dx).abs() > 0.5
          ? (routeEnd.dx - routeStart.dx).sign
          : 1.0;
      double detourX = routeStart.dx + detourSign * clearance;
      if (startRect != null) {
        final edge = detourSign > 0 ? startRect.right : startRect.left;
        detourX = detourSign > 0
            ? max(detourX, edge + clearance)
            : min(detourX, edge - clearance);
      }
      if (endRect != null) {
        final edge = detourSign > 0 ? endRect.right : endRect.left;
        detourX = detourSign > 0
            ? max(detourX, edge + clearance)
            : min(detourX, edge - clearance);
      }
      return [
        Offset(detourX, routeStart.dy),
        Offset(detourX, routeEnd.dy),
      ];
    }
  }

  // ── L-corner fast path ──────────────────────────────────────────────────

  static Offset? _findClearLCorner(
    Offset start,
    Offset end,
    List<Rect> obstacles, {
    Offset? exitDir,
    List<(Offset, Offset)> existingSegments = const [],
  }) {
    if (_isAxisAligned(start, end)) {
      return _segmentHitsAny(start, end, obstacles) ? null : start;
    }

    final corner1 = Offset(end.dx, start.dy); // horizontal-first
    final corner2 = Offset(start.dx, end.dy); // vertical-first
    final c1Clear = !_segmentHitsAny(start, corner1, obstacles) &&
        !_segmentHitsAny(corner1, end, obstacles);
    final c2Clear = !_segmentHitsAny(start, corner2, obstacles) &&
        !_segmentHitsAny(corner2, end, obstacles);

    if (!c1Clear && !c2Clear) return null;
    if (c1Clear && !c2Clear) return corner1;
    if (!c1Clear && c2Clear) return corner2;

    // Both clear — pick by exit direction first, then by less overlap.
    if (exitDir != null) {
      final isHorizExit = exitDir.dx.abs() > exitDir.dy.abs();
      if (isHorizExit) {
        final exitSign = exitDir.dx.sign;
        final cornerSign = (end.dx - start.dx).sign;
        if (exitSign != 0 && cornerSign != 0) {
          final preferred = exitSign == cornerSign ? corner1 : corner2;
          final fallback = exitSign == cornerSign ? corner2 : corner1;
          // Still prefer the one with less overlap.
          final prefOverlap = _overlapLength(start, preferred, existingSegments) +
              _overlapLength(preferred, end, existingSegments);
          final fbOverlap = _overlapLength(start, fallback, existingSegments) +
              _overlapLength(fallback, end, existingSegments);
          return prefOverlap <= fbOverlap ? preferred : fallback;
        }
      } else {
        final exitSign = exitDir.dy.sign;
        final cornerSign = (end.dy - start.dy).sign;
        if (exitSign != 0 && cornerSign != 0) {
          final preferred = exitSign == cornerSign ? corner2 : corner1;
          final fallback = exitSign == cornerSign ? corner1 : corner2;
          final prefOverlap = _overlapLength(start, preferred, existingSegments) +
              _overlapLength(preferred, end, existingSegments);
          final fbOverlap = _overlapLength(start, fallback, existingSegments) +
              _overlapLength(fallback, end, existingSegments);
          return prefOverlap <= fbOverlap ? preferred : fallback;
        }
      }
    }

    // Tie-break by overlap length, then by aspect ratio.
    final c1Overlap = _overlapLength(start, corner1, existingSegments) +
        _overlapLength(corner1, end, existingSegments);
    final c2Overlap = _overlapLength(start, corner2, existingSegments) +
        _overlapLength(corner2, end, existingSegments);
    if ((c1Overlap - c2Overlap).abs() > 1.0) {
      return c1Overlap < c2Overlap ? corner1 : corner2;
    }
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    return dx > dy ? corner1 : corner2;
  }

  // ── Visibility graph + A* ───────────────────────────────────────────────

  static List<Offset> _generateCandidates(
      Offset start, Offset end, List<Rect> candidateRects, List<Rect> collisionRects) {
    final candidates = <Offset>{};

    // Corners of inflated obstacles.
    for (final rect in candidateRects) {
      candidates.addAll(
          [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]);
    }

    // Grid intersections: rows at each obstacle edge + start/end Y;
    //                     cols at each obstacle edge + start/end X.
    final xs = <double>{start.dx, end.dx};
    final ys = <double>{start.dy, end.dy};
    for (final rect in candidateRects) {
      xs.addAll([rect.left, rect.right]);
      ys.addAll([rect.top, rect.bottom]);
    }
    for (final x in xs) {
      for (final y in ys) {
        candidates.add(Offset(x, y));
      }
    }

    // Midpoints between start/end and each obstacle face — gives the router
    // "hallway" points between tight obstacles.
    for (final rect in candidateRects) {
      candidates.addAll([
        Offset(rect.left, start.dy),
        Offset(rect.right, start.dy),
        Offset(start.dx, rect.top),
        Offset(start.dx, rect.bottom),
        Offset(rect.left, end.dy),
        Offset(rect.right, end.dy),
        Offset(end.dx, rect.top),
        Offset(end.dx, rect.bottom),
      ]);
    }

    candidates.removeWhere((p) => collisionRects.any((r) =>
        p.dx > r.left && p.dx < r.right && p.dy > r.top && p.dy < r.bottom));

    return candidates.toList();
  }

  /// A* with state = (node index, incoming direction).
  /// Cost = Manhattan distance + [_bendPenalty] per direction change
  ///       + [_overlapPenalty] × overlap length with existing segments.
  static List<Offset> _astar(
    Offset start,
    Offset end,
    List<Offset> candidates,
    List<Rect> obstacles, {
    List<(Offset, Offset)> existingSegments = const [],
  }) {
    final points = [start, ...candidates, end];
    final n = points.length;
    final endIdx = n - 1;

    // Build adjacency: only axis-aligned, unobstructed edges.
    final adj = List.generate(n, (_) => <(int, double)>[]);
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final a = points[i];
        final b = points[j];
        if ((a.dx - b.dx).abs() < 0.5 || (a.dy - b.dy).abs() < 0.5) {
          if (!_segmentHitsAny(a, b, obstacles)) {
            final dist = (a.dx - b.dx).abs() + (a.dy - b.dy).abs();
            // Add overlap penalty to edge weight.
            final overlap = existingSegments.isEmpty
                ? 0.0
                : _overlapLength(a, b, existingSegments);
            final cost = dist + overlap * _overlapPenalty;
            adj[i].add((j, cost));
            adj[j].add((i, cost));
          }
        }
      }
    }

    // Direction: 0=none, 1=horizontal, 2=vertical.
    int direction(Offset a, Offset b) {
      if ((a.dy - b.dy).abs() < 0.5) return 1;
      return 2;
    }

    final dist = List.generate(n, (_) => List.filled(3, double.infinity));
    final prev = List.generate(n, (_) => List.filled(3, (-1, -1)));
    dist[0][0] = 0;

    double heuristic(int i) =>
        (points[i].dx - end.dx).abs() + (points[i].dy - end.dy).abs();

    final pq = SplayTreeSet<(double, double, int, int)>((a, b) {
      var cmp = a.$1.compareTo(b.$1);
      if (cmp != 0) return cmp;
      cmp = a.$2.compareTo(b.$2);
      if (cmp != 0) return cmp;
      cmp = a.$3.compareTo(b.$3);
      if (cmp != 0) return cmp;
      return a.$4.compareTo(b.$4);
    });
    pq.add((heuristic(0), 0.0, 0, 0));

    while (pq.isNotEmpty) {
      final entry = pq.first;
      pq.remove(entry);
      final (_, cost, u, uDir) = entry;
      if (cost > dist[u][uDir]) continue;
      if (u == endIdx) break;

      for (final (v, edgeCost) in adj[u]) {
        final vDir = direction(points[u], points[v]);
        final bendCost = (uDir != 0 && uDir != vDir) ? _bendPenalty : 0.0;
        final newCost = cost + edgeCost + bendCost;
        if (newCost < dist[v][vDir]) {
          dist[v][vDir] = newCost;
          prev[v][vDir] = (u, uDir);
          pq.add((newCost + heuristic(v), newCost, v, vDir));
        }
      }
    }

    int bestDir = 0;
    double bestCost = double.infinity;
    for (int d = 0; d < 3; d++) {
      if (dist[endIdx][d] < bestCost) {
        bestCost = dist[endIdx][d];
        bestDir = d;
      }
    }
    if (bestCost == double.infinity) return const [];

    final path = <int>[];
    var at = (endIdx, bestDir);
    while (at.$1 != -1) {
      path.add(at.$1);
      at = prev[at.$1][at.$2];
    }

    if (path.length <= 2) return const [];
    final inner =
        path.reversed.skip(1).take(path.length - 2).map((i) => points[i]).toList();
    return inner;
  }

  // ── Path assembly ────────────────────────────────────────────────────────

  static List<Offset> _assemble(Offset start, Offset? exitStub,
      List<Offset> inner, Offset? entryStub, Offset end, List<Rect> obstacles) {
    final fullPath = <Offset>[start];
    if (exitStub != null) fullPath.add(exitStub);
    fullPath.addAll(inner);
    if (entryStub != null) fullPath.add(entryStub);
    fullPath.add(end);

    final aligned = _ensureAxisAligned(fullPath, obstacles);
    final simplified = _removeCollinear(aligned);

    if (simplified.length <= 2) return const [];
    return simplified.sublist(1, simplified.length - 1);
  }

  // ── Geometry helpers ─────────────────────────────────────────────────────

  static bool _isAxisAligned(Offset a, Offset b) =>
      (a.dx - b.dx).abs() < 0.5 || (a.dy - b.dy).abs() < 0.5;

  static List<Offset> _ensureAxisAligned(List<Offset> path,
      [List<Rect> obstacles = const []]) {
    if (path.length < 2) return path;
    final result = <Offset>[path.first];

    for (int i = 1; i < path.length; i++) {
      final a = result.last;
      final b = path[i];

      if ((a.dy - b.dy).abs() < 0.5 || (a.dx - b.dx).abs() < 0.5) {
        result.add(b);
      } else {
        final corner1 = Offset(b.dx, a.dy);
        final corner2 = Offset(a.dx, b.dy);
        final dx = (b.dx - a.dx).abs();
        final dy = (b.dy - a.dy).abs();
        final preferred = dx > dy ? corner1 : corner2;
        final fallback = dx > dy ? corner2 : corner1;

        if (obstacles.isEmpty) {
          result.add(preferred);
        } else {
          final prefClear = !_segmentHitsAny(a, preferred, obstacles) &&
              !_segmentHitsAny(preferred, b, obstacles);
          final fbClear = !_segmentHitsAny(a, fallback, obstacles) &&
              !_segmentHitsAny(fallback, b, obstacles);
          result.add(prefClear ? preferred : (fbClear ? fallback : preferred));
        }
        result.add(b);
      }
    }
    return result;
  }

  static List<Offset> _removeCollinear(List<Offset> path) {
    if (path.length < 3) return path;
    final result = <Offset>[path.first];
    for (int i = 1; i < path.length - 1; i++) {
      final prev = result.last;
      final curr = path[i];
      final next = path[i + 1];
      final sameX =
          (prev.dx - curr.dx).abs() < 0.5 && (curr.dx - next.dx).abs() < 0.5;
      final sameY =
          (prev.dy - curr.dy).abs() < 0.5 && (curr.dy - next.dy).abs() < 0.5;
      if (sameX || sameY) continue;
      result.add(curr);
    }
    result.add(path.last);
    return result;
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
      return y > rect.top && y < rect.bottom &&
          maxX > rect.left && minX < rect.right;
    } else {
      final x = a.dx;
      final minY = min(a.dy, b.dy);
      final maxY = max(a.dy, b.dy);
      return x > rect.left && x < rect.right &&
          maxY > rect.top && minY < rect.bottom;
    }
  }

  /// Returns the total length of segment (a→b) that overlaps (within [tol]
  /// pixels) any segment in [existing].
  static double _overlapLength(
      Offset a, Offset b, List<(Offset, Offset)> existing,
      {double tol = 6.0}) {
    if (existing.isEmpty) return 0.0;
    final isH = (a.dy - b.dy).abs() < 0.5;
    double total = 0.0;

    for (final (p, q) in existing) {
      final exIsH = (p.dy - q.dy).abs() < 0.5;
      if (isH != exIsH) continue; // different axis

      if (isH) {
        // Both horizontal: check Y proximity and X overlap.
        if ((a.dy - p.dy).abs() > tol) continue;
        final minX = max(min(a.dx, b.dx), min(p.dx, q.dx));
        final maxX = min(max(a.dx, b.dx), max(p.dx, q.dx));
        if (maxX > minX) total += maxX - minX;
      } else {
        // Both vertical: check X proximity and Y overlap.
        if ((a.dx - p.dx).abs() > tol) continue;
        final minY = max(min(a.dy, b.dy), min(p.dy, q.dy));
        final maxY = min(max(a.dy, b.dy), max(p.dy, q.dy));
        if (maxY > minY) total += maxY - minY;
      }
    }
    return total;
  }

  static List<Rect> _excludeRect(
      List<Rect> originals, List<Rect> inflated, Rect exclude) {
    return [
      for (int i = 0; i < originals.length; i++)
        if (originals[i] != exclude) inflated[i],
    ];
  }
}
