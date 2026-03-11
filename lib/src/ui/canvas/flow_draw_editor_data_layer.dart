import 'dart:async';
import 'package:flow_draw/src/core/utils/platform_info/platform_info.dart'
    show PlatformInfoImpl;
import 'dart:math';

import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/core/node_editor/clipboard.dart';
import 'package:flow_draw/src/core/utils/json_extensions.dart';
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';
import 'package:flow_draw/src/core/utils/snap_utils.dart';
import 'package:flow_draw/src/core/utils/renderbox.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/ui/canvas/flow_draw_editor_render_object.dart';
import 'package:flow_draw/src/ui/shared/context_menu.dart';
import 'package:flow_draw/src/ui/shared/snap_guides.dart';
import 'package:flow_draw/src/ui/shared/improved_listener.dart';
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

class FlowDrawEditorDataLayer extends StatefulWidget {
  final FlNodeHeaderBuilder? headerBuilder;
  final FlNodeBuilder? nodeBuilder;
  final String fragmentShader;

  const FlowDrawEditorDataLayer({
    super.key,
    this.headerBuilder,
    this.nodeBuilder,
    required this.fragmentShader,
  });

  @override
  State<FlowDrawEditorDataLayer> createState() => _FlowDrawEditorDataLayerState();
}

class _FlowDrawEditorDataLayerState extends State<FlowDrawEditorDataLayer>
    with TickerProviderStateMixin {
  late CanvasBloc _canvasBloc;
  late SelectionBloc _selectionBloc;
  late ToolBloc _toolBloc;
  final FocusNode _canvasFocusNode = FocusNode();

  bool _isPanning = false;
  bool _isAreaSelecting = false;
  bool _isDraggingSelection = false;
  bool _isDrawing = false;
  bool _isEditingText = false;

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
  List<SnapGuide> _activeSnapGuides = const [];

  int _activePointers = 0;
  double _scaleStartZoom = 1.0;
  bool _isScaling = false;
  double _totalDragDelta = 0.0;
  DateTime? _lastClickTime;
  Offset? _lastClickPosition;

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
    _canvasFocusNode.dispose();
    _kineticTimer?.cancel();
    _shapeTextController?.dispose();
    _shapeTextFocusNode?.dispose();
    super.dispose();
  }

  /// Computes the bounding rect of all selected objects (drawing objects and
  /// nodes) in world coordinates. Returns null if no objects are selected.
  Rect? _getSelectionBoundingRect(Set<String> selectedIds) {
    Rect? bounds;
    final canvasState = _canvasBloc.state;

    for (final id in selectedIds) {
      Rect? objRect;

      final drawingObj = canvasState.drawingObjects[id];
      if (drawingObj != null) {
        objRect = drawingObj.rect;
      } else {
        final node = canvasState.nodes[id];
        if (node != null) {
          objRect = getNodeBoundsInWorld(node);
        }
      }

      if (objRect != null) {
        bounds = bounds == null ? objRect : bounds.expandToInclude(objRect);
      }
    }

    return bounds;
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

    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Match the render sizes from _paintQuickActionArrows
    final double handleSize = 20.0 * dpr / sqrt(zoom);
    final double halfHandle = handleSize / 2;
    final double spacing = 10.0 * dpr / sqrt(zoom);

    // Compute connector offsets (same logic as _paintQuickActionArrows)
    final edgeApproachFromLeft = <String, List<bool>>{};
    for (final obj in _canvasBloc.state.drawingObjects.values) {
      if (obj is ArrowObject || obj is LineObject) {
        final startAtt = obj is ArrowObject ? obj.startAttachment : (obj as LineObject).startAttachment;
        final endAtt = obj is ArrowObject ? obj.endAttachment : (obj as LineObject).endAttachment;
        final otherEnd = obj is ArrowObject ? obj.end : (obj as LineObject).end;
        final otherStart = obj is ArrowObject ? obj.start : (obj as LineObject).start;
        for (final (att, otherPoint) in [(startAtt, otherEnd), (endAtt, otherStart)]) {
          if (att != null && att.objectId == objectId) {
            final rp = att.relativePosition;
            if (rp.dy < 0.25) (edgeApproachFromLeft['top'] ??= []).add(otherPoint.dx < object.rect.center.dx);
            if (rp.dy > 0.75) (edgeApproachFromLeft['bottom'] ??= []).add(otherPoint.dx < object.rect.center.dx);
            if (rp.dx < 0.25) (edgeApproachFromLeft['left'] ??= []).add(otherPoint.dy < object.rect.center.dy);
            if (rp.dx > 0.75) (edgeApproachFromLeft['right'] ??= []).add(otherPoint.dy < object.rect.center.dy);
          }
        }
      }
    }
    final double connOffset = handleSize * 2.0;
    Offset _edgeOffset(String edge) {
      final approaches = edgeApproachFromLeft[edge];
      if (approaches == null) return Offset.zero;
      final mostlyFromLeft = approaches.where((b) => b).length >= approaches.length / 2;
      switch (edge) {
        case 'top':
        case 'bottom':
          return Offset(mostlyFromLeft ? connOffset : -connOffset, 0);
        case 'left':
        case 'right':
          return Offset(0, mostlyFromLeft ? connOffset : -connOffset);
        default:
          return Offset.zero;
      }
    }

    final localPositions = {
      QuickActionDirection.top: object.rect.topCenter - Offset(0, spacing + halfHandle) + _edgeOffset('top'),
      QuickActionDirection.right: object.rect.centerRight + Offset(spacing + halfHandle, 0) + _edgeOffset('right'),
      QuickActionDirection.bottom: object.rect.bottomCenter + Offset(0, spacing + halfHandle) + _edgeOffset('bottom'),
      QuickActionDirection.left: object.rect.centerLeft - Offset(spacing + halfHandle, 0) + _edgeOffset('left'),
    };

    for (var entry in localPositions.entries) {
      final direction = entry.key;
      final localCenter = entry.value;

      final worldCenter = localCenter.rotate(object.rect.center, object.angle);

      if ((worldPos - worldCenter).distance < halfHandle * 1.5) {
        _canvasBloc.add(ObjectDuplicatedWithConnection(objectId, direction));
        return true;
      }
    }

    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    // If text overlay is active, let the TextField handle all pointer events
    if (_isEditingText) return;

    // If inline shape text editor is active, finish editing and proceed
    if (_editingShapeObject != null) {
      _finishShapeTextEditing();
    }

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

    // Double-click detection: check BEFORE requesting canvas focus so
    // the text editor can acquire focus without contention.
    final now = DateTime.now();
    final isDoubleClick = _lastClickTime != null &&
        _lastClickPosition != null &&
        now.difference(_lastClickTime!).inMilliseconds < 500 &&
        (event.position - _lastClickPosition!).distance < 60;
    _lastClickTime = now;
    _lastClickPosition = event.position;

    if (isDoubleClick) {
      _onDoubleClick();
      return;
    }

    // Request canvas focus for keyboard shortcuts only when NOT entering
    // text editing (double-click already returned above).
    if (!_canvasFocusNode.hasFocus) {
      _canvasFocusNode.requestFocus();
    }

    final tool = _toolBloc.state.activeTool;

    if (event.buttons == kMiddleMouseButton) {
      _onPanStart();
      return;
    }

    if (event.buttons == kSecondaryMouseButton) {
      _handleRightClick(event, worldPos);
      return;
    }

    if (tool == EditorTool.arrow) {
      // Update hovered handle from tap position before checking —
      // on touch devices there are no hover events, so the handle
      // state can be stale from a previous interaction.
      _updateHoveredHandle(event.position);
      // Check resize/rotation handles before quick actions so that
      // handle taps are not swallowed by quick connector buttons.
      if (_hoveredHandle.handle == Handle.rotate) {
        _beginRotation(worldPos);
        return;
      }
      if (_hoveredHandle.handle != Handle.none) {
        _isResizing = _hoveredHandle;
        _originalResizeRect =
            _canvasBloc.state.drawingObjects[_isResizing.objectId]?.rect;
        return;
      }
    }

    if (_checkAndHandleQuickAction(worldPos)) {
      return;
    }

    if (tool == EditorTool.arrow) {
      _handleArrowToolPointerDown(event, worldPos);
    } else {
      _handleDrawingToolPointerDown(event, worldPos);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_editingShapeObject != null) return;
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
      final selectedIds = _selectionBloc.state.selectedNodeIds.union(
        _selectionBloc.state.selectedDrawingObjectIds,
      );

      // Compute bounding rect of all selected objects for snap guide detection.
      final movingRect = _getSelectionBoundingRect(selectedIds);
      if (movingRect != null) {
        // Build node rects so nodes also serve as snap references.
        final nodeRects = <String, Rect>{};
        for (final node in _canvasBloc.state.nodes.values) {
          if (selectedIds.contains(node.id)) continue;
          final bounds = getNodeBoundsInWorld(node);
          if (bounds != null) nodeRects[node.id] = bounds;
        }

        final guides = AlignmentGuide.findGuides(
          movingRect,
          _canvasBloc.state.drawingObjects,
          selectedIds,
          additionalRects: nodeRects,
        );

        // Find the closest snap per axis and apply correction.
        double? bestDx;
        double bestDxAbs = double.infinity;
        double? bestDy;
        double bestDyAbs = double.infinity;
        final appliedGuides = <SnapGuide>[];

        for (final guide in guides) {
          if (guide.axis == SnapGuideAxis.vertical) {
            final leftDiff = movingRect.left - guide.position;
            final rightDiff = movingRect.right - guide.position;
            final centerDiff = movingRect.center.dx - guide.position;
            final minDiff = [leftDiff, rightDiff, centerDiff]
                .reduce((a, b) => a.abs() < b.abs() ? a : b);
            if (minDiff.abs() < bestDxAbs) {
              bestDxAbs = minDiff.abs();
              bestDx = minDiff;
            }
          } else {
            final topDiff = movingRect.top - guide.position;
            final bottomDiff = movingRect.bottom - guide.position;
            final centerDiff = movingRect.center.dy - guide.position;
            final minDiff = [topDiff, bottomDiff, centerDiff]
                .reduce((a, b) => a.abs() < b.abs() ? a : b);
            if (minDiff.abs() < bestDyAbs) {
              bestDyAbs = minDiff.abs();
              bestDy = minDiff;
            }
          }
        }

        var snappedDelta = dragDelta;
        if (bestDx != null) snappedDelta = Offset(snappedDelta.dx - bestDx, snappedDelta.dy);
        if (bestDy != null) snappedDelta = Offset(snappedDelta.dx, snappedDelta.dy - bestDy);

        // Only show guides whose axis was actually snapped.
        for (final guide in guides) {
          if (guide.axis == SnapGuideAxis.vertical && bestDx != null) {
            appliedGuides.add(guide);
          } else if (guide.axis == SnapGuideAxis.horizontal && bestDy != null) {
            appliedGuides.add(guide);
          }
        }

        setState(() => _activeSnapGuides = appliedGuides);
        _canvasBloc.add(ObjectsDragged(selectedIds, snappedDelta));
      } else {
        _canvasBloc.add(ObjectsDragged(selectedIds, dragDelta));
      }
      _totalDragDelta += event.delta.distance;
    } else if (_isAreaSelecting) {
      setState(
            () => _selectionArea = Rect.fromPoints(_selectionStart, worldPos),
      );
    } else if (_isDrawing) {
      _handleObjectDrawing(worldPos, event.pressure);
    } else {
      _updateHoveredHandle(event.position);
      _updateHoveredDrawingObject(worldPos);
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
        _canvasBloc.add(ObjectsDragEnded(
          _selectionBloc.state.selectedNodeIds.union(
            _selectionBloc.state.selectedDrawingObjectIds,
          ),
        ));
      }
    }
    _isRotating = false;
    _isDraggingSelection = false;
    _isResizing = (objectId: '', handle: Handle.none);
    _originalResizeRect = null;
    if (_activeSnapGuides.isNotEmpty) {
      setState(() => _activeSnapGuides = const []);
    }
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
      _activeSnapGuides = const [];
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
    final rawAngle = _originalObjectAngle + angleDelta;
    // Snap to 15-degree increments
    const snap = 15.0 * pi / 180.0;
    final newAngle = (rawAngle / snap).round() * snap;

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

    final hitPadding = 6.0 / _canvasBloc.state.viewportZoom;
    final objects = _canvasBloc.state.drawingObjects.values;

    // Prefer editable shapes (rectangle/circle/text) over arrows/lines
    // so that double-tapping near an edge where an arrow overlaps still
    // enters text editing for the shape underneath.
    for (final obj in objects.toList().reversed) {
      if (obj is TextObject && obj.rect.inflate(hitPadding).contains(worldPos)) {
        _beginTextEditing(existingObject: obj);
        return;
      }
      if ((obj is RectangleObject || obj is CircleObject || obj is DiamondObject || obj is ParallelogramObject) &&
          obj.rect.inflate(hitPadding).contains(worldPos)) {
        _beginShapeTextEditing(obj);
        return;
      }
    }
  }

  void _handleRightClick(PointerDownEvent event, Offset worldPos) {
    final hitObjectId = _findHitObject(worldPos);
    final selectionState = _selectionBloc.state;

    // If right-clicked on an object not yet selected, select it
    if (hitObjectId != null &&
        !selectionState.selectedDrawingObjectIds.contains(hitObjectId) &&
        !selectionState.selectedNodeIds.contains(hitObjectId)) {
      final isNode = _canvasBloc.state.nodes.containsKey(hitObjectId);
      _selectionBloc.add(SelectionReplaced(
        nodeIds: isNode ? {hitObjectId} : {},
        drawingObjectIds: !isNode ? {hitObjectId} : {},
      ));
    }

    final selectedIds = _selectionBloc.state.selectedDrawingObjectIds;
    final selectedNodeIds = _selectionBloc.state.selectedNodeIds;
    final hasSelection = selectedIds.isNotEmpty || selectedNodeIds.isNotEmpty;

    showCanvasContextMenu(
      context: context,
      position: event.position,
      hasSelection: hasSelection,
      selectedCount: selectedIds.length,
      onAction: (action) {
        final ids = _selectionBloc.state.selectedDrawingObjectIds;
        switch (action) {
          case CanvasContextMenuAction.cut:
            _canvasBloc.add(SelectionCut());
            _canvasBloc.add(ObjectsRemoved(
              nodeIds: _selectionBloc.state.selectedNodeIds,
              drawingObjectIds: ids,
            ));
            _selectionBloc.add(SelectionCleared());
          case CanvasContextMenuAction.copy:
            _canvasBloc.add(SelectionCopied());
          case CanvasContextMenuAction.paste:
            final pasteWorldPos = screenToWorld(
              _lastFocalPoint,
              _canvasBloc.state.viewportOffset,
              _canvasBloc.state.viewportZoom,
            );
            if (pasteWorldPos != null) {
              _canvasBloc.add(SelectionPasted(pastePosition: pasteWorldPos));
            }
          case CanvasContextMenuAction.selectAll:
            final canvasState = _canvasBloc.state;
            _selectionBloc.add(SelectionReplaced(
              nodeIds: canvasState.nodes.keys.toSet(),
              drawingObjectIds: canvasState.drawingObjects.keys.toSet(),
            ));
          case CanvasContextMenuAction.duplicate:
            _canvasBloc.add(SelectionDuplicated(ids));
            final newIds = _canvasBloc.consumeLastDuplicatedIds();
            if (newIds.isNotEmpty) {
              _selectionBloc.add(SelectionReplaced(
                nodeIds: {},
                drawingObjectIds: newIds,
              ));
            }
          case CanvasContextMenuAction.bringForward:
            _canvasBloc.add(ObjectsBroughtForward(ids));
          case CanvasContextMenuAction.sendBackward:
            _canvasBloc.add(ObjectsSentBackward(ids));
          case CanvasContextMenuAction.bringToFront:
            _canvasBloc.add(ObjectsBroughtToFront(ids));
          case CanvasContextMenuAction.sendToBack:
            _canvasBloc.add(ObjectsSentToBack(ids));
          case CanvasContextMenuAction.alignLeft:
            _canvasBloc.add(ObjectsAligned(ids, AlignmentType.left));
          case CanvasContextMenuAction.alignCenterH:
            _canvasBloc.add(ObjectsAligned(ids, AlignmentType.centerH));
          case CanvasContextMenuAction.alignRight:
            _canvasBloc.add(ObjectsAligned(ids, AlignmentType.right));
          case CanvasContextMenuAction.alignTop:
            _canvasBloc.add(ObjectsAligned(ids, AlignmentType.top));
          case CanvasContextMenuAction.alignCenterV:
            _canvasBloc.add(ObjectsAligned(ids, AlignmentType.centerV));
          case CanvasContextMenuAction.alignBottom:
            _canvasBloc.add(ObjectsAligned(ids, AlignmentType.bottom));
          case CanvasContextMenuAction.distributeHorizontal:
            _canvasBloc.add(ObjectsDistributed(ids, DistributionType.horizontal));
          case CanvasContextMenuAction.distributeVertical:
            _canvasBloc.add(ObjectsDistributed(ids, DistributionType.vertical));
          case CanvasContextMenuAction.delete:
            _canvasBloc.add(ObjectsRemoved(
              nodeIds: _selectionBloc.state.selectedNodeIds,
              drawingObjectIds: ids,
            ));
            _selectionBloc.add(SelectionCleared());
        }
      },
    );
  }

  void _handleArrowToolPointerDown(PointerDownEvent event, Offset worldPos) {
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
          newStart = _hoveredSnapPoint?.worldPosition ?? snapOffset(worldPos);
        } else if (handle == Handle.arrowEnd) {
          newEnd = _hoveredSnapPoint?.worldPosition ?? snapOffset(worldPos);
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
          devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
          zoom: _canvasBloc.state.viewportZoom,
        );

        final updatedObject = object.copyWith(
          start: newStart,
          end: newEnd,
          waypoints: waypoints,
        );
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));

      }  else {
        if (handle == Handle.arrowStart) {
          final pos = _hoveredSnapPoint?.worldPosition ?? snapOffset(worldPos);
          final updatedObject = object.copyWith(start: pos);
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        } else if (handle == Handle.arrowEnd) {
          final pos = _hoveredSnapPoint?.worldPosition ?? snapOffset(worldPos);
          final updatedObject = object.copyWith(end: pos);
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
        final pos = _hoveredSnapPoint?.worldPosition ?? snapOffset(worldPos);
        final updatedObject = object.copyWith(start: pos);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      } else if (_isResizing.handle == Handle.arrowEnd) {
        final pos = _hoveredSnapPoint?.worldPosition ?? snapOffset(worldPos);
        final updatedObject = object.copyWith(end: pos);
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
      final rawRect = Rect.fromCenter(
        center: newCenter,
        width: localDragVector.dx.abs(),
        height: localDragVector.dy.abs(),
      );
      final newRect = snapRect(rawRect);

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

  List<Rect> _collectObstacles({String? excludeId, Set<String>? excludeIds}) {
    final canvasState = _canvasBloc.state;
    final obstacles = <Rect>[];

    for (final obj in canvasState.drawingObjects.values) {
      if (obj.id == excludeId) continue;
      if (excludeIds != null && excludeIds.contains(obj.id)) continue;
      // Skip arrows, lines, pencil strokes — only solid objects are obstacles
      if (obj is ArrowObject || obj is LineObject || obj is PencilStrokeObject) {
        continue;
      }
      obstacles.add(obj.rect);
    }

    for (final node in canvasState.nodes.values) {
      if (node.id == excludeId) continue;
      if (excludeIds != null && excludeIds.contains(node.id)) continue;
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
            tool == EditorTool.diamond ||
            tool == EditorTool.parallelogram ||
            tool == EditorTool.forkJoin ||
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
        final drawDist = (finalPos - _tempDrawingObject!.start).distance;
        if (pathType == LinkPathType.orthogonal && drawDist > 2) {
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
            devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
            zoom: _canvasBloc.state.viewportZoom,
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
    bool isTapCreated = false;
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

    final lineStyle = _toolBloc.state.lineStyle;

    if (tool == EditorTool.arrowTopRight) {
      if ((_drawingStart - endPos).distance > 2) {
        final hasAttachments = startAttachment != null || endAttachment != null;
        final snapStart = hasAttachments ? _drawingStart : snapOffset(_drawingStart);
        final snapEnd = hasAttachments ? endPos : snapOffset(endPos);
        newObject = ArrowObject(
          id: id,
          start: snapStart,
          end: snapEnd,
          pathType: _tempDrawingObject!.pathType,
          startAttachment: startAttachment,
          endAttachment: endAttachment,
          waypoints: _tempDrawingObject!.waypoints,
          lineStyle: lineStyle,
        );
      }
    } else if (tool == EditorTool.pencil) {
      if (_currentPencilPoints.length > 1) {
        newObject = PencilStrokeObject(id: id, points: _currentPencilPoints);
      }
    } else {
      final snappedStart = snapOffset(_drawingStart);
      final snappedEnd = snapOffset(_tempDrawingObject!.end);
      final rect = Rect.fromPoints(
        snappedStart,
        snappedEnd,
      ).normalize;
      final isTap = rect.width <= 2 && rect.height <= 2;
      isTapCreated = isTap;
      final shapeRect = isTap
          ? snapRect(Rect.fromCenter(center: snappedStart, width: 1008, height: 608))
          : snapRect(rect);
      switch (tool) {
        case EditorTool.circle:
          newObject = CircleObject(id: id, rect: shapeRect, lineStyle: lineStyle);
          break;
        case EditorTool.square:
          newObject = RectangleObject(id: id, rect: shapeRect, lineStyle: lineStyle);
          break;
        case EditorTool.diamond:
          newObject = DiamondObject(id: id, rect: shapeRect, lineStyle: lineStyle);
          break;
        case EditorTool.parallelogram:
          newObject = ParallelogramObject(id: id, rect: shapeRect, lineStyle: lineStyle);
          break;
        case EditorTool.forkJoin:
          final forkRect = isTap
              ? snapRect(Rect.fromCenter(center: snappedStart, width: 1008, height: 10))
              : snapRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 10));
          newObject = ForkJoinObject(id: id, rect: forkRect, lineStyle: lineStyle);
          break;
        case EditorTool.arrowTopRight:
          if (!isTap) {
            newObject = ArrowObject(
              id: id,
              start: snappedStart,
              end: snappedEnd,
              pathType: _tempDrawingObject!.pathType,
              lineStyle: lineStyle,
            );
          }
          break;
        case EditorTool.line:
          if (!isTap) {
            final hasAttachments = startAttachment != null || endAttachment != null;
            newObject = LineObject(
              id: id,
              start: hasAttachments ? _drawingStart : snappedStart,
              end: hasAttachments ? endPos : snappedEnd,
              startAttachment: startAttachment,
              endAttachment: endAttachment,
              lineStyle: lineStyle,
            );
          }
          break;
        case EditorTool.figure:
          newObject = FigureObject(id: id, rect: shapeRect);
          break;
        case EditorTool.text:
          newObject = TextObject(id: id, rect: shapeRect);
          break;
        default:
          break;
      }
    }

    if (newObject != null) {
      _canvasBloc.add(DrawingObjectAdded(newObject));
      if (isTapCreated && (newObject is RectangleObject || newObject is CircleObject || newObject is ParallelogramObject)) {
        _selectionBloc.add(SelectionReplaced(
          nodeIds: const {},
          drawingObjectIds: {newObject.id},
        ));
        _toolBloc.add(const ToolSelected(EditorTool.arrow));
      }
    } else {
      _selectionBloc.add(SelectionCleared());
    }

    final autoEditObject = (isTapCreated && newObject != null &&
        (newObject is RectangleObject || newObject is CircleObject || newObject is ParallelogramObject))
        ? newObject
        : null;

    setState(() {
      _isDrawing = false;
      _tempDrawingObject = null;
      _currentPencilPoints = [];
      _startSnapPoint = null;
      _hoveredSnapPoint = null;
    });

    // Auto-enter text editing for tap-created shapes (inline widget, no overlay)
    // Deferred to next frame so BlocBuilder rebuilds from tool/selection changes settle first.
    if (autoEditObject != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _beginShapeTextEditing(autoEditObject);
      });
    }
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
    final tolerance = 12.0 / canvasState.viewportZoom;
    final hitPadding = 6.0 / canvasState.viewportZoom;

    for (final obj in canvasState.drawingObjects.values.toList().reversed) {
      if (obj is ArrowObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final controlPoint = obj.midPoint ?? (start + end) / 2;

        Path path;
        if (obj.pathType == LinkPathType.orthogonal) {
          // Recompute waypoints dynamically for hit testing
          List<Offset>? waypoints = obj.waypoints;
          if (obj.startAttachment != null && obj.endAttachment != null) {
            final startObjRect = _getAttachedObjectRect(obj.startAttachment);
            final endObjRect = _getAttachedObjectRect(obj.endAttachment);
            if (startObjRect != null && endObjRect != null) {
              final obstacles = _collectObstacles(excludeId: obj.id);
              waypoints = OrthogonalRouter.route(
                start: start,
                end: end,
                obstacles: obstacles,
                startObjectRect: startObjRect,
                endObjectRect: endObjRect,
                devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
                zoom: _canvasBloc.state.viewportZoom,
              );
            }
          }
          final allPoints = [start, ...?waypoints, end];
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
      } else if (obj.rect.inflate(hitPadding).contains(worldPos)) {
        return obj.id;
      }
    }

    for (final node in canvasState.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds != null && nodeBounds.inflate(hitPadding).contains(worldPos)) {
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

  /// Detects which shape (Rectangle, Circle, Diamond) the pointer is over
  /// and dispatches a [DrawingObjectHovered] event so connection ports can
  /// be shown on hover.
  void _updateHoveredDrawingObject(Offset worldPos) {
    final canvasState = _canvasBloc.state;
    final hitPadding = 6.0 / canvasState.viewportZoom;
    String? hoveredId;

    for (final obj in canvasState.drawingObjects.values.toList().reversed) {
      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is DiamondObject ||
          obj is ParallelogramObject ||
          obj is ForkJoinObject) {
        if (obj.rect.inflate(hitPadding).contains(worldPos)) {
          hoveredId = obj.id;
          break;
        }
      }
    }

    if (hoveredId != _selectionBloc.state.hoveredDrawingObjectId) {
      _selectionBloc.add(DrawingObjectHovered(drawingObjectId: hoveredId));
    }
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

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final handleHitAreaRadius = 20.0 * dpr / sqrt(canvasState.viewportZoom);
    final rotationHitAreaRadius = 22.0 * dpr / sqrt(canvasState.viewportZoom);

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
        // topRight is the dedicated rotation handle, offset away from object
        final rotOffset = 8.0 / canvasState.viewportZoom;
        final rotationCorner = selectionRect.topRight + Offset(rotOffset, -rotOffset);
        final rotDist = (localPos - rotationCorner).distance;
        if (rotDist < rotationHitAreaRadius) {
          if (_hoveredHandle.objectId != objectId ||
              _hoveredHandle.handle != Handle.rotate) {
            setState(() => _hoveredHandle =
                (objectId: objectId, handle: Handle.rotate));
          }
          return;
        }

        // Other 3 corners are resize handles
        final resizeHandles = {
          Handle.topLeft: selectionRect.topLeft,
          Handle.bottomRight: selectionRect.bottomRight,
          Handle.bottomLeft: selectionRect.bottomLeft,
        };
        for (final entry in resizeHandles.entries) {
          final distance = (localPos - entry.value).distance;
          if (distance < handleHitAreaRadius) {
            if (_hoveredHandle.objectId != objectId ||
                _hoveredHandle.handle != entry.key) {
              setState(() =>
                  _hoveredHandle = (objectId: objectId, handle: entry.key));
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

  void _nudgeSelection(Offset delta) {
    final selectedIds = _selectionBloc.state.selectedNodeIds.union(
      _selectionBloc.state.selectedDrawingObjectIds,
    );
    if (selectedIds.isEmpty) return;
    _canvasBloc.add(ObjectsNudged(selectedIds, delta));
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

      final w = initialSize.width + 4;
      final h = initialSize.height + 4;
      object = TextObject(
        id: const Uuid().v4(),
        rect: Rect.fromLTWH(at!.dx - w / 2, at.dy - h / 2, w, h),
        text: initialText,
        style: initialStyle,
      );
      _canvasBloc.add(DrawingObjectAdded(object));
      _selectionBloc.add(SelectionReplaced(drawingObjectIds: {object.id}));
    }

    setState(() {
      object.isEditing = true;
      _isEditingText = true;
    });

    final textEditingController = TextEditingController(text: object.text);
    final focusNode = FocusNode();
    OverlayEntry? overlayEntry;

    bool _closed = false;
    void _submitAndClose() {
      if (!mounted || _closed) return;
      _closed = true;
      final newText = textEditingController.text;

      setState(() {
        object.isEditing = false;
        _isEditingText = false;
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
          // Re-center the text rect around its current center
          final center = object.rect.center;
          object.rect = Rect.fromCenter(
            center: center,
            width: textPainter.width,
            height: textPainter.height,
          );
        });
      }

      // Remove the overlay. The controller and focus node are intentionally
      // NOT disposed here — the gesture arena may still hold references to
      // the TextField's RenderEditable, and disposing the controller while
      // a gesture is pending causes "used after disposed" assertions.
      // They will be garbage-collected once all references are released.
      overlayEntry?.remove();
    }

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
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _submitAndClose();
                  });
                },
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: Material(
                color: Colors.transparent,
                child: DefaultTextEditingShortcuts(
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
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(overlayEntry);
  }

  // Shape text editing state
  DrawingObject? _editingShapeObject;
  TextEditingController? _shapeTextController;
  FocusNode? _shapeTextFocusNode;
  TextStyle _shapeTextStyle = const TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Courier');

  DateTime? _shapeEditOpenedAt;

  void _beginShapeTextEditing(DrawingObject shapeObject) {
    const defaultStyle = TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Courier');

    String? existingText;
    TextStyle existingStyle = defaultStyle;
    if (shapeObject is RectangleObject) {
      existingText = shapeObject.text;
      existingStyle = shapeObject.textStyle ?? defaultStyle;
    } else if (shapeObject is CircleObject) {
      existingText = shapeObject.text;
      existingStyle = shapeObject.textStyle ?? defaultStyle;
    } else if (shapeObject is DiamondObject) {
      existingText = shapeObject.text;
      existingStyle = shapeObject.textStyle ?? defaultStyle;
    } else if (shapeObject is ParallelogramObject) {
      existingText = shapeObject.text;
      existingStyle = shapeObject.textStyle ?? defaultStyle;
    }

    _shapeTextController?.dispose();
    _shapeTextFocusNode?.dispose();

    _shapeTextController = TextEditingController(text: existingText ?? '');
    _shapeTextFocusNode = FocusNode();
    _shapeTextStyle = existingStyle;
    _shapeEditOpenedAt = DateTime.now();

    if (existingText != null && existingText.isNotEmpty) {
      _shapeTextController!.selection = TextSelection(
        baseOffset: 0,
        extentOffset: existingText.length,
      );
    }

    setState(() {
      _editingShapeObject = shapeObject;
      if (shapeObject is RectangleObject) shapeObject.isEditing = true;
      if (shapeObject is CircleObject) shapeObject.isEditing = true;
      if (shapeObject is DiamondObject) shapeObject.isEditing = true;
    });

    // Explicitly request focus for the text field after the next frame
    // so the widget tree has rebuilt with the TextField present.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shapeTextFocusNode?.requestFocus();
    });
  }

  void _finishShapeTextEditing() {
    // Ignore dismiss if editor just opened (prevents event bleeding)
    if (_shapeEditOpenedAt != null &&
        DateTime.now().difference(_shapeEditOpenedAt!).inMilliseconds < 500) {
      return;
    }
    final shapeObject = _editingShapeObject;
    if (shapeObject == null) return;

    final newText = _shapeTextController?.text.trim() ?? '';

    setState(() {
      if (shapeObject is RectangleObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
      } else if (shapeObject is CircleObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
      } else if (shapeObject is DiamondObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
      } else if (shapeObject is ParallelogramObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
      }
      _editingShapeObject = null;
    });
    // Don't dispose controller/focusNode here — they stay alive until
    // _beginShapeTextEditing replaces them or the widget is disposed.
    // This avoids "used after disposed" errors when gesture callbacks
    // fire on the TextField after we've scheduled its removal.
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
                        FlowDrawEditorRenderObjectWidget(
                          key: kNodeEditorWidgetKey,
                          canvasState: canvasState,
                          selectionState: selectionState,
                          style: const FlowDrawEditorStyle(),
                          gridShader: gridShader,
                          tempDrawingObject: _tempDrawingObject,
                          selectionArea: _selectionArea,
                          headerBuilder: widget.headerBuilder,
                          nodeBuilder: widget.nodeBuilder,
                          snapHandlePosition: _hoveredSnapPoint?.worldPosition,
                          snapGuides: _activeSnapGuides,
                        ),
                  ),
                );

                return CallbackShortcuts(
                  bindings: (_editingShapeObject != null || _isEditingText) ? {} : {
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
                    // Duplicate selection
                    const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
                      _canvasBloc.add(SelectionDuplicated(selectionState.selectedDrawingObjectIds));
                      final newIds = _canvasBloc.consumeLastDuplicatedIds();
                      if (newIds.isNotEmpty) {
                        _selectionBloc.add(SelectionReplaced(
                          nodeIds: {},
                          drawingObjectIds: newIds,
                        ));
                      }
                    },
                    const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
                      _canvasBloc.add(SelectionDuplicated(selectionState.selectedDrawingObjectIds));
                      final newIds = _canvasBloc.consumeLastDuplicatedIds();
                      if (newIds.isNotEmpty) {
                        _selectionBloc.add(SelectionReplaced(
                          nodeIds: {},
                          drawingObjectIds: newIds,
                        ));
                      }
                    },
                    // Z-ordering
                    const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): () =>
                      _canvasBloc.add(ObjectsBroughtForward(selectionState.selectedDrawingObjectIds)),
                    const SingleActivator(LogicalKeyboardKey.bracketRight, control: true): () =>
                      _canvasBloc.add(ObjectsBroughtForward(selectionState.selectedDrawingObjectIds)),
                    const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): () =>
                      _canvasBloc.add(ObjectsSentBackward(selectionState.selectedDrawingObjectIds)),
                    const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true): () =>
                      _canvasBloc.add(ObjectsSentBackward(selectionState.selectedDrawingObjectIds)),
                    const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true, shift: true): () =>
                      _canvasBloc.add(ObjectsBroughtToFront(selectionState.selectedDrawingObjectIds)),
                    const SingleActivator(LogicalKeyboardKey.bracketRight, control: true, shift: true): () =>
                      _canvasBloc.add(ObjectsBroughtToFront(selectionState.selectedDrawingObjectIds)),
                    const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true, shift: true): () =>
                      _canvasBloc.add(ObjectsSentToBack(selectionState.selectedDrawingObjectIds)),
                    const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true, shift: true): () =>
                      _canvasBloc.add(ObjectsSentToBack(selectionState.selectedDrawingObjectIds)),
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
                    const SingleActivator(LogicalKeyboardKey.keyV): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.arrow)),
                    const SingleActivator(LogicalKeyboardKey.keyR): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.square)),
                    const SingleActivator(LogicalKeyboardKey.keyO): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.circle)),
                    const SingleActivator(LogicalKeyboardKey.keyG): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.diamond)),
                    const SingleActivator(LogicalKeyboardKey.keyP): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.parallelogram)),
                    const SingleActivator(LogicalKeyboardKey.keyJ): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.forkJoin)),
                    const SingleActivator(LogicalKeyboardKey.keyA): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.arrowTopRight)),
                    const SingleActivator(LogicalKeyboardKey.keyL): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.line)),
                    const SingleActivator(LogicalKeyboardKey.keyD): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.pencil)),
                    const SingleActivator(LogicalKeyboardKey.keyT): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.text)),
                    const SingleActivator(LogicalKeyboardKey.keyF): () =>
                      _toolBloc.add(const ToolSelected(EditorTool.figure)),
                    const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
                      _canvasBloc.add(const GridToggled()),
                    const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
                      _canvasBloc.add(const GridToggled()),
                    // Nudge: arrow keys = 1 grid square, shift+arrow = 1px
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _nudgeSelection(const Offset(0, -kGridSize)),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _nudgeSelection(const Offset(0, kGridSize)),
                    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      _nudgeSelection(const Offset(-kGridSize, 0)),
                    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      _nudgeSelection(const Offset(kGridSize, 0)),
                    const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
                      _nudgeSelection(const Offset(0, -1)),
                    const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
                      _nudgeSelection(const Offset(0, 1)),
                    const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
                      _nudgeSelection(const Offset(-1, 0)),
                    const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
                      _nudgeSelection(const Offset(1, 0)),
                  },
                  child: Focus(
                    focusNode: _canvasFocusNode,
                    autofocus: true,
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _onPointerDown,
                          onPointerMove: _onPointerMove,
                          onPointerUp: _onPointerUp,
                          onPointerCancel: _onPointerCancel,
                          onPointerSignal: _onPointerSignal,
                          child: GestureDetector(
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onScaleEnd: _onScaleEnd,
                            child: Stack(
                              children: [
                                canvasChild,
                                if (_editingShapeObject != null)
                                  _buildInlineShapeTextEditor(canvasState),
                              ],
                            ),
                          ),
                        ),
                        if (selectionState.selectedDrawingObjectIds.length >= 2)
                          _buildAlignmentToolbar(canvasState, selectionState),
                      ],
                    ),
                  ),
                ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAlignmentToolbar(
    CanvasState canvasState,
    SelectionState selectionState,
  ) {
    final selectedIds = selectionState.selectedDrawingObjectIds;
    final zoom = canvasState.viewportZoom;
    final vpOffset = canvasState.viewportOffset;

    // Compute bounding box of selected objects in world coords
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final id in selectedIds) {
      final obj = canvasState.drawingObjects[id];
      if (obj == null) continue;
      final r = obj.rect;
      if (r.left < minX) minX = r.left;
      if (r.top < minY) minY = r.top;
      if (r.right > maxX) maxX = r.right;
      if (r.bottom > maxY) maxY = r.bottom;
    }

    // World top-center → screen position via worldToScreen
    final worldTopCenter = Offset((minX + maxX) / 2, minY);
    final screenPos = worldToScreen(worldTopCenter, vpOffset, zoom);
    if (screenPos == null) return const SizedBox.shrink();

    // Convert from global to local (relative to editor widget)
    final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
    if (editorBounds == null) return const SizedBox.shrink();
    final localX = screenPos.dx - editorBounds.left;
    final localY = screenPos.dy - editorBounds.top;

    const toolbarGap = 8.0;

    final bool canDistribute = selectedIds.length >= 3;

    Widget iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
      return IconButton(
        tooltip: tooltip,
        iconSize: 16,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        padding: EdgeInsets.zero,
        splashRadius: 14,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
      );
    }

    return Positioned(
      left: localX - 150,
      top: localY - toolbarGap - 36,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconBtn(Icons.align_horizontal_left, 'Align left', () {
                _canvasBloc.add(ObjectsAligned(selectedIds, AlignmentType.left));
              }),
              iconBtn(Icons.align_horizontal_center, 'Align center', () {
                _canvasBloc.add(ObjectsAligned(selectedIds, AlignmentType.centerH));
              }),
              iconBtn(Icons.align_horizontal_right, 'Align right', () {
                _canvasBloc.add(ObjectsAligned(selectedIds, AlignmentType.right));
              }),
              const SizedBox(width: 2),
              iconBtn(Icons.align_vertical_top, 'Align top', () {
                _canvasBloc.add(ObjectsAligned(selectedIds, AlignmentType.top));
              }),
              iconBtn(Icons.align_vertical_center, 'Align middle', () {
                _canvasBloc.add(ObjectsAligned(selectedIds, AlignmentType.centerV));
              }),
              iconBtn(Icons.align_vertical_bottom, 'Align bottom', () {
                _canvasBloc.add(ObjectsAligned(selectedIds, AlignmentType.bottom));
              }),
              const SizedBox(width: 2),
              iconBtn(
                Icons.horizontal_distribute,
                'Distribute horizontal',
                canDistribute
                    ? () {
                        _canvasBloc.add(ObjectsDistributed(
                          selectedIds,
                          DistributionType.horizontal,
                        ));
                      }
                    : null,
              ),
              iconBtn(
                Icons.vertical_distribute,
                'Distribute vertical',
                canDistribute
                    ? () {
                        _canvasBloc.add(ObjectsDistributed(
                          selectedIds,
                          DistributionType.vertical,
                        ));
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineShapeTextEditor(CanvasState canvasState) {
    final shapeObject = _editingShapeObject!;
    final zoom = canvasState.viewportZoom;
    final offset = canvasState.viewportOffset;

    return LayoutBuilder(
      builder: (context, constraints) {
        final editorWidth = constraints.maxWidth;
        final editorHeight = constraints.maxHeight;

        final shapeCenter = shapeObject.rect.center;
        final screenX = (shapeCenter.dx + offset.dx) * zoom + editorWidth / 2;
        final screenY = (shapeCenter.dy + offset.dy) * zoom + editorHeight / 2;
        final screenWidth = shapeObject.rect.width * zoom;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _finishShapeTextEditing,
              ),
            ),
            Positioned(
              left: screenX - screenWidth / 2,
              top: screenY - (_shapeTextStyle.fontSize! * zoom) / 2,
              width: screenWidth,
              child: Material(
                color: Colors.transparent,
                child: TextField(
                  key: const ValueKey('shape_text_editor'),
                  controller: _shapeTextController,
                  focusNode: _shapeTextFocusNode,
                  textAlign: TextAlign.center,
                  style: _shapeTextStyle.copyWith(
                    fontSize: _shapeTextStyle.fontSize! * zoom,
                  ),
                  maxLines: 1,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _finishShapeTextEditing(),
                ),
              ),
            ),
          ],
        );
      },
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
