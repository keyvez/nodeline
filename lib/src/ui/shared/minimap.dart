import 'dart:math';

import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

String _formatZoom(double zoom) {
  if (zoom >= 100) return '${zoom.round()}x';
  if (zoom >= 10) return '${zoom.toStringAsFixed(1)}x';
  if (zoom >= 1) return '${zoom.toStringAsFixed(2)}x';
  if (zoom >= 0.1) return '${zoom.toStringAsFixed(3)}x';
  if (zoom >= 0.01) return '${zoom.toStringAsFixed(4)}x';
  return '${zoom.toStringAsExponential(2)}x';
}

/// A small overlay widget that renders a bird's-eye view of the entire canvas.
///
/// Place this in a [Stack] on top of the [FlowDrawCanvas]. It reads from
/// [CanvasBloc] via [BlocBuilder] and paints a scaled-down representation of
/// every drawing object plus a blue viewport indicator.
class MiniMap extends StatelessWidget {
  /// Width of the minimap widget.
  final double width;

  /// Height of the minimap widget.
  final double height;

  /// The actual size of the canvas viewport in screen pixels.
  /// When null, the widget uses a LayoutBuilder to obtain the parent size.
  final Size? canvasSize;

  const MiniMap({
    super.key,
    this.width = 200,
    this.height = 150,
    this.canvasSize,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        final miniMapWidget = Material(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          child: SizedBox(
            width: width,
            height: height,
            child: canvasSize != null
                ? CustomPaint(
                    painter: _MiniMapPainter(
                      drawingObjects: state.drawingObjects,
                      viewportOffset: state.viewportOffset,
                      viewportZoom: state.viewportZoom,
                      miniMapSize: Size(width, height),
                      canvasSize: canvasSize!,
                    ),
                  )
                : Builder(
                    builder: (ctx) {
                      final screenSize = MediaQuery.of(ctx).size;
                      return CustomPaint(
                        painter: _MiniMapPainter(
                          drawingObjects: state.drawingObjects,
                          viewportOffset: state.viewportOffset,
                          viewportZoom: state.viewportZoom,
                          miniMapSize: Size(width, height),
                          canvasSize: screenSize,
                        ),
                      );
                    },
                  ),
          ),
        );
        return Stack(
          children: [
            miniMapWidget,
            Positioned(
              top: 6,
              right: 8,
              child: Text(
                _formatZoom(state.viewportZoom),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final Map<String, DrawingObject> drawingObjects;
  final Offset viewportOffset;
  final double viewportZoom;
  final Size miniMapSize;
  final Size canvasSize;

  /// Padding inside the minimap so objects don't touch the edges.
  static const double _padding = 10;

  _MiniMapPainter({
    required this.drawingObjects,
    required this.viewportOffset,
    required this.viewportZoom,
    required this.miniMapSize,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (drawingObjects.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    // Compute bounding box of all objects in canvas space.
    final worldBounds = _computeWorldBounds();

    // Scale is based only on object bounds so panning doesn't change the
    // minimap zoom level. The viewport indicator may be clipped at the edges.
    final paddedBounds = worldBounds.inflate(
      max(worldBounds.width, worldBounds.height) * 0.1,
    );

    // Match the viewport→world transform used in screenToWorld/worldToScreen:
    // viewport.left = -canvasWidth/2/zoom - offset.dx
    final viewportRect = Rect.fromLTWH(
      -canvasSize.width / 2 / viewportZoom - viewportOffset.dx,
      -canvasSize.height / 2 / viewportZoom - viewportOffset.dy,
      canvasSize.width / viewportZoom,
      canvasSize.height / viewportZoom,
    );

    // Compute scale to fit paddedBounds into the minimap area (with padding).
    final drawArea = Size(
      size.width - _padding * 2,
      size.height - _padding * 2,
    );

    final scaleX = drawArea.width / paddedBounds.width;
    final scaleY = drawArea.height / paddedBounds.height;
    final scale = min(scaleX, scaleY);

    // Centering offset so the content is centered in the minimap.
    final scaledWidth = paddedBounds.width * scale;
    final scaledHeight = paddedBounds.height * scale;
    final offsetX = _padding + (drawArea.width - scaledWidth) / 2;
    final offsetY = _padding + (drawArea.height - scaledHeight) / 2;

    Offset toMiniMap(Offset worldPoint) {
      return Offset(
        offsetX + (worldPoint.dx - paddedBounds.left) * scale,
        offsetY + (worldPoint.dy - paddedBounds.top) * scale,
      );
    }

    Rect rectToMiniMap(Rect worldRect) {
      final tl = toMiniMap(worldRect.topLeft);
      final br = toMiniMap(worldRect.bottomRight);
      return Rect.fromPoints(tl, br);
    }

    // Draw objects
    for (final obj in drawingObjects.values) {
      if (obj is RectangleObject || obj is DiamondObject || obj is FigureObject) {
        _drawShapeRect(canvas, rectToMiniMap(obj.rect), obj);
      } else if (obj is CircleObject) {
        _drawShapeEllipse(canvas, rectToMiniMap(obj.rect));
      } else if (obj is TextObject) {
        _drawTextIndicator(canvas, rectToMiniMap(obj.rect));
      } else if (obj is ArrowObject) {
        final arrow = obj;
        final resolvedStart = _resolveAttachment(arrow.startAttachment, arrow.start);
        final resolvedEnd = _resolveAttachment(arrow.endAttachment, arrow.end);
        // Recompute orthogonal waypoints for accurate minimap rendering
        List<Offset>? waypoints;
        if (arrow.pathType == LinkPathType.orthogonal) {
          final obstacles = <Rect>[];
          for (final o in drawingObjects.values) {
            if (o.id == obj.id) continue;
            if (o is ArrowObject || o is LineObject || o is PencilStrokeObject) continue;
            obstacles.add(o.rect);
          }
          final startObjRect = arrow.startAttachment != null
              ? drawingObjects[arrow.startAttachment!.objectId]?.rect
              : null;
          final endObjRect = arrow.endAttachment != null
              ? drawingObjects[arrow.endAttachment!.objectId]?.rect
              : null;
          waypoints = OrthogonalRouter.route(
            start: resolvedStart,
            end: resolvedEnd,
            obstacles: obstacles,
            startObjectRect: startObjRect,
            endObjectRect: endObjRect,
            devicePixelRatio: 1.0,
            zoom: 1.0,
          );
        }
        final startPt = toMiniMap(resolvedStart);
        final endPt = toMiniMap(resolvedEnd);
        _drawConnection(canvas, startPt, endPt, waypoints, toMiniMap);
      } else if (obj is LineObject) {
        final line = obj;
        final resolvedStart = _resolveAttachment(line.startAttachment, line.start);
        final resolvedEnd = _resolveAttachment(line.endAttachment, line.end);
        final startPt = toMiniMap(resolvedStart);
        final endPt = toMiniMap(resolvedEnd);
        _drawLine(canvas, startPt, endPt);
      } else if (obj is PencilStrokeObject) {
        _drawPencilStroke(canvas, obj, toMiniMap);
      }
    }

    // Draw viewport indicator
    final vpMini = rectToMiniMap(viewportRect);
    final vpPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawRect(vpMini, vpPaint);

    final vpBorderPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(vpMini, vpBorderPaint);
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Empty canvas',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  Rect _computeWorldBounds() {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final obj in drawingObjects.values) {
      final r = obj.rect;
      minX = min(minX, r.left);
      minY = min(minY, r.top);
      maxX = max(maxX, r.right);
      maxY = max(maxY, r.bottom);
    }

    if (minX > maxX) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _drawShapeRect(Canvas canvas, Rect miniRect, DrawingObject obj) {
    final fillColor = obj is DiamondObject
        ? Colors.orange.withValues(alpha: 0.6)
        : obj is FigureObject
            ? Colors.purple.withValues(alpha: 0.4)
            : Colors.teal.withValues(alpha: 0.6);

    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    // Ensure a minimum visible size
    final visibleRect = _ensureMinSize(miniRect, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(visibleRect, const Radius.circular(3)),
      paint,
    );

    final borderPaint = Paint()
      ..color = fillColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(visibleRect, const Radius.circular(3)),
      borderPaint,
    );
  }

  void _drawShapeEllipse(Canvas canvas, Rect miniRect) {
    final visibleRect = _ensureMinSize(miniRect, 3);
    final paint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawOval(visibleRect, paint);

    final borderPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawOval(visibleRect, borderPaint);
  }

  void _drawTextIndicator(Canvas canvas, Rect miniRect) {
    final visibleRect = _ensureMinSize(miniRect, 2);
    final paint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawRect(visibleRect, paint);
  }

  void _drawConnection(
    Canvas canvas,
    Offset start,
    Offset end,
    List<Offset>? waypoints,
    Offset Function(Offset) toMiniMap,
  ) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    if (waypoints != null && waypoints.isNotEmpty) {
      final path = Path()..moveTo(start.dx, start.dy);
      for (final wp in waypoints) {
        final miniWp = toMiniMap(wp);
        path.lineTo(miniWp.dx, miniWp.dy);
      }
      path.lineTo(end.dx, end.dy);
      canvas.drawPath(path, paint);
    } else {
      canvas.drawLine(start, end, paint);
    }
  }

  void _drawLine(Canvas canvas, Offset start, Offset end) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawLine(start, end, paint);
  }

  void _drawPencilStroke(
    Canvas canvas,
    PencilStrokeObject stroke,
    Offset Function(Offset) toMiniMap,
  ) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final path = Path();
    final first = toMiniMap(Offset(stroke.points.first.x, stroke.points.first.y));
    path.moveTo(first.dx, first.dy);

    for (var i = 1; i < stroke.points.length; i++) {
      final pt = toMiniMap(Offset(stroke.points[i].x, stroke.points[i].y));
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, paint);
  }

  /// Resolves an attachment to its actual world position on the target object.
  /// Falls back to [fallback] if no attachment or target not found.
  Offset _resolveAttachment(ObjectAttachment? attachment, Offset fallback) {
    if (attachment == null) return fallback;
    final target = drawingObjects[attachment.objectId];
    if (target == null) return fallback;
    final r = target.rect;
    final rp = attachment.relativePosition;
    return r.topLeft + Offset(r.width * rp.dx, r.height * rp.dy);
  }

  /// Ensures a rect has at least [minDim] pixels so tiny objects remain visible.
  Rect _ensureMinSize(Rect rect, double minDim) {
    double w = rect.width;
    double h = rect.height;
    double left = rect.left;
    double top = rect.top;

    if (w < minDim) {
      left -= (minDim - w) / 2;
      w = minDim;
    }
    if (h < minDim) {
      top -= (minDim - h) / 2;
      h = minDim;
    }
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.drawingObjects != drawingObjects ||
        oldDelegate.viewportOffset != viewportOffset ||
        oldDelegate.viewportZoom != viewportZoom ||
        oldDelegate.canvasSize != canvasSize;
  }
}
