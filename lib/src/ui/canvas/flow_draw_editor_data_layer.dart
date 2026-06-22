import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flow_draw/src/core/utils/platform_info/platform_info.dart'
    show PlatformInfoImpl;
import 'dart:math';

import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/core/node_editor/clipboard.dart';
import 'package:flow_draw/src/core/utils/json_extensions.dart';
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';
import 'package:flow_draw/src/core/utils/layered_layout.dart';
import 'package:flow_draw/src/core/utils/path_layout.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flow_draw/src/core/utils/swap_layout.dart';
import 'package:flow_draw/src/core/utils/snap_utils.dart';
import 'package:flow_draw/src/core/utils/renderbox.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/ui/canvas/flow_draw_editor_render_object.dart';
import 'package:flow_draw/src/ui/canvas/rich_text_editing_controller.dart';
import 'package:flow_draw/src/ui/shared/active_text_editing.dart';
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

/// What the "Swap" action will do given the current selection.
enum _SwapKind { none, nodes, endpoints }

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

  /// Debug: overlay the handle hit-test zones on the canvas. Toggle with
  /// Cmd/Ctrl+Shift+H. Endpoints (connection points) are drawn in blue with
  /// the expanded radius; resize/rotate/midpoint zones in orange.
  bool _debugShowHitAreas = false;

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
  Size? _lastCanvasSize;

  Offset get offset => _canvasBloc.state.viewportOffset;

  double get zoom => _canvasBloc.state.viewportZoom;

  /// Computes the minimum allowed zoom so the entire diagram never shrinks
  /// below 32 screen pixels in its largest dimension. Returns a very small
  /// value when the canvas is empty (allowing infinite zoom out).
  /// Fits the viewport to all content (drawing objects + nodes), centering it.
  /// World→screen is `size/2 + zoom*(w + offset)`, so centering the content's
  /// bbox center `c` means `offset = -c`, and zoom = fit ratio with a margin.
  void _fitViewToContent() {
    final canvasState = _canvasBloc.state;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    void acc(Rect r) {
      minX = min(minX, r.left);
      minY = min(minY, r.top);
      maxX = max(maxX, r.right);
      maxY = max(maxY, r.bottom);
    }

    for (final obj in canvasState.drawingObjects.values) {
      if (obj is ArrowObject || obj is LineObject) continue;
      acc(obj.rect);
    }
    for (final node in canvasState.nodes.values) {
      final b = getNodeBoundsInWorld(node);
      if (b != null) acc(b);
    }
    if (minX == double.infinity) return;

    final bbox = Rect.fromLTRB(minX, minY, maxX, maxY);
    final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
    if (editorBounds == null) return;
    final size = editorBounds.size;
    if (bbox.width <= 0 || bbox.height <= 0) return;

    const margin = 0.85;
    final zoom = (min(size.width / bbox.width, size.height / bbox.height) * margin)
        .clamp(1e-4, 2.0);
    _canvasBloc.add(CanvasTransformed(zoom: zoom, offset: -bbox.center));
  }

  double _computeMinZoom() {
    final objects = _canvasBloc.state.drawingObjects;
    if (objects.isEmpty) return 1e-7;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final obj in objects.values) {
      final r = obj.rect;
      if (r.left < minX) minX = r.left;
      if (r.top < minY) minY = r.top;
      if (r.right > maxX) maxX = r.right;
      if (r.bottom > maxY) maxY = r.bottom;
    }
    final worldDim = max(maxX - minX, maxY - minY);
    if (worldDim <= 0) return 1e-7;
    return 32.0 / worldDim;
  }

  @override
  void initState() {
    super.initState();
    _canvasBloc = context.read<CanvasBloc>();
    _selectionBloc = context.read<SelectionBloc>();
    _toolBloc = context.read<ToolBloc>();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_globalPointerRoute);
    _registerServiceExtensions();
    // Tidy is triggered from the toolbar via the bloc's tidyRequests stream,
    // but the layout needs rendered node geometry, so the data layer runs it.
    _autoLayoutReqSub = _canvasBloc.tidyRequests.listen((_) {
      if (mounted) _applyAutoLayout();
    });
    _layoutAlongGuideReqSub =
        _canvasBloc.layoutAlongGuideRequests.listen((_) {
      if (mounted) _layoutSelectionAlongSelectedGuide();
    });
    _swapReqSub = _canvasBloc.swapRequests.listen((_) {
      if (mounted) _swapSelection();
    });
    // Rebuild when keyboard focus moves so the canvas shortcut bindings can be
    // suppressed while a text input (incl. external overlays like the flan
    // annotation box) is focused — letting it receive Cmd/Ctrl+V/C/X natively.
    FocusManager.instance.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  StreamSubscription<void>? _autoLayoutReqSub;
  StreamSubscription<void>? _layoutAlongGuideReqSub;
  StreamSubscription<void>? _swapReqSub;

  static bool _serviceExtensionsRegistered = false;

  /// Registers VM service extensions that let an external agent (e.g. via Flan)
  /// read review comments and resolve a screen point to the entity under it,
  /// without taking screenshots. Closes the human→agent feedback loop: a human
  /// points at a connector ("can't drag this"), and the agent resolves that to
  /// an unambiguous entity id, type, and geometry.
  void _registerServiceExtensions() {
    if (_serviceExtensionsRegistered) return;
    _serviceExtensionsRegistered = true;

    // ext.fldraw.comments — returns every comment with its resolved entity
    // metadata (kind, label, endpoints, and current rendered path for arrows).
    developer.registerExtension('ext.fldraw.comments', (method, params) async {
      final ordered = _canvasBloc.state.comments.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final list = <Map<String, dynamic>>[];
      for (var i = 0; i < ordered.length; i++) {
        final c = ordered[i];
        list.add({
          'index': i + 1,
          ...c.toJson(),
          'entity': _describeEntity(c.targetId),
        });
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'comments': list}),
      );
    });

    // ext.fldraw.entityAt — resolves screen coordinates (x, y) to the entity
    // under that point. Pass params {x, y}. Returns the same entity description
    // used by comments, so an annotation dropped anywhere can be identified.
    developer.registerExtension('ext.fldraw.entityAt', (method, params) async {
      final x = double.tryParse(params['x'] ?? '');
      final y = double.tryParse(params['y'] ?? '');
      if (x == null || y == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          'entityAt requires numeric x and y params (screen coordinates)',
        );
      }
      final worldPos = screenToWorld(
        Offset(x, y),
        _canvasBloc.state.viewportOffset,
        _canvasBloc.state.viewportZoom,
      );
      final hitId = worldPos == null ? null : _findHitObject(worldPos);
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'screen': {'x': x, 'y': y},
          'world': worldPos == null ? null : {'x': worldPos.dx, 'y': worldPos.dy},
          'entity': _describeEntity(hitId),
        }),
      );
    });

    // ext.fldraw.autoLayout — trigger the layered "Tidy" auto-layout
    // programmatically (same as the Cmd/Ctrl+Shift+L shortcut).
    developer.registerExtension('ext.fldraw.autoLayout', (method, params) async {
      _applyAutoLayout();
      return developer.ServiceExtensionResponse.result(jsonEncode({'ok': true}));
    });
  }

  /// Builds a JSON-able description of the entity with [id], or a `canvas`
  /// placeholder when [id] is null (a bare-canvas hit).
  Map<String, dynamic> _describeEntity(String? id) {
    if (id == null) {
      return {'id': null, 'kind': 'canvas'};
    }
    final obj = _canvasBloc.state.drawingObjects[id];
    if (obj is ArrowObject) {
      return {
        'id': id,
        'kind': 'arrow',
        'label': obj.arrowLabel,
        'pathType': obj.pathType.name,
        'source': obj.startAttachment?.objectId,
        'target': obj.endAttachment?.objectId,
        'renderedPath': obj.renderedPath
            ?.map((p) => [p.dx, p.dy])
            .toList(),
      };
    }
    if (obj is LineObject) {
      return {
        'id': id,
        'kind': 'line',
        'source': obj.startAttachment?.objectId,
        'target': obj.endAttachment?.objectId,
      };
    }
    if (obj != null) {
      final rect = obj.rect;
      String? label;
      if (obj is RectangleObject) {
        label = obj.text;
      } else if (obj is CircleObject) {
        label = obj.text;
      } else if (obj is DiamondObject) {
        label = obj.text;
      } else if (obj is TextObject) {
        label = obj.text;
      }
      return {
        'id': id,
        'kind': 'shape',
        'type': obj.runtimeType.toString(),
        if (label != null) 'label': label,
        'rect': [rect.left, rect.top, rect.width, rect.height],
      };
    }
    final node = _canvasBloc.state.nodes[id];
    if (node != null) {
      final nb = getNodeBoundsInWorld(node);
      return {
        'id': id,
        'kind': 'node',
        'heading': node.heading,
        'value': node.value,
        if (nb != null) 'rect': [nb.left, nb.top, nb.width, nb.height],
      };
    }
    return {'id': id, 'kind': 'unknown'};
  }

  void _globalPointerRoute(PointerEvent event) {
    if (!mounted) return;
    if (event is PointerPanZoomStartEvent) {
      _onPointerPanZoomStart(event);
    } else if (event is PointerPanZoomUpdateEvent) {
      _onPointerPanZoomUpdate(event);
    } else if (event is PointerPanZoomEndEvent) {
      _onPointerPanZoomEnd(event);
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_globalPointerRoute);
    _autoLayoutReqSub?.cancel();
    _layoutAlongGuideReqSub?.cancel();
    _swapReqSub?.cancel();
    FocusManager.instance.removeListener(_onFocusChanged);
    _canvasFocusNode.dispose();
    _kineticTimer?.cancel();
    if (activeTextEditing.value == _shapeTextController) {
      activeTextEditing.value = null;
    }
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

    // Holding Shift suppresses snapping entirely, giving a free-drag escape
    // hatch — essential in dense diagrams where an endpoint would otherwise be
    // captured by some node border on almost every move.
    final bool snapSuppressed = HardwareKeyboard.instance.isShiftPressed;

    bool shouldCheckForSnapping = !snapSuppressed &&
        (((tool == EditorTool.arrowTopRight || tool == EditorTool.line) &&
                !_isDrawing) ||
            (_isDrawing &&
                (_tempDrawingObject?.tool == EditorTool.arrowTopRight ||
                    _tempDrawingObject?.tool == EditorTool.line)) ||
            (_isResizing.handle == Handle.arrowStart ||
                _isResizing.handle == Handle.arrowEnd));
    if (!shouldCheckForSnapping) {
      if (_hoveredSnapPoint != null) {
        setState(() => _hoveredSnapPoint = null);
      }
      return;
    }

    final tolerance = 10.0 / canvasState.viewportZoom;

    // Frames (FigureObjects) are large containers that enclose other nodes. A
    // frame border is almost always within snap range of any node sitting
    // inside it, so a flat "nearest border wins" search makes the frame steal
    // connections meant for the inner node. Track frame candidates separately
    // and only fall back to a frame when nothing else is snappable — so you can
    // always connect to a node inside a frame.
    SnapPoint? bestNonFrame;
    double bestNonFrameDist = double.infinity;
    SnapPoint? bestFrame;
    double bestFrameDist = double.infinity;

    SnapPoint snapOnRect(String objectId, Rect rect) {
      final closestPoint = getClosestPointOnRectBorder(worldPos, rect);
      return (
        objectId: objectId,
        worldPosition: closestPoint,
        relativePosition: Offset(
          (closestPoint.dx - rect.left) /
              rect.width.clamp(0.001, double.infinity),
          (closestPoint.dy - rect.top) /
              rect.height.clamp(0.001, double.infinity),
        ),
      );
    }

    for (final obj in canvasState.drawingObjects.values) {
      if (obj.id == _isResizing.objectId) continue;
      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is FigureObject ||
          obj is SvgObject) {
        final distance = distanceToRectBorder(worldPos, obj.rect);
        if (distance >= tolerance) continue;
        if (obj is FigureObject) {
          if (distance < bestFrameDist) {
            bestFrameDist = distance;
            bestFrame = snapOnRect(obj.id, obj.rect);
          }
        } else if (distance < bestNonFrameDist) {
          bestNonFrameDist = distance;
          bestNonFrame = snapOnRect(obj.id, obj.rect);
        }
      }
    }

    for (final node in canvasState.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds == null) continue;
      final distance = distanceToRectBorder(worldPos, nodeBounds);
      if (distance < tolerance && distance < bestNonFrameDist) {
        bestNonFrameDist = distance;
        bestNonFrame = snapOnRect(node.id, nodeBounds);
      }
    }

    // Prefer any non-frame target; only snap to a frame when nothing else is
    // in range.
    final SnapPoint? newSnapPoint = bestNonFrame ?? bestFrame;

    if (newSnapPoint != _hoveredSnapPoint) {
      // Always track the CURRENT nearest snap point (or null when the cursor
      // leaves every snap band). The old code returned early when both an
      // existing start-snap and a new snap were present, which froze
      // _hoveredSnapPoint at its first value and made a dragged endpoint stick
      // to whatever it first snapped to — you couldn't drag back out.
      _hoveredSnapPoint = newSnapPoint;
      if (shouldCheckForSnapping && _startSnapPoint == null && newSnapPoint != null) {
        _startSnapPoint = newSnapPoint;
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
    _scaleStartZoom = _canvasBloc.state.viewportZoom;
    if (details.pointerCount > 1) {
      _isScaling = true;
      setState(() {
        _isAreaSelecting = false;
        _isDrawing = false;
        _tempDrawingObject = null;
        _selectionArea = Rect.zero;
      });
      _onPanStart();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Only handle genuine multi-touch (e.g. touchscreen). Trackpad pinch is
    // handled via onPointerPanZoomUpdate in the Listener instead.
    if (details.pointerCount < 2) return;

    final state = _canvasBloc.state;
    final newZoom = (_scaleStartZoom * details.scale).clamp(_computeMinZoom(), double.infinity);

    final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
    if (editorBounds == null) return;

    final focalPointRelativeToCenter = details.focalPoint - editorBounds.center;
    final zoomPanCorrection =
        focalPointRelativeToCenter * (1 / newZoom - 1 / state.viewportZoom);
    final panDelta = details.focalPointDelta / state.viewportZoom;
    final newOffset = state.viewportOffset + panDelta + zoomPanCorrection;

    _canvasBloc.add(CanvasTransformed(zoom: newZoom, offset: newOffset));
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isScaling) {
      _isScaling = false;
      _onPanEnd();
    }
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _scaleStartZoom = _canvasBloc.state.viewportZoom;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // Pure pan (no pinch) is already handled by PointerScrollEvent in
    // _onPointerSignal. Only handle scale changes here to avoid double-applying
    // pan and incorrectly snapping zoom when scale == 1.0.
    if (event.scale == 1.0) return;
    final state = _canvasBloc.state;
    final newZoom = (_scaleStartZoom * event.scale).clamp(_computeMinZoom(), double.infinity);
    final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
    if (editorBounds == null) return;
    final focalPointRelativeToCenter = event.position - editorBounds.center;
    final zoomPanCorrection =
        focalPointRelativeToCenter * (1 / newZoom - 1 / state.viewportZoom);
    final panDelta = event.panDelta / state.viewportZoom;
    final newOffset = state.viewportOffset + panDelta + zoomPanCorrection;
    _canvasBloc.add(CanvasTransformed(zoom: newZoom, offset: newOffset));
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {}

  void _onPointerSignal(PointerSignalEvent event) {
    if (_isPanning) return;
    if (event is PointerScrollEvent) {
      final state = _canvasBloc.state;
      final isZoomModifier = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (isZoomModifier) {
        final zoomDelta = -event.scrollDelta.dy * 0.001;
        final newZoom = state.viewportZoom * (1 + zoomDelta);
        _canvasBloc.add(CanvasZoomed(newZoom.clamp(_computeMinZoom(), double.infinity)));
      } else {
        final panDelta = Offset(event.scrollDelta.dx, event.scrollDelta.dy) / state.viewportZoom;
        _canvasBloc.add(CanvasPanned(-panDelta));
      }
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

    // Match the render sizes from _paintQuickActionArrows exactly
    final double iz = (1.0 / zoom).clamp(0.5, 2.0);
    final double handleSize = 20.0 * iz;
    final double halfHandle = handleSize / 2;
    final double spacing = 10.0 * iz;

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

  /// True when a text input currently holds the keyboard focus — including
  /// inputs we don't own (e.g. the flan annotation overlay, dialogs, the
  /// Mermaid/Text-to-Diagram fields). When one is focused the canvas must NOT
  /// claim Cmd/Ctrl+V (and C/X) as shortcuts, or it swallows the paste before
  /// the field receives it. `_isEditingText`/`_editingShapeObject` only cover
  /// our own editors, so this catches everything else.
  bool get _textInputHasFocus {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Copies the current selection to the clipboard. Prefers the diagram's
  /// drawing objects (shapes/connectors/text); falls back to the node-editor
  /// clipboard when only nodes are selected. Returns true if anything was
  /// copied.
  Future<bool> _copySelection(
      CanvasState canvasState, SelectionState selectionState) async {
    final selectedDrawing = selectionState.selectedDrawingObjectIds
        .map((id) => canvasState.drawingObjects[id])
        .whereType<DrawingObject>()
        .toList();
    if (selectedDrawing.isNotEmpty) {
      final copied = await ClipboardService.copyDrawingObjects(selectedDrawing);
      return copied != null;
    }
    final copied = await ClipboardService.copySelection(
      allNodes: canvasState.nodes,
      selectedNodeIds: selectionState.selectedNodeIds,
    );
    return copied != null;
  }

  /// Pastes clipboard contents at the current cursor position and selects any
  /// newly pasted drawing objects.
  void _pasteAtCursor(CanvasState canvasState) {
    final worldPos = screenToWorld(
          _lastFocalPoint,
          canvasState.viewportOffset,
          canvasState.viewportZoom,
        ) ??
        Offset.zero;
    _canvasBloc.add(SelectionPasted(pastePosition: worldPos));
    // The paste resolves asynchronously (it awaits a clipboard read), so the
    // pasted IDs aren't available this frame. Poll a few times for them, then
    // select the new objects so they can be moved/styled immediately.
    _selectPastedObjectsWhenReady(8);
  }

  void _selectPastedObjectsWhenReady(int attemptsLeft) {
    final pastedIds = _canvasBloc.consumeLastPastedDrawingObjectIds();
    if (pastedIds.isNotEmpty) {
      if (mounted) {
        _selectionBloc.add(SelectionReplaced(drawingObjectIds: pastedIds));
      }
      return;
    }
    if (attemptsLeft <= 0 || !mounted) return;
    Future.delayed(const Duration(milliseconds: 16), () {
      if (mounted) _selectPastedObjectsWhenReady(attemptsLeft - 1);
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    // If text overlay is active, let the TextField handle all pointer events
    if (_isEditingText) return;

    // If inline shape text editor is active, check if the tap is inside
    // the editing shape — if so, let the TextField handle pointer events
    // (for cursor repositioning). Otherwise finish editing.
    if (_editingShapeObject != null) {
      final worldPos = screenToWorld(
        event.position,
        _canvasBloc.state.viewportOffset,
        _canvasBloc.state.viewportZoom,
      );
      if (worldPos != null && _editingShapeObject!.rect.contains(worldPos)) {
        return; // Let the TextField handle this tap
      }
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

    // A click on a comment pin opens its popup (view / resolve / delete),
    // regardless of the active tool. Checked FIRST — before resize handles and
    // tool handling — so a deliberate click on a pin always wins over the node
    // it sits on (pins overlap their target, especially when zoomed out).
    if (event.buttons == kPrimaryMouseButton) {
      final pinComment = _findCommentAt(worldPos);
      if (pinComment != null) {
        _openCommentPopup(pinComment, event.position);
        return;
      }
    }

    // Update hovered handle from tap position before checking —
    // on touch devices there are no hover events, so the handle
    // state can be stale from a previous interaction.
    _updateHoveredHandle(event.position);
    // Check resize/rotation handles for any tool when something is selected,
    // so objects can always be resized/rotated regardless of active tool.
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

    if (_checkAndHandleQuickAction(worldPos)) {
      return;
    }

    if (tool == EditorTool.comment) {
      _handleCommentToolPointerDown(worldPos);
    } else if (tool == EditorTool.arrow) {
      _handleArrowToolPointerDown(event, worldPos);
    } else {
      _handleDrawingToolPointerDown(event, worldPos);
    }
  }

  /// Resolves the entity under [worldPos] and opens a small text overlay to
  /// attach a review comment to it. For arrows we also capture the source/target
  /// connections and the polyline actually drawn, so feedback about dragging or
  /// routing references the real geometry.
  void _handleCommentToolPointerDown(Offset worldPos) {
    final hitId = _findHitObject(worldPos);

    CommentTargetType targetType = CommentTargetType.canvas;
    String? sourceObjectId;
    String? targetObjectId;
    List<Offset>? renderedPath;

    if (hitId != null) {
      final obj = _canvasBloc.state.drawingObjects[hitId];
      if (obj is ArrowObject) {
        targetType = CommentTargetType.arrow;
        sourceObjectId = obj.startAttachment?.objectId;
        targetObjectId = obj.endAttachment?.objectId;
        renderedPath = obj.renderedPath != null
            ? List<Offset>.from(obj.renderedPath!)
            : null;
      } else if (obj is LineObject) {
        targetType = CommentTargetType.line;
        sourceObjectId = obj.startAttachment?.objectId;
        targetObjectId = obj.endAttachment?.objectId;
      } else if (obj != null) {
        targetType = CommentTargetType.shape;
      } else if (_canvasBloc.state.nodes.containsKey(hitId)) {
        targetType = CommentTargetType.node;
      }
    }

    _beginCommentEditing(
      anchorWorld: worldPos,
      targetId: hitId,
      targetType: targetType,
      sourceObjectId: sourceObjectId,
      targetObjectId: targetObjectId,
      renderedPath: renderedPath,
    );
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
      if (obj is TextObject &&
          _textHitRect(obj).inflate(hitPadding).contains(worldPos)) {
        _beginTextEditing(existingObject: obj);
        return;
      }
      if ((obj is RectangleObject || obj is CircleObject || obj is DiamondObject || obj is ParallelogramObject) &&
          obj.rect.inflate(hitPadding).contains(worldPos)) {
        _beginShapeTextEditing(obj);
        return;
      }
    }

    // Double-clicking an edge edits its label. Reuse the connection hit-test so
    // it matches what a click would select, then prompt for the label text.
    final hitId = _findHitObject(worldPos);
    if (hitId != null) {
      final hit = _canvasBloc.state.drawingObjects[hitId];
      if (hit is ArrowObject) {
        _editArrowLabel(hit);
      }
    }
  }

  /// Prompts for [arrow]'s label text and commits the change (empty clears it).
  Future<void> _editArrowLabel(ArrowObject arrow) async {
    final controller = TextEditingController(text: arrow.arrowLabel ?? '');
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edge label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Label (leave empty to remove)'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newLabel == null) return; // cancelled
    final trimmed = newLabel.trim();
    final updated = (trimmed.isEmpty
        ? arrow.copyWith(clearArrowLabel: true)
        : arrow.copyWith(arrowLabel: trimmed)) as ArrowObject;
    _canvasBloc.add(DrawingObjectUpdated(updated));
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

    // Check if any selected objects are arrows or lines
    final bool hasArrowSelected = selectedIds.any((id) {
      final obj = _canvasBloc.state.drawingObjects[id];
      return obj is ArrowObject || obj is LineObject;
    });

    showCanvasContextMenu(
      context: context,
      position: event.position,
      hasSelection: hasSelection,
      selectedCount: selectedIds.length,
      hasArrowSelected: hasArrowSelected,
      canSwap: _canSwapSelection(),
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
          case CanvasContextMenuAction.flipArrow:
            for (final id in ids) {
              final obj = _canvasBloc.state.drawingObjects[id];
              if (obj is ArrowObject) {
                final flipped = ArrowObject(
                  id: obj.id,
                  start: obj.end,
                  end: obj.start,
                  isSelected: obj.isSelected,
                  midPoint: obj.midPoint,
                  pathType: obj.pathType,
                  startAttachment: obj.endAttachment,
                  endAttachment: obj.startAttachment,
                  waypoints: obj.waypoints?.reversed.toList(),
                  lineStyle: obj.lineStyle,
                  arrowLabel: obj.arrowLabel,
                  angle: obj.angle,
                );
                _canvasBloc.add(DrawingObjectUpdated(flipped));
              } else if (obj is LineObject) {
                final flipped = LineObject(
                  id: obj.id,
                  start: obj.end,
                  end: obj.start,
                  isSelected: obj.isSelected,
                  midPoint: obj.midPoint,
                  startAttachment: obj.endAttachment,
                  endAttachment: obj.startAttachment,
                  lineStyle: obj.lineStyle,
                  angle: obj.angle,
                );
                _canvasBloc.add(DrawingObjectUpdated(flipped));
              }
            }
          case CanvasContextMenuAction.swap:
            _swapSelection();
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

  /// True when a modifier that means "add to / toggle the current selection"
  /// is held. Shift is the classic one; Cmd (meta, macOS) and Ctrl (other
  /// platforms) now behave the same way for multi-select.
  bool get _additiveSelectModifier =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  void _handleArrowToolPointerDown(PointerDownEvent event, Offset worldPos) {
    final hitObjectId = _findHitObject(worldPos);
    if (hitObjectId != null) {
      final isShiftPressed = _additiveSelectModifier;
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

      // Show a preview temp line for endpoint drags; midpoint updates live.
      if (handle == Handle.arrowStart || handle == Handle.arrowEnd) {
        // Shift = free drag: skip object-snap (cleared in _updateSnapHandle)
        // AND grid-snap, so the endpoint follows the cursor exactly.
        final dragPos = _hoveredSnapPoint?.worldPosition ??
            (HardwareKeyboard.instance.isShiftPressed
                ? worldPos
                : snapOffset(worldPos));
        final tempStart = handle == Handle.arrowStart ? dragPos : start;
        final tempEnd = handle == Handle.arrowEnd ? dragPos : end;

        List<Offset>? waypoints;
        if (pathType == LinkPathType.orthogonal) {
          final obstacles = _collectObstacles(excludeId: objectId);
          // The dragged endpoint will attach to whatever it's hovering on drop,
          // so route the preview against that target's rect (not null) — this
          // is what the final render does, so the preview matches the drop.
          final draggedEndRect = _getSnapPointObjectRect(_hoveredSnapPoint);
          final startObjRect = handle == Handle.arrowStart
              ? draggedEndRect
              : _getAttachedObjectRect(object.startAttachment);
          final endObjRect = handle == Handle.arrowEnd
              ? draggedEndRect
              : _getAttachedObjectRect(object.endAttachment);
          waypoints = OrthogonalRouter.route(
            start: tempStart,
            end: tempEnd,
            obstacles: obstacles,
            startObjectRect: startObjRect,
            endObjectRect: endObjRect,
            devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
            zoom: _canvasBloc.state.viewportZoom,
            existingSegments: _collectRoutedSegments(excludeId: objectId),
          );
        }

        setState(() {
          _tempDrawingObject = TempDrawingObject(
            tool: EditorTool.arrowTopRight,
            start: tempStart,
            end: tempEnd,
            pathType: pathType,
            waypoints: waypoints,
          );
        });
        return;
      }

      if (pathType == LinkPathType.orthogonal) {
        Offset newStart = start;
        Offset newEnd = end;

        if (handle == Handle.midPoint) {
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

      } else {
        if (handle == Handle.midPoint) {
          final midPoint = (worldPos * 2) - (start * 0.5) - (end * 0.5);
          final updatedObject = object.copyWith(midPoint: midPoint);
          _canvasBloc.add(DrawingObjectUpdated(updatedObject));
        }
      }
      return;
    } else if (object is LineObject) {
      final (start, end) = _getDynamicEndpoints(object);

      if (_isResizing.handle == Handle.arrowStart || _isResizing.handle == Handle.arrowEnd) {
        final dragPos = _hoveredSnapPoint?.worldPosition ??
            (HardwareKeyboard.instance.isShiftPressed
                ? worldPos
                : snapOffset(worldPos));
        final tempStart = _isResizing.handle == Handle.arrowStart ? dragPos : start;
        final tempEnd = _isResizing.handle == Handle.arrowEnd ? dragPos : end;
        setState(() {
          _tempDrawingObject = TempDrawingObject(
            tool: EditorTool.line,
            start: tempStart,
            end: tempEnd,
          );
        });
      } else if (_isResizing.handle == Handle.midPoint) {
        final midPoint = (worldPos * 2) - (start * 0.5) - (end * 0.5);
        final updatedObject = object.copyWith(midPoint: midPoint);
        _canvasBloc.add(DrawingObjectUpdated(updatedObject));
      }
    } else if (object is RectangleObject ||
        object is CircleObject ||
        object is FigureObject ||
        object is SvgObject ||
        object is TextObject) {
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
        // Resizing the box only changes the rect; the font size is governed by
        // the font size setting, not the box dimensions.
        updatedObject = object.copyWith(rect: newRect);
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

  /// The rect a [TextObject] actually occupies on screen. Its [rect] only bounds
  /// the layout width; large text overflows it, so hit-testing against the bare
  /// rect makes big text unselectable. The canvas paints from [rect].topLeft via
  /// [layoutPainter], so the clickable extent is the union of the rect and the
  /// laid-out painter size.
  Rect _textHitRect(TextObject obj) {
    final painter = obj.layoutPainter();
    return obj.rect.expandToInclude(
      Rect.fromLTWH(
        obj.rect.left,
        obj.rect.top,
        painter.width,
        painter.height,
      ),
    );
  }

  Rect? _getAttachedObjectRect(ObjectAttachment? attachment) {
    if (attachment == null) return null;
    final canvasState = _canvasBloc.state;
    final targetNode = canvasState.nodes[attachment.objectId];
    final targetObject = canvasState.drawingObjects[attachment.objectId];
    if (targetNode != null) return getNodeBoundsInWorld(targetNode);
    return targetObject?.rect;
  }

  /// World rect of the object a hovered snap point sits on, or null if none.
  /// Used so a drag preview routes against the same target rect the endpoint
  /// will attach to on drop.
  Rect? _getSnapPointObjectRect(SnapPoint? snapPoint) {
    if (snapPoint == null) return null;
    final canvasState = _canvasBloc.state;
    final targetNode = canvasState.nodes[snapPoint.objectId];
    if (targetNode != null) return getNodeBoundsInWorld(targetNode);
    return canvasState.drawingObjects[snapPoint.objectId]?.rect;
  }

  /// Segments of every other arrow/line's currently-rendered path, so a drag
  /// preview routes around them exactly as the final render does.
  List<(Offset, Offset)> _collectRoutedSegments({String? excludeId}) {
    final segments = <(Offset, Offset)>[];
    for (final obj in _canvasBloc.state.drawingObjects.values) {
      if (obj.id == excludeId) continue;
      if (obj is! ArrowObject) continue;
      final path = obj.renderedPath;
      if (path == null || path.length < 2) continue;
      for (int i = 0; i < path.length - 1; i++) {
        segments.add((path[i], path[i + 1]));
      }
    }
    return segments;
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
      final holdSelection = _additiveSelectModifier;
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
    } else if (!_additiveSelectModifier) {
      _selectionBloc.add(SelectionCleared());
    }
    setState(() {
      _isAreaSelecting = false;
      _selectionArea = Rect.zero;
    });
  }

  // ---- Lay-selected-nodes-along-a-guide feature -----------------------
  // Workflow: draw a guide (pencil stroke, line/arrow, or circle/rect/diamond/
  // parallelogram outline) as a normal object, select it TOGETHER with the
  // boxes to arrange, then press Cmd/Ctrl+Shift+P. The selected boxes are
  // distributed along the guide; the guide object is left on the canvas.
  //
  // This is selection-driven (not modifier-during-drag): on macOS the canvas
  // never sees a held Option key mid-drag, so the earlier Alt approach could
  // not arm reliably.

  /// World-space rect of a box (node or shape drawing object), or null if [id]
  /// is not an arrangeable box (edges/lines/pencil are guides, not boxes).
  Rect? _layoutBoxRect(String id) {
    final node = _canvasBloc.state.nodes[id];
    if (node != null) {
      return getNodeBoundsInWorld(node) ??
          Rect.fromLTWH(node.offset.dx, node.offset.dy, 120, 48);
    }
    final obj = _canvasBloc.state.drawingObjects[id];
    if (obj == null) return null;
    if (obj is ArrowObject || obj is LineObject || obj is PencilStrokeObject) {
      return null;
    }
    return obj.rect;
  }

  /// Flattens a committed drawing object into a world-space polyline plus a
  /// closed/open flag, when it can act as a layout guide. Returns null for
  /// objects that aren't usable guides (boxes, degenerate geometry).
  (List<Offset>, bool)? _guidePolylineFromObject(DrawingObject obj) {
    if (obj is PencilStrokeObject) {
      final pts = [for (final p in obj.points) Offset(p.x, p.y)];
      return pts.length >= 2 ? (pts, false) : null;
    }
    if (obj is ArrowObject) {
      // Prefer the actual routed path (handles curved/orthogonal arrows);
      // fall back to start→waypoints→end.
      final rp = obj.renderedPath;
      if (rp != null && rp.length >= 2) return (List<Offset>.of(rp), false);
      final pts = <Offset>[obj.start, ...?obj.waypoints, obj.end];
      return pts.length >= 2 ? (pts, false) : null;
    }
    if (obj is LineObject) {
      if ((obj.end - obj.start).distance < 1) return null;
      return ([obj.start, obj.end], false);
    }

    // Closed shape outlines.
    final rect = obj.rect;
    if (rect.shortestSide < 1) return null;
    if (obj is CircleObject) {
      final c = rect.center;
      final rx = rect.width / 2;
      final ry = rect.height / 2;
      const segments = 120;
      return ([
        for (int i = 0; i < segments; i++)
          Offset(
            c.dx + rx * cos(2 * pi * i / segments),
            c.dy + ry * sin(2 * pi * i / segments),
          ),
      ], true);
    }
    if (obj is RectangleObject) {
      return ([
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ], true);
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

  /// A "strong" guide is a shape you'd deliberately draw *as* a path — a pen
  /// stroke, line/arrow, circle, diamond, or parallelogram. Plain rectangles
  /// are NOT strong guides: they're the usual node shape, so a circle drawn
  /// around a column of rectangle nodes must resolve to the circle, not "many
  /// guides". A rectangle is only used as a guide when nothing stronger is
  /// selected.
  bool _isStrongGuide(DrawingObject obj) =>
      obj is PencilStrokeObject ||
      obj is ArrowObject ||
      obj is LineObject ||
      obj is CircleObject ||
      obj is DiamondObject ||
      obj is ParallelogramObject;

  /// "Lay on path": lay the selected boxes out along the single selected guide
  /// object. Emits one undoable [AutoLayoutApplied]; leaves the guide on the
  /// canvas. No-op (with a toast) when the selection isn't one guide plus at
  /// least one box.
  void _layoutSelectionAlongSelectedGuide() {
    final sel = _selectionBloc.state;
    final objIds = sel.selectedDrawingObjectIds;

    // Classify selected drawing objects into strong guides (pen/line/arrow/
    // circle/diamond/parallelogram) and weak guides (rectangles). A rectangle
    // only counts as the guide when no strong guide is present, so circle +
    // rectangle nodes resolves unambiguously to the circle.
    final strong = <(DrawingObject, List<Offset>, bool)>[];
    final weak = <(DrawingObject, List<Offset>, bool)>[];
    for (final id in objIds) {
      final obj = _canvasBloc.state.drawingObjects[id];
      if (obj == null) continue;
      final g = _guidePolylineFromObject(obj);
      if (g == null) continue;
      (_isStrongGuide(obj) ? strong : weak).add((obj, g.$1, g.$2));
    }

    final guides = strong.isNotEmpty ? strong : weak;

    if (guides.isEmpty) {
      showNodeEditorSnackbar(
          'Select a guide (pen stroke, line, circle, diamond, or '
          'parallelogram) plus the nodes to arrange, then click "Lay on path" '
          '(⇧⌘U).',
          SnackbarType.info);
      return;
    }
    if (guides.length > 1) {
      showNodeEditorSnackbar(
          'Select exactly one guide shape to lay nodes along (the rest of the '
          'selection is treated as nodes).',
          SnackbarType.warning);
      return;
    }
    final (guideObj, polyline, closed) = guides.first;

    // The boxes to arrange: every selected node, plus selected shape objects
    // that aren't the guide itself.
    final centres = <String, Offset>{};
    final rects = <String, Rect>{};
    for (final id in sel.selectedNodeIds) {
      final r = _layoutBoxRect(id);
      if (r == null) continue;
      centres[id] = r.center;
      rects[id] = r;
    }
    for (final id in objIds) {
      if (id == guideObj.id) continue;
      final r = _layoutBoxRect(id);
      if (r == null) continue;
      centres[id] = r.center;
      rects[id] = r;
    }

    if (centres.isEmpty) {
      showNodeEditorSnackbar(
          'Also select the nodes to lay along the guide.', SnackbarType.info);
      return;
    }

    final newCentres = PathLayout.distribute(
      boxes: centres,
      polyline: polyline,
      closed: closed,
    );
    if (newCentres.isEmpty) return;

    // AutoLayoutApplied takes top-left offsets; convert from centre using each
    // box's size.
    final offsets = <String, Offset>{};
    newCentres.forEach((id, centre) {
      final r = rects[id]!;
      offsets[id] = Offset(centre.dx - r.width / 2, centre.dy - r.height / 2);
    });

    _canvasBloc.add(AutoLayoutApplied(offsets));
  }

  // ---- Swap feature ----------------------------------------------------
  // "Swap" acts on exactly two selected things:
  //   * two nodes/shapes  → exchange their centre positions (sizes unchanged;
  //     attached edges re-route automatically).
  //   * two edges (arrows/lines) → exchange their END endpoints (world point +
  //     attachment), so each edge ends where the other did.

  /// True when the current selection is something Swap can act on. Drives the
  /// toolbar button's enabled state and the context-menu item's visibility.
  bool _canSwapSelection() => _swapKind() != _SwapKind.none;

  _SwapKind _swapKind() {
    final sel = _selectionBloc.state;
    final objIds = sel.selectedDrawingObjectIds;
    final nodeIds = sel.selectedNodeIds;

    // Two edges (and nothing else)?
    if (nodeIds.isEmpty && objIds.length == 2) {
      final objs = [
        for (final id in objIds) _canvasBloc.state.drawingObjects[id],
      ];
      if (objs.every((o) => o is ArrowObject || o is LineObject)) {
        return _SwapKind.endpoints;
      }
    }

    // Two boxes (nodes and/or non-edge shapes), nothing else?
    final boxIds = <String>[
      ...nodeIds,
      for (final id in objIds)
        if (_layoutBoxRect(id) != null) id,
    ];
    final hasEdge = objIds.any((id) {
      final o = _canvasBloc.state.drawingObjects[id];
      return o is ArrowObject || o is LineObject;
    });
    if (!hasEdge &&
        boxIds.length == 2 &&
        nodeIds.length + objIds.length == 2) {
      return _SwapKind.nodes;
    }
    return _SwapKind.none;
  }

  /// Swap action shared by the toolbar button, the shortcut, and the context
  /// menu. Picks node-swap or endpoint-swap from the selection; shows a hint
  /// when neither applies.
  void _swapSelection() {
    switch (_swapKind()) {
      case _SwapKind.nodes:
        _swapTwoBoxes();
      case _SwapKind.endpoints:
        _swapTwoEdgeEndpoints();
      case _SwapKind.none:
        showNodeEditorSnackbar(
            'Select exactly two nodes (to swap positions) or two edges (to '
            'swap their endpoints), then Swap.',
            SnackbarType.info);
    }
  }

  /// Exchanges the centre positions of the two selected boxes. Emits one
  /// undoable [AutoLayoutApplied]; sizes are preserved.
  void _swapTwoBoxes() {
    final sel = _selectionBloc.state;
    final ids = <String>[...sel.selectedNodeIds, ...sel.selectedDrawingObjectIds];
    final rects = <String, Rect>{};
    for (final id in ids) {
      final r = _layoutBoxRect(id);
      if (r != null) rects[id] = r;
    }
    final offsets = SwapLayout.swapBoxCentres(rects);
    if (offsets.isEmpty) return;
    _canvasBloc.add(AutoLayoutApplied(offsets));
  }

  /// Exchanges the END endpoints (world point + attachment) of the two selected
  /// edges, so each edge ends where the other did. Emits one
  /// [DrawingObjectUpdated] per edge.
  void _swapTwoEdgeEndpoints() {
    final ids = _selectionBloc.state.selectedDrawingObjectIds.toList();
    if (ids.length != 2) return;
    final objA = _canvasBloc.state.drawingObjects[ids[0]];
    final objB = _canvasBloc.state.drawingObjects[ids[1]];

    // Snapshot each edge's end (point + attachment), then cross-assign.
    final endA = _edgeEnd(objA);
    final endB = _edgeEnd(objB);
    if (endA == null || endB == null) return;

    final newA = _withEnd(objA!, point: endB.$1, attachment: endB.$2);
    final newB = _withEnd(objB!, point: endA.$1, attachment: endA.$2);
    if (newA != null) _canvasBloc.add(DrawingObjectUpdated(newA));
    if (newB != null) _canvasBloc.add(DrawingObjectUpdated(newB));
  }

  /// The (end point, end attachment) of an edge, or null if not an edge.
  (Offset, ObjectAttachment?)? _edgeEnd(DrawingObject? obj) {
    if (obj is ArrowObject) return (obj.end, obj.endAttachment);
    if (obj is LineObject) return (obj.end, obj.endAttachment);
    return null;
  }

  /// Returns a copy of [obj] with its end point + attachment replaced. The
  /// routed [waypoints]/[renderedPath] cache is dropped so the arrow re-routes
  /// to the new endpoint.
  DrawingObject? _withEnd(
    DrawingObject obj, {
    required Offset point,
    required ObjectAttachment? attachment,
  }) {
    // Reconstruct with the new end point/attachment. Carry ALL other
    // attributes — including strokeColor, routeGuide, creationZoom — so a swap
    // never silently drops styling (e.g. resetting a colored edge to white).
    if (obj is ArrowObject) {
      return ArrowObject(
        id: obj.id,
        start: obj.start,
        end: point,
        isSelected: obj.isSelected,
        midPoint: obj.midPoint,
        pathType: obj.pathType,
        startAttachment: obj.startAttachment,
        endAttachment: attachment,
        waypoints: null,
        lineStyle: obj.lineStyle,
        strokeColor: obj.strokeColor,
        arrowLabel: obj.arrowLabel,
        routeGuide: obj.routeGuide,
        angle: obj.angle,
        creationZoom: obj.creationZoom,
      );
    }
    if (obj is LineObject) {
      return LineObject(
        id: obj.id,
        start: obj.start,
        end: point,
        isSelected: obj.isSelected,
        midPoint: obj.midPoint,
        startAttachment: obj.startAttachment,
        endAttachment: attachment,
        lineStyle: obj.lineStyle,
        strokeColor: obj.strokeColor,
        angle: obj.angle,
        creationZoom: obj.creationZoom,
      );
    }
    return null;
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
          creationZoom: _canvasBloc.state.viewportZoom,
        );
      }
    } else if (tool == EditorTool.pencil) {
      if (_currentPencilPoints.length > 1) {
        // Guide-routing is disabled (path-shaping proved intractable). Pencil
        // strokes are always freehand ink again, regardless of Alt.
        newObject = PencilStrokeObject(id: id, points: _currentPencilPoints, creationZoom: _canvasBloc.state.viewportZoom);
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
      final iz = 1.0 / _canvasBloc.state.viewportZoom;
      final shapeRect = isTap
          ? snapRect(Rect.fromCenter(center: snappedStart, width: 160 * iz, height: 100 * iz))
          : snapRect(rect);
      final cz = _canvasBloc.state.viewportZoom;
      switch (tool) {
        case EditorTool.circle:
          newObject = CircleObject(id: id, rect: shapeRect, lineStyle: lineStyle, creationZoom: cz);
          break;
        case EditorTool.square:
          newObject = RectangleObject(id: id, rect: shapeRect, lineStyle: lineStyle, creationZoom: cz);
          break;
        case EditorTool.diamond:
          newObject = DiamondObject(id: id, rect: shapeRect, lineStyle: lineStyle, creationZoom: cz);
          break;
        case EditorTool.parallelogram:
          newObject = ParallelogramObject(id: id, rect: shapeRect, lineStyle: lineStyle, creationZoom: cz);
          break;
        case EditorTool.forkJoin:
          final forkRect = isTap
              ? snapRect(Rect.fromCenter(center: snappedStart, width: 160 * iz, height: 10 * iz))
              : snapRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 10));
          newObject = ForkJoinObject(id: id, rect: forkRect, lineStyle: lineStyle, creationZoom: cz);
          break;
        case EditorTool.arrowTopRight:
          if (!isTap) {
            newObject = ArrowObject(
              id: id,
              start: snappedStart,
              end: snappedEnd,
              pathType: _tempDrawingObject!.pathType,
              lineStyle: lineStyle,
              creationZoom: cz,
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
              creationZoom: cz,
            );
          }
          break;
        case EditorTool.figure:
          newObject = FigureObject(id: id, rect: shapeRect, creationZoom: cz);
          break;
        case EditorTool.text:
          newObject = TextObject(id: id, rect: shapeRect, creationZoom: cz);
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

    // For arrow/line endpoint drags, commit the position from the temp preview.
    final temp = _tempDrawingObject;
    if (temp != null &&
        (_isResizing.handle == Handle.arrowStart ||
            _isResizing.handle == Handle.arrowEnd)) {
      final newPos = _isResizing.handle == Handle.arrowEnd ? temp.end : temp.start;
      final attachment = _hoveredSnapPoint != null
          ? ObjectAttachment(
              objectId: _hoveredSnapPoint!.objectId,
              relativePosition: _hoveredSnapPoint!.relativePosition,
            )
          : null;
      if (object is ArrowObject) {
        finalObject = ArrowObject(
          id: object.id,
          start: _isResizing.handle == Handle.arrowStart ? newPos : object.start,
          end: _isResizing.handle == Handle.arrowEnd ? newPos : object.end,
          midPoint: object.midPoint,
          isSelected: object.isSelected,
          pathType: object.pathType,
          startAttachment: _isResizing.handle == Handle.arrowStart ? attachment : object.startAttachment,
          endAttachment: _isResizing.handle == Handle.arrowEnd ? attachment : object.endAttachment,
          angle: object.angle,
          waypoints: temp.waypoints ?? object.waypoints,
          lineStyle: object.lineStyle,
          arrowLabel: object.arrowLabel,
        );
      } else if (object is LineObject) {
        finalObject = LineObject(
          id: object.id,
          start: _isResizing.handle == Handle.arrowStart ? newPos : object.start,
          end: _isResizing.handle == Handle.arrowEnd ? newPos : object.end,
          midPoint: object.midPoint,
          isSelected: object.isSelected,
          startAttachment: _isResizing.handle == Handle.arrowStart ? attachment : object.startAttachment,
          endAttachment: _isResizing.handle == Handle.arrowEnd ? attachment : object.endAttachment,
          angle: object.angle,
          lineStyle: object.lineStyle,
        );
      }
      setState(() => _tempDrawingObject = null);
      _canvasBloc.add(DrawingObjectUpdated(finalObject));
      return;
    }

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

  /// Runs a layered (top-to-bottom) auto-layout over all nodes on the canvas,
  /// repositioning them to minimize edge crossings, then runs the existing
  /// port/route optimizer as a finishing pass. Reroute of attached arrows
  /// happens automatically in paint once nodes move.
  void _applyAutoLayout() {
    final canvasState = _canvasBloc.state;

    // Layout operates on every "box": NodeInstance nodes AND shape drawing
    // objects (rectangles/circles/diamonds/etc.). Diagrams imported from
    // Mermaid use RectangleObjects, not nodes, so both must be handled.
    final layoutNodes = <LayoutNode>[];
    final boxIds = <String>{};

    for (final node in canvasState.nodes.values) {
      final bounds = getNodeBoundsInWorld(node);
      final size = bounds?.size ?? const Size(120, 48);
      layoutNodes.add(LayoutNode(node.id, size));
      boxIds.add(node.id);
    }
    for (final obj in canvasState.drawingObjects.values) {
      if (obj is ArrowObject ||
          obj is LineObject ||
          obj is PencilStrokeObject) {
        continue;
      }
      layoutNodes.add(LayoutNode(obj.id, obj.rect.size));
      boxIds.add(obj.id);
    }

    if (layoutNodes.isEmpty) return;

    // Directed edges from arrows that connect two boxes (node or shape).
    final edges = <(String, String)>[];
    for (final obj in canvasState.drawingObjects.values) {
      if (obj is ArrowObject) {
        final s = obj.startAttachment?.objectId;
        final t = obj.endAttachment?.objectId;
        if (s != null && t != null && boxIds.contains(s) && boxIds.contains(t)) {
          edges.add((s, t));
        }
      }
    }

    // Anchor the laid-out block near the current centroid so the view doesn't
    // jump far away.
    Offset centroid = Offset.zero;
    int count = 0;
    for (final n in canvasState.nodes.values) {
      centroid += n.offset;
      count++;
    }
    for (final id in boxIds) {
      final obj = canvasState.drawingObjects[id];
      if (obj != null) {
        centroid += obj.rect.topLeft;
        count++;
      }
    }
    centroid = count > 0 ? centroid / count.toDouble() : Offset.zero;

    // Generous spacing so the orthogonal router has room to run edges straight
    // — tight packing makes it zigzag and reintroduces crossings the layered
    // model doesn't see.
    final layout = LayeredLayout(
      origin: centroid,
      nodeSpacing: 80,
      rankSpacing: 140,
    );
    final offsets = layout.layout(layoutNodes, edges);
    if (offsets.isEmpty) return;

    _canvasBloc.add(AutoLayoutApplied(offsets));

    // Port assignment by geometry: once nodes have moved, attach each arrow's
    // endpoints to the cardinal ports that match the boxes' relative positions
    // (downward edge → source bottom / target top, etc.). This is what makes
    // the router run clean L-shapes instead of long crossing detours — the
    // same thing you do by hand when picking better connection points.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Set each arrow's ports to the cardinal side matching the boxes' new
      // relative geometry (downward edge → source bottom / target top, etc.),
      // so the router runs clean L-shapes. (Finer crossing-aware port search was
      // explored but couldn't beat the renderer's own routing reliably; left to
      // manual tuning.)
      _assignPortsByGeometry();
      // Center + zoom the view on the freshly laid-out content.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitViewToContent();
      });
    });
  }

  /// After an auto-layout, reassigns every connecting arrow's start/end ports
  /// (the attachment [relativePosition]) to the cardinal port best matching the
  /// two boxes' current relative geometry. Top-to-bottom layouts want downward
  /// edges leaving the source bottom and entering the target top; back-edges
  /// and sideways edges pick top/left/right accordingly.
  void _assignPortsByGeometry() {
    final canvasState = _canvasBloc.state;

    Rect? rectOf(String id) {
      final node = canvasState.nodes[id];
      if (node != null) return getNodeBoundsInWorld(node);
      return canvasState.drawingObjects[id]?.rect;
    }

    // Cardinal port → attachment relativePosition.
    const top = Offset(0.5, 0.0);
    const bottom = Offset(0.5, 1.0);
    const left = Offset(0.0, 0.5);
    const right = Offset(1.0, 0.5);

    for (final obj in canvasState.drawingObjects.values) {
      if (obj is! ArrowObject) continue;
      final sId = obj.startAttachment?.objectId;
      final tId = obj.endAttachment?.objectId;
      if (sId == null || tId == null) continue;
      final sRect = rectOf(sId);
      final tRect = rectOf(tId);
      if (sRect == null || tRect == null) continue;

      final d = tRect.center - sRect.center;
      late Offset startRel;
      late Offset endRel;
      if (d.dy.abs() >= d.dx.abs()) {
        // Predominantly vertical.
        if (d.dy >= 0) {
          startRel = bottom; // target below
          endRel = top;
        } else {
          startRel = top; // target above (back-edge)
          endRel = bottom;
        }
      } else {
        // Predominantly horizontal.
        if (d.dx >= 0) {
          startRel = right; // target to the right
          endRel = left;
        } else {
          startRel = left;
          endRel = right;
        }
      }

      _canvasBloc.add(DrawingObjectUpdated(obj.copyWith(
        startAttachment: ObjectAttachment(objectId: sId, relativePosition: startRel),
        endAttachment: ObjectAttachment(objectId: tId, relativePosition: endRel),
      )));
    }
  }

  /// Returns the comment whose pin marker is under [worldPos], or null.
  ///
  /// Mirrors the pin geometry in the render object: a circle of screen-radius
  /// 9px centered at `anchorWorld + (0, -radius*1.4)`. The hit radius is a bit
  /// generous so the small marker is easy to click.
  EntityComment? _findCommentAt(Offset worldPos) {
    final zoom = _canvasBloc.state.viewportZoom;
    final iz = 1.0 / zoom;
    final radius = 9.0 * iz;
    final hitRadius = 13.0 * iz; // a little larger than the visual pin
    // Newest pins are drawn last (on top), so prefer them on overlap.
    final ordered = _canvasBloc.state.comments.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final c in ordered) {
      final pinCenter = c.anchorWorld.translate(0, -radius * 1.4);
      if ((worldPos - pinCenter).distance <= hitRadius) return c;
    }
    return null;
  }


  String? _findHitObject(Offset worldPos) {
    final canvasState = _canvasBloc.state;
    final tolerance = 12.0 / canvasState.viewportZoom;
    final hitPadding = 6.0 / canvasState.viewportZoom;

    // Connections (arrows/lines) are thin: when several run close together, the
    // click can be within tolerance of more than one. Picking the FIRST in
    // z-order (the old behaviour) meant tapping near one segment could select a
    // parallel segment farther away. Instead, gather every connection within
    // tolerance and keep the one whose path is genuinely CLOSEST to the click;
    // z-order only breaks near-exact ties.
    String? closestConnectionId;
    double closestConnectionDist = double.infinity;
    int closestConnectionIndex = -1;

    final objects = canvasState.drawingObjects.values.toList();
    // Walk in reverse so a higher z-order index wins exact-distance ties.
    for (int i = objects.length - 1; i >= 0; i--) {
      final obj = objects[i];
      if (obj is ArrowObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final controlPoint = obj.midPoint ?? (start + end) / 2;

        // Prefer the exact polyline the render object drew this frame so the
        // hit corridor matches the visible line. `renderedPath` is set for
        // orthogonal arrows (where a naive re-route diverges from what's drawn).
        final rendered = obj.renderedPath;
        double? dist;
        if (obj.pathType == LinkPathType.orthogonal &&
            rendered != null &&
            rendered.length >= 2) {
          dist = _distanceToPolyline(rendered, worldPos, tolerance);
        } else {
          dist = _distanceToPolyline(
              _sampleQuadratic(start, controlPoint, end), worldPos, tolerance);
        }
        if (dist != null && dist < closestConnectionDist) {
          closestConnectionDist = dist;
          closestConnectionId = obj.id;
          closestConnectionIndex = i;
        }
      } else if (obj is LineObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final controlPoint = obj.midPoint ?? (start + end) / 2;

        final dist = _distanceToPolyline(
            _sampleQuadratic(start, controlPoint, end), worldPos, tolerance);
        if (dist != null && dist < closestConnectionDist) {
          closestConnectionDist = dist;
          closestConnectionId = obj.id;
          closestConnectionIndex = i;
        }
      } else if ((obj is TextObject ? _textHitRect(obj) : obj.rect)
          .inflate(hitPadding)
          .contains(worldPos)) {
        // A solid shape body contains the point. Prefer it over a connection
        // only if the shape is above the closest connection in z-order;
        // otherwise the connection (which sits on top) keeps priority.
        if (closestConnectionId == null || i > closestConnectionIndex) {
          return obj.id;
        }
      }
    }

    if (closestConnectionId != null) {
      return closestConnectionId;
    }

    for (final node in canvasState.nodes.values) {
      final nodeBounds = getNodeBoundsInWorld(node);
      if (nodeBounds != null && nodeBounds.inflate(hitPadding).contains(worldPos)) {
        return node.id;
      }
    }

    return null;
  }

  /// Returns the minimum distance from [point] to [path], or null if no sampled
  /// point lies within [tolerance]. Samples finely (1px in world space) so thin,
  /// closely-spaced connections can be ranked by true proximity.
  double? distanceToPath(Path path, Offset point, double tolerance) {
    final pathBounds = path.getBounds();
    if (!pathBounds.inflate(tolerance).contains(point)) {
      return null;
    }

    double minDist = double.infinity;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += 1.0) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;
        final dist = (tangent.position - point).distance;
        if (dist < minDist) minDist = dist;
      }
    }
    return minDist <= tolerance ? minDist : null;
  }

  /// Exact point-to-polyline distance for orthogonal/segmented arrows.
  /// O(segments) — avoids Path.computeMetrics() + per-pixel getTangentForOffset
  /// sampling, which was costing ~hundreds of ms per pointer move across all
  /// arrows during hover hit-testing.
  double? _distanceToPolyline(
      List<Offset> pts, Offset point, double tolerance) {
    if (pts.length < 2) return null;
    // Cheap bounding-box reject.
    double minX = pts[0].dx, maxX = pts[0].dx, minY = pts[0].dy, maxY = pts[0].dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (point.dx < minX - tolerance ||
        point.dx > maxX + tolerance ||
        point.dy < minY - tolerance ||
        point.dy > maxY + tolerance) {
      return null;
    }
    double minDist = double.infinity;
    for (int i = 0; i < pts.length - 1; i++) {
      final d = _distanceToSegment(point, pts[i], pts[i + 1]);
      if (d < minDist) minDist = d;
    }
    return minDist <= tolerance ? minDist : null;
  }

  /// Samples a quadratic bezier into a short polyline for cheap hit-testing.
  List<Offset> _sampleQuadratic(Offset p0, Offset c, Offset p1,
      {int segments = 16}) {
    final pts = <Offset>[];
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final u = 1 - t;
      // B(t) = u²·p0 + 2·u·t·c + t²·p1
      final x = u * u * p0.dx + 2 * u * t * c.dx + t * t * p1.dx;
      final y = u * u * p0.dy + 2 * u * t * c.dy + t * t * p1.dy;
      pts.add(Offset(x, y));
    }
    return pts;
  }

  /// Shortest distance from [p] to the line segment [a]-[b].
  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final projX = a.dx + t * dx;
    final projY = a.dy + t * dy;
    final ddx = p.dx - projX;
    final ddy = p.dy - projY;
    return sqrt(ddx * ddx + ddy * ddy);
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
      final hitRect = obj is TextObject ? _textHitRect(obj) : _renderedBounds(obj);
      if (area.overlaps(hitRect)) {
        drawingObjectIds.add(obj.id);
      }
    }
    return (nodeIds, drawingObjectIds);
  }

  /// The bounds of an object as it is actually drawn on screen. For arrows and
  /// lines this resolves attachments and prefers the polyline the render object
  /// drew this frame (`renderedPath`), because an arrow's persisted
  /// `start`/`end` can be stale (e.g. an endpoint left behind when a connected
  /// box moved). Using the raw `rect` there makes a marquee far from the visible
  /// arrow still select it — and balloons the minimap bounds. Everything else
  /// falls back to `obj.rect`.
  Rect _renderedBounds(DrawingObject obj) {
    if (obj is ArrowObject || obj is LineObject) {
      final rendered = obj is ArrowObject ? obj.renderedPath : null;
      final points = <Offset>[];
      if (rendered != null && rendered.length >= 2) {
        points.addAll(rendered);
      } else {
        final (start, end) = _getDynamicEndpoints(obj);
        points.add(start);
        points.add(end);
        if (obj is ArrowObject && obj.waypoints != null) {
          points.addAll(obj.waypoints!);
        }
        final mid = obj is ArrowObject
            ? obj.midPoint
            : (obj as LineObject).midPoint;
        if (mid != null) points.add(mid);
      }
      double minX = points.first.dx, minY = points.first.dy;
      double maxX = points.first.dx, maxY = points.first.dy;
      for (final p in points) {
        minX = min(minX, p.dx);
        minY = min(minY, p.dy);
        maxX = max(maxX, p.dx);
        maxY = max(maxY, p.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return obj.rect;
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

    final handleHitAreaRadius = 10.0 / canvasState.viewportZoom;
    final rotationHitAreaRadius = 10.0 / canvasState.viewportZoom;

    // Instead of "first handle within a flat circular zone wins" (which made
    // grabbing arrow/line endpoints unreliable wherever their hit zones overlap
    // a node body, a resize corner, or another endpoint), collect *every*
    // candidate handle across all selected objects and pick the best by a
    // priority-weighted distance.
    //
    // Connection points (arrowStart/arrowEnd) get a larger effective radius and
    // a distance discount, so their zone effectively expands while competing
    // handles narrow against it — the pointer is pulled toward the connection
    // point when zones compete, matching user intent.
    const double endpointRadiusFactor = 1.6; // expand connection-point reach
    const double endpointDistanceBias = 0.5; // and discount its distance
    const double midPointDistanceBias = 0.85;

    (({String objectId, Handle handle}) candidate, double score)? best;

    void consider(
      String objectId,
      Handle handle,
      double distance,
      double radius,
      double bias,
    ) {
      if (distance >= radius) return;
      final score = distance * bias;
      if (best == null || score < best!.$2) {
        best = ((objectId: objectId, handle: handle), score);
      }
    }

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
        consider(objectId, Handle.rotate,
            (localPos - rotationCorner).distance, rotationHitAreaRadius, 1.0);

        // Other 3 corners are resize handles
        final resizeHandles = {
          Handle.topLeft: selectionRect.topLeft,
          Handle.bottomRight: selectionRect.bottomRight,
          Handle.bottomLeft: selectionRect.bottomLeft,
        };
        for (final entry in resizeHandles.entries) {
          consider(objectId, entry.key, (localPos - entry.value).distance,
              handleHitAreaRadius, 1.0);
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

        // The grab zone must sit where the line is actually DRAWN. For
        // orthogonal arrows the router snaps endpoints to a node-edge port,
        // which can be far from the relative-position point _getDynamicEndpoints
        // returns — so the visible endpoint and the hit zone diverged (you'd
        // click the line's end but grab nothing). Prefer renderedPath endpoints.
        // See memory: hit-test-path-must-match-render.
        final rendered = obj.renderedPath;
        final bool useRendered = rendered != null && rendered.length >= 2;
        final Offset hitStart = useRendered ? rendered.first : start;
        final Offset hitEnd = useRendered ? rendered.last : end;

        consider(objectId, Handle.arrowStart, (worldPos - hitStart).distance,
            handleHitAreaRadius * endpointRadiusFactor, endpointDistanceBias);
        consider(objectId, Handle.arrowEnd, (worldPos - hitEnd).distance,
            handleHitAreaRadius * endpointRadiusFactor, endpointDistanceBias);

        // For orthogonal arrows with waypoints, hide the midpoint handle.
        final hasWaypoints = obj.pathType == LinkPathType.orthogonal &&
            obj.waypoints != null &&
            obj.waypoints!.isNotEmpty;
        if (!hasWaypoints) {
          final midHandlePos = obj.pathType == LinkPathType.orthogonal
              ? cornerPoint
              : onCurveMidPoint;
          consider(objectId, Handle.midPoint,
              (worldPos - midHandlePos).distance, handleHitAreaRadius,
              midPointDistanceBias);
        }
      } else if (obj is LineObject) {
        final (start, end) = _getDynamicEndpoints(obj);
        final midPoint = obj.midPoint ?? (start + end) / 2.0;
        final onCurveMidPoint =
            (start * 0.25) + (midPoint * 0.5) + (end * 0.25);
        consider(objectId, Handle.arrowStart, (worldPos - start).distance,
            handleHitAreaRadius * endpointRadiusFactor, endpointDistanceBias);
        consider(objectId, Handle.arrowEnd, (worldPos - end).distance,
            handleHitAreaRadius * endpointRadiusFactor, endpointDistanceBias);
        consider(objectId, Handle.midPoint,
            (worldPos - onCurveMidPoint).distance, handleHitAreaRadius,
            midPointDistanceBias);
      }
    }

    if (best != null) {
      final winner = best!.$1;
      if (_hoveredHandle.objectId != winner.objectId ||
          _hoveredHandle.handle != winner.handle) {
        setState(() => _hoveredHandle = winner);
      }
      return;
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
      final zoom = _canvasBloc.state.viewportZoom;
      const initialText = 'Text';
      // fontSize in world units: 16 screen-px / zoom, so text appears as
      // 16px on screen at creation zoom and scales naturally with zoom.
      final initialStyle = TextStyle(fontSize: 16.0 / zoom, color: Colors.white);

      // Rect in world units: ~60×24 screen-px / zoom.
      final w = 60.0 / zoom;
      final h = 24.0 / zoom;
      object = TextObject(
        id: const Uuid().v4(),
        rect: Rect.fromLTWH(at!.dx - w / 2, at.dy - h / 2, w, h),
        text: initialText,
        style: initialStyle,
        creationZoom: zoom,
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
        setState(() {
          object.text = newText;
        });
      }

      // Remove the overlay. The controller and focus node are intentionally
      // NOT disposed here — the gesture arena may still hold references to
      // the TextField's RenderEditable, and disposing the controller while
      // a gesture is pending causes "used after disposed" assertions.
      // They will be garbage-collected once all references are released.
      overlayEntry?.remove();
      // Return keyboard focus to the canvas so single-key tool shortcuts
      // (V, R, O, …) work again. Without this the dismissed TextField's focus
      // node lingers as primaryFocus, which keeps the canvas shortcut bindings
      // suppressed (a text input "has focus") and makes those keys ding.
      _canvasFocusNode.requestFocus();
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
                    // Enter submits, Shift+Enter inserts a newline, Escape
                    // cancels. Handled here because a multi-line TextField
                    // doesn't fire onSubmitted on Enter.
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          _submitAndClose();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _submitAndClose();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        style: object.style.copyWith(
                          fontSize: object.style.fontSize! * zoom,
                        ),
                        maxLines: null,
                        minLines: 1,
                        autofocus: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
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

  /// Opens a small text overlay at the comment anchor to capture comment text,
  /// then dispatches [CommentAdded] with the resolved entity metadata.
  void _beginCommentEditing({
    required Offset anchorWorld,
    required String? targetId,
    required CommentTargetType targetType,
    String? sourceObjectId,
    String? targetObjectId,
    List<Offset>? renderedPath,
  }) {
    final zoom = _canvasBloc.state.viewportZoom;
    final textEditingController = TextEditingController();
    final focusNode = FocusNode();
    OverlayEntry? overlayEntry;

    setState(() => _isEditingText = true);

    bool closed = false;
    void submitAndClose() {
      if (!mounted || closed) return;
      closed = true;
      final text = textEditingController.text.trim();
      setState(() => _isEditingText = false);

      if (text.isNotEmpty) {
        _canvasBloc.add(
          CommentAdded(
            EntityComment(
              id: const Uuid().v4(),
              targetId: targetId,
              targetType: targetType,
              text: text,
              anchorWorld: anchorWorld,
              createdAt: DateTime.now(),
              sourceObjectId: sourceObjectId,
              targetObjectId: targetObjectId,
              renderedPath: renderedPath,
            ),
          ),
        );
      }
      overlayEntry?.remove();
      // Return focus to the canvas so single-key shortcuts work again.
      _canvasFocusNode.requestFocus();
    }

    overlayEntry = OverlayEntry(
      builder: (context) {
        final editorBox =
            kNodeEditorWidgetKey.currentContext!.findRenderObject() as RenderBox;
        final editorSize = editorBox.size;
        final editorGlobalOffset = editorBox.localToGlobal(Offset.zero);

        final screenX =
            (anchorWorld.dx + offset.dx) * zoom + editorSize.width / 2;
        final screenY =
            (anchorWorld.dy + offset.dy) * zoom + editorSize.height / 2;
        final globalPosition =
            Offset(screenX, screenY) + editorGlobalOffset;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    submitAndClose();
                  });
                },
              ),
            ),
            Positioned(
              left: globalPosition.dx + 12,
              top: globalPosition.dy - 12,
              child: Material(
                color: Colors.transparent,
                child: DefaultTextEditingShortcuts(
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8C4),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    // Enter submits, Shift+Enter inserts a newline, Escape
                    // cancels. Handled here because a multi-line TextField
                    // doesn't fire onSubmitted on Enter.
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          textEditingController.clear();
                          submitAndClose();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          submitAndClose();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        key: const ValueKey('comment_input'),
                        controller: textEditingController,
                        focusNode: focusNode,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87),
                        maxLines: null,
                        minLines: 1,
                        autofocus: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          hintText: 'Comment on this…  (Enter to save)',
                          hintStyle: TextStyle(color: Colors.black38),
                        ),
                      ),
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

  /// Opens a popup anchored near a comment pin showing its text, with actions
  /// to toggle resolved or delete the comment.
  void _openCommentPopup(EntityComment comment, Offset globalAnchor) {
    OverlayEntry? overlayEntry;
    void close() => overlayEntry?.remove();

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Tap-away scrim to dismiss.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
              ),
            ),
            Positioned(
              left: globalAnchor.dx + 12,
              top: globalAnchor.dy + 12,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8C4),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.text,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black54,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              _canvasBloc
                                  .add(CommentResolvedToggled(comment.id));
                              close();
                            },
                            child: Text(
                                comment.resolved ? 'Reopen' : 'Resolve'),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              _canvasBloc.add(CommentRemoved(comment.id));
                              close();
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ],
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
  RichTextEditingController? _shapeTextController;
  FocusNode? _shapeTextFocusNode;
  TextStyle _shapeTextStyle = const TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Courier');

  DateTime? _shapeEditOpenedAt;

  void _beginShapeTextEditing(DrawingObject shapeObject) {
    const defaultStyle = TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Courier');
    final canvasState = _canvasBloc.state;

    String? existingText;
    TextStyle? rawStyle;
    bool customized = false;
    List<TextRun>? existingRuns;
    if (shapeObject is RectangleObject) {
      existingText = shapeObject.text;
      rawStyle = shapeObject.textStyle;
      customized = shapeObject.fontCustomized;
      existingRuns = shapeObject.richText;
    } else if (shapeObject is CircleObject) {
      existingText = shapeObject.text;
      rawStyle = shapeObject.textStyle;
      customized = shapeObject.fontCustomized;
      existingRuns = shapeObject.richText;
    } else if (shapeObject is DiamondObject) {
      existingText = shapeObject.text;
      rawStyle = shapeObject.textStyle;
      customized = shapeObject.fontCustomized;
      existingRuns = shapeObject.richText;
    } else if (shapeObject is ParallelogramObject) {
      existingText = shapeObject.text;
      rawStyle = shapeObject.textStyle;
      customized = shapeObject.fontCustomized;
      existingRuns = shapeObject.richText;
    }

    // The controller resolves per-run overrides on top of this base, so it must
    // be the shape's *effective* style (folding in the global default).
    final baseStyle = effectiveShapeTextStyle(
      style: rawStyle,
      customized: customized,
      defaultFamily: canvasState.defaultFontFamily,
      defaultSize: canvasState.defaultFontSize,
    );

    // Seed runs from richText when present, else from the plain text (so legacy
    // single-style nodes still edit as one uniform run).
    final seedRuns = existingRuns ??
        (existingText != null && existingText.isNotEmpty
            ? [TextRun(existingText)]
            : null);

    _shapeTextController?.dispose();
    _shapeTextFocusNode?.dispose();

    final controller =
        RichTextEditingController(base: baseStyle, runs: seedRuns);
    _shapeTextController = controller;
    _shapeTextFocusNode = FocusNode();
    _shapeTextStyle = baseStyle;
    _shapeEditOpenedAt = DateTime.now();

    final text = controller.text;
    if (text.isNotEmpty) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    }

    // Publish to the toolbar so its font controls retarget the live selection.
    activeTextEditing.value = controller;

    setState(() {
      _editingShapeObject = shapeObject;
      if (shapeObject is RectangleObject) shapeObject.isEditing = true;
      if (shapeObject is CircleObject) shapeObject.isEditing = true;
      if (shapeObject is DiamondObject) shapeObject.isEditing = true;
      if (shapeObject is ParallelogramObject) shapeObject.isEditing = true;
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

    final controller = _shapeTextController;
    // The plain-text mirror is trimmed; rich runs come from the controller and
    // are nulled out when there's no text (so an empty node serializes lean).
    final newText = controller?.text.trim() ?? '';
    List<TextRun>? newRuns = newText.isEmpty ? null : controller?.toRuns();
    // Drop a single inherited run to null — it's indistinguishable from plain
    // text and keeps round-tripping/serialization minimal.
    if (newRuns != null &&
        newRuns.length == 1 &&
        !newRuns.first.hasOverrides) {
      newRuns = null;
    }

    // Clear the toolbar channel before rebuilding so it stops targeting the
    // (about-to-be-disposed) controller.
    activeTextEditing.value = null;

    setState(() {
      if (shapeObject is RectangleObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
        shapeObject.richText = newRuns;
      } else if (shapeObject is CircleObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
        shapeObject.richText = newRuns;
      } else if (shapeObject is DiamondObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
        shapeObject.richText = newRuns;
      } else if (shapeObject is ParallelogramObject) {
        shapeObject.isEditing = false;
        shapeObject.text = newText.isEmpty ? null : newText;
        shapeObject.textStyle = newText.isEmpty ? null : _shapeTextStyle;
        shapeObject.richText = newRuns;
      }
      _editingShapeObject = null;
    });
    // Don't dispose controller/focusNode here — they stay alive until
    // _beginShapeTextEditing replaces them or the widget is disposed.
    // This avoids "used after disposed" errors when gesture callbacks
    // fire on the TextField after we've scheduled its removal.
    // Return focus to the canvas so single-key shortcuts work again (see note
    // in the text-tool _submitAndClose).
    _canvasFocusNode.requestFocus();
  }

  /// Called when the canvas widget size changes (e.g. window resize).
  /// Adjusts viewportOffset so the visible world content stays centered.
  void _onCanvasSizeChanged(Size newSize) {
    final prev = _lastCanvasSize;
    _lastCanvasSize = newSize;
    if (prev == null) return;
    final zoom = _canvasBloc.state.viewportZoom;
    // The canvas centers the world at (size.width/2, size.height/2).
    // When size shrinks, the center moves left/up, making content appear to
    // drift right/down. Compensate by shifting the viewport offset.
    final delta = Offset(
      (newSize.width - prev.width) / 2 / zoom,
      (newSize.height - prev.height) / 2 / zoom,
    );
    _canvasBloc.add(CanvasPanned(delta));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastCanvasSize != size) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onCanvasSizeChanged(size);
          });
        }
        if (!PaintProfiler.enabled) return _buildContent();
        final sw = Stopwatch()..start();
        final w = _buildContent();
        PaintProfiler.instance.recordBuild(sw.elapsedMicroseconds);
        return w;
      },
    );
  }

  Widget _buildContent() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerPanZoomStart: _onPointerPanZoomStart,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      child: BlocBuilder<CanvasBloc, CanvasState>(
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
                          debugShowHitAreas: _debugShowHitAreas,
                        ),
                  ),
                );

                return CallbackShortcuts(
                  bindings: (_editingShapeObject != null ||
                          _isEditingText ||
                          _textInputHasFocus)
                      ? const {}
                      : {
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
                    // Tidy: layered auto-layout to minimize edge crossings.
                    const SingleActivator(LogicalKeyboardKey.keyL,
                        meta: true, shift: true): _applyAutoLayout,
                    const SingleActivator(LogicalKeyboardKey.keyL,
                        control: true, shift: true): _applyAutoLayout,
                    // Lay selected nodes out along the selected guide shape.
                    // (Cmd/Ctrl+Shift+P is swallowed by macOS, so use U.)
                    const SingleActivator(LogicalKeyboardKey.keyU,
                            meta: true, shift: true):
                        _layoutSelectionAlongSelectedGuide,
                    const SingleActivator(LogicalKeyboardKey.keyU,
                            control: true, shift: true):
                        _layoutSelectionAlongSelectedGuide,
                    // Swap: exchange two nodes' positions, or two edges' ends.
                    const SingleActivator(LogicalKeyboardKey.keyS,
                        meta: true, shift: true): _swapSelection,
                    const SingleActivator(LogicalKeyboardKey.keyS,
                        control: true, shift: true): _swapSelection,
                    const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () async {
                      if (_textInputHasFocus) return;
                      await _copySelection(canvasState, selectionState);
                    },
                    const SingleActivator(LogicalKeyboardKey.keyC, control: true): () async {
                      if (_textInputHasFocus) return;
                      await _copySelection(canvasState, selectionState);
                    },
                    const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
                      // A focused text input (incl. external overlays like the
                      // flan annotation box) must get the paste itself.
                      if (_textInputHasFocus) return;
                      _pasteAtCursor(canvasState);
                    },
                    const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
                      if (_textInputHasFocus) return;
                      _pasteAtCursor(canvasState);
                    },
                    const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () async {
                      if (_textInputHasFocus) return;
                      final copied = await _copySelection(canvasState, selectionState);
                      if (copied) {
                        _canvasBloc.add(ObjectsRemoved(
                          nodeIds: selectionState.selectedNodeIds,
                          drawingObjectIds: selectionState.selectedDrawingObjectIds,
                        ));
                      }
                    },
                    const SingleActivator(LogicalKeyboardKey.keyX, control: true): () async {
                      if (_textInputHasFocus) return;
                      final copied = await _copySelection(canvasState, selectionState);
                      if (copied) {
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
                    // Debug: toggle hit-area overlay
                    const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true): () =>
                      setState(() => _debugShowHitAreas = !_debugShowHitAreas),
                    const SingleActivator(LogicalKeyboardKey.keyH, control: true, shift: true): () =>
                      setState(() => _debugShowHitAreas = !_debugShowHitAreas),
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
                          child: RawGestureDetector(
                            gestures: {
                              ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                                () => ScaleGestureRecognizer(
                                  supportedDevices: {
                                    PointerDeviceKind.touch,
                                    // Trackpad is handled via Listener onPointerPanZoom
                                    // and _onPointerSignal to avoid double-processing.
                                    PointerDeviceKind.mouse,
                                  },
                                ),
                                (instance) {
                                  instance
                                    ..onStart = _onScaleStart
                                    ..onUpdate = _onScaleUpdate
                                    ..onEnd = _onScaleEnd;
                                },
                              ),
                            },
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
    ),
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

    // If no valid objects were found, bail out early to avoid NaN positions
    if (minX == double.infinity || maxX == double.negativeInfinity) {
      return const SizedBox.shrink();
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
              const SizedBox(width: 2),
              _MinimizeCrossingsMenuButton(
                onSelected: (changeConnectionPoints) {
                  _canvasBloc.add(CrossingsMinimized(
                    selectedIds,
                    changeConnectionPoints: changeConnectionPoints,
                  ));
                },
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
              top: screenY - (shapeObject.rect.height * zoom) / 2,
              width: screenWidth,
              height: shapeObject.rect.height * zoom,
              child: Material(
                color: Colors.transparent,
                // The editor content is laid out at the node's exact world rect
                // (rect.width x rect.height); FittedBox(fill) then scales it to
                // fill the screen-sized Positioned edge-to-edge. This makes the
                // editable/selection area match the visible node and renders
                // per-run world-unit font sizes at the correct on-screen scale,
                // without manual zoom math.
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: shapeObject.rect.width,
                    height: shapeObject.rect.height,
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed &&
                            !HardwareKeyboard.instance.isAltPressed) {
                          _finishShapeTextEditing();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        key: const ValueKey('shape_text_editor'),
                        controller: _shapeTextController,
                        focusNode: _shapeTextFocusNode,
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        style: _shapeTextStyle,
                        // Fill the node vertically so the editable/selection
                        // area matches the visible box edge-to-edge.
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        autofocus: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
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

/// A popup menu button that offers two crossing-minimization strategies.
class _MinimizeCrossingsMenuButton extends StatelessWidget {
  final ValueChanged<bool> onSelected;

  const _MinimizeCrossingsMenuButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Minimize Crossings',
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: true,
          child: Row(
            children: [
              Icon(Icons.route, size: 16),
              SizedBox(width: 8),
              Text('Reroute & change ports'),
            ],
          ),
        ),
        PopupMenuItem(
          value: false,
          child: Row(
            children: [
              Icon(Icons.alt_route, size: 16),
              SizedBox(width: 8),
              Text('Reroute only'),
            ],
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.device_hub, size: 16),
      ),
    );
  }
}
