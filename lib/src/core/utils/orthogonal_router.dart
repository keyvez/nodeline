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
  // Flat penalty per perpendicular crossing of an existing path segment. Tuned
  // so the router will take a moderately longer/bendier route to avoid weaving
  // through another connector, but won't make extreme detours just to dodge a
  // single unavoidable crossing.
  static const double _crossingPenalty = 30.0;

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
    var exitStub = startObjectRect != null
        ? _computeExitStub(start, startObjectRect,
            _excludeRect(relevant, inflated, startObjectRect), end)
        : null;
    var entryStub = endObjectRect != null
        ? _computeExitStub(end, endObjectRect,
            _excludeRect(relevant, inflated, endObjectRect), start)
        : null;

    // Tight facing-edge gap: when the source's exit and the target's entry leave
    // along the SAME axis in OPPOSITE directions (the two nodes face each other)
    // and the gap between their edges is narrower than two full stubs, a full
    // stub on each side overshoots into the other node — collapsing one side to
    // a hug. Instead, share a single corridor at the midpoint of the gap so both
    // ends get equal, visible clearance ("out a bit, then turn, then in").
    if (exitStub != null &&
        entryStub != null &&
        startObjectRect != null &&
        endObjectRect != null) {
      final sr = startObjectRect;
      final er = endObjectRect;
      final exitDir = exitStub - start;
      final entryDir = entryStub - end;
      final exitH = exitDir.dx.abs() > exitDir.dy.abs();
      final entryH = entryDir.dx.abs() > entryDir.dy.abs();

      // Horizontal facing: source's right/left edge faces target's opposite
      // edge across a narrow horizontal gap. The stubs are horizontal in
      // opposite directions and the rects are separated horizontally with a
      // clear, narrow gap between their facing edges. (The endpoints may sit at
      // different heights — the shared corridor is the vertical line in the gap;
      // a too-strict vertical-overlap requirement would drop legit diagonal
      // pairs like World→Maya back to a hug.)
      // A "real" gap to share a corridor in must be wider than this; below it
      // the facing edges are effectively coincident (the midpoint would BE the
      // hug line), so we keep full perpendicular stubs and let A* route out and
      // around instead.
      const minSharedGap = 12.0;
      if (exitH && entryH && exitDir.dx.sign != entryDir.dx.sign) {
        final innerGap = sr.right < er.left
            ? er.left - sr.right // source on the left
            : (er.right < sr.left ? sr.left - er.right : -1.0);
        if (innerGap > minSharedGap && innerGap < _stubDistance * 2) {
          final mid = sr.right < er.left
              ? (sr.right + er.left) / 2
              : (er.right + sr.left) / 2;
          exitStub = Offset(mid, start.dy);
          entryStub = Offset(mid, end.dy);
        }
      } else if (!exitH && !entryH && exitDir.dy.sign != entryDir.dy.sign) {
        // Vertical facing: requires horizontal overlap + a clear vertical gap
        // between the facing edges. (Guards against side-by-side nodes whose
        // top/bottom edges face opposite ways but aren't stacked — putting the
        // corridor through the node bodies.)
        final hOverlap = min(sr.right, er.right) - max(sr.left, er.left);
        final innerGap = sr.bottom < er.top
            ? er.top - sr.bottom // source above
            : (er.bottom < sr.top ? sr.top - er.bottom : -1.0);
        if (hOverlap > 0 &&
            innerGap > minSharedGap &&
            innerGap < _stubDistance * 2) {
          final mid = sr.bottom < er.top
              ? (sr.bottom + er.top) / 2
              : (er.bottom + sr.top) / 2;
          exitStub = Offset(start.dx, mid);
          entryStub = Offset(end.dx, mid);
        }
      }
    }

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

    // If the point lies clearly on exactly one edge, that edge is the true
    // attachment side: the connector MUST leave/enter perpendicular to it. Lock
    // to that edge even when its stub is crowded by a nearby (inflated)
    // obstacle — switching to another edge would make the final segment run
    // parallel to the edge the point actually sits on (the "line hugs the node
    // edge" bug).
    final onEdge = _soleEdge(point, objectRect);
    if (onEdge != null) {
      Offset stubAt(double d) => switch (onEdge) {
            0 => Offset(objectRect.left - d, point.dy),
            1 => Offset(objectRect.right + d, point.dy),
            2 => Offset(point.dx, objectRect.top - d),
            _ => Offset(point.dx, objectRect.bottom + d),
          };
      // Always stand the connector OFF the node by a visible clearance before
      // it turns in. Prefer the full stub; if crowded, step inward to the
      // largest still-clear clearance down to a visible floor.
      if (isClear(exits[onEdge])) return exits[onEdge];
      for (final d in const [
        _stubDistance * 0.6,
        _stubDistance * 0.4,
        16.0,
        10.0,
      ]) {
        if (isClear(stubAt(d))) return stubAt(d);
      }
      return exits[onEdge]; // full clearance; corridor detours to reach it
    }

    final natural = _naturalExitIndex(point, objectRect, target);
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

  /// If [point] lies clearly on exactly one edge of [rect] (within tolerance)
  /// and is not near a corner, returns that edge index (0=left,1=right,
  /// 2=top,3=bottom). Returns null for corner/center/ambiguous points, where
  /// the caller is free to choose the best-facing edge.
  static int? _soleEdge(Offset point, Rect rect) {
    const tol = 1.0;
    final onLeft = (point.dx - rect.left).abs() < tol;
    final onRight = (point.dx - rect.right).abs() < tol;
    final onTop = (point.dy - rect.top).abs() < tol;
    final onBottom = (point.dy - rect.bottom).abs() < tol;
    final count = (onLeft ? 1 : 0) +
        (onRight ? 1 : 0) +
        (onTop ? 1 : 0) +
        (onBottom ? 1 : 0);
    if (count != 1) return null; // corner (2), or not on any edge (0)
    // Require the point to be within the edge's span (not at its very corner).
    const corner = 6.0;
    if (onLeft || onRight) {
      if (point.dy <= rect.top + corner || point.dy >= rect.bottom - corner) {
        return null;
      }
      return onLeft ? 0 : 1;
    }
    if (point.dx <= rect.left + corner || point.dx >= rect.right - corner) {
      return null;
    }
    return onTop ? 2 : 3;
  }

  // Edge indices: 0=left, 1=right, 2=top, 3=bottom.
  static int _naturalExitIndex(Offset point, Rect rect, [Offset? target]) {
    final dists = [
      (point.dx - rect.left).abs(),
      (point.dx - rect.right).abs(),
      (point.dy - rect.top).abs(),
      (point.dy - rect.bottom).abs(),
    ];
    final minD = dists.reduce(min);

    // Which edges is the point (nearly) on? At a corner two will tie.
    const cornerTol = 8.0;
    final candidates = <int>[];
    for (var i = 0; i < 4; i++) {
      if ((dists[i] - minD).abs() < cornerTol) candidates.add(i);
    }

    // When the attachment sits at/near a corner, a fixed edge-priority order
    // makes the stub project along an edge the path is already running
    // parallel to — so the connector hugs that edge instead of turning in
    // perpendicularly. Disambiguate by the direction toward the other
    // endpoint: pick the edge whose outward normal points most toward the
    // source, so the final segment approaches that edge head-on.
    if (candidates.length > 1 && target != null) {
      // Outward normals per edge index.
      const normals = [
        Offset(-1, 0), // left
        Offset(1, 0), // right
        Offset(0, -1), // top
        Offset(0, 1), // bottom
      ];
      // Pick the edge whose outward normal points toward the other endpoint,
      // so the stub sticks out on the approach side and the final segment
      // comes in along that edge's normal (perpendicular to the edge).
      final toTarget = target - point;
      int best = candidates.first;
      double bestDot = double.negativeInfinity;
      for (final i in candidates) {
        final d = normals[i].dx * toTarget.dx + normals[i].dy * toTarget.dy;
        if (d > bestDot) {
          bestDot = d;
          best = i;
        }
      }
      return best;
    }

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
          // Still prefer the one that weaves through fewer routes (crossings
          // first, then overlap).
          final prefCost = _lWeaveCost(start, preferred, end, existingSegments);
          final fbCost = _lWeaveCost(start, fallback, end, existingSegments);
          return prefCost <= fbCost ? preferred : fallback;
        }
      } else {
        final exitSign = exitDir.dy.sign;
        final cornerSign = (end.dy - start.dy).sign;
        if (exitSign != 0 && cornerSign != 0) {
          final preferred = exitSign == cornerSign ? corner2 : corner1;
          final fallback = exitSign == cornerSign ? corner1 : corner2;
          final prefCost = _lWeaveCost(start, preferred, end, existingSegments);
          final fbCost = _lWeaveCost(start, fallback, end, existingSegments);
          return prefCost <= fbCost ? preferred : fallback;
        }
      }
    }

    // Tie-break by weave cost (crossings + overlap), then by aspect ratio.
    final c1Cost = _lWeaveCost(start, corner1, end, existingSegments);
    final c2Cost = _lWeaveCost(start, corner2, end, existingSegments);
    if ((c1Cost - c2Cost).abs() > 1.0) {
      return c1Cost < c2Cost ? corner1 : corner2;
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
            // Penalize running along (overlap) AND weaving through (crossing)
            // existing routes, so paths neither share lanes nor box regions.
            final overlap = existingSegments.isEmpty
                ? 0.0
                : _overlapLength(a, b, existingSegments);
            final crossings = existingSegments.isEmpty
                ? 0
                : _crossingCount(a, b, existingSegments);
            final cost = dist +
                overlap * _overlapPenalty +
                crossings * _crossingPenalty;
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
    var simplified = _removeCollinear(aligned);

    // Guarantee a perpendicular approach into the endpoint. The entry stub is
    // offset from `end` along the attachment edge's normal, so the final
    // segment must be parallel to (end - entryStub). When obstacles force the
    // route to arrive along the edge instead, the last segment comes in
    // *parallel* to the edge — the "line hugs the node edge" artifact. Re-anchor
    // the tail through the stub so the connector turns in head-on. Do the same
    // for the exit so it leaves its node perpendicularly.
    if (entryStub != null) {
      simplified = _forcePerpendicularEnd(simplified, entryStub, end);
    }
    if (exitStub != null) {
      // Reverse, force perpendicular at the start, reverse back.
      final rev = simplified.reversed.toList();
      final fixed = _forcePerpendicularEnd(rev, exitStub, start);
      simplified = fixed.reversed.toList();
    }
    simplified = _removeCollinear(simplified);

    if (simplified.length <= 2) return const [];
    return simplified.sublist(1, simplified.length - 1);
  }

  /// Ensures the segment entering [end] is perpendicular to the endpoint's
  /// attachment edge. [stub] sits one stub-distance off [end] along the edge
  /// normal, so the final leg must run parallel to (end - stub). If the path
  /// currently arrives along the other axis (parallel to the edge), insert the
  /// stub and an L-corner so the connector turns in head-on instead of hugging
  /// the edge.
  static List<Offset> _forcePerpendicularEnd(
      List<Offset> path, Offset stub, Offset end) {
    if (path.length < 2) return path;
    final normal = end - stub; // points from stub into the node, along the edge normal
    final normalIsHorizontal = normal.dx.abs() > normal.dy.abs();

    final pen = path[path.length - 2];
    final lastIsHorizontal = (pen.dy - end.dy).abs() < 0.5;

    // The final segment is already perpendicular to the edge. Good — UNLESS it's
    // too short, i.e. the corridor ran up alongside the edge and only nubbed in
    // (the "too close / too parallel to the node" hug). In that case the segment
    // before it runs parallel to the edge close by; rebuild the tail so the
    // approach steps out to the stub distance and comes in with real clearance.
    if (lastIsHorizontal == normalIsHorizontal) {
      final finalLen = (end - pen).distance;
      final stubLen = (end - stub).distance;
      if (finalLen >= stubLen - 0.5) return path; // already has full clearance
      // Too short: re-anchor the approach through the stub.
      final result = List<Offset>.from(path)..removeLast(); // drop end
      result.removeLast(); // drop the too-short pen too; we re-route to stub
      if (result.isEmpty) result.add(pen);
      if (normalIsHorizontal) {
        if ((result.last.dx - stub.dx).abs() > 0.5) {
          result.add(Offset(stub.dx, result.last.dy));
        }
        if ((result.last.dy - stub.dy).abs() > 0.5) {
          result.add(Offset(stub.dx, stub.dy));
        }
      } else {
        if ((result.last.dy - stub.dy).abs() > 0.5) {
          result.add(Offset(result.last.dx, stub.dy));
        }
        if ((result.last.dx - stub.dx).abs() > 0.5) {
          result.add(Offset(stub.dx, stub.dy));
        }
      }
      if ((result.last - stub).distanceSquared > 0.25) result.add(stub);
      result.add(end);
      return result;
    }

    // The last segment is parallel to the edge. Rebuild the tail: come to the
    // stub, then step perpendicular into the node. The pre-stub point keeps the
    // incoming axis, turning at the stub.
    final result = List<Offset>.from(path)..removeLast(); // drop end
    // `pen` is now the last element; route pen -> stub with an axis-aligned
    // corner, then stub -> end (perpendicular by construction).
    if (normalIsHorizontal) {
      // Final leg horizontal: stub shares end.dy. Bring pen across at stub.dx
      // then down/up to stub.dy.
      if ((result.last.dx - stub.dx).abs() > 0.5) {
        result.add(Offset(stub.dx, result.last.dy));
      }
      if ((result.last.dy - stub.dy).abs() > 0.5) {
        result.add(Offset(stub.dx, stub.dy));
      }
    } else {
      // Final leg vertical: stub shares end.dx.
      if ((result.last.dy - stub.dy).abs() > 0.5) {
        result.add(Offset(result.last.dx, stub.dy));
      }
      if ((result.last.dx - stub.dx).abs() > 0.5) {
        result.add(Offset(stub.dx, stub.dy));
      }
    }
    if ((result.last - stub).distanceSquared > 0.25) result.add(stub);
    result.add(end);
    return result;
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

  /// Counts how many segments in [existing] the axis-aligned segment (a→b)
  /// perpendicularly crosses. Used to prefer routes/corners that don't weave
  /// through other connectors (which boxes regions and reads as tangled).
  static int _crossingCount(
      Offset a, Offset b, List<(Offset, Offset)> existing) {
    if (existing.isEmpty) return 0;
    final isH = (a.dy - b.dy).abs() < 0.5;
    final aMinX = min(a.dx, b.dx), aMaxX = max(a.dx, b.dx);
    final aMinY = min(a.dy, b.dy), aMaxY = max(a.dy, b.dy);
    int count = 0;
    for (final (p, q) in existing) {
      final exIsH = (p.dy - q.dy).abs() < 0.5;
      if (isH == exIsH) continue; // parallel — handled by overlap, not crossing
      if (isH) {
        // this segment horizontal at y=a.dy; existing vertical at x=p.dx.
        final exMinY = min(p.dy, q.dy), exMaxY = max(p.dy, q.dy);
        if (p.dx > aMinX && p.dx < aMaxX && a.dy > exMinY && a.dy < exMaxY) {
          count++;
        }
      } else {
        // this segment vertical at x=a.dx; existing horizontal at y=p.dy.
        final exMinX = min(p.dx, q.dx), exMaxX = max(p.dx, q.dx);
        if (p.dy > aMinY && p.dy < aMaxY && a.dx > exMinX && a.dx < exMaxX) {
          count++;
        }
      }
    }
    return count;
  }

  /// Combined "weave" cost of a two-segment L (start→corner→end) against
  /// already-routed segments: collinear overlap length plus a heavier penalty
  /// per perpendicular crossing.
  static double _lWeaveCost(Offset start, Offset corner, Offset end,
      List<(Offset, Offset)> existing) {
    const crossingWeight = 60.0; // ~ a long detour; crossings are worse than minor overlap
    final overlap = _overlapLength(start, corner, existing) +
        _overlapLength(corner, end, existing);
    final crossings = _crossingCount(start, corner, existing) +
        _crossingCount(corner, end, existing);
    return overlap + crossings * crossingWeight;
  }

  static List<Rect> _excludeRect(
      List<Rect> originals, List<Rect> inflated, Rect exclude) {
    return [
      for (int i = 0; i < originals.length; i++)
        if (originals[i] != exclude) inflated[i],
    ];
  }
}
