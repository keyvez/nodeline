import 'dart:ui';

import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flutter/material.dart';

/// Represents an alignment guide line for smart snapping.
class SnapGuide {
  /// The axis this guide aligns on.
  final SnapGuideAxis axis;

  /// Position of the guide line (x for vertical, y for horizontal).
  final double position;

  /// The snapped coordinate.
  final double snappedValue;

  /// ID of the reference object that generated this guide.
  final String referenceObjectId;

  const SnapGuide({
    required this.axis,
    required this.position,
    required this.snappedValue,
    required this.referenceObjectId,
  });
}

enum SnapGuideAxis { horizontal, vertical }

/// Computes smart snap guides for object alignment.
///
/// Detects when a moving object aligns with other objects' edges or centers,
/// providing visual guides and snapped positions.
class AlignmentGuide {
  /// Snap threshold in logical pixels.
  static const double snapThreshold = 8.0;

  /// Finds snap guides for a moving rect relative to other objects.
  ///
  /// [additionalRects] allows passing extra reference rects (e.g. node bounds)
  /// that are not part of the [allObjects] drawing-object map.
  static List<SnapGuide> findGuides(
    Rect movingRect,
    Map<String, DrawingObject> allObjects,
    Set<String> excludeIds, {
    Map<String, Rect> additionalRects = const {},
  }) {
    final guides = <SnapGuide>[];
    final movingCx = movingRect.center.dx;
    final movingCy = movingRect.center.dy;

    for (final entry in allObjects.entries) {
      if (excludeIds.contains(entry.key)) continue;
      final obj = entry.value;
      if (obj is ArrowObject || obj is LineObject || obj is PencilStrokeObject) {
        continue;
      }

      _checkRect(movingRect, movingCx, movingCy, obj.rect, entry.key, guides);
    }

    for (final entry in additionalRects.entries) {
      if (excludeIds.contains(entry.key)) continue;
      _checkRect(movingRect, movingCx, movingCy, entry.value, entry.key, guides);
    }

    return guides;
  }

  static void _checkRect(
    Rect movingRect,
    double movingCx,
    double movingCy,
    Rect ref,
    String refId,
    List<SnapGuide> guides,
  ) {
    // Vertical guides (x alignment)
    _checkSnap(movingRect.left, ref.left, SnapGuideAxis.vertical, refId, guides);
    _checkSnap(movingRect.right, ref.right, SnapGuideAxis.vertical, refId, guides);
    _checkSnap(movingCx, ref.center.dx, SnapGuideAxis.vertical, refId, guides);
    _checkSnap(movingRect.left, ref.right, SnapGuideAxis.vertical, refId, guides);
    _checkSnap(movingRect.right, ref.left, SnapGuideAxis.vertical, refId, guides);

    // Horizontal guides (y alignment)
    _checkSnap(movingRect.top, ref.top, SnapGuideAxis.horizontal, refId, guides);
    _checkSnap(movingRect.bottom, ref.bottom, SnapGuideAxis.horizontal, refId, guides);
    _checkSnap(movingCy, ref.center.dy, SnapGuideAxis.horizontal, refId, guides);
    _checkSnap(movingRect.top, ref.bottom, SnapGuideAxis.horizontal, refId, guides);
    _checkSnap(movingRect.bottom, ref.top, SnapGuideAxis.horizontal, refId, guides);
  }

  static void _checkSnap(
    double movingValue,
    double refValue,
    SnapGuideAxis axis,
    String refId,
    List<SnapGuide> guides,
  ) {
    final diff = (movingValue - refValue).abs();
    if (diff < snapThreshold) {
      guides.add(SnapGuide(
        axis: axis,
        position: refValue,
        snappedValue: refValue,
        referenceObjectId: refId,
      ));
    }
  }

  /// Paints snap guide lines on the canvas.
  static void paintGuides(
    Canvas canvas,
    List<SnapGuide> guides,
    Rect visibleArea,
  ) {
    if (guides.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF2196F3)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // De-duplicate by axis + position
    final seen = <String>{};
    for (final guide in guides) {
      final key = '${guide.axis.name}_${guide.position.toStringAsFixed(1)}';
      if (seen.contains(key)) continue;
      seen.add(key);

      if (guide.axis == SnapGuideAxis.vertical) {
        canvas.drawLine(
          Offset(guide.position, visibleArea.top),
          Offset(guide.position, visibleArea.bottom),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(visibleArea.left, guide.position),
          Offset(visibleArea.right, guide.position),
          paint,
        );
      }
    }
  }
}
