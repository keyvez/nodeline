import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flutter/rendering.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Exports the canvas to a PNG image.
///
/// Captures the current state of drawing objects and renders them to
/// an offscreen canvas, returning the PNG bytes.
class PngExporter {
  PngExporter._();

  // Theme constants matching the app's dark theme.
  static const _defaultStrokeColor = ui.Color(0xFFE0E0E0);
  static const _defaultFillColor = ui.Color(0xFF2A2A2A);
  static const _arrowColor = ui.Color(0xFF90CAF9);
  static const _lineColor = ui.Color(0xFFA5D6A7);
  static const _pencilColor = ui.Color(0xFFFFCC80);
  static const _figureColor = ui.Color(0xFFCE93D8);
  static const _textColor = ui.Color(0xFFE0E0E0);
  static const _defaultStrokeWidth = 2.0;

  /// Exports drawing objects to PNG bytes.
  ///
  /// [objects] - map of drawing objects to render.
  /// [pixelRatio] - device pixel ratio for rendering quality.
  /// [backgroundColor] - background color (default: dark).
  /// [padding] - padding around the content.
  ///
  /// Returns PNG image bytes, or null if there are no objects to export.
  static Future<Uint8List?> exportPng(
    Map<String, DrawingObject> objects, {
    double pixelRatio = 2.0,
    ui.Color backgroundColor = const ui.Color(0xFF1C1C1E),
    double padding = 40.0,
  }) async {
    if (objects.isEmpty) return null;

    // Compute bounding box of all objects
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final obj in objects.values) {
      final r = obj.rect;
      if (r.left < minX) minX = r.left;
      if (r.top < minY) minY = r.top;
      if (r.right > maxX) maxX = r.right;
      if (r.bottom > maxY) maxY = r.bottom;
    }

    if (minX.isInfinite) return null;

    final contentWidth = maxX - minX + padding * 2;
    final contentHeight = maxY - minY + padding * 2;

    final width = (contentWidth * pixelRatio).ceil();
    final height = (contentHeight * pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.scale(pixelRatio);

    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, contentWidth, contentHeight),
      Paint()..color = backgroundColor,
    );

    // Translate to center content
    canvas.translate(-minX + padding, -minY + padding);

    // Draw each object
    for (final obj in objects.values) {
      if (obj is RectangleObject) {
        _drawRectangle(canvas, obj);
      } else if (obj is CircleObject) {
        _drawCircle(canvas, obj);
      } else if (obj is DiamondObject) {
        _drawDiamond(canvas, obj);
      } else if (obj is ParallelogramObject) {
        _drawParallelogram(canvas, obj);
      } else if (obj is ForkJoinObject) {
        _drawForkJoin(canvas, obj);
      } else if (obj is ArrowObject) {
        _drawArrow(canvas, obj);
      } else if (obj is LineObject) {
        _drawLine(canvas, obj);
      } else if (obj is PencilStrokeObject) {
        _drawPencilStroke(canvas, obj);
      } else if (obj is FigureObject) {
        _drawFigure(canvas, obj);
      } else if (obj is TextObject) {
        _drawTextObject(canvas, obj);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return byteData?.buffer.asUint8List();
  }

  // -- Shape Renderers --------------------------------------------------------

  static void _drawRectangle(Canvas canvas, RectangleObject obj) {
    final radius = obj.borderRadius > 0 ? obj.borderRadius : 6.0;
    final rrect = RRect.fromRectAndRadius(obj.rect, Radius.circular(radius));
    final fill = _fillPaint(obj.fillColor);
    final stroke = _strokePaint(obj.strokeColor);

    _withRotation(canvas, obj.angle, obj.rect.center, () {
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
      _drawShapeText(canvas, obj.rect, obj.text, obj.textStyle);
    });
  }

  static void _drawCircle(Canvas canvas, CircleObject obj) {
    final fill = _fillPaint(obj.fillColor);
    final stroke = _strokePaint(obj.strokeColor);

    _withRotation(canvas, obj.angle, obj.rect.center, () {
      canvas.drawOval(obj.rect, fill);
      canvas.drawOval(obj.rect, stroke);
      _drawShapeText(canvas, obj.rect, obj.text, obj.textStyle);
    });
  }

  static void _drawDiamond(Canvas canvas, DiamondObject obj) {
    final fill = _fillPaint(obj.fillColor);
    final stroke = _strokePaint(obj.strokeColor);

    _withRotation(canvas, obj.angle, obj.rect.center, () {
      canvas.drawPath(obj.path, fill);
      canvas.drawPath(obj.path, stroke);
      _drawShapeText(canvas, obj.rect, obj.text, obj.textStyle);
    });
  }

  static void _drawParallelogram(Canvas canvas, ParallelogramObject obj) {
    final fill = _fillPaint(null);
    final stroke = _strokePaint(null);

    _withRotation(canvas, obj.angle, obj.rect.center, () {
      canvas.drawPath(obj.path, fill);
      canvas.drawPath(obj.path, stroke);
      _drawShapeText(canvas, obj.rect, obj.text, obj.textStyle);
    });
  }

  static void _drawForkJoin(Canvas canvas, ForkJoinObject obj) {
    final barPaint = Paint()
      ..color = _defaultStrokeColor
      ..style = PaintingStyle.fill;
    final barRect = RRect.fromRectAndRadius(
      obj.rect,
      const Radius.circular(3),
    );

    _withRotation(canvas, obj.angle, obj.rect.center, () {
      canvas.drawRRect(barRect, barPaint);
    });
  }

  static void _drawArrow(Canvas canvas, ArrowObject obj) {
    final arrowPaint = Paint()
      ..color = _arrowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _defaultStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (obj.pathType == LinkPathType.orthogonal &&
        obj.waypoints != null &&
        obj.waypoints!.isNotEmpty) {
      // Draw orthogonal path segments
      final fullPath = [obj.start, ...obj.waypoints!, obj.end];
      final path = _buildRoundedOrthogonalPath(fullPath);
      canvas.drawPath(path, arrowPaint);
      // Arrowhead from last waypoint to end
      _drawArrowHead(canvas, fullPath[fullPath.length - 2], obj.end, arrowPaint);
    } else if (obj.midPoint != null) {
      // Quadratic bezier curve
      final cp = obj.midPoint!;
      final path = Path()
        ..moveTo(obj.start.dx, obj.start.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, obj.end.dx, obj.end.dy);
      canvas.drawPath(path, arrowPaint);
      // Arrowhead using tangent at t=1
      final tangent = obj.end - cp;
      final len = tangent.distance;
      if (len > 0.1) {
        _drawArrowHead(
            canvas, obj.end - tangent * (1.0 / len), obj.end, arrowPaint);
      }
    } else {
      // Simple straight line
      canvas.drawLine(obj.start, obj.end, arrowPaint);
      _drawArrowHead(canvas, obj.start, obj.end, arrowPaint);
    }

    // Draw arrow label at midpoint
    if (obj.arrowLabel != null && obj.arrowLabel!.isNotEmpty) {
      final labelCenter = _computeArrowLabelCenter(obj);
      _drawLabelAtPoint(canvas, obj.arrowLabel!, labelCenter);
    }
  }

  static void _drawLine(Canvas canvas, LineObject obj) {
    final linePaint = Paint()
      ..color = _lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _defaultStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (obj.midPoint != null) {
      final cp = obj.midPoint!;
      final path = Path()
        ..moveTo(obj.start.dx, obj.start.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, obj.end.dx, obj.end.dy);
      canvas.drawPath(path, linePaint);
    } else {
      canvas.drawLine(obj.start, obj.end, linePaint);
    }
  }

  static void _drawPencilStroke(Canvas canvas, PencilStrokeObject obj) {
    if (obj.points.isEmpty) return;

    final paint = Paint()
      ..color = _pencilColor
      ..style = PaintingStyle.fill;

    final options = StrokeOptions(size: 4.0, smoothing: 0.5);
    final outlinePoints = getStroke(obj.points, options: options);

    if (outlinePoints.isEmpty) return;

    if (outlinePoints.length < 2) {
      canvas.drawCircle(outlinePoints.first, options.size / 2, paint);
      return;
    }

    final path = Path();
    path.moveTo(outlinePoints.first.dx, outlinePoints.first.dy);
    for (int i = 0; i < outlinePoints.length - 1; i++) {
      final p0 = outlinePoints[i];
      final p1 = outlinePoints[i + 1];
      path.quadraticBezierTo(
        p0.dx,
        p0.dy,
        (p0.dx + p1.dx) / 2,
        (p0.dy + p1.dy) / 2,
      );
    }
    canvas.drawPath(path, paint);
  }

  static void _drawFigure(Canvas canvas, FigureObject obj) {
    final figurePaint = Paint()
      ..color = _figureColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    _withRotation(canvas, obj.angle, obj.rect.center, () {
      // Dashed border rectangle
      _drawDashedRect(canvas, obj.rect, figurePaint);

      // Label at top-left
      if (obj.label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: obj.label,
            style: TextStyle(fontSize: 12, color: _figureColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, obj.rect.topLeft + const Offset(6, 2));
      }
    });
  }

  static void _drawTextObject(Canvas canvas, TextObject obj) {
    if (obj.text.isEmpty) return;

    _withRotation(canvas, obj.angle, obj.rect.center, () {
      final tp = TextPainter(
        text: TextSpan(text: obj.text, style: obj.style),
        textDirection: TextDirection.ltr,
      )..layout(
          maxWidth:
              obj.rect.width.isFinite ? obj.rect.width : double.infinity);
      tp.paint(canvas, obj.rect.topLeft);
    });
  }

  // -- Rotation Helper --------------------------------------------------------

  /// Applies rotation around [center] for the duration of [draw], then restores.
  static void _withRotation(
      Canvas canvas, double angle, Offset center, void Function() draw) {
    if (angle.abs() < 0.001) {
      draw();
      return;
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);
    draw();
    canvas.restore();
  }

  // -- Paint Helpers ----------------------------------------------------------

  static Paint _fillPaint(ui.Color? color) {
    return Paint()
      ..color = color ?? _defaultFillColor
      ..style = PaintingStyle.fill;
  }

  static Paint _strokePaint(ui.Color? color) {
    return Paint()
      ..color = color ?? _defaultStrokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _defaultStrokeWidth;
  }

  // -- Text Helpers -----------------------------------------------------------

  /// Draws centered text inside a shape's rect.
  static void _drawShapeText(
      Canvas canvas, Rect shapeRect, String? text, TextStyle? style) {
    if (text == null || text.isEmpty) return;

    const defaultStyle =
        TextStyle(fontSize: 14, color: _textColor, fontFamily: 'sans-serif');
    final tp = TextPainter(
      text: TextSpan(text: text, style: style ?? defaultStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: shapeRect.width - 8);
    final offset = Offset(
      shapeRect.center.dx - tp.width / 2,
      shapeRect.center.dy - tp.height / 2,
    );
    tp.paint(canvas, offset);
  }

  /// Draws a label with a background box at the given point.
  static void _drawLabelAtPoint(Canvas canvas, String label, Offset center) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
            fontSize: 12, color: _textColor, fontFamily: 'sans-serif'),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    // Background rect for readability
    final bgRect = Rect.fromCenter(
      center: center,
      width: tp.width + 8,
      height: tp.height + 4,
    );
    final bgPaint = Paint()..color = const ui.Color(0xE01C1C1E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      bgPaint,
    );

    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  // -- Arrow Helpers ----------------------------------------------------------

  static void _drawArrowHead(
      Canvas canvas, Offset from, Offset to, Paint paint) {
    final angle = (to - from).direction;
    const headLength = 12.0;
    const headAngle = 0.5;

    final p1 = Offset(
      to.dx - headLength * math.cos(angle - headAngle),
      to.dy - headLength * math.sin(angle - headAngle),
    );
    final p2 = Offset(
      to.dx - headLength * math.cos(angle + headAngle),
      to.dy - headLength * math.sin(angle + headAngle),
    );

    final headPath = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(
      headPath,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
  }

  /// Computes the geometric midpoint of an arrow path for label placement.
  static Offset _computeArrowLabelCenter(ArrowObject obj) {
    if (obj.pathType == LinkPathType.orthogonal &&
        obj.waypoints != null &&
        obj.waypoints!.isNotEmpty) {
      final fullPath = [obj.start, ...obj.waypoints!, obj.end];
      double totalLen = 0;
      for (int i = 0; i < fullPath.length - 1; i++) {
        totalLen += (fullPath[i + 1] - fullPath[i]).distance;
      }
      double halfLen = totalLen / 2;
      for (int i = 0; i < fullPath.length - 1; i++) {
        final segLen = (fullPath[i + 1] - fullPath[i]).distance;
        if (halfLen <= segLen) {
          final t = segLen > 0 ? halfLen / segLen : 0.0;
          return Offset(
            fullPath[i].dx + (fullPath[i + 1].dx - fullPath[i].dx) * t,
            fullPath[i].dy + (fullPath[i + 1].dy - fullPath[i].dy) * t,
          );
        }
        halfLen -= segLen;
      }
      return fullPath.last;
    }

    // Straight or curved: use quadratic midpoint at t=0.5
    final cp = obj.midPoint ?? (obj.start + obj.end) / 2;
    return Offset(
      0.25 * obj.start.dx + 0.5 * cp.dx + 0.25 * obj.end.dx,
      0.25 * obj.start.dy + 0.5 * cp.dy + 0.25 * obj.end.dy,
    );
  }

  // -- Orthogonal Path --------------------------------------------------------

  /// Builds a [Path] with rounded corners at each bend in an orthogonal route.
  static Path _buildRoundedOrthogonalPath(List<Offset> allPoints) {
    const double cornerRadius = 30.0;
    final path = Path();
    path.moveTo(allPoints[0].dx, allPoints[0].dy);

    for (int i = 1; i < allPoints.length - 1; i++) {
      final prev = allPoints[i - 1];
      final curr = allPoints[i];
      final next = allPoints[i + 1];
      final segPrev = (curr - prev).distance;
      final segNext = (next - curr).distance;
      final r = math.min(cornerRadius, math.min(segPrev / 2, segNext / 2));

      if (r < 1.0) {
        path.lineTo(curr.dx, curr.dy);
        continue;
      }

      final dirIn = Offset(
          (curr.dx - prev.dx) / segPrev, (curr.dy - prev.dy) / segPrev);
      final dirOut = Offset(
          (next.dx - curr.dx) / segNext, (next.dy - curr.dy) / segNext);
      final cross = dirIn.dx * dirOut.dy - dirIn.dy * dirOut.dx;
      if (cross.abs() < 0.01) {
        path.lineTo(curr.dx, curr.dy);
        continue;
      }

      final arcStart =
          Offset(curr.dx - dirIn.dx * r, curr.dy - dirIn.dy * r);
      final arcEnd =
          Offset(curr.dx + dirOut.dx * r, curr.dy + dirOut.dy * r);

      path.lineTo(arcStart.dx, arcStart.dy);
      path.arcToPoint(
        arcEnd,
        radius: Radius.circular(r),
        clockwise: cross > 0,
      );
    }

    path.lineTo(allPoints.last.dx, allPoints.last.dy);
    return path;
  }

  // -- Dashed Rect ------------------------------------------------------------

  /// Draws a dashed rectangle (used for FigureObject).
  static void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 3.0;

    void drawDashedLine(Offset from, Offset to) {
      final delta = to - from;
      final len = delta.distance;
      if (len < 0.1) return;
      final dir = delta / len;
      double drawn = 0;
      while (drawn < len) {
        final segEnd = math.min(drawn + dashLen, len);
        canvas.drawLine(
          from + dir * drawn,
          from + dir * segEnd,
          paint,
        );
        drawn = segEnd + gapLen;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }
}
