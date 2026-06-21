import 'dart:math';
import 'dart:ui';

import 'package:flow_draw/src/models/drawing_entities.dart';

/// Pure extraction of a polyline from a drawing object, for treating any drawn
/// shape as a "guide" path. Used by Canvas Mode's `read_drawing` tool so the
/// model can read a sketch the user drew and lay nodes along it / transfer its
/// shape.
///
/// This mirrors the data layer's private `_guidePolylineFromObject` but is pure
/// (no dependency on the transient `renderedPath` render cache): arrows fall
/// back to start→waypoints→end. Open shapes return `closed: false`; outlines of
/// closed shapes return `closed: true`.
class GuideGeometry {
  /// Number of segments used to approximate an ellipse outline.
  static const int circleSegments = 120;

  /// Returns `(polyline, closed)` for [obj], or null if it can't act as a guide
  /// (too small, or not a guide-capable type).
  static (List<Offset>, bool)? polylineOf(DrawingObject obj) {
    if (obj is PencilStrokeObject) {
      final pts = [for (final p in obj.points) Offset(p.x, p.y)];
      return pts.length >= 2 ? (pts, false) : null;
    }
    if (obj is ArrowObject) {
      final pts = <Offset>[obj.start, ...?obj.waypoints, obj.end];
      return pts.length >= 2 ? (pts, false) : null;
    }
    if (obj is LineObject) {
      if ((obj.end - obj.start).distance < 1) return null;
      return ([obj.start, obj.end], false);
    }

    final rect = obj.rect;
    if (rect.shortestSide < 1) return null;
    if (obj is CircleObject) {
      final c = rect.center;
      final rx = rect.width / 2;
      final ry = rect.height / 2;
      return ([
        for (int i = 0; i < circleSegments; i++)
          Offset(
            c.dx + rx * cos(2 * pi * i / circleSegments),
            c.dy + ry * sin(2 * pi * i / circleSegments),
          ),
      ], true);
    }
    if (obj is RectangleObject) {
      return ([rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft], true);
    }
    if (obj is DiamondObject) {
      final c = rect.center;
      return ([
        Offset(c.dx, rect.top),
        Offset(rect.right, c.dy),
        Offset(c.dx, rect.bottom),
        Offset(rect.left, c.dy),
      ], true);
    }
    if (obj is ParallelogramObject) {
      final skew = min(obj.skewOffset, rect.width / 2);
      return ([
        Offset(rect.left + skew, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right - skew, rect.bottom),
        Offset(rect.left, rect.bottom),
      ], true);
    }
    return null;
  }

  /// Whether [obj] is a shape you'd deliberately draw *as* a path (pen stroke,
  /// line, arrow, circle, diamond, parallelogram). Plain rectangles are excluded
  /// — they're the usual node shape, not a guide.
  static bool isStrongGuide(DrawingObject obj) =>
      obj is PencilStrokeObject ||
      obj is ArrowObject ||
      obj is LineObject ||
      obj is CircleObject ||
      obj is DiamondObject ||
      obj is ParallelogramObject;
}
