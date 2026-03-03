import 'dart:async';
import 'package:fldraw/src/core/utils/platform_info/platform_info.dart'
    show PlatformInfoImpl;
import 'dart:math';

import 'package:fldraw/fldraw.dart';
import 'package:fldraw/src/core/node_editor/clipboard.dart';
import 'package:fldraw/src/core/utils/json_extensions.dart';
import 'package:fldraw/src/core/utils/orthogonal_router.dart';
import 'package:fldraw/src/core/utils/renderbox.dart';
import 'package:fldraw/src/models/drawing_entities.dart';
import 'package:fldraw/src/ui/canvas/fldraw_editor_render_object.dart';
import 'package:fldraw/src/ui/shared/improved_listener.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:uuid/uuid.dart';

import '../../constants.dart';

typedef SnapPoint = ({
  String objectId,
  Offset worldPosition,
  Offset relativePosition,
});

class FlOverlayData {
  final Widget child;
  final double? top;
  final double? left;
  final double? bottom;
  final double? right;

  FlOverlayData({
    required this.child,
    this.top,
    this.left,
    this.bottom,
    this.right,
  });
}

class FlDrawEditorDataLayer extends StatefulWidget {
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final String fragmentShader;

  const FlDrawEditorDataLayer({
    super.key,
    this.headerBuilder,
    this.nodeBuilder,
    required this.fragmentShader,
  });

  @override
  State<FlDrawEditorDataLayer> createState() => _FlDrawEditorDataLayerState();
}

class _FlDrawEditorDataLayerState extends State<FlDrawEditorDataLayer>
    with TickerProviderStateMixin {
  late CanvasBloc _canvasBloc;
  late SelectionBloc _selectionBloc;
  late ToolBloc _toolBloc;

  bool _isPanning = false;
  bool _isAreaSelecting = false;
  bool _isDraggingSelection = false;
  bool _isDrawing = false;

  bool _isRotating = false;
  Offset _rotationStartCenter = Offset.zero;
  double _rotationStartAngle = 0.0;
  double _originalObjectAngle = 0.0;

  ({String objectId, Handle handle}) _isResizing = (
    objectId: '',
    handle: Handle.none,
  );
  ({String objectId, Handle handle}) _hoveredHandle = (
    objectId: '',
    handle: Handle.none,
  );

  Offset _lastPositionDelta = Offset.zero;
  Offset _lastFocalPoint = Offset.zero;
  Offset _kineticEnergy = Offset.zero;
  Timer? _kineticTimer;
  Offset _selectionStart = Offset.zero;
  Rect _selectionArea = Rect.zero;
  Offset _drawingStart = Offset.zero;
  List<PointVector> _currentPencilPoints = [];
  TempDrawingObject? _tempDrawingObject;
  Rect? _originalResizeRect;
  SnapPoint? _hoveredSnapPoint;
  SnapPoint? _startSnapPoint;

  int _activePointers = 0;
  double _scaleStartZoom = 1.0;
  bool _isScaling = false;
  double _totalDragDelta = 0.0;

  Offset get offset => _canvasBloc.state.viewportOffset;

  double get zoom => _canvasBloc.state.viewportZoom;

  @override
  void initState() {
    super.initState();
    _canvasBloc = context.read<CanvasBloc>();
    _selectionBloc = context.read<SelectionBloc>();
    _toolBloc = context.read<ToolBloc>();
  }

  @override
  void dispose() {
    _kineticTimer?.cancel();
    super.dispose();
  }

  void _updateSnapHandle(Offset worldPos) {
    final tool = _toolBloc.state.activeTool;
    final canvasState = _canvasBloc.state;

    bool shouldCheckForSnapping =
        ((tool == EditorTool.arrowTopRight || tool == EditorTool.line) &&
            !_isDrawing) ||
        (_isDrawing &&
            (_tempDrawingObject?.tool == EditorTool.arrowTopRight ||
                _tempDrawingObject?.tool == EditorTool.line)) ||
        (_isResizing.handle == Handle.arrowStart ||
            _isResizing.handle == Handle.arrowEnd);
    if (!shouldCheckForSnapping) {
      if (_hoveredSnapPoint != null) {
        setState(() => _hoveredSnapPoint = null);
      }
      return;
    }

    SnapPoint? newSnapPoint;
    double minDistance = double.infinity;
    final tolerance = 10.0 / canvasState.viewportZoom;

    for (final obj in canvasState.drawingObjects.values) {
      if (obj.id == _isResizing.objectId) continue;
      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is FigureObject ||
          obj is SvgObject) {
        final distance = distanceToRectBorder(worldPos, obj.rect);
        if (distance < tolerance && distance < minDistance) {
          minDistance = distance;
          final closestPoint = getClosestPointOnRectBorder(worldPos, obj.rect);
          newSnapPoint = (
            objectId: obj.id,
            worldPosition: closestPoint,
            relativePosition: Offset(
              (closestPoint.dx - obj.rect.left) /
                  obj.rect.width.clamp(0.001, double.infinity),
              (closestPoint.dy - obj.rect.top) /
                  obj.rect.height.clamp(0.001, double.infinity),
            ),
          );
        }
      }
    }

    for (final node in canvasState.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds == null) continue;
      final distance = distanceToRectBorder(worldPos, nodeBounds);
      if (distance < tolerance && distance < minDistance) {
        minDistance = distance;
        final closestPoint = getClosestPointOnRectBorder(worldPos, nodeBounds);
        newSnapPoint = (
          objectId: node.id,
          worldPosition: closestPoint,
          relativePosition: Offset(
            (closestPoint.dx - nodeBounds.left) /
                nodeBounds.width.clamp(0.001, double.infinity),
            (closestPoint.dy - nodeBounds.top) /
                nodeBounds.height.clamp(0.001, double.infinity),
          ),
        );
      }
    }

    if (newSnapPoint != _hoveredSnapPoint) {
      _hoveredSnapPoint = newSnapPoint;
      if (shouldCheckForSnapping &&
          _startSnapPoint != null &&
          newSnapPoint != null) {
        return;
      } else if (shouldCheckForSnapping && _hoveredSnapPoint != null) {
        _startSnapPoint = _hoveredSnapPoint;
      }
      setState(() {});
    }
  }

  double distanceToRectBorder(Offset point, Rect rect) {
    double dx = max(rect.left - point.dx, max(0, point.dx - rect.right));
    double dy = max(rect.top - point.dy, max(0, point.dy - rect.bottom));
    return sqrt(dx * dx + dy * dy);
  }

  Offset getClosestPointOnRectBorder(Offset point, Rect rect) {
    return Offset(
      point.dx.clamp(rect.left, rect.right),
      point.dy.clamp(rect.top, rect.bottom),
    );
  }

  void _onPanStart() {
    setState(() => _isPanning = true);
    _startKineticTimer();
  }

  void _onPanUpdate(Offset delta) {
    setState(() => _lastPositionDelta = delta);
    _resetKineticTimer();
    final panDelta = delta / _canvasBloc.state.viewportZoom;
    _canvasBloc.add(CanvasPanned(panDelta));
  }

  void _onPanEnd() {
    setState(() {
      _isPanning = false;
      _kineticEnergy = _lastPositionDelta;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    // If there's more than one pointer, it's a genuine multi-touch gesture.
    if (details.pointerCount > 1) {
      _isScaling = true; // Set the flag to lock single-finger moves.

      // Immediately cancel any single-finger actions that might have started.
      setState(() {
        _isAreaSelecting = false;
        _isDrawing = false;
        _tempDrawingObject = null;
        _selectionArea = Rect.zero;
      });

      _scaleStartZoom = _canvasBloc.state.viewportZoom;
      _onPanStart();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;

    final state = _canvasBloc.state;

    final newZoom = (_scaleStartZoom * details.scale).clamp(0.1, 10.0);
    final panDelta = details.focalPointDelta;

    final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
    if (editorBounds == null) return;

    final focalPointOnScreen = details.focalPoint;
    final focalPointRelativeToCenter = focalPointOnScreen - editorBounds.center;

    final zoomPanCorrection =
        focalPointRelativeToCenter * (1 / newZoom - 1 / state.viewportZoom);

    final newOffset =
        state.viewportOffset + (panDelta / state.viewportZoom) + zoomPanCorrection;

    _canvasBloc.add(CanvasTransformed(zoom: newZoom, offset: newOffset));
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isScaling) {
      _isScaling = false;
      _onPanEnd();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (_isPanning) return;
    if (event is PointerScrollEvent) {
      final state = _canvasBloc.state;
      final zoomDelta = -event.scrollDelta.dy * 0.001;
      final newZoom = state.viewportZoom * (1 + zoomDelta);
      _canvasBloc.add(CanvasZoomed(newZoom.clamp(0.1, 10.0)));
    }
  }

  void _startKineticTimer() {
    _kineticTimer?.cancel();
    _kineticTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_isPanning && _kineticEnergy.distance > 0.1) {
        final panDelta = _kineticEnergy / _canvasBloc.state.viewportZoom;
        _canvasBloc.add(CanvasPanned(panDelta));
        setState(() => _kineticEnergy *= 0.9);
      } else {
        timer.cancel();
      }
    });
  }

  void _resetKineticTimer() {
    _kineticTimer?.cancel();
    _startKineticTimer();
  }

  bool _checkAndHandleQuickAction(Offset worldPos) {
    final selection = _selectionBloc.state;
    if (selection.selectedDrawingObjectIds.length != 1) {
      return false;
    }

    final objectId = selection.selectedDrawingObjectIds.first;
    final object = _canvasBloc.state.drawingObjects[objectId];
    if (object == null || !(object is RectangleObject || object is CircleObject)) {
      return false;
    }

    final double handleSize = 24.0 / zoom;
    final double halfHandle = handleSize / 2;
    final double spacing = 12.0 / zoom;

    final localPositions = {
      QuickActionDirection.top: object.rect.topCenter - Offset(0, spacing + halfHandle),
      QuickActionDirection.right: object.rect.centerRight + Offset(spacing + halfHandle, 0),
      QuickActionDirection.bottom: object.rect.bottomCenter + Offset(0, spacing + halfHandle),
      QuickActionDirection.left: object.rect.centerLeft - Offset(spacing + halfHandle, 0),
    };

    for (var entry in localPositions.entries) {
      final direction = entry.key;
      final localCenter = entry.value;

      final worldCenter = localCenter.rotate(object.rect.center, object.angle);

      if ((worldPos - worldCenter).distance < halfHandle) {
        _canvasBloc.add(ObjectDuplicatedWithConnection(objectId, direction));
        return true;
      }
    }

    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;

    if (_activePointers > 1) {
      setState(() {
        _isAreaSelecting = false;
        _isDrawing = false;
        _tempDrawingObject = null;
        _selectionArea = Rect.zero;
      });
      return;
    }

    _lastFocalPoint = event.position;
    final worldPos = screenToWorld(
      event.position,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    if (_checkAndHandleQuickAction(worldPos)) {
      return;
    }

    final tool = _toolBloc.state.activeTool;

    if (event.buttons == kMiddleMouseButton) {
      _onPanStart();
      return;
    }

    if (tool == EditorTool.arrow) {
      if (_hoveredHandle.handle == Handle.rotate) {
        _beginRotation(worldPos);
        return;
      }
      _handleArrowToolPointerDown(event, worldPos);
    } else {
      _handleDrawingToolPointerDown(event, worldPos);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isScaling) return;
    if (_isPanning) {
      _onPanUpdate(event.delta);
      return;
    }

    final worldPos = screenToWorld(
      event.position,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    _updateSnapHandle(worldPos);

    if (_isRotating) {
      _handleObjectRotation(worldPos);
    } else if (_isResizing.handle != Handle.none) {
      _handleObjectResizing(worldPos);
    } else if (_isDraggingSelection) {
      final dragDelta = event.delta / _canvasBloc.state.viewportZoom;
      _canvasBloc.add(
        ObjectsDragged(
          _selectionBloc.state.selectedNodeIds.union(
            _selectionBloc.state.selectedDrawingObjectIds,
          ),
          dragDelta,
        ),
      );
      _totalDragDelta += event.delta.distance;
    } else if (_isAreaSelecting) {
      setState(
            () => _selectionArea = Rect.fromPoints(_selectionStart, worldPos),
      );
    } else if (_isDrawing) {
      _handleObjectDrawing(worldPos, event.pressure);
    } else {
      _updateHoveredHandle(event.position);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);

    if (_isPanning) _onPanEnd();
    if (_isAreaSelecting) _finalizeAreaSelection();
    if (_isDrawing) _finalizeDrawing();

    if (_isResizing.handle != Handle.none) {
      _finalizeResizing();
      _canvasBloc.add(const ObjectsResizeEnded());
    }

    if (_isRotating) {
      _finalizeRotation();
    }

    if (_isDraggingSelection) {
      if (_totalDragDelta > 3.0) {
        _canvasBloc.add(const ObjectsDragEnded());
      }
    }
    _isRotating = false;
    _isDraggingSelection = false;
    _isResizing = (objectId: '', handle: Handle.none);
    _originalResizeRect = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    setState(() {
      _isAreaSelecting = false;
      _isDrawing = false;
      _tempDrawingObject = null;
      _selectionArea = Rect.zero;
      _isResizing = (objectId: '', handle: Handle.none);
      _isDraggingSelection = false;
      _isRotating = false;
    });
  }

  void _beginRotation(Offset worldPos) {
    final objectId = _hoveredHandle.objectId;
    final object = _canvasBloc.state.drawingObjects[objectId];
    if (object == null) return;

    setState(() {
      _isRotating = true;
      _rotationStartCenter = object.rect.center;
      _originalObjectAngle = object.angle;
      _rotationStartAngle =
          (worldPos - _rotationStartCenter).direction;
    });
  }

  void _handleObjectRotation(Offset worldPos) {
    final objectId = _hoveredHandle.objectId;
    final object = _canvasBloc.state.drawingObjects[objectId];
    if (object == null) return;

    final currentAngle = (worldPos - _rotationStartCenter).direction;
    final angleDelta = currentAngle - _rotationStartAngle;
    final newAngle = _originalObjectAngle + angleDelta;

    final updatedObject = (object as dynamic).copyWith(angle: newAngle);
    _canvasBloc.add(DrawingObjectUpdated(updatedObject));
  }

  void _finalizeRotation() {
    _canvasBloc.add(const ObjectsRotationEnded());
    _isRotating = false;
  }

  void _onDoubleClick() {
    final worldPos = screenToWorld(
      _lastFocalPoint,
      _canvasBloc.state.viewportOffset,
      _canvasBloc.state.viewportZoom,
    );
    if (worldPos == null) return;

    final hitObject = _findHitObject(worldPos);
    if (hitObject != null &&
        _canvasBloc.state.drawingObjects[hitObject] is TextObject) {
      _beginTextEditing(
        existingObject:
            _canvasBloc.state.drawingObjects[hitObject] as TextObject,
      );
    }
  }

  void _handleArrowToolPointerDown(PointerDownEvent event, Offset worldPos) {
    _updateHoveredHandle(event.position);
    if (_hoveredHandle.handle != Handle.none) {
      _isResizing = _hoveredHandle;
      _originalResizeRect =
          _canvasBloc.state.drawingObjects[_isResizing.objectId]?.rect;
      return;
    }

    final hitObjectId = _findHitObject(worldPos);
    if (hitObjectId != null) {
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final currentSelection = _selectionBloc.state;
      final isNode = _canvasBloc.state.nodes.containsKey(hitObjectId);

      final alreadySelected = isNode
          ? currentSelection.selectedNodeIds.contains(hitObjectId)
          : currentSelection.selectedDrawingObjectIds.contains(hitObjectId);

      if (!alreadySelected) {
        final nodeIds = isNode ? {hitObjectId} : <String>{};
        final drawingObjectIds = !isNode ? {hitObjectId} : <String>{};

        if (isShiftPressed) {
          _selectionBloc.add(
            SelectionObjectsAdded(
              nodeIds: nodeIds,
              drawingObjectIds: drawingObjectIds,
            ),
          );
        } else {
          _selectionBloc.add(
            SelectionReplaced(
              nodeIds: nodeIds,
              drawingObjectIds: drawingObjectIds,
            ),
          );
        }
      }
      _totalDragDelta = 0.0;
      _isDraggingSelection = true;
      return;
    }

    setState(() {
      _isAreaSelecting = true;
      _selectionStart = worldPos;
      _selectionArea = Rect.fromPoints(worldPos, worldPos);
    });
  }

  void _handleDrawingToolPointerDown(PointerDownEvent event, Offset worldPos) {
    final tool = _toolBloc.state.activeTool;
    _isDrawing = true;
    _drawingStart = _hoveredSnapPoint?.worldPosition ?? worldPos;
    _startSnapPoint = _hoveredSnapPoint;

    if (tool == EditorTool.text) {
      _beginTextEditing(at: _drawingStart);
      return;
    }

    setState(() {
      if (tool == EditorTool.pencil) {
        _currentPencilPoints = [
          PointVector(_drawingStart.dx, _drawingStart.dy, event.pressure),
        ];
        _tempDrawingObject = TempDrawingObject(
          tool: tool,
          start: _drawingStart,
          end: _drawingStart,
          points: _currentPencilPoints,
        );
      } else {
        _tempDrawingObject = TempDrawingObject(
          tool: tool,
          start: _drawingStart,
          end: _drawingStart,
        );
      }
    });
  }

  void _handleObjectResizing(Offset worldPos) {
    final objectId = _isResizing.objectId;
    final handle = _isResizing.handle;
    final object = _canvasBloc.state.drawingObjects[objectId];
    if (object == null || _originalResizeRect == null) return;

    if (object is ArrowObject) {
      final (start, end) = _getDynamicEndpoints(object);
      final pathType = object.pathType;

      if (pathType == LinkPathType.orthogonal) {
        Offset newStart = start;
        Offset newEnd = end;

        if (handle == Handle.arrowStart) {
          newStart = _hoveredSnapPoint?.worldPosition ?? worldPos;
        } else if (handle == Handle.arrowEnd) {
          newEnd = _hoveredSnapPoint?.worldPosition ?? worldPos;
        } else if (handle == Handle.midPoint) {
          final dx = end.dx - start.dx;
          final dy = end.dy - start.dy;
          if (dx.abs() > dy.abs()) {
            newStart = Offset(start.dx, worldPos.dy);
            newEnd = Offset(worldPos.dx, end.dy);
          } else {
            newStart = Offset(worldPos.dx, start.dy);
            newEnd = Offset(end.dx, worldPos.dy);
          }
        }

        // Recompute waypoints
        final obstacles = _collectObstacles(excludeId: objectId);
        final startObjRect = _getAttachedObjectRect(object.startAttachment);
        final endObjRect = _getAttachedObjectRect(object.endAttachment);
        final waypoints = OrthogonalRouter.route(
          start: newStart,
          end: newEnd,
          obstacles: obstacles,
          startObjectRect: startObjRect,
          endObjectRect: endObjRect,
        );

        final updatedObject = object.copyWith(
          start: newStart,
          end: newEnd,
          waypoints: waypoints,
        );
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));

      }  else {
        if (handle == Handle.arrowStart) {
          final updatedObject = object.copyWith(start: worldPos);
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        } else if (handle == Handle.arrowEnd) {
          final updatedObject = object.copyWith(end: worldPos);
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        } else if (handle == Handle.midPoint) {
          final midPoint = (worldPos * 2) - (start * 0.5) - (end * 0.5);
          final updatedObject = object.copyWith(midPoint: midPoint);
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        }
      }
      return;
    } else if (object is LineObject) {
      final (start, end) = _getDynamicEndpoints(object);

      if (_isResizing.handle == Handle.arrowStart) {
        final updatedObject = object.copyWith(start: worldPos);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      } else if (_isResizing.handle == Handle.arrowEnd) {
        final updatedObject = object.copyWith(end: worldPos);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      } else if (_isResizing.handle == Handle.midPoint) {
        final midPoint = (worldPos * 2) - (start * 0.5) - (end * 0.5);
        final updatedObject = object.copyWith(midPoint: midPoint);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      }
    } else if (object is RectangleObject ||
        object is CircleObject ||
        object is FigureObject ||
        object is SvgObject) {
      final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

      final Offset anchorWorld;
      switch (handle) {
        case Handle.topLeft:
          anchorWorld = _originalResizeRect!.bottomRight
              .rotate(_originalResizeRect!.center, object.angle);
          break;
        case Handle.topRight:
          anchorWorld = _originalResizeRect!.bottomLeft
              .rotate(_originalResizeRect!.center, object.angle);
          break;
        case Handle.bottomRight:
          anchorWorld = _originalResizeRect!.topLeft
              .rotate(_originalResizeRect!.center, object.angle);
          break;
        case Handle.bottomLeft:
          anchorWorld = _originalResizeRect!.topRight
              .rotate(_originalResizeRect!.center, object.angle);
          break;
        default:
          return;
      }

      var dragVector = worldPos - anchorWorld;
      var localDragVector = dragVector.rotate(Offset.zero, -object.angle);

      if (isShiftPressed &&
          _originalResizeRect!.width > 0 &&
          _originalResizeRect!.height > 0) {
        final aspectRatio =
            _originalResizeRect!.width / _originalResizeRect!.height;
        final newAspectRatio =
            localDragVector.dx.abs() / localDragVector.dy.abs();
        if (newAspectRatio > aspectRatio) {
          localDragVector = Offset(localDragVector.dx,
              localDragVector.dx.abs() / aspectRatio * localDragVector.dy.sign);
        } else {
          localDragVector = Offset(
              localDragVector.dy.abs() * aspectRatio * localDragVector.dx.sign,
              localDragVector.dy);
        }
        dragVector = localDragVector.rotate(Offset.zero, object.angle);
      }

      final newCenter = anchorWorld + dragVector / 2;
      final newRect = Rect.fromCenter(
        center: newCenter,
        width: localDragVector.dx.abs(),
        height: localDragVector.dy.abs(),
      );

      dynamic updatedObject;
      if (object is TextObject) {
        if (newRect.shortestSide < 10.0) return;
        updatedObject = object.copyWith(
          rect: newRect,
          style: object.style.copyWith(fontSize: newRect.height * 0.8),
        );
      } else {
        updatedObject = (object as dynamic).copyWith(rect: newRect);
      }
      _canvasBloc.add(DrawingObjectUpdated(updatedObject));
    } else if (object is PencilStrokeObject) {
      // Resizing for pencil strokes is not yet implemented
    }
  }

  List<Rect> _collectObstacles({String? excludeId}) {
    final canvasState = _canvasBloc.state;
    final obstacles = <Rect>[];

    for (final obj in canvasState.drawingObjects.values) {
      if (obj.id == excludeId) continue;
      // Skip arrows, lines, pencil strokes — only solid objects are obstacles
      if (obj is ArrowObject || obj is LineObject || obj is PencilStrokeObject) {
        continue;
      }
      obstacles.add(obj.rect);
    }

    for (final node in canvasState.nodes.values) {
      if (node.id == excludeId) continue;
      final bounds = getNodeBoundsInWorld(node);
      if (bounds != null) {
        obstacles.add(bounds);
      }
    }

    return obstacles;
  }

  Rect? _getAttachedObjectRect(ObjectAttachment? attachment) {
    if (attachment == null) return null;
    final canvasState = _canvasBloc.state;
    final targetNode = canvasState.nodes[attachment.objectId];
    final targetObject = canvasState.drawingObjects[attachment.objectId];
    if (targetNode != null) return getNodeBoundsInWorld(targetNode);
    return targetObject?.rect;
  }

  void _handleObjectDrawing(Offset worldPos, double pressure) {
    final tool = _toolBloc.state.activeTool;
    final endPos = _hoveredSnapPoint?.worldPosition ?? worldPos;
    if (tool == EditorTool.pencil) {
      setState(() {
        _currentPencilPoints.add(PointVector(endPos.dx, endPos.dy, pressure));
        if (_tempDrawingObject != null) {
          _tempDrawingObject = TempDrawingObject(
            tool: _tempDrawingObject!.tool,
            start: _tempDrawingObject!.start,
            end: endPos,
            points: _currentPencilPoints,
          );
        }
      });
    } else {
      final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
      Offset finalPos = endPos;
      LinkPathType pathType = tool == EditorTool.arrowTopRight
          ? LinkPathType.orthogonal
          : LinkPathType.straight;

      if (isShiftPressed) {
        if (tool == EditorTool.square ||
            tool == EditorTool.circle ||
            tool == EditorTool.figure) {
          final dx = worldPos.dx - _drawingStart.dx;
          final dy = worldPos.dy - _drawingStart.dy;
          final side = max(dx.abs(), dy.abs());
          finalPos = Offset(
            _drawingStart.dx + side * dx.sign,
            _drawingStart.dy + side * dy.sign,
          );
        } else if (tool == EditorTool.line) {
          finalPos = _snapPointToAngle(_drawingStart, worldPos);
        } else if (tool == EditorTool.arrowTopRight) {
          pathType = LinkPathType.orthogonal;
          finalPos = worldPos;
        }
      }
      if (_tempDrawingObject != null) {
        List<Offset>? waypoints;
        if (pathType == LinkPathType.orthogonal) {
          final obstacles = _collectObstacles();
          final startObjRect = _getAttachedObjectRect(
            _startSnapPoint != null
                ? ObjectAttachment(
                    objectId: _startSnapPoint!.objectId,
                    relativePosition: _startSnapPoint!.relativePosition,
                  )
                : null,
          );
          final endObjRect = _getAttachedObjectRect(
            _hoveredSnapPoint != null
                ? ObjectAttachment(
                    objectId: _hoveredSnapPoint!.objectId,
                    relativePosition: _hoveredSnapPoint!.relativePosition,
                  )
                : null,
          );
          waypoints = OrthogonalRouter.route(
            start: _tempDrawingObject!.start,
            end: finalPos,
            obstacles: obstacles,
            startObjectRect: startObjRect,
            endObjectRect: endObjRect,
          );
        }
        _tempDrawingObject = TempDrawingObject(
          tool: _tempDrawingObject!.tool,
          start: _tempDrawingObject!.start,
          end: finalPos,
          pathType: pathType,
          points: _tempDrawingObject!.points,
          waypoints: waypoints,
        );
      }
      setState(() {});
    }
  }

  void _finalizeAreaSelection() {
    final selectedArea = _selectionArea.normalize;
    if (selectedArea.size.longestSide > 10.0 / _canvasBloc.state.viewportZoom) {
      final holdSelection =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isShiftPressed;
      final (nodes, objects) = _findObjectsInArea(selectedArea);

      if (holdSelection) {
        _selectionBloc.add(
          SelectionObjectsAdded(nodeIds: nodes, drawingObjectIds: objects),
        );
      } else {
        _selectionBloc.add(
          SelectionReplaced(nodeIds: nodes, drawingObjectIds: objects),
        );
      }
    } else if (!HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _selectionBloc.add(SelectionCleared());
    }
    setState(() {
      _isAreaSelecting = false;
      _selectionArea = Rect.zero;
    });
  }

  void _finalizeDrawing() {
    if (_tempDrawingObject == null) return;

    final tool = _tempDrawingObject!.tool;
    DrawingObject? newObject;
    final id = const Uuid().v4();

    final endPos = _hoveredSnapPoint?.worldPosition ?? _tempDrawingObject!.end;

    ObjectAttachment? startAttachment = _startSnapPoint != null
        ? ObjectAttachment(
            objectId: _startSnapPoint!.objectId,
            relativePosition: _startSnapPoint!.relativePosition,
          )
        : null;

    ObjectAttachment? endAttachment = _hoveredSnapPoint != null
        ? ObjectAttachment(
            objectId: _hoveredSnapPoint!.objectId,
            relativePosition: _hoveredSnapPoint!.relativePosition,
          )
        : null;

    if (tool == EditorTool.arrowTopRight) {
      newObject = ArrowObject(
        id: id,
        start: _drawingStart,
        end: endPos,
        pathType: _tempDrawingObject!.pathType,
        startAttachment: startAttachment,
        endAttachment: endAttachment,
        waypoints: _tempDrawingObject!.waypoints,
      );
    } else if (tool == EditorTool.pencil) {
      if (_currentPencilPoints.length > 1) {
        newObject = PencilStrokeObject(id: id, points: _currentPencilPoints);
      }
    } else {
      final rect = Rect.fromPoints(
        _drawingStart,
        _tempDrawingObject!.end,
      ).normalize;
      if (rect.width > 2 || rect.height > 2) {
        switch (tool) {
          case EditorTool.circle:
            newObject = CircleObject(id: id, rect: rect);
            break;
          case EditorTool.square:
            newObject = RectangleObject(id: id, rect: rect);
            break;
          case EditorTool.arrowTopRight:
            newObject = ArrowObject(
              id: id,
              start: _drawingStart,
              end: _tempDrawingObject!.end,
              pathType: _tempDrawingObject!.pathType,
            );
            break;
          case EditorTool.line:
            newObject = LineObject(
              id: id,
              start: _drawingStart,
              end: endPos,
              startAttachment: startAttachment,
              endAttachment: endAttachment,
            );
            break;
          case EditorTool.figure:
            newObject = FigureObject(id: id, rect: rect);
            break;
          case EditorTool.text:
            newObject = TextObject(id: id, rect: rect);
            break;
          default:
            break;
        }
      }
    }

    if (newObject != null) {
      _canvasBloc.add(DrawingObjectAdded(newObject));
    } else {
      _selectionBloc.add(SelectionCleared());
    }

    setState(() {
      _isDrawing = false;
      _tempDrawingObject = null;
      _currentPencilPoints = [];
      _startSnapPoint = null;
      _hoveredSnapPoint = null;
    });
  }

  void _finalizeResizing() {
    final objectId = _isResizing.objectId;
    final object = _canvasBloc.state.drawingObjects[objectId];
    if (object == null) return;

    dynamic finalObject = object;

    if (_hoveredSnapPoint != null && (object is ArrowObject)) {
      final endAttachment = ObjectAttachment(
        objectId: _hoveredSnapPoint!.objectId,
        relativePosition: _hoveredSnapPoint!.relativePosition,
      );
      if (_isResizing.handle == Handle.arrowEnd) {
        finalObject = (object).copyWith(endAttachment: endAttachment);
      } else if (_isResizing.handle == Handle.arrowStart) {
        finalObject = (object).copyWith(startAttachment: endAttachment);
      }
    }

    if (_hoveredSnapPoint != null && (object is LineObject)) {
      final endAttachment = ObjectAttachment(
        objectId: _hoveredSnapPoint!.objectId,
        relativePosition: _hoveredSnapPoint!.relativePosition,
      );
      if (_isResizing.handle == Handle.arrowEnd) {
        finalObject = (object).copyWith(endAttachment: endAttachment);
      } else if (_isResizing.handle == Handle.arrowStart) {
        finalObject = (object).copyWith(startAttachment: endAttachment);
      }
    }

    if (finalObject.rect.width < 0 || finalObject.rect.height < 0) {
      finalObject = (finalObject as dynamic).copyWith(
        rect: finalObject.rect.normalize,
      );
    }

    _canvasBloc.add(DrawingObjectUpdated(finalObject));
  }

  (Offset, Offset) _getDynamicEndpoints(DrawingObject obj) {
    if (obj is! ArrowObject && obj is! LineObject) {
      return (Offset.zero, Offset.zero);
    }
    dynamic objectWithEndpoints = obj;
    var start = objectWithEndpoints.start as Offset;
    var end = objectWithEndpoints.end as Offset;
    final startAttachment =
    objectWithEndpoints.startAttachment as ObjectAttachment?;
    final endAttachment = objectWithEndpoints.endAttachment as ObjectAttachment?;
    final canvasState = _canvasBloc.state;

    if (startAttachment != null) {
      final targetNode = canvasState.nodes[startAttachment.objectId];
      final targetObject = canvasState.drawingObjects[startAttachment.objectId];
      final Rect? targetRect =
      targetNode != null ? getNodeBoundsInWorld(targetNode) : targetObject?.rect;

      if (targetRect != null) {
        final relPos = startAttachment.relativePosition;
        start = targetRect.topLeft +
            Offset(
              targetRect.width * relPos.dx,
              targetRect.height * relPos.dy,
            );
      }
    }

    if (endAttachment != null) {
      final targetNode = canvasState.nodes[endAttachment.objectId];
      final targetObject = canvasState.drawingObjects[endAttachment.objectId];
      final Rect? targetRect =
      targetNode != null ? getNodeBoundsInWorld(targetNode) : targetObject?.rect;

      if (targetRect != null) {
        final relPos = endAttachment.relativePosition;
        end = targetRect.topLeft +
            Offset(
              targetRect.width * relPos.dx,
              targetRect.height * relPos.dy,
            );
      }
    }
    return (start, end);
  }

  String? _findHitObject(Offset worldPos) {
    final canvasState = _canvasBloc.state;
    final tolerance = 8.0 / canvasState.viewportZoom;

    for (final obj in canvasState.drawingObjects.values.toList().reversed) {
      if (obj is ArrowObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final controlPoint = obj.midPoint ?? (start + end) / 2;

        Path path;
        if (obj.pathType == LinkPathType.orthogonal) {
          final allPoints = [start, ...?obj.waypoints, end];
          path = Path();
          path.moveTo(allPoints[0].dx, allPoints[0].dy);
          for (int i = 1; i < allPoints.length; i++) {
            path.lineTo(allPoints[i].dx, allPoints[i].dy);
          }
        } else {
          path = Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(
              controlPoint.dx,
              controlPoint.dy,
              end.dx,
              end.dy,
            );
        }

        if (isPointNearPath(path, worldPos, tolerance)) {
          return obj.id;
        }
      } else if (obj is LineObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final controlPoint = obj.midPoint ?? (start + end) / 2;

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, end.dx, end.dy);

        if (isPointNearPath(path, worldPos, tolerance)) {
          return obj.id;
        }
      } else if (obj.rect.contains(worldPos)) {
        return obj.id;
      }
    }

    for (final node in canvasState.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds != null && nodeBounds.contains(worldPos)) {
        return node.id;
      }
    }

    return null;
  }

  bool isPointNearPath(Path path, Offset point, double tolerance) {
    final pathBounds = path.getBounds();
    if (!pathBounds.inflate(tolerance).contains(point)) {
      return false;
    }

    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 2.0) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null &&
            (tangent.position - point).distance < tolerance) {
          return true;
        }
      }
    }
    return false;
  }

  (Set<String>, Set<String>) _findObjectsInArea(Rect area) {
    final Set<String> nodeIds = {};
    final Set<String> drawingObjectIds = {};

    for (final node in _canvasBloc.state.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds != null && area.overlaps(nodeBounds)) {
        nodeIds.add(node.id);
      }
    }

    for (final obj in _canvasBloc.state.drawingObjects.values) {
      if (area.overlaps(obj.rect)) {
        drawingObjectIds.add(obj.id);
      }
    }
    return (nodeIds, drawingObjectIds);
  }

  void _updateHoveredHandle(Offset screenPosition) {
    final selectionState = _selectionBloc.state;
    if (selectionState.selectedDrawingObjectIds.isEmpty) {
      if (_hoveredHandle.handle != Handle.none) {
        setState(() => _hoveredHandle = (objectId: '', handle: Handle.none));
      }
      return;
    }

    final canvasState = _canvasBloc.state;
    final worldPos = screenToWorld(
      screenPosition,
      canvasState.viewportOffset,
      canvasState.viewportZoom,
    );
    if (worldPos == null) return;

    final handleHitAreaRadius = 10.0 / canvasState.viewportZoom;
    final rotationHitAreaRadius = 22.0 / canvasState.viewportZoom;

    for (final objectId in selectionState.selectedDrawingObjectIds) {
      final obj = canvasState.drawingObjects[objectId];
      if (obj == null) continue;

      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is FigureObject ||
          obj is TextObject ||
          obj is SvgObject ||
          obj is PencilStrokeObject) {
        final center = obj.rect.center;
        final translatedPos = worldPos - center;
        final rotatedPos = Offset(
          translatedPos.dx * cos(-obj.angle) -
              translatedPos.dy * sin(-obj.angle),
          translatedPos.dx * sin(-obj.angle) +
              translatedPos.dy * cos(-obj.angle),
        );
        final localPos = rotatedPos + center;

        final selectionRect = obj.rect.inflate(4.0 / canvasState.viewportZoom);
        final handles = {
          Handle.topLeft: selectionRect.topLeft,
          Handle.topRight: selectionRect.topRight,
          Handle.bottomRight: selectionRect.bottomRight,
          Handle.bottomLeft: selectionRect.bottomLeft,
        };
        for (final entry in handles.entries) {
          final distance = (localPos - entry.value).distance;

          if (distance < rotationHitAreaRadius) {
            if (distance < handleHitAreaRadius) {
              if (_hoveredHandle.objectId != objectId ||
                  _hoveredHandle.handle != entry.key) {
                setState(() =>
                _hoveredHandle = (objectId: objectId, handle: entry.key));
              }
            } else {
              if (_hoveredHandle.objectId != objectId ||
                  _hoveredHandle.handle != Handle.rotate) {
                setState(() => _hoveredHandle =
                (objectId: objectId, handle: Handle.rotate));
              }
            }
            return;
          }
        }
      } else if (obj is ArrowObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final midPoint = obj.midPoint ?? (start + end) / 2.0;

        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final Offset cornerPoint;
        if (dx.abs() > dy.abs()) {
          cornerPoint = Offset(end.dx, start.dy);
        } else {
          cornerPoint = Offset(start.dx, end.dy);
        }

        final onCurveMidPoint =
            (start * 0.25) + (midPoint * 0.5) + (end * 0.25);

        // For orthogonal arrows with waypoints, hide midpoint handle
        final Map<Handle, Offset> handles;
        if (obj.pathType == LinkPathType.orthogonal && obj.waypoints != null && obj.waypoints!.isNotEmpty) {
          handles = {
            Handle.arrowStart: start,
            Handle.arrowEnd: end,
          };
        } else {
          handles = {
            Handle.arrowStart: start,
            Handle.arrowEnd: end,
            Handle.midPoint: obj.pathType == LinkPathType.orthogonal
                ? cornerPoint
                : onCurveMidPoint,
          };
        }
        for (final entry in handles.entries) {
          if ((worldPos - entry.value).distance < handleHitAreaRadius) {
            if (_hoveredHandle.objectId != objectId ||
                _hoveredHandle.handle != entry.key) {
              setState(
                    () => _hoveredHandle = (objectId: objectId, handle: entry.key),
              );
            }
            return;
          }
        }
      } else if (obj is LineObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final midPoint = obj.midPoint ?? (start + end) / 2.0;
        final onCurveMidPoint =
            (start * 0.25) + (midPoint * 0.5) + (end * 0.25);
        final handles = {
          Handle.arrowStart: start,
          Handle.arrowEnd: end,
          Handle.midPoint: onCurveMidPoint,
        };
        for (final entry in handles.entries) {
          if ((worldPos - entry.value).distance < handleHitAreaRadius) {
            if (_hoveredHandle.objectId != objectId ||
                _hoveredHandle.handle != entry.key) {
              setState(
                    () => _hoveredHandle = (objectId: objectId, handle: entry.key),
              );
            }
            return;
          }
        }
      }
    }

    if (_hoveredHandle.handle != Handle.none) {
      setState(() => _hoveredHandle = (objectId: '', handle: Handle.none));
    }
  }

  Rect _resizeWithAspectRatio({
    required Offset worldPos,
    required double originalAspectRatio,
    required Offset anchor,
  }) {
    final dx = worldPos.dx - anchor.dx;
    final dy = worldPos.dy - anchor.dy;
    double newWidth, newHeight;
    if ((dx.abs() * (1 / originalAspectRatio)) > dy.abs()) {
      newWidth = dx.abs();
      newHeight = newWidth / originalAspectRatio;
    } else {
      newHeight = dy.abs();
      newWidth = newHeight * originalAspectRatio;
    }
    return Rect.fromLTWH(
      (dx < 0) ? anchor.dx - newWidth : anchor.dx,
      (dy < 0) ? anchor.dy - newHeight : anchor.dy,
      newWidth,
      newHeight,
    );
  }

  Offset _snapPointToAngle(Offset startPoint, Offset currentPoint) {
    final dx = currentPoint.dx - startPoint.dx;
    final dy = currentPoint.dy - startPoint.dy;
    final angle = atan2(dy, dx);
    final distance = sqrt(dx * dx + dy * dy);
    const snapAngleIncrement = pi / 4;
    final snappedAngle =
        (angle / snapAngleIncrement).round() * snapAngleIncrement;
    final newDx = cos(snappedAngle) * distance;
    final newDy = sin(snappedAngle) * distance;
    return Offset(startPoint.dx + newDx, startPoint.dy + newDy);
  }

  void _beginTextEditing({TextObject? existingObject, Offset? at}) {
    if (existingObject == null && at == null) return;

    final TextObject object;
    if (existingObject != null) {
      object = existingObject;
      _selectionBloc.add(SelectionReplaced(drawingObjectIds: {object.id}));
    } else {
      const initialText = 'Text';
      const initialStyle = TextStyle(fontSize: 16, color: Colors.white);

      final textPainter = TextPainter(
        text: const TextSpan(text: initialText, style: initialStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final initialSize = textPainter.size;

      object = TextObject(
        id: const Uuid().v4(),
        rect: Rect.fromLTWH(
            at!.dx, at.dy, initialSize.width + 4, initialSize.height + 4),
        text: initialText,
        style: initialStyle,
      );
      _canvasBloc.add(DrawingObjectAdded(object));
      _selectionBloc.add(SelectionReplaced(drawingObjectIds: {object.id}));
    }

    setState(() {
      object.isEditing = true;
    });

    final textEditingController = TextEditingController(text: object.text);
    final focusNode = FocusNode();
    OverlayEntry? overlayEntry;

    void _submitAndClose() {
      if (!mounted) return;
      final newText = textEditingController.text;

      setState(() {
        object.isEditing = false;
      });

      if (newText.trim().isEmpty) {
        _canvasBloc.add(
          ObjectsRemoved(nodeIds: {}, drawingObjectIds: {object.id}),
        );
      } else {
        final textPainter = TextPainter(
          text: TextSpan(text: newText, style: object.style),
          textDirection: TextDirection.ltr,
        )..layout();

        setState(() {
          object.text = newText;
          object.rect = Rect.fromLTWH(
            object.rect.left,
            object.rect.top,
            textPainter.width,
            textPainter.height,
          );
        });
      }

      // focusNode.dispose();
      textEditingController.dispose();
      overlayEntry?.remove();
    }

    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        _submitAndClose();
      }
    });

    overlayEntry = OverlayEntry(
      builder: (context) {
        final editorBox =
            kNodeEditorWidgetKey.currentContext!.findRenderObject()
                as RenderBox;
        final editorSize = editorBox.size;
        final editorGlobalOffset = editorBox.localToGlobal(Offset.zero);

        Offset worldToGlobal(Offset worldPoint) {
          final screenPointX =
              (worldPoint.dx + offset.dx) * zoom + editorSize.width / 2;
          final screenPointY =
              (worldPoint.dy + offset.dy) * zoom + editorSize.height / 2;
          return Offset(screenPointX, screenPointY) + editorGlobalOffset;
        }

        final globalPosition = worldToGlobal(object.rect.topLeft);

        final screenSize = Size(
          object.rect.width * zoom,
          object.rect.height * zoom,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  focusNode.unfocus();
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: Material(
                color: Colors.transparent,
                child: IntrinsicWidth(
                  child: TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    style: object.style.copyWith(
                      fontSize: object.style.fontSize! * zoom,
                    ),
                    maxLines: 1,
                    autofocus: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submitAndClose(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(overlayEntry);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, canvasState) {
        return BlocBuilder<SelectionBloc, SelectionState>(
          builder: (context, selectionState) {
            return BlocBuilder<ToolBloc, ToolState>(
              builder: (context, toolState) {
                final Widget canvasChild = RepaintBoundary(
                  child: ShaderBuilder(
                    assetKey: widget.fragmentShader,
                        (context, gridShader, child) =>
                        FlDrawEditorRenderObjectWidget(
                          key: kNodeEditorWidgetKey,
                          canvasState: canvasState,
                          selectionState: selectionState,
                          style: const FlDrawEditorStyle(),
                          gridShader: gridShader,
                          tempDrawingObject: _tempDrawingObject,
                          selectionArea: _selectionArea,
                          headerBuilder: widget.headerBuilder,
                          nodeBuilder: widget.nodeBuilder,
                          snapHandlePosition: _hoveredSnapPoint?.worldPosition,
                        ),
                  ),
                );

                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.delete): () =>
                      _canvasBloc.add(ObjectsRemoved(
                        nodeIds: selectionState.selectedNodeIds,
                        drawingObjectIds: selectionState.selectedDrawingObjectIds,
                      )),
                    const SingleActivator(LogicalKeyboardKey.backspace): () =>
                      _canvasBloc.add(ObjectsRemoved(
                        nodeIds: selectionState.selectedNodeIds,
                        drawingObjectIds: selectionState.selectedDrawingObjectIds,
                      )),
                    const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () async {
                      await ClipboardService.copySelection(
                        allNodes: canvasState.nodes,
                        selectedNodeIds: selectionState.selectedNodeIds,
                      );
                    },
                    const SingleActivator(LogicalKeyboardKey.keyC, control: true): () async {
                      await ClipboardService.copySelection(
                        allNodes: canvasState.nodes,
                        selectedNodeIds: selectionState.selectedNodeIds,
                      );
                    },
                    const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
                      final worldPos = screenToWorld(
                        _lastFocalPoint,
                        canvasState.viewportOffset,
                        canvasState.viewportZoom,
                      ) ?? Offset.zero;
                      _canvasBloc.add(SelectionPasted(pastePosition: worldPos));
                    },
                    const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
                      final worldPos = screenToWorld(
                        _lastFocalPoint,
                        canvasState.viewportOffset,
                        canvasState.viewportZoom,
                      ) ?? Offset.zero;
                      _canvasBloc.add(SelectionPasted(pastePosition: worldPos));
                    },
                    const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () async {
                      final copied = await ClipboardService.copySelection(
                        allNodes: canvasState.nodes,
                        selectedNodeIds: selectionState.selectedNodeIds,
                      );
                      if (copied != null) {
                        _canvasBloc.add(ObjectsRemoved(
                          nodeIds: selectionState.selectedNodeIds,
                          drawingObjectIds: selectionState.selectedDrawingObjectIds,
                        ));
                      }
                    },
                    const SingleActivator(LogicalKeyboardKey.keyX, control: true): () async {
                      final copied = await ClipboardService.copySelection(
                        allNodes: canvasState.nodes,
                        selectedNodeIds: selectionState.selectedNodeIds,
                      );
                      if (copied != null) {
                        _canvasBloc.add(ObjectsRemoved(
                          nodeIds: selectionState.selectedNodeIds,
                          drawingObjectIds: selectionState.selectedDrawingObjectIds,
                        ));
                      }
                    },
                    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
                      _canvasBloc.add(UndoRequested()),
                    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
                      _canvasBloc.add(UndoRequested()),
                    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): () =>
                      _canvasBloc.add(RedoRequested()),
                    const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
                      _canvasBloc.add(RedoRequested()),
                    const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
                      final canvasState = _canvasBloc.state;
                      _selectionBloc.add(SelectionReplaced(
                        nodeIds: canvasState.nodes.keys.toSet(),
                        drawingObjectIds: canvasState.drawingObjects.keys.toSet(),
                      ));
                    },
                    const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
                      final canvasState = _canvasBloc.state;
                      _selectionBloc.add(SelectionReplaced(
                        nodeIds: canvasState.nodes.keys.toSet(),
                        drawingObjectIds: canvasState.drawingObjects.keys.toSet(),
                      ));
                    },
                  },
                  child: Focus(
                    autofocus: true,
                    child: _buildToolShortcutHandler(
                      child: MouseRegion(
                    cursor: _getCursor(toolState.activeTool),
                    onHover: (event) {
                      if (!_isDrawing &&
                          _isResizing.handle == Handle.none &&
                          !_isDraggingSelection &&
                          !_isPanning) {
                        _updateHoveredHandle(event.position);
                      }
                    },
                    onExit: (event) {
                      if (_hoveredHandle.handle != Handle.none) {
                        setState(
                              () => _hoveredHandle = (
                          objectId: '',
                          handle: Handle.none,
                          ),
                        );
                      }
                    },
                    child: GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerCancel,
                        onPointerSignal: _onPointerSignal,
                        child: canvasChild,
                      ),
                    ),
                  ),
                )),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildToolShortcutHandler({required Widget child}) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // Don't handle tool shortcuts when a modifier key is pressed
        if (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        final toolMap = {
          LogicalKeyboardKey.keyV: EditorTool.arrow,
          LogicalKeyboardKey.keyR: EditorTool.square,
          LogicalKeyboardKey.keyO: EditorTool.circle,
          LogicalKeyboardKey.keyA: EditorTool.arrowTopRight,
          LogicalKeyboardKey.keyL: EditorTool.line,
          LogicalKeyboardKey.keyD: EditorTool.pencil,
          LogicalKeyboardKey.keyT: EditorTool.text,
          LogicalKeyboardKey.keyF: EditorTool.figure,
        };
        final tool = toolMap[key];
        if (tool != null) {
          _toolBloc.add(ToolSelected(tool));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  SystemMouseCursor _getCursor(EditorTool currentTool) {
    if (_hoveredHandle.handle != Handle.none) {
      switch (_hoveredHandle.handle) {
        case Handle.topLeft:
        case Handle.bottomRight:
          return SystemMouseCursors.resizeUpLeftDownRight;
        case Handle.topRight:
        case Handle.bottomLeft:
          return SystemMouseCursors.resizeUpRightDownLeft;
        case Handle.arrowStart:
        case Handle.arrowEnd:
          return SystemMouseCursors.resizeColumn;
        case Handle.midPoint:
          return SystemMouseCursors.grab;
        case Handle.rotate:
          return SystemMouseCursors.alias;
        default:
          return SystemMouseCursors.basic;
      }
    }
    if (_isPanning) return SystemMouseCursors.move;

    switch (currentTool) {
      case EditorTool.arrow:
        return SystemMouseCursors.basic;
      default:
        return SystemMouseCursors.precise;
    }
  }
}
