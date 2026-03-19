import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/core/utils/json_extensions.dart';
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';
import 'package:flow_draw/src/core/utils/renderbox.dart';
import 'package:flow_draw/src/core/utils/spatial_hash_grid.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/ui/nodes/node_widget.dart';
import 'package:flow_draw/src/ui/shared/snap_guides.dart';
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

class FlowDrawEditorRenderObjectWidget extends MultiChildRenderObjectWidget {
  final CanvasState canvasState;
  final SelectionState selectionState;
  final FlowDrawEditorStyle style;
  final FragmentShader gridShader;
  final TempDrawingObject? tempDrawingObject;
  final Rect selectionArea;
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final Offset? snapHandlePosition;
  final List<SnapGuide> snapGuides;

  FlowDrawEditorRenderObjectWidget({
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
    this.snapGuides = const [],
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
  FlowDrawEditorRenderBox createRenderObject(BuildContext context) {
    return FlowDrawEditorRenderBox(
      style: style,
      gridShader: gridShader,
      canvasState: canvasState,
      selectionState: selectionState,
      selectionArea: selectionArea,
      nodesData: _getNodeDrawData(),
      tempDrawingObject: tempDrawingObject,
      snapHandlePosition: snapHandlePosition,
      snapGuides: snapGuides,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    FlowDrawEditorRenderBox renderObject,
  ) {
    renderObject
      ..style = style
      ..canvasState = canvasState
      ..selectionState = selectionState
      ..selectionArea = selectionArea
      ..tempDrawingObject = tempDrawingObject
      ..snapHandlePosition = snapHandlePosition
      ..snapGuides = snapGuides
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

class FlowDrawEditorRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ParentData> {
  FlowDrawEditorRenderBox({
    required FlowDrawEditorStyle style,
    required FragmentShader gridShader,
    required CanvasState canvasState,
    required SelectionState selectionState,
    required Rect selectionArea,
    required List<NodeDiffCheckData> nodesData,
    required this.tempDrawingObject,
    this.snapHandlePosition,
    List<SnapGuide> snapGuides = const [],
  }) : _style = style,
       _gridShader = gridShader,
       _canvasState = canvasState,
       _selectionState = selectionState,
       _selectionArea = selectionArea,
       _snapGuides = snapGuides {
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

  List<SnapGuide> _snapGuides;

  List<SnapGuide> get snapGuides => _snapGuides;

  set snapGuides(List<SnapGuide> value) {
    if (identical(_snapGuides, value)) return;
    _snapGuides = value;
    markNeedsPaint();
  }

  FlowDrawEditorStyle _style;

  FlowDrawEditorStyle get style => _style;

  set style(FlowDrawEditorStyle value) {
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
    final viewport = _prepareCanvas(context.canvas, size);
    _paintGrid(context.canvas, viewport);

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
    _paintSnapGuides(context.canvas, viewport);
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

  Rect _prepareCanvas(Canvas canvas, Size size) {
    canvas.transform(_getTransformMatrix().storage);
    final viewport = _calculateViewport();
    canvas.clipRect(viewport, clipOp: ui.ClipOp.intersect, doAntiAlias: false);
    return viewport;
  }

  final _pencilOptions = StrokeOptions(
    size: 8.0,
    thinning: 0.7,
    smoothing: 0.5,
    streamline: 0.5,
    simulatePressure: true,
  );

  get zoom => canvasState.viewportZoom;

  /// Inverse zoom factor clamped so strokes stay within a comfortable
  /// screen-pixel range instead of growing/shrinking without bound.
  /// At zoom 1.0 → 1.0, zoomed out → capped at 2.0, zoomed in → floored at 0.5.
  double get clampedInverseZoom => (1.0 / zoom).clamp(0.5, 2.0);

  get drawingObjects => canvasState.drawingObjects;

  void _paintGrid(Canvas canvas, Rect viewport) {
    final double z = canvasState.viewportZoom;
    final gridStyle = style.gridStyle;
    final bool showDots = canvasState.showGrid;

    // Clamp screen-space dot spacing to a narrow range (12–32 px).
    // When the base spacing * zoom falls outside this range, double or halve
    // the world-space spacing to keep dots comfortable on screen.
    const double minScreenSpacing = 12.0;
    const double maxScreenSpacing = 32.0;
    double spacingX = gridStyle.gridSpacingX;
    double spacingY = gridStyle.gridSpacingY;
    while (spacingX * z < minScreenSpacing) { spacingX *= 2; }
    while (spacingX * z > maxScreenSpacing) { spacingX /= 2; }
    while (spacingY * z < minScreenSpacing) { spacingY *= 2; }
    while (spacingY * z > maxScreenSpacing) { spacingY /= 2; }

    // Re-align start to the adjusted spacing
    final adjustedStartX = (viewport.left / spacingX).floor() * spacingX;
    final adjustedStartY = (viewport.top / spacingY).floor() * spacingY;

    gridShader.setFloat(0, spacingX);
    gridShader.setFloat(1, spacingY);
    gridShader.setFloat(2, adjustedStartX.toDouble());
    gridShader.setFloat(3, adjustedStartY.toDouble());
    gridShader.setFloat(4, showDots ? gridStyle.lineWidth : 0);
    final intersectionColor = gridStyle.intersectionColor;
    gridShader.setFloat(9, showDots ? gridStyle.intersectionRadius : 0);
    gridShader.setFloat(10, intersectionColor.red / 255.0);
    gridShader.setFloat(11, intersectionColor.green / 255.0);
    gridShader.setFloat(12, intersectionColor.blue / 255.0);
    gridShader.setFloat(13, intersectionColor.opacity);
    gridShader.setFloat(14, viewport.left);
    gridShader.setFloat(15, viewport.top);
    gridShader.setFloat(16, viewport.right);
    gridShader.setFloat(17, viewport.bottom);
    gridShader.setFloat(18, z);
    // Background color for paper texture
    final bgColor = style.decoration.color ?? const Color(0xFF1A1A1A);
    gridShader.setFloat(19, bgColor.red / 255.0);
    gridShader.setFloat(20, bgColor.green / 255.0);
    gridShader.setFloat(21, bgColor.blue / 255.0);
    gridShader.setFloat(22, bgColor.opacity);
    canvas.drawRect(viewport, Paint()..shader = gridShader);
  }

  void _paintSnapHandle(Canvas canvas) {
    if (snapHandlePosition == null) return;
    final paint = Paint()..color = Colors.cyan.withOpacity(0.8);
    canvas.drawCircle(snapHandlePosition!, 6.0 / zoom, paint);
  }

  void _paintSnapGuides(Canvas canvas, Rect viewport) {
    AlignmentGuide.paintGuides(canvas, _snapGuides, viewport);
  }

  double get dpr => WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

  void _paintDrawingObjects(Canvas canvas) {
    final iz = clampedInverseZoom;
    final Paint objectPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * iz;
    final Paint selectedBorderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * iz;
    final Paint selectedArrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * iz;

    final Paint fillPaint = Paint()
      ..color = const Color(0xFF1a1a1a)
      ..style = PaintingStyle.fill;

    final Paint handlePaint = Paint()..color = Colors.blue;
    final Paint handleHitAreaPaint = Paint()..color = Colors.transparent;
    final Paint selectedRectBorderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * iz;

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
            ..strokeWidth = obj.isSelected ? 2.0 * clampedInverseZoom : 1.5 * clampedInverseZoom;
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
          final circleFill = obj.fillColor != null ? (Paint()..color = obj.fillColor!..style = PaintingStyle.fill) : fillPaint;
          final circleStroke = obj.strokeColor != null ? (Paint()..color = obj.strokeColor!..style = PaintingStyle.stroke..strokeWidth = objectPaint.strokeWidth) : objectPaint;
          canvas.drawOval(obj.rect, circleFill);
          if (obj.lineStyle == LineStyle.solid) {
            canvas.drawOval(obj.rect, circleStroke);
          } else {
            final ovalPath = Path()..addOval(obj.rect);
            _paintStyledPath(canvas, ovalPath, circleStroke, obj.lineStyle, seed: obj.id.hashCode);
          }
          if (obj.text != null && obj.text!.isNotEmpty && !obj.isEditing) {
            _paintShapeText(canvas, obj.rect, obj.text!, obj.textStyle);
          }
        } else if (obj is RectangleObject) {
          final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
          final objCornerRadius = obj.borderRadius > 0 ? obj.borderRadius : 10.0 * dpr / zoom;
          final rrect =
          RRect.fromRectAndRadius(obj.rect, Radius.circular(objCornerRadius));
          final rectFill = obj.fillColor != null ? (Paint()..color = obj.fillColor!..style = PaintingStyle.fill) : fillPaint;
          final rectStroke = obj.strokeColor != null ? (Paint()..color = obj.strokeColor!..style = PaintingStyle.stroke..strokeWidth = objectPaint.strokeWidth) : objectPaint;
          canvas.drawRRect(rrect, rectFill);
          if (obj.lineStyle == LineStyle.solid) {
            canvas.drawRRect(rrect, rectStroke);
          } else {
            final rrectPath = Path()..addRRect(rrect);
            _paintStyledPath(canvas, rrectPath, rectStroke, obj.lineStyle, seed: obj.id.hashCode);
          }
          if (obj.text != null && obj.text!.isNotEmpty && !obj.isEditing) {
            _paintShapeText(canvas, obj.rect, obj.text!, obj.textStyle);
          }
        } else if (obj is DiamondObject) {
          final diamondPath = obj.path;
          final diaFill = obj.fillColor != null ? (Paint()..color = obj.fillColor!..style = PaintingStyle.fill) : fillPaint;
          final diaStroke = obj.strokeColor != null ? (Paint()..color = obj.strokeColor!..style = PaintingStyle.stroke..strokeWidth = objectPaint.strokeWidth) : objectPaint;
          canvas.drawPath(diamondPath, diaFill);
          if (obj.lineStyle == LineStyle.solid) {
            canvas.drawPath(diamondPath, diaStroke);
          } else {
            _paintStyledPath(canvas, diamondPath, diaStroke, obj.lineStyle, seed: obj.id.hashCode);
          }
          if (obj.text != null && obj.text!.isNotEmpty && !obj.isEditing) {
            _paintShapeText(canvas, obj.rect, obj.text!, obj.textStyle);
          }
        } else if (obj is ParallelogramObject) {
          final paraPath = obj.path;
          final paraFill = obj.fillColor != null ? (Paint()..color = obj.fillColor!..style = PaintingStyle.fill) : fillPaint;
          final paraStroke = obj.strokeColor != null ? (Paint()..color = obj.strokeColor!..style = PaintingStyle.stroke..strokeWidth = objectPaint.strokeWidth) : objectPaint;
          canvas.drawPath(paraPath, paraFill);
          if (obj.lineStyle == LineStyle.solid) {
            canvas.drawPath(paraPath, paraStroke);
          } else {
            _paintStyledPath(canvas, paraPath, paraStroke, obj.lineStyle, seed: obj.id.hashCode);
          }
          if (obj.text != null && obj.text!.isNotEmpty && !obj.isEditing) {
            _paintShapeText(canvas, obj.rect, obj.text!, obj.textStyle);
          }
        } else if (obj is ForkJoinObject) {
          // Fork/join renders as a thick bar
          final barFill = obj.fillColor != null ? (Paint()..color = obj.fillColor!..style = PaintingStyle.fill) : (Paint()..color = objectPaint.color..style = PaintingStyle.fill);
          final barRect = RRect.fromRectAndRadius(
            obj.rect,
            const Radius.circular(3),
          );
          canvas.drawRRect(barRect, barFill);
          if (obj.strokeColor != null) {
            final barStroke = Paint()..color = obj.strokeColor!..style = PaintingStyle.stroke..strokeWidth = objectPaint.strokeWidth;
            canvas.drawRRect(barRect, barStroke);
          }
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
          // Resize handles on 3 corners, rotation icon on topRight
          final resizeCorners = [
            selectionRect.topLeft,
            selectionRect.bottomRight,
            selectionRect.bottomLeft,
          ];
          for (final corner in resizeCorners) {
            canvas.drawCircle(corner, handleHitAreaRadius, handleHitAreaPaint);
            canvas.drawCircle(corner, visibleHandleRadius, handlePaint);
          }
          // Rotation handle at topRight, offset away from the object
          final rotOffset = 8.0 / zoom;
          final rotCorner = selectionRect.topRight + Offset(rotOffset, -rotOffset);
          canvas.drawCircle(rotCorner, handleHitAreaRadius, handleHitAreaPaint);
          _paintRotationIcon(canvas, rotCorner, handlePaint, visibleHandleRadius);

          if (selectionState.selectedDrawingObjectIds.length == 1 && (obj is RectangleObject || obj is CircleObject)) {
            _paintQuickActionArrows(canvas, obj.rect, obj.id);
          }
        }

        // Paint connection port indicators when the shape is selected or hovered
        final isHovered = selectionState.hoveredDrawingObjectId == obj.id;
        if ((isSelected || isHovered) &&
            (obj is RectangleObject || obj is CircleObject || obj is DiamondObject ||
             obj is ParallelogramObject || obj is ForkJoinObject)) {
          _paintConnectionPortIndicators(canvas, obj);
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
          // Snap to rotated edge if the attached object is meaningfully rotated
          final startObj = canvasState.drawingObjects[startAttachment.objectId];
          if (startObj != null && startObj.angle.abs() > 0.05) {
            start = _snapToRotatedEdge(
                _rotatePoint(start, startObjRect.center, startObj.angle),
                startObjRect, startObj.angle);
          }
        }
        if (endObjRect != null && endAttachment != null) {
          final relPos = endAttachment.relativePosition;
          end = endObjRect.topLeft +
              Offset(endObjRect.width * relPos.dx, endObjRect.height * relPos.dy);
          // Snap to rotated edge if the attached object is meaningfully rotated
          final endObj = canvasState.drawingObjects[endAttachment.objectId];
          if (endObj != null && endObj.angle.abs() > 0.05) {
            end = _snapToRotatedEdge(
                _rotatePoint(end, endObjRect.center, endObj.angle),
                endObjRect, endObj.angle);
          }
        }

        // Check if attached objects are meaningfully rotated (> ~1 degree)
        const rotationThreshold = 0.05; // ~2.9 degrees
        final startObjAngle = startAttachment != null
            ? (canvasState.drawingObjects[startAttachment.objectId]?.angle ?? 0.0)
            : 0.0;
        final endObjAngle = endAttachment != null
            ? (canvasState.drawingObjects[endAttachment.objectId]?.angle ?? 0.0)
            : 0.0;
        final startIsRotated = startObjAngle.abs() > rotationThreshold;
        final endIsRotated = endObjAngle.abs() > rotationThreshold;

        if (pathType == LinkPathType.orthogonal) {
          // Snap start/end to nearest object edge, but skip for rotated
          // objects — the rotated point is already on the correct visual edge.
          if (startObjRect != null && !startIsRotated) {
            start = _snapToNearestEdge(start, startObjRect);
          }
          if (endObjRect != null && !endIsRotated) {
            end = _snapToNearestEdge(end, endObjRect);
          }

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

          final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
          // For rotated objects, pass the rotated bounding box so the router
          // still provides proper padding and curved entry stubs.
          final routerStartRect = startIsRotated && startObjRect != null
              ? _rotatedBoundingBox(startObjRect, startObjAngle)
              : startObjRect;
          final routerEndRect = endIsRotated && endObjRect != null
              ? _rotatedBoundingBox(endObjRect, endObjAngle)
              : endObjRect;
          waypoints = OrthogonalRouter.route(
            start: start,
            end: end,
            obstacles: obstacles,
            startObjectRect: routerStartRect,
            endObjectRect: routerEndRect,
            devicePixelRatio: dpr,
            zoom: canvasState.viewportZoom,
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

        // Connection dot radius and arrowhead pullback
        final dotRadius = 2.0 * clampedInverseZoom;
        final pullback = dotRadius * 3;

        // Compute the shortened end point for the line so it stops at the
        // arrowhead tip rather than extending past it to the connection dot.
        Offset lineEnd = end;
        Offset? arrowControl;

        if (pathType == LinkPathType.orthogonal) {
          // Find a control point distinct from `end` for arrowhead direction
          if (waypoints != null && waypoints.isNotEmpty) {
            for (int i = waypoints.length - 1; i >= 0; i--) {
              if ((waypoints[i] - end).distanceSquared > 1e-6) {
                arrowControl = waypoints[i];
                break;
              }
            }
          }
          arrowControl ??= ((end - start).distanceSquared > 1e-6) ? start : null;
          if (arrowControl != null && obj.endAttachment != null) {
            final dir = (end - arrowControl);
            final len = dir.distance;
            if (len > pullback) {
              lineEnd = end - dir * (pullback / len);
            }
          }
        } else {
          if (obj.endAttachment != null) {
            final dir = (end - controlPoint);
            final len = dir.distance;
            if (len > pullback) {
              lineEnd = end - dir * (pullback / len);
            }
          }
        }

        // Draw the line/path with shortened end
        if (pathType == LinkPathType.orthogonal) {
          if (obj.lineStyle == LineStyle.solid) {
            _paintOrthogonalPath(canvas, start, lineEnd, paint, waypoints: waypoints);
          } else {
            final orthoPath = _buildOrthogonalPath(start, lineEnd, waypoints: waypoints);
            _paintStyledPath(canvas, orthoPath, paint, obj.lineStyle, seed: obj.id.hashCode);
          }
        } else {
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(
              controlPoint.dx,
              controlPoint.dy,
              lineEnd.dx,
              lineEnd.dy,
            );
          _paintStyledPath(canvas, path, paint, obj.lineStyle, seed: obj.id.hashCode);
        }

        // Draw the arrowhead at the shortened end
        if (pathType == LinkPathType.orthogonal) {
          if (arrowControl != null) {
            _paintArrowHead(canvas, arrowControl, lineEnd, paint, lineStyle: obj.lineStyle);
          }
        } else {
          _paintArrowHead(canvas, controlPoint, lineEnd, paint, lineStyle: obj.lineStyle);
        }

        // Draw connection point dots at attached endpoints
        {
          final dotPaint = Paint()
            ..color = paint.color
            ..style = PaintingStyle.fill;
          if (obj.startAttachment != null) {
            canvas.drawCircle(start, dotRadius, dotPaint);
          }
          if (obj.endAttachment != null) {
            canvas.drawCircle(end, dotRadius, dotPaint);
          }
        }

        // Draw arrow label at the midpoint of the arrow
        if (obj.arrowLabel != null && obj.arrowLabel!.isNotEmpty) {
          final labelText = obj.arrowLabel!;
          final labelFontSize = 12.0 / zoom;
          final labelParagraphBuilder = ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: labelFontSize,
              fontFamily: 'sans-serif',
            ),
          )
            ..pushStyle(ui.TextStyle(color: const Color(0xFFE0E0E0)))
            ..addText(labelText);
          final labelParagraph = labelParagraphBuilder.build();
          labelParagraph.layout(ui.ParagraphConstraints(width: 200.0 / zoom));

          // Compute midpoint: for orthogonal paths use the path midpoint,
          // otherwise use the quadratic bezier midpoint at t=0.5.
          Offset labelCenter;
          if (pathType == LinkPathType.orthogonal &&
              waypoints != null &&
              waypoints.isNotEmpty) {
            final fullPath = [start, ...waypoints, end];
            // Walk along segments to find the geometric midpoint
            double totalLen = 0;
            for (int i = 0; i < fullPath.length - 1; i++) {
              totalLen += (fullPath[i + 1] - fullPath[i]).distance;
            }
            double halfLen = totalLen / 2;
            labelCenter = fullPath.last;
            for (int i = 0; i < fullPath.length - 1; i++) {
              final segLen = (fullPath[i + 1] - fullPath[i]).distance;
              if (halfLen <= segLen) {
                final t = segLen > 0 ? halfLen / segLen : 0.0;
                labelCenter = Offset.lerp(fullPath[i], fullPath[i + 1], t)!;
                break;
              }
              halfLen -= segLen;
            }
          } else {
            final cp = controlPoint;
            labelCenter = Offset(
              0.25 * start.dx + 0.5 * cp.dx + 0.25 * end.dx,
              0.25 * start.dy + 0.5 * cp.dy + 0.25 * end.dy,
            );
          }

          final textWidth = labelParagraph.longestLine;
          final textHeight = labelParagraph.height;
          final padding = 4.0 / zoom;
          final bgRect = Rect.fromCenter(
            center: labelCenter,
            width: textWidth + padding * 2,
            height: textHeight + padding * 2,
          );
          final bgPaint = Paint()
            ..color = const Color(0xE0202020)
            ..style = PaintingStyle.fill;
          canvas.drawRRect(
            RRect.fromRectAndRadius(bgRect, Radius.circular(3.0 / zoom)),
            bgPaint,
          );
          canvas.drawParagraph(
            labelParagraph,
            Offset(
              labelCenter.dx - textWidth / 2,
              labelCenter.dy - textHeight / 2,
            ),
          );
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
            final startObj = canvasState.drawingObjects[startAttachment.objectId];
            if (startObj != null && startObj.angle.abs() > 0.05) {
              start = _snapToRotatedEdge(
                  _rotatePoint(start, targetRect.center, startObj.angle),
                  targetRect, startObj.angle);
            }
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
            final endObj = canvasState.drawingObjects[endAttachment.objectId];
            if (endObj != null && endObj.angle.abs() > 0.05) {
              end = _snapToRotatedEdge(
                  _rotatePoint(end, targetRect.center, endObj.angle),
                  targetRect, endObj.angle);
            }
          }
        }

        final controlPoint = obj.midPoint ?? (start + end) / 2;

        final path = Path();
        path.moveTo(start.dx, start.dy);
        final mid = obj.midPoint ?? (start + end) / 2;
        path.quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);

        _paintStyledPath(canvas, path, paint, obj.lineStyle, seed: obj.id.hashCode);

        // Draw connection point dots at attached endpoints
        {
          final dotRadius = 2.0 * clampedInverseZoom;
          final dotPaint = Paint()
            ..color = paint.color
            ..style = PaintingStyle.fill;
          if (obj.startAttachment != null) {
            canvas.drawCircle(start, dotRadius, dotPaint);
          }
          if (obj.endAttachment != null) {
            canvas.drawCircle(end, dotRadius, dotPaint);
          }
        }

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

  /// Paints small port indicator circles at each cardinal anchor point of a
  /// shape. These visually communicate where arrows can connect.
  void _paintConnectionPortIndicators(Canvas canvas, DrawingObject obj) {
    final ports = obj.getConnectionPorts();
    final double portRadius = 5.0 / zoom;
    final double borderWidth = 1.5 / zoom;

    final Paint portFillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final Paint portBorderPaint = Paint()
      ..color = const Color(0xFF2196F3) // Blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    for (final port in ports) {
      // Draw filled circle with blue border at each anchorPoint position
      canvas.drawCircle(port.portPosition, portRadius, portFillPaint);
      canvas.drawCircle(port.portPosition, portRadius, portBorderPaint);
    }
  }

  void _paintQuickActionArrows(Canvas canvas, Rect rect, String objectId) {
    final iz = clampedInverseZoom;
    final double handleSize = 20.0 * iz;
    final double halfHandle = handleSize / 2;
    final double spacing = 10.0 * iz;

    final Paint handlePaint = Paint()..color = Colors.blue.withOpacity(0.8);
    final Paint arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * clampedInverseZoom
      ..strokeCap = StrokeCap.round;

    // Find where connectors approach each edge from, using the other endpoint
    // For horizontal edges (top/bottom): track x of the other end relative to this object's center
    // For vertical edges (left/right): track y of the other end relative to this object's center
    final edgeApproachFromLeft = <String, List<bool>>{};
    for (final obj in canvasState.drawingObjects.values) {
      if (obj is ArrowObject || obj is LineObject) {
        final startAtt = obj is ArrowObject ? obj.startAttachment : (obj as LineObject).startAttachment;
        final endAtt = obj is ArrowObject ? obj.endAttachment : (obj as LineObject).endAttachment;
        final otherEnd = obj is ArrowObject ? obj.end : (obj as LineObject).end;
        final otherStart = obj is ArrowObject ? obj.start : (obj as LineObject).start;
        for (final (att, otherPoint) in [(startAtt, otherEnd), (endAtt, otherStart)]) {
          if (att != null && att.objectId == objectId) {
            final rp = att.relativePosition;
            if (rp.dy < 0.25) {
              // Top edge: does the connector go left or right?
              (edgeApproachFromLeft['top'] ??= []).add(otherPoint.dx < rect.center.dx);
            }
            if (rp.dy > 0.75) {
              (edgeApproachFromLeft['bottom'] ??= []).add(otherPoint.dx < rect.center.dx);
            }
            if (rp.dx < 0.25) {
              (edgeApproachFromLeft['left'] ??= []).add(otherPoint.dy < rect.center.dy);
            }
            if (rp.dx > 0.75) {
              (edgeApproachFromLeft['right'] ??= []).add(otherPoint.dy < rect.center.dy);
            }
          }
        }
      }
    }

    // Offset perpendicular to the edge to avoid overlapping connection lines
    final double connOffset = handleSize * 2.0;

    Offset _edgeOffset(String edge) {
      final approaches = edgeApproachFromLeft[edge];
      if (approaches == null) return Offset.zero;
      // If connector approaches from the left/top, move icon to the right/bottom
      final mostlyFromLeft = approaches.where((b) => b).length >= approaches.length / 2;
      switch (edge) {
        case 'top':
        case 'bottom':
          // Connector comes from left → move icon right, and vice versa
          return Offset(mostlyFromLeft ? connOffset : -connOffset, 0);
        case 'left':
        case 'right':
          // Connector comes from above → move icon down, and vice versa
          return Offset(0, mostlyFromLeft ? connOffset : -connOffset);
        default:
          return Offset.zero;
      }
    }

    final positions = {
      'top': rect.topCenter - Offset(0, spacing + halfHandle) + _edgeOffset('top'),
      'right': rect.centerRight + Offset(spacing + halfHandle, 0) + _edgeOffset('right'),
      'bottom': rect.bottomCenter + Offset(0, spacing + halfHandle) + _edgeOffset('bottom'),
      'left': rect.centerLeft - Offset(spacing + halfHandle, 0) + _edgeOffset('left'),
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

  /// Paints a quick-action style icon (blue oval + white arrow) for rotation.
  void _paintRotationIcon(Canvas canvas, Offset center, Paint paint, double radius) {
    final double handleSize = 20.0 * clampedInverseZoom;

    final handleRect = Rect.fromCenter(center: center, width: handleSize, height: handleSize);
    final handlePaint = Paint()..color = Colors.blue.withOpacity(0.8);
    canvas.drawOval(handleRect, handlePaint);

    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * clampedInverseZoom
      ..strokeCap = StrokeCap.round;

    // Same arrow as quick action icons, slightly smaller, shifted toward edge
    final arrowSize = handleSize * 0.19;
    final lineLen = handleSize * 0.43;
    final shift = handleSize * 0.12; // push arrow toward the edge
    final arrowPath = Path();
    arrowPath.moveTo(center.dx, center.dy - arrowSize - shift);
    arrowPath.lineTo(center.dx, center.dy + lineLen - shift);
    // Top arrowhead
    arrowPath.moveTo(center.dx - arrowSize, center.dy - shift);
    arrowPath.lineTo(center.dx, center.dy - arrowSize - shift);
    arrowPath.lineTo(center.dx + arrowSize, center.dy - shift);
    // Bottom arrowhead (mirrored)
    final bottomTip = center.dy + lineLen - shift;
    arrowPath.moveTo(center.dx - arrowSize, bottomTip - arrowSize);
    arrowPath.lineTo(center.dx, bottomTip);
    arrowPath.lineTo(center.dx + arrowSize, bottomTip - arrowSize);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-pi / 2 + pi / 6);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.restore();
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

  /// Paints centered text inside a shape's rect.
  void _paintShapeText(Canvas canvas, Rect shapeRect, String text, TextStyle? style) {
    const defaultStyle = TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Courier');
    final scaledStyle = style ?? defaultStyle;
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: scaledStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: shapeRect.width - 8);
    final textOffset = Offset(
      shapeRect.center.dx - textPainter.width / 2,
      shapeRect.center.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  /// Returns the axis-aligned bounding box that encloses [rect] after
  /// rotating it by [angle] around its center.
  static Rect _rotatedBoundingBox(Rect rect, double angle) {
    final center = rect.center;
    final corners = [
      _rotatePoint(rect.topLeft, center, angle),
      _rotatePoint(rect.topRight, center, angle),
      _rotatePoint(rect.bottomRight, center, angle),
      _rotatePoint(rect.bottomLeft, center, angle),
    ];
    double minX = corners[0].dx, minY = corners[0].dy;
    double maxX = corners[0].dx, maxY = corners[0].dy;
    for (int i = 1; i < 4; i++) {
      if (corners[i].dx < minX) minX = corners[i].dx;
      if (corners[i].dy < minY) minY = corners[i].dy;
      if (corners[i].dx > maxX) maxX = corners[i].dx;
      if (corners[i].dy > maxY) maxY = corners[i].dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Snaps [point] to the nearest edge of a rotated rectangle.
  /// Computes the 4 corners of [rect] rotated by [angle] around its center,
  /// then projects [point] onto the nearest edge.
  static Offset _snapToRotatedEdge(Offset point, Rect rect, double angle) {
    final center = rect.center;
    // Compute rotated corners
    final corners = [
      _rotatePoint(rect.topLeft, center, angle),
      _rotatePoint(rect.topRight, center, angle),
      _rotatePoint(rect.bottomRight, center, angle),
      _rotatePoint(rect.bottomLeft, center, angle),
    ];
    // Find the nearest point on any edge
    Offset nearest = point;
    double minDist = double.infinity;
    for (int i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final projected = _projectOntoSegment(point, a, b);
      final dist = (projected - point).distanceSquared;
      if (dist < minDist) {
        minDist = dist;
        nearest = projected;
      }
    }
    return nearest;
  }

  /// Projects [point] onto the line segment from [a] to [b].
  static Offset _projectOntoSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final ap = point - a;
    final lenSq = ab.distanceSquared;
    if (lenSq < 1e-12) return a;
    final t = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
    final tc = t.clamp(0.0, 1.0);
    return a + ab * tc;
  }

  /// Rotates [point] around [center] by [angle] radians.
  static Offset _rotatePoint(Offset point, Offset center, double angle) {
    final cosA = cos(angle);
    final sinA = sin(angle);
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return Offset(
      center.dx + dx * cosA - dy * sinA,
      center.dy + dx * sinA + dy * cosA,
    );
  }

  static Offset _snapToNearestEdge(Offset point, Rect rect) {
    final distToLeft = (point.dx - rect.left).abs();
    final distToRight = (point.dx - rect.right).abs();
    final distToTop = (point.dy - rect.top).abs();
    final distToBottom = (point.dy - rect.bottom).abs();
    final minDist = [distToLeft, distToRight, distToTop, distToBottom].reduce(min);
    if (minDist == distToLeft) return Offset(rect.left, point.dy);
    if (minDist == distToRight) return Offset(rect.right, point.dy);
    if (minDist == distToTop) return Offset(point.dx, rect.top);
    return Offset(point.dx, rect.bottom);
  }

  /// Shortens the endpoint by [amount] along the direction from [prev] to [end].
  static Offset _shortenEndpoint(Offset prev, Offset end, double amount) {
    final dir = end - prev;
    final dist = dir.distance;
    if (dist < amount * 2) return end; // Too short to shorten
    final unit = dir / dist;
    return end - unit * amount;
  }

  /// Draws a dashed line along [path] using [paint].
  void _paintDashedPath(Canvas canvas, Path path, Paint paint) {
    final double dashWidth = 8.0 / zoom;
    final double dashSpace = 5.0 / zoom;
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final end = min(distance + dashWidth, metric.length);
        final segment = metric.extractPath(distance, end);
        canvas.drawPath(segment, paint);
        distance = end + dashSpace;
      }
    }
  }

  /// Draws evenly spaced dots along [path] using [paint].
  void _paintDottedPath(Canvas canvas, Path path, Paint paint) {
    final double spacing = 6.0 / zoom;
    final double radius = 1.5 * clampedInverseZoom;
    final dotPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final tangent = metric.getTangentForOffset(distance);
        if (tangent != null) {
          canvas.drawCircle(tangent.position, radius, dotPaint);
        }
        distance += spacing;
      }
    }
  }

  /// Returns a new path with small random perpendicular offsets applied to
  /// sample points, producing a hand-drawn/sketchy appearance. Uses
  /// [Random(seed)] for deterministic wobble across repaints.
  Path _roughenPath(Path source, double amplitude, int seed) {
    final rng = Random(seed);
    final result = Path();
    for (final metric in source.computeMetrics()) {
      final step = max(4.0 / zoom, 3.0);
      final points = <Offset>[];
      double d = 0.0;
      while (d < metric.length) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) {
          // Perpendicular direction
          final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
          final offset = (rng.nextDouble() - 0.5) * 2.0 * amplitude;
          points.add(tangent.position + normal * offset);
        }
        d += step;
      }
      // Always include the very last point
      final lastTangent = metric.getTangentForOffset(metric.length);
      if (lastTangent != null) points.add(lastTangent.position);

      if (points.length < 2) continue;
      result.moveTo(points[0].dx, points[0].dy);
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final mx = (p0.dx + p1.dx) / 2;
        final my = (p0.dy + p1.dy) / 2;
        result.quadraticBezierTo(p0.dx, p0.dy, mx, my);
      }
      result.lineTo(points.last.dx, points.last.dy);
    }
    return result;
  }

  /// Draws a [path] on [canvas] according to the given [lineStyle].
  /// For solid, draws normally. For rough, roughens the path first then draws.
  /// For dashed/dotted, uses the corresponding utility.
  void _paintStyledPath(Canvas canvas, Path path, Paint paint, LineStyle lineStyle, {int seed = 0}) {
    switch (lineStyle) {
      case LineStyle.solid:
        canvas.drawPath(path, paint);
        break;
      case LineStyle.dashed:
        _paintDashedPath(canvas, path, paint);
        break;
      case LineStyle.dotted:
        _paintDottedPath(canvas, path, paint);
        break;
      case LineStyle.rough:
        final roughPath = _roughenPath(path, 0.15 / zoom, seed);
        canvas.drawPath(roughPath, paint);
        break;
    }
  }

  void _paintArrowHead(
    Canvas canvas,
    Offset controlPoint,
    Offset end,
    Paint paint, {
    LineStyle lineStyle = LineStyle.solid,
  }) {
    final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final double arrowSize = 7.0 * dpr * clampedInverseZoom;
    const double arrowAngle = 25 * (pi / 180);

    final lineVector = end - controlPoint;
    if (lineVector.distanceSquared == 0)
      return; // Avoid errors if start and end are the same
    final angle = lineVector.direction;

    final p2 = end - Offset.fromDirection(angle - arrowAngle, arrowSize);
    final p3 = end - Offset.fromDirection(angle + arrowAngle, arrowSize);

    final headPaint = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    if (lineStyle == LineStyle.rough) {
      // Quadratic bezier only bends toward the control point, doesn't pass
      // through it. Push the control point beyond `end` so the curve apex
      // lands at the actual tip.
      final mid = (p2 + p3) / 2;
      final cp = end * 2 - mid;
      path.moveTo(p2.dx, p2.dy);
      path.quadraticBezierTo(cp.dx, cp.dy, p3.dx, p3.dy);
    } else {
      path.moveTo(p2.dx, p2.dy);
      path.lineTo(end.dx, end.dy);
      path.lineTo(p3.dx, p3.dy);
    }

    canvas.drawPath(path, headPaint);
  }

  /// Builds the orthogonal path without drawing it.
  Path _buildOrthogonalPath(Offset start, Offset end, {List<Offset>? waypoints}) {
    final allPoints = [start, ...?waypoints, end];

    if (allPoints.length == 2) {
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
      return path;
    }

    final dprForRadius = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final double cornerRadius = 30.0 * dprForRadius / zoom;
    final Path path = Path();
    path.moveTo(allPoints[0].dx, allPoints[0].dy);

    for (int i = 1; i < allPoints.length - 1; i++) {
      final prev = allPoints[i - 1];
      final curr = allPoints[i];
      final next = allPoints[i + 1];
      final segPrev = (curr - prev).distance;
      final segNext = (next - curr).distance;
      final r = min(cornerRadius, min(segPrev / 2, segNext / 2));

      if (r < 1.0) {
        path.lineTo(curr.dx, curr.dy);
        continue;
      }

      final dirIn = Offset((curr.dx - prev.dx) / segPrev, (curr.dy - prev.dy) / segPrev);
      final dirOut = Offset((next.dx - curr.dx) / segNext, (next.dy - curr.dy) / segNext);
      final cross = dirIn.dx * dirOut.dy - dirIn.dy * dirOut.dx;
      if (cross.abs() < 0.01) {
        path.lineTo(curr.dx, curr.dy);
        continue;
      }

      final arcStart = Offset(curr.dx - dirIn.dx * r, curr.dy - dirIn.dy * r);
      final arcEnd = Offset(curr.dx + dirOut.dx * r, curr.dy + dirOut.dy * r);
      path.lineTo(arcStart.dx, arcStart.dy);
      path.arcToPoint(arcEnd, radius: Radius.circular(r), clockwise: cross > 0);
    }

    path.lineTo(allPoints.last.dx, allPoints.last.dy);
    return path;
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
    final dprForRadius = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final double cornerRadius = 30.0 * dprForRadius / zoom;
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
      ..strokeWidth = 1.5 * clampedInverseZoom;
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
      case EditorTool.diamond:
        final nr = rect.normalize;
        final c = nr.center;
        final hw = nr.width / 2;
        final hh = nr.height / 2;
        final diamondPath = Path()
          ..moveTo(c.dx, c.dy - hh)
          ..lineTo(c.dx + hw, c.dy)
          ..lineTo(c.dx, c.dy + hh)
          ..lineTo(c.dx - hw, c.dy)
          ..close();
        canvas.drawPath(diamondPath, tempPaint);
        break;
      case EditorTool.parallelogram:
        final nr = rect.normalize;
        const skew = 20.0;
        final paraPath = Path()
          ..moveTo(nr.left + skew, nr.top)
          ..lineTo(nr.right, nr.top)
          ..lineTo(nr.right - skew, nr.bottom)
          ..lineTo(nr.left, nr.bottom)
          ..close();
        canvas.drawPath(paraPath, tempPaint);
        break;
      case EditorTool.forkJoin:
        final nr = rect.normalize;
        final barRect = Rect.fromLTWH(nr.left, nr.top, nr.width, 10);
        canvas.drawRRect(
          RRect.fromRectAndRadius(barRect, const Radius.circular(3)),
          tempPaint,
        );
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
