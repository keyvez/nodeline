import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:fldraw/fldraw.dart';
import 'package:fldraw/src/core/utils/json_extensions.dart';
import 'package:fldraw/src/core/utils/orthogonal_router.dart';
import 'package:fldraw/src/core/utils/renderbox.dart';
import 'package:fldraw/src/core/utils/spatial_hash_grid.dart';
import 'package:fldraw/src/models/drawing_entities.dart';
import 'package:fldraw/src/ui/nodes/node_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

class NodeDiffCheckData {
  final String id;
  final Offset offset;
  final NodeState state;

  NodeDiffCheckData({
    required this.id,
    required this.offset,
    required this.state,
  });
}

class _ParentData extends ContainerBoxParentData<RenderBox> {
  String id = '';
  Offset nodeOffset = Offset.zero;
  NodeState state = NodeState();
  Rect rect = Rect.zero;
}

class FlDrawEditorRenderObjectWidget extends MultiChildRenderObjectWidget {
  final CanvasState canvasState;
  final SelectionState selectionState;
  final FlDrawEditorStyle style;
  final FragmentShader gridShader;
  final TempDrawingObject? tempDrawingObject;
  final Rect selectionArea;
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final Offset? snapHandlePosition;

  FlDrawEditorRenderObjectWidget({
    super.key,
    required this.canvasState,
    required this.selectionState,
    required this.style,
    required this.gridShader,
    this.tempDrawingObject,
    required this.selectionArea,
    this.headerBuilder,
    this.nodeBuilder,
    this.snapHandlePosition,
  }) : super(
         children: canvasState.nodes.values.map((node) {
           node.state.isSelected = selectionState.selectedNodeIds.contains(
             node.id,
           );
           return DefaultNodeWidget(
             node: node,
             headerBuilder: headerBuilder,
             nodeBuilder: nodeBuilder,
           );
         }).toList(),
       );

  @override
  FlDrawEditorRenderBox createRenderObject(BuildContext context) {
    return FlDrawEditorRenderBox(
      style: style,
      gridShader: gridShader,
      canvasState: canvasState,
      selectionState: selectionState,
      selectionArea: selectionArea,
      nodesData: _getNodeDrawData(),
      tempDrawingObject: tempDrawingObject,
      snapHandlePosition: snapHandlePosition,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    FlDrawEditorRenderBox renderObject,
  ) {
    renderObject
      ..style = style
      ..canvasState = canvasState
      ..selectionState = selectionState
      ..selectionArea = selectionArea
      ..tempDrawingObject = tempDrawingObject
      ..snapHandlePosition = snapHandlePosition
      ..updateNodes(_getNodeDrawData());
  }

  List<NodeDiffCheckData> _getNodeDrawData() {
    return canvasState.nodes.values
        .map(
          (node) => NodeDiffCheckData(
            id: node.id,
            offset: node.offset,
            state: node.state,
          ),
        )
        .toList();
  }
}

class FlDrawEditorRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ParentData> {
  FlDrawEditorRenderBox({
    required FlDrawEditorStyle style,
    required FragmentShader gridShader,
    required CanvasState canvasState,
    required SelectionState selectionState,
    required Rect selectionArea,
    required List<NodeDiffCheckData> nodesData,
    required this.tempDrawingObject,
    this.snapHandlePosition,
  }) : _style = style,
       _gridShader = gridShader,
       _canvasState = canvasState,
       _selectionState = selectionState,
       _selectionArea = selectionArea {
    _loadGridShader();
    updateNodes(nodesData);
  }

  final SpatialHashGrid _spatialHashGrid = SpatialHashGrid();

  CanvasState _canvasState;

  CanvasState get canvasState => _canvasState;

  set canvasState(CanvasState value) {
    if (_canvasState == value) return;
    _canvasState = value;
    _transformMatrixDirty = true;
    markNeedsLayout();
  }

  SelectionState _selectionState;

  SelectionState get selectionState => _selectionState;

  set selectionState(SelectionState value) {
    if (_selectionState == value) return;
    _selectionState = value;
    markNeedsPaint();
  }

  Offset? snapHandlePosition;

  FlDrawEditorStyle _style;

  FlDrawEditorStyle get style => _style;

  set style(FlDrawEditorStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaint();
  }

  FragmentShader _gridShader;

  FragmentShader get gridShader => _gridShader;

  set gridShader(FragmentShader value) {
    if (_gridShader == value) return;
    _gridShader = value;
    markNeedsPaint();
  }

  Matrix4? _transformMatrix;
  bool _transformMatrixDirty = true;

  Rect _selectionArea;

  Rect get selectionArea => _selectionArea;

  set selectionArea(Rect value) {
    if (_selectionArea == value) return;
    _selectionArea = value;
    markNeedsPaint();
  }

  TempDrawingObject? tempDrawingObject;
  List<NodeDiffCheckData> _nodesDiffCheckData = [];

  void _loadGridShader() {
    final gridStyle = style.gridStyle;
    gridShader.setFloat(0, gridStyle.gridSpacingX);
    gridShader.setFloat(1, gridStyle.gridSpacingY);
    final lineColor = gridStyle.lineColor;
    gridShader.setFloat(4, gridStyle.lineWidth);
    gridShader.setFloat(5, lineColor.red / 255.0);
    gridShader.setFloat(6, lineColor.green / 255.0);
    gridShader.setFloat(7, lineColor.blue / 255.0);
    gridShader.setFloat(8, lineColor.opacity);
    final intersectionColor = gridStyle.intersectionColor;
    gridShader.setFloat(9, gridStyle.intersectionRadius);
    gridShader.setFloat(10, intersectionColor.red / 255.0);
    gridShader.setFloat(11, intersectionColor.green / 255.0);
    gridShader.setFloat(12, intersectionColor.blue / 255.0);
    gridShader.setFloat(13, intersectionColor.opacity);
  }

  void updateNodes(List<NodeDiffCheckData> nodesData) {
    _nodesDiffCheckData = nodesData;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ParentData) {
      child.parentData = _ParentData();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    RenderBox? child = firstChild;
    _spatialHashGrid.clear();

    int i = 0;
    while (child != null && i < _nodesDiffCheckData.length) {
      final nodeData = _nodesDiffCheckData[i];
      final childParentData = child.parentData as _ParentData;

      childParentData.id = nodeData.id;

      child.layout(
        BoxConstraints.loose(constraints.biggest),
        parentUsesSize: true,
      );

      final rect = Rect.fromLTWH(
        nodeData.offset.dx,
        nodeData.offset.dy,
        child.size.width,
        child.size.height,
      );
      childParentData.rect = rect;

      _spatialHashGrid.insert((id: nodeData.id, rect: rect));

      child = childParentData.nextSibling;
      i++;
    }
  }

  Rect _calculateViewport() {
    return Rect.fromLTWH(
      -size.width / 2 / canvasState.viewportZoom -
          canvasState.viewportOffset.dx,
      -size.height / 2 / canvasState.viewportZoom -
          canvasState.viewportOffset.dy,
      size.width / canvasState.viewportZoom,
      size.height / canvasState.viewportZoom,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final (viewport, startX, startY) = _prepareCanvas(context.canvas, size);
    _paintGrid(context.canvas, viewport, startX, startY);

    final visibleNodes = _spatialHashGrid.queryArea(viewport.inflate(300));

    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData as _ParentData;
      final nodeInstance = canvasState.nodes[childParentData.id];
      if (nodeInstance != null && visibleNodes.contains(childParentData.id)) {
        context.paintChild(child, nodeInstance.offset);
      }
      child = childParentData.nextSibling;
    }

    _paintDrawingObjects(context.canvas);
    _paintSnapHandle(context.canvas);
    _paintTempDrawingObject(context.canvas);
    _paintSelectionArea(context.canvas, viewport);

    _transformMatrixDirty = false;
  }

  Matrix4 _getTransformMatrix() {
    if (_transformMatrix != null && !_transformMatrixDirty)
      return _transformMatrix!;
    return _transformMatrix = Matrix4.identity()
      ..translate(size.width / 2, size.height / 2)
      ..scale(canvasState.viewportZoom, canvasState.viewportZoom)
      ..translate(canvasState.viewportOffset.dx, canvasState.viewportOffset.dy);
  }

  (Rect, double, double) _prepareCanvas(Canvas canvas, Size size) {
    canvas.transform(_getTransformMatrix().storage);
    final viewport = _calculateViewport();
    final startX =
        (viewport.left / style.gridStyle.gridSpacingX).floor() *
        style.gridStyle.gridSpacingX;
    final startY =
        (viewport.top / style.gridStyle.gridSpacingY).floor() *
        style.gridStyle.gridSpacingY;
    canvas.clipRect(viewport, clipOp: ui.ClipOp.intersect, doAntiAlias: false);
    return (viewport, startX, startY);
  }

  final _pencilOptions = StrokeOptions(
    size: 8.0,
    thinning: 0.7,
    smoothing: 0.5,
    streamline: 0.5,
    simulatePressure: true,
  );

  get zoom => canvasState.viewportZoom;

  get drawingObjects => canvasState.drawingObjects;

  void _paintGrid(Canvas canvas, Rect viewport, double startX, double startY) {
    if (!canvasState.showGrid) return;
    gridShader.setFloat(2, startX);
    gridShader.setFloat(3, startY);
    // Scale down dots and lines when zoomed out (half size at zoom <= 0.5, full at zoom >= 1.0)
    final double z = canvasState.viewportZoom;
    final double scale = z >= 1.0 ? 1.0 : (0.5 + 0.5 * ((z - 0.5) / 0.5).clamp(0.0, 1.0));
    gridShader.setFloat(4, style.gridStyle.lineWidth * scale);
    gridShader.setFloat(9, style.gridStyle.intersectionRadius * scale);
    gridShader.setFloat(14, viewport.left);
    gridShader.setFloat(15, viewport.top);
    gridShader.setFloat(16, viewport.right);
    gridShader.setFloat(17, viewport.bottom);
    gridShader.setFloat(18, z);
    canvas.drawRect(viewport, Paint()..shader = gridShader);
  }

  void _paintSnapHandle(Canvas canvas) {
    if (snapHandlePosition == null) return;
    final paint = Paint()..color = Colors.cyan.withOpacity(0.8);
    canvas.drawCircle(snapHandlePosition!, 6.0 / zoom, paint);
  }

  void _paintDrawingObjects(Canvas canvas) {
    final Paint objectPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    final Paint selectedBorderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;
    final Paint selectedArrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;

    final Paint handlePaint = Paint()..color = Colors.blue;
    final Paint handleHitAreaPaint = Paint()..color = Colors.transparent;
    final Paint selectedRectBorderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / zoom;

    for (final obj in drawingObjects.values) {
      final isSelected = selectionState.selectedDrawingObjectIds.contains(
        obj.id,
      );
      obj.isSelected = isSelected;

      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is FigureObject ||
          obj is TextObject ||
          obj is SvgObject) {
        canvas.save();
        canvas.translate(obj.rect.center.dx, obj.rect.center.dy);
        canvas.rotate(obj.angle);
        canvas.translate(-obj.rect.center.dx, -obj.rect.center.dy);

        if (obj is FigureObject) {
          final paint = Paint()
            ..color =
            obj.isSelected ? Colors.blue : Colors.white.withOpacity(0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = obj.isSelected ? 2.0 / zoom : 1.5 / zoom;
          _paintDashedRect(canvas, obj.rect, paint);
          final textStyle = TextStyle(
              color: paint.color,
              fontSize: 14.0 / zoom,
              fontWeight: FontWeight.bold);
          final textSpan = TextSpan(text: obj.label, style: textStyle);
          final textPainter =
          TextPainter(text: textSpan, textDirection: TextDirection.ltr)
            ..layout();
          textPainter.paint(
              canvas, obj.rect.topLeft - Offset(0, textPainter.height));
        } else if (obj is TextObject) {
          if (!obj.isEditing) {
            final textPainter = TextPainter(
                text: TextSpan(text: obj.text, style: obj.style),
                textDirection: TextDirection.ltr)
              ..layout(
                  maxWidth:
                  obj.rect.width.isFinite ? obj.rect.width : double.infinity)
              ..paint(canvas, obj.rect.topLeft);
          }
        } else if (obj is CircleObject) {
          canvas.drawOval(obj.rect, objectPaint);
        } else if (obj is RectangleObject) {
          final rrect =
          RRect.fromRectAndRadius(obj.rect, const Radius.circular(24.0));
          canvas.drawRRect(rrect, objectPaint);
        } else if (obj is SvgObject) {
          canvas.save();
          canvas.translate(obj.rect.left, obj.rect.top);
          final Size svgSize = obj.pictureInfo.size;
          final double scaleX = obj.rect.width /
              (svgSize.width.isFinite && svgSize.width > 0
                  ? svgSize.width
                  : 1);
          final double scaleY = obj.rect.height /
              (svgSize.height.isFinite && svgSize.height > 0
                  ? svgSize.height
                  : 1);
          canvas.scale(scaleX, scaleY);
          canvas.drawPicture(obj.pictureInfo.picture);
          canvas.restore();
        }

        if (isSelected) {
          final selectionPadding = 4.0 / zoom;
          final selectionRect = obj.rect.inflate(selectionPadding);
          canvas.drawRect(selectionRect, selectedBorderPaint);

          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;
          final corners = [
            selectionRect.topLeft,
            selectionRect.topRight,
            selectionRect.bottomRight,
            selectionRect.bottomLeft
          ];
          for (final corner in corners) {
            canvas.drawCircle(corner, handleHitAreaRadius, handleHitAreaPaint);
            canvas.drawCircle(corner, visibleHandleRadius, handlePaint);
          }

          if (selectionState.selectedDrawingObjectIds.length == 1 && (obj is RectangleObject || obj is CircleObject)) {
            _paintQuickActionArrows(canvas, obj.rect);
          }
        }

        canvas.restore();
        continue;
      }

      if (obj is PencilStrokeObject) {
        final paint =
        Paint()..color = obj.isSelected ? Colors.blue : Colors.white;
        _paintPencilStroke(canvas, obj, paint);

        if (obj.isSelected) {
          final selectionPadding = 4.0 / zoom;
          final selectionRect = obj.rect.inflate(selectionPadding);
          final selectionRRect = RRect.fromRectAndRadius(
            selectionRect,
            const Radius.circular(6.0),
          );
          canvas.drawRRect(selectionRRect, selectedRectBorderPaint);

          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;
          final corners = [
            selectionRect.topLeft,
            selectionRect.topRight,
            selectionRect.bottomRight,
            selectionRect.bottomLeft,
          ];
          for (final corner in corners) {
            canvas.drawCircle(corner, handleHitAreaRadius, handleHitAreaPaint);
            canvas.drawCircle(corner, visibleHandleRadius, handlePaint);
          }
        }
        continue;
      } else if (obj is ArrowObject) {
        final paint = obj.isSelected ? selectedArrowPaint : objectPaint;
        final pathType = obj.pathType;
        // Resolve attached object rects
        Rect? startObjRect;
        Rect? endObjRect;
        final startAttachment = obj.startAttachment;
        final endAttachment = obj.endAttachment;

        if (startAttachment != null) {
          final targetNode = canvasState.nodes[startAttachment.objectId];
          final targetObject =
          canvasState.drawingObjects[startAttachment.objectId];
          startObjRect = targetNode != null
              ? getNodeBoundsInWorld(targetNode)
              : targetObject?.rect;
        }

        if (endAttachment != null) {
          final targetNode = canvasState.nodes[endAttachment.objectId];
          final targetObject =
          canvasState.drawingObjects[endAttachment.objectId];
          endObjRect = targetNode != null
              ? getNodeBoundsInWorld(targetNode)
              : targetObject?.rect;
        }

        var start = obj.start;
        var end = obj.end;
        List<Offset>? waypoints = obj.waypoints;

        // Resolve endpoints from relativePosition (always respect stored attachments)
        if (startObjRect != null && startAttachment != null) {
          final relPos = startAttachment.relativePosition;
          start = startObjRect.topLeft +
              Offset(startObjRect.width * relPos.dx, startObjRect.height * relPos.dy);
        }
        if (endObjRect != null && endAttachment != null) {
          final relPos = endAttachment.relativePosition;
          end = endObjRect.topLeft +
              Offset(endObjRect.width * relPos.dx, endObjRect.height * relPos.dy);
        }

        // For orthogonal arrows, dynamically recompute waypoints for routing
        if (pathType == LinkPathType.orthogonal) {
          // Collect obstacles, excluding source/target objects — the router
          // handles them separately via startObjectRect/endObjectRect
          final startAttachId = obj.startAttachment?.objectId;
          final endAttachId = obj.endAttachment?.objectId;
          final obstacles = <Rect>[];
          for (final o in canvasState.drawingObjects.values) {
            if (o.id == obj.id) continue;
            if (o.id == startAttachId || o.id == endAttachId) continue;
            if (o is ArrowObject || o is LineObject || o is PencilStrokeObject) continue;
            obstacles.add(o.rect);
          }
          for (final node in canvasState.nodes.values) {
            if (node.id == startAttachId || node.id == endAttachId) continue;
            final bounds = getNodeBoundsInWorld(node);
            if (bounds != null) obstacles.add(bounds);
          }

          waypoints = OrthogonalRouter.route(
            start: start,
            end: end,
            obstacles: obstacles,
            startObjectRect: startObjRect,
            endObjectRect: endObjRect,
          );
        }

        var controlPoint = obj.midPoint ?? (start + end) / 2;

        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final Offset cornerPoint;
        if (dx.abs() > dy.abs()) {
          cornerPoint = Offset(end.dx, start.dy);
        } else {
          cornerPoint = Offset(start.dx, end.dy);
        }

        if (pathType == LinkPathType.orthogonal) {
          // Stop the drawn path slightly before the end object edge so the
          // arrow doesn't cross into the object. The arrowhead tip becomes
          // the visual endpoint.
          final drawEnd = (waypoints != null && waypoints.isNotEmpty && endObjRect != null)
              ? _shortenEndpoint(waypoints.last, end, 4.0 / zoom)
              : end;
          _paintOrthogonalPath(canvas, start, drawEnd, paint, waypoints: waypoints);
        } else {
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(
              controlPoint.dx,
              controlPoint.dy,
              end.dx,
              end.dy,
            );
          canvas.drawPath(path, paint);
        }

        if (pathType == LinkPathType.orthogonal) {
          // Determine arrow head direction from the last segment
          final arrowEnd = (waypoints != null && waypoints.isNotEmpty && endObjRect != null)
              ? _shortenEndpoint(waypoints.last, end, 4.0 / zoom)
              : end;
          if (waypoints != null && waypoints.isNotEmpty) {
            controlPoint = waypoints.last;
          } else {
            final dx = end.dx - start.dx;
            final dy = end.dy - start.dy;
            if (dx.abs() > dy.abs()) {
              controlPoint = Offset(end.dx, start.dy);
            } else {
              controlPoint = Offset(start.dx, end.dy);
            }
          }
          _paintArrowHead(canvas, controlPoint, arrowEnd, paint);
        } else {
          _paintArrowHead(canvas, controlPoint, end, paint);
        }

        if (obj.isSelected) {
          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;
          final onCurveMidPoint =
              (start * 0.25) + (controlPoint * 0.5) + (end * 0.25);

          // For orthogonal arrows with waypoints, only show start/end handles
          final List<Offset> handles;
          if (pathType == LinkPathType.orthogonal && waypoints != null && waypoints.isNotEmpty) {
            handles = [start, end];
          } else {
            handles = [
              start,
              end,
              pathType == LinkPathType.orthogonal ? cornerPoint : onCurveMidPoint,
            ];
          }
          for (final handlePos in handles) {
            canvas.drawCircle(
              handlePos,
              handleHitAreaRadius,
              handleHitAreaPaint,
            );
            canvas.drawCircle(handlePos, visibleHandleRadius, handlePaint);
          }
        }
        continue;
      } else if (obj is LineObject) {
        final paint = obj.isSelected ? selectedArrowPaint : objectPaint;

        var start = obj.start;
        final startAttachment = obj.startAttachment;
        if (startAttachment != null) {
          final targetNode = canvasState.nodes[startAttachment.objectId];
          final targetObject =
          canvasState.drawingObjects[startAttachment.objectId];
          final Rect? targetRect = targetNode != null
              ? getNodeBoundsInWorld(targetNode)
              : targetObject?.rect;

          if (targetRect != null) {
            final relPos = startAttachment.relativePosition;
            start = targetRect.topLeft +
                Offset(
                  targetRect.width * relPos.dx,
                  targetRect.height * relPos.dy,
                );
          }
        }

        var end = obj.end;
        final endAttachment = obj.endAttachment;
        if (endAttachment != null) {
          final targetNode = canvasState.nodes[endAttachment.objectId];
          final targetObject =
          canvasState.drawingObjects[endAttachment.objectId];
          final Rect? targetRect = targetNode != null
              ? getNodeBoundsInWorld(targetNode)
              : targetObject?.rect;

          if (targetRect != null) {
            final relPos = endAttachment.relativePosition;
            end = targetRect.topLeft +
                Offset(
                  targetRect.width * relPos.dx,
                  targetRect.height * relPos.dy,
                );
          }
        }

        final controlPoint = obj.midPoint ?? (start + end) / 2;

        final path = Path();
        path.moveTo(start.dx, start.dy);
        final mid = obj.midPoint ?? (start + end) / 2;
        path.quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);

        canvas.drawPath(path, paint);

        if (obj.isSelected) {
          final double visibleHandleRadius = 4.0 / zoom;
          final double handleHitAreaRadius = 10.0 / zoom;
          final onCurveMidPoint =
              (start * 0.25) + (controlPoint * 0.5) + (end * 0.25);

          final handles = [start, end, onCurveMidPoint];
          for (final handlePos in handles) {
            canvas.drawCircle(
              handlePos,
              handleHitAreaRadius,
              handleHitAreaPaint,
            );
            canvas.drawCircle(handlePos, visibleHandleRadius, handlePaint);
          }
        }
        continue;
      }
    }
  }

  void _paintQuickActionArrows(Canvas canvas, Rect rect) {
    final double baseHandleSize = 20.0;
    final double handleSize = baseHandleSize / sqrt(zoom);
    final double halfHandle = handleSize / 2;
    final double spacing = 10.0 / sqrt(zoom);

    final Paint handlePaint = Paint()..color = Colors.blue.withOpacity(0.8);
    final Paint arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom
      ..strokeCap = StrokeCap.round;

    final positions = {
      'top': rect.topCenter - Offset(0, spacing + halfHandle),
      'right': rect.centerRight + Offset(spacing + halfHandle, 0),
      'bottom': rect.bottomCenter + Offset(0, spacing + halfHandle),
      'left': rect.centerLeft - Offset(spacing + halfHandle, 0),
    };

    for (var entry in positions.entries) {
      final center = entry.value;
      final handleRect =
      Rect.fromCenter(center: center, width: handleSize, height: handleSize);
      canvas.drawOval(handleRect, handlePaint);

      final Path arrowPath = Path();
      final arrowSize = handleSize * 0.3;
      switch (entry.key) {
        case 'top':
          arrowPath.moveTo(center.dx, center.dy - arrowSize);
          arrowPath.lineTo(center.dx, center.dy + arrowSize);
          arrowPath.moveTo(center.dx - arrowSize, center.dy);
          arrowPath.lineTo(center.dx, center.dy - arrowSize);
          arrowPath.lineTo(center.dx + arrowSize, center.dy);
          break;
        case 'right':
          arrowPath.moveTo(center.dx - arrowSize, center.dy);
          arrowPath.lineTo(center.dx + arrowSize, center.dy);
          arrowPath.moveTo(center.dx, center.dy - arrowSize);
          arrowPath.lineTo(center.dx + arrowSize, center.dy);
          arrowPath.lineTo(center.dx, center.dy + arrowSize);
          break;
        case 'bottom':
          arrowPath.moveTo(center.dx, center.dy - arrowSize);
          arrowPath.lineTo(center.dx, center.dy + arrowSize);
          arrowPath.moveTo(center.dx - arrowSize, center.dy);
          arrowPath.lineTo(center.dx, center.dy + arrowSize);
          arrowPath.lineTo(center.dx + arrowSize, center.dy);
          break;
        case 'left':
          arrowPath.moveTo(center.dx - arrowSize, center.dy);
          arrowPath.lineTo(center.dx + arrowSize, center.dy);
          arrowPath.moveTo(center.dx, center.dy - arrowSize);
          arrowPath.lineTo(center.dx - arrowSize, center.dy);
          arrowPath.lineTo(center.dx, center.dy + arrowSize);
          break;
      }
      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  void _paintDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const double dashWidth = 5.0;
    const double dashSpace = 3.0;

    double startX = rect.left;
    while (startX < rect.right) {
      canvas.drawLine(
        Offset(startX, rect.top),
        Offset(min(startX + dashWidth, rect.right), rect.top),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
    startX = rect.left;
    while (startX < rect.right) {
      canvas.drawLine(
        Offset(startX, rect.bottom),
        Offset(min(startX + dashWidth, rect.right), rect.bottom),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
    double startY = rect.top;
    while (startY < rect.bottom) {
      canvas.drawLine(
        Offset(rect.left, startY),
        Offset(rect.left, min(startY + dashWidth, rect.bottom)),
        paint,
      );
      startY += dashWidth + dashSpace;
    }
    startY = rect.top;
    while (startY < rect.bottom) {
      canvas.drawLine(
        Offset(rect.right, startY),
        Offset(rect.right, min(startY + dashWidth, rect.bottom)),
        paint,
      );
      startY += dashWidth + dashSpace;
    }
  }

  void _paintPencilStroke(
    Canvas canvas,
    PencilStrokeObject object,
    Paint paint,
  ) {
    final options = _pencilOptions.copyWith(size: 8.0 / sqrt(zoom));
    final outlinePoints = getStroke(object.points, options: options);

    if (outlinePoints.isEmpty) {
      object.cachedPath = null;
      return;
    } else if (outlinePoints.length < 2) {
      final path = Path()
        ..addOval(
          Rect.fromCircle(
            center: outlinePoints.first,
            radius: options.size / 2,
          ),
        );
      object.cachedPath = path;
      canvas.drawPath(path, paint..style = PaintingStyle.fill);
    } else {
      final path = Path();
      path.moveTo(outlinePoints.first.dx, outlinePoints.first.dy);
      for (int i = 0; i < outlinePoints.length - 1; ++i) {
        final p0 = outlinePoints[i];
        final p1 = outlinePoints[i + 1];
        path.quadraticBezierTo(
          p0.dx,
          p0.dy,
          (p0.dx + p1.dx) / 2,
          (p0.dy + p1.dy) / 2,
        );
      }
      object.cachedPath = path;
      canvas.drawPath(path, paint..style = PaintingStyle.fill);
    }
  }

  /// Shortens the endpoint by [amount] along the direction from [prev] to [end].
  static Offset _shortenEndpoint(Offset prev, Offset end, double amount) {
    final dir = end - prev;
    final dist = dir.distance;
    if (dist < amount * 2) return end; // Too short to shorten
    final unit = dir / dist;
    return end - unit * amount;
  }

  void _paintArrowHead(
    Canvas canvas,
    Offset controlPoint,
    Offset end,
    Paint paint,
  ) {
    final double arrowSize = 12.0 / zoom;
    const double arrowAngle = 25 * (pi / 180);

    final lineVector = end - controlPoint;
    if (lineVector.distanceSquared == 0)
      return; // Avoid errors if start and end are the same
    final angle = lineVector.direction;

    final Path path = Path();
    final p2 = end - Offset.fromDirection(angle - arrowAngle, arrowSize);
    final p3 = end - Offset.fromDirection(angle + arrowAngle, arrowSize);

    path.moveTo(p2.dx, p2.dy);
    path.lineTo(end.dx, end.dy);
    path.lineTo(p3.dx, p3.dy);

    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  void _paintOrthogonalPath(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    List<Offset>? waypoints,
  }) {
    final allPoints = [start, ...?waypoints, end];

    if (allPoints.length == 2) {
      // Simple L-path fallback
      final double dx = end.dx - start.dx;
      final double dy = end.dy - start.dy;
      final Path path = Path();
      path.moveTo(start.dx, start.dy);
      if (dx.abs() > dy.abs()) {
        path.lineTo(end.dx, start.dy);
        path.lineTo(end.dx, end.dy);
      } else {
        path.lineTo(start.dx, end.dy);
        path.lineTo(end.dx, end.dy);
      }
      canvas.drawPath(path, paint);
      return;
    }

    // Multi-segment path with rounded corners
    final double cornerRadius = 24.0 / zoom;
    final Path path = Path();
    path.moveTo(allPoints[0].dx, allPoints[0].dy);

    for (int i = 1; i < allPoints.length - 1; i++) {
      final prev = allPoints[i - 1];
      final curr = allPoints[i];
      final next = allPoints[i + 1];

      // Compute segment lengths
      final segPrev = (curr - prev).distance;
      final segNext = (next - curr).distance;

      // Clamp radius to half the shorter adjacent segment
      final r = min(cornerRadius, min(segPrev / 2, segNext / 2));

      if (r < 1.0) {
        // Too tight, just draw straight
        path.lineTo(curr.dx, curr.dy);
        continue;
      }

      // Direction vectors (normalized)
      final dirIn = Offset(
        (curr.dx - prev.dx) / segPrev,
        (curr.dy - prev.dy) / segPrev,
      );
      final dirOut = Offset(
        (next.dx - curr.dx) / segNext,
        (next.dy - curr.dy) / segNext,
      );

      // Check if points are collinear (no actual turn) — skip arc
      final cross = dirIn.dx * dirOut.dy - dirIn.dy * dirOut.dx;
      if (cross.abs() < 0.01) {
        path.lineTo(curr.dx, curr.dy);
        continue;
      }

      // Points where the arc starts/ends
      final arcStart = Offset(
        curr.dx - dirIn.dx * r,
        curr.dy - dirIn.dy * r,
      );
      final arcEnd = Offset(
        curr.dx + dirOut.dx * r,
        curr.dy + dirOut.dy * r,
      );

      // Draw line to arc start
      path.lineTo(arcStart.dx, arcStart.dy);

      final clockwise = cross > 0;

      path.arcToPoint(
        arcEnd,
        radius: Radius.circular(r),
        clockwise: clockwise,
      );
    }

    // Final segment to end
    path.lineTo(allPoints.last.dx, allPoints.last.dy);

    canvas.drawPath(path, paint);
  }

  void _paintTempDrawingObject(Canvas canvas) {
    if (tempDrawingObject == null) return;
    final Paint tempPaint = Paint()
      ..color = Colors.grey.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    final start = tempDrawingObject!.start;
    final end = tempDrawingObject!.end;
    final rect = Rect.fromPoints(start, end);

    switch (tempDrawingObject!.tool) {
      case EditorTool.circle:
        canvas.drawOval(rect.normalize, tempPaint);
        break;
      case EditorTool.square:
        canvas.drawRect(rect.normalize, tempPaint);
        break;
      case EditorTool.arrowTopRight:
        if (tempDrawingObject!.pathType == LinkPathType.orthogonal) {
          _paintOrthogonalPath(canvas, start, end, tempPaint, waypoints: tempDrawingObject!.waypoints);
        } else {
          canvas.drawLine(start, end, tempPaint);
        }
        // Compute arrow head direction from last waypoint if available
        Offset arrowHeadControl = start;
        if (tempDrawingObject!.pathType == LinkPathType.orthogonal) {
          final wps = tempDrawingObject!.waypoints;
          if (wps != null && wps.isNotEmpty) {
            arrowHeadControl = wps.last;
          } else {
            final dx = end.dx - start.dx;
            final dy = end.dy - start.dy;
            if (dx.abs() > dy.abs()) {
              arrowHeadControl = Offset(end.dx, start.dy);
            } else {
              arrowHeadControl = Offset(start.dx, end.dy);
            }
          }
        }
        _paintArrowHead(canvas, arrowHeadControl, end, tempPaint);
        break;
      case EditorTool.line:
        canvas.drawLine(start, end, tempPaint);
        break;
      case EditorTool.pencil:
        _paintPencilStroke(
          canvas,
          PencilStrokeObject(id: "temp", points: tempDrawingObject!.points),
          tempPaint,
        );
        break;
      case EditorTool.figure:
        _paintDashedRect(canvas, rect.normalize, tempPaint);
        break;
      default:
        break;
    }
  }

  void _paintSelectionArea(Canvas canvas, Rect viewport) {
    if (selectionArea.isEmpty) return;
    final style = FlSelectionAreaStyle();
    final Paint selectionPaint = Paint()
      ..color = style.color
      ..style = PaintingStyle.fill;
    canvas.drawRect(selectionArea, selectionPaint);
    final Paint borderPaint = Paint()
      ..color = style.borderColor
      ..strokeWidth = style.borderWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRect(selectionArea, borderPaint);
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }

    if (size.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }

    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final childParentData = child.parentData as _ParentData;
      final nodeInstance = canvasState.nodes[childParentData.id];

      if (nodeInstance == null) {
        child = childParentData.previousSibling;
        continue;
      }

      final transform = _getTransformMatrix();
      final invertedTransform = Matrix4.tryInvert(transform);
      if (invertedTransform == null) {
        child = childParentData.previousSibling;
        continue;
      }

      final worldPosition = MatrixUtils.transformPoint(
        invertedTransform,
        position,
      );

      final childLocalPosition = worldPosition - nodeInstance.offset;

      if (child.hitTest(result, position: childLocalPosition)) {
        return true;
      }

      child = childParentData.previousSibling;
    }
    return false;
  }
}
