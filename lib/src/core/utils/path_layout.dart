import 'dart:math' as math;
import 'dart:ui';

/// Distributes a set of selected boxes along a guide polyline.
///
/// This powers the "lay selected nodes out along a path I draw" feature: the
/// user selects a handful of nodes, then Alt-draws a guide (a pencil stroke, a
/// circle/diamond/rectangle outline, or a straight line/arrow). The guide is
/// flattened to a [polyline] of world points and handed here.
///
/// Behaviour:
///   * Each box keeps its natural order *along the path*. We project every box
///     centre onto the polyline, take the arc-length of the nearest point, and
///     sort by that. The box nearest the path's start ends up first. This
///     preserves the existing visual arrangement instead of reshuffling.
///   * The boxes are then placed at evenly-spaced arc-length positions between
///     the path start and end (for an open path) or evenly around the full loop
///     (for a closed path — circle/rectangle/diamond), so they don't pile up at
///     a seam.
///
/// Returns a map from box id to its new *centre* point. The caller converts
/// centre → top-left using each box's size. Boxes whose id isn't placeable
/// (degenerate path, etc.) are simply omitted.
class PathLayout {
  /// [boxes] maps box id → current centre (world space).
  /// [polyline] is the guide path as world points (>= 2 points).
  /// [closed] is true for shape outlines that loop (circle, rect, diamond).
  static Map<String, Offset> distribute({
    required Map<String, Offset> boxes,
    required List<Offset> polyline,
    required bool closed,
  }) {
    final result = <String, Offset>{};
    if (boxes.isEmpty) return result;

    final path = _Polyline.fromPoints(polyline, closed: closed);
    if (path == null) return result; // degenerate

    // 1. Order boxes by where they project onto the path.
    final entries = boxes.entries.toList();
    final projected = <(_MapEntryLike, double)>[
      for (final e in entries)
        (
          _MapEntryLike(e.key, e.value),
          path.arcLengthOfNearestPoint(e.value),
        ),
    ];
    projected.sort((a, b) => a.$2.compareTo(b.$2));

    // 2. Spread along the path by even arc-length.
    final n = projected.length;
    final total = path.totalLength;
    for (int i = 0; i < n; i++) {
      final double t;
      if (n == 1) {
        // Single box → midpoint of an open path, or first sample of a loop.
        t = closed ? 0.0 : total / 2.0;
      } else if (closed) {
        // Evenly around the loop; n slots, no duplicate at the seam.
        t = total * i / n;
      } else {
        // Endpoints inclusive across an open path.
        t = total * i / (n - 1);
      }
      result[projected[i].$1.key] = path.pointAtArcLength(t);
    }
    return result;
  }
}

class _MapEntryLike {
  final String key;
  final Offset value;
  const _MapEntryLike(this.key, this.value);
}

/// A polyline with cached cumulative arc-lengths for fast point/projection
/// queries. Coordinates are world space.
class _Polyline {
  final List<Offset> points; // closed paths repeat the first point at the end
  final List<double> cumLen; // cumLen[i] = arc length up to points[i]
  final double totalLength;

  _Polyline._(this.points, this.cumLen, this.totalLength);

  static _Polyline? fromPoints(List<Offset> raw, {required bool closed}) {
    // Drop consecutive duplicates that would create zero-length segments.
    final pts = <Offset>[];
    for (final p in raw) {
      if (pts.isEmpty || (p - pts.last).distance > 1e-6) pts.add(p);
    }
    if (closed && pts.length >= 2 && (pts.first - pts.last).distance > 1e-6) {
      pts.add(pts.first);
    }
    if (pts.length < 2) return null;

    final cum = <double>[0.0];
    double total = 0.0;
    for (int i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
      cum.add(total);
    }
    if (total <= 1e-6) return null;
    return _Polyline._(pts, cum, total);
  }

  /// Point at the given arc length (clamped to [0, totalLength]).
  Offset pointAtArcLength(double s) {
    s = s.clamp(0.0, totalLength);
    // Binary search for the segment containing arc length s.
    int lo = 0, hi = cumLen.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cumLen[mid] < s) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = lo == 0 ? 1 : lo;
    final segStart = cumLen[i - 1];
    final segLen = cumLen[i] - segStart;
    final t = segLen <= 1e-9 ? 0.0 : (s - segStart) / segLen;
    return Offset.lerp(points[i - 1], points[i], t)!;
  }

  /// Arc length at the point on the polyline nearest to [q]. Used to order
  /// boxes by their position along the path.
  double arcLengthOfNearestPoint(Offset q) {
    double best = double.infinity;
    double bestArc = 0.0;
    for (int i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final ab = b - a;
      final segLen2 = ab.dx * ab.dx + ab.dy * ab.dy;
      double t = 0.0;
      if (segLen2 > 1e-12) {
        t = (((q - a).dx * ab.dx) + ((q - a).dy * ab.dy)) / segLen2;
        t = t.clamp(0.0, 1.0);
      }
      final proj = a + ab * t;
      final d2 = (q - proj).distanceSquared;
      if (d2 < best) {
        best = d2;
        bestArc = cumLen[i - 1] + math.sqrt(segLen2) * t;
      }
    }
    return bestArc;
  }
}
