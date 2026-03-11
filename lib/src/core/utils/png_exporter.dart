import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flutter/rendering.dart';

/// Exports the canvas to a PNG image.
///
/// Captures the current state of drawing objects and renders them to
/// an offscreen canvas, returning the PNG bytes.
class PngExporter {
  PngExporter._();

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
    final objectPaint = Paint()
      ..color = const ui.Color(0xFFE0E0E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final fillPaint = Paint()
      ..color = const ui.Color(0xFF2A2A2A)
      ..style = PaintingStyle.fill;

    for (final obj in objects.values) {
      if (obj is RectangleObject) {
        final rrect = RRect.fromRectAndRadius(obj.rect, const Radius.circular(6));
        canvas.drawRRect(rrect, fillPaint);
        canvas.drawRRect(rrect, objectPaint);
      } else if (obj is CircleObject) {
        canvas.drawOval(obj.rect, fillPaint);
        canvas.drawOval(obj.rect, objectPaint);
      } else if (obj is DiamondObject) {
        canvas.drawPath(obj.path, fillPaint);
        canvas.drawPath(obj.path, objectPaint);
      } else if (obj is ArrowObject) {
        final arrowPaint = Paint()
          ..color = const ui.Color(0xFF90CAF9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawLine(obj.start, obj.end, arrowPaint);
        _drawArrowHead(canvas, obj.start, obj.end, arrowPaint);
      } else if (obj is LineObject) {
        final linePaint = Paint()
          ..color = const ui.Color(0xFFA5D6A7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawLine(obj.start, obj.end, linePaint);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return byteData?.buffer.asUint8List();
  }

  static void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
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

    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(p1.dx, p1.dy)
      ..moveTo(to.dx, to.dy)
      ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(path, paint);
  }
}
