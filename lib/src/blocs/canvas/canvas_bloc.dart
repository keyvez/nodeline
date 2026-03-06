import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flow_draw/src/core/node_editor/clipboard.dart';
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';
import 'package:flow_draw/src/core/utils/snap_utils.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/entities.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:uuid/uuid.dart';

part 'canvas_event.dart';
part 'canvas_state.dart';

class CanvasBloc extends Bloc<CanvasEvent, CanvasState> {
  static const int _maxHistoryStack = 100;
  /// Snapshot of the state before an ongoing non-undoable operation
  /// (drag, resize, rotation). Captured on the first non-undoable event
  /// and consumed by the corresponding "ended" event.
  CanvasState? _preOperationSnapshot;

  CanvasBloc() : super(const CanvasState()) {
    on<CanvasEvent>((event, emit) async {
      return (switch (event) {
        CanvasTransformed e => _onCanvasTransformed(e, emit),
        CanvasPanned e => _onCanvasPanned(e, emit),
        CanvasZoomed e => _onCanvasZoomed(e, emit),
        NodeAdded e => _onNodeAdded(e, emit),
        DrawingObjectAdded e => _onDrawingObjectAdded(e, emit),
        ObjectsRemoved e => _onObjectsRemoved(e, emit),
        ObjectsDragged e => _onObjectsDragged(e, emit),
        ObjectsDragEnded e => _onObjectsDragEnded(e, emit),
        DrawingObjectUpdated e => _onDrawingObjectUpdated(e, emit),
        ObjectsResizeEnded e => _onObjectsResizeEnded(e, emit),
        ObjectsRotationEnded e => _onObjectsRotationEnded(e, emit),
        NodeValueUpdated e => _onNodeValueUpdated(e, emit),
        NodeHeadingUpdated e => _onNodeHeadingUpdated(e, emit),
        NodeToggled e => _onNodeToggled(e, emit),
        UndoRequested e => _onUndo(e, emit),
        RedoRequested e => _onRedo(e, emit),
        ProjectSaved e => _onProjectSaved(e, emit),
        ProjectLoaded e => _onProjectLoaded(e, emit),
        NewProjectCreated e => _onNewProjectCreated(e, emit),
        SelectionCut e => _onSelectionCut(e, emit),
        SelectionPasted e => _onSelectionPasted(e, emit),
        SelectionCopied e => _onSelectionCopied(e, emit),
        ObjectDuplicatedWithConnection e => _onObjectDuplicatedWithConnection(e, emit),
        GridToggled e => _onGridToggled(e, emit),
      });
    });
  }

  void _emitWithHistory(
    CanvasState newState,
    CanvasEvent event,
    Emitter<CanvasState> emit,
  ) {
    if (event.isUndoable) {
      final historicState = CanvasState.historic(
        nodes: Map<String, NodeInstance>.from(state.nodes),
        drawingObjects: Map<String, DrawingObject>.from(state.drawingObjects),
        viewportOffset: state.viewportOffset,
        viewportZoom: state.viewportZoom,
      );

      final newUndoStack = List<HistoryEntry>.from(state.undoStack)
        ..add((historicState, event));
      if (newUndoStack.length > _maxHistoryStack) {
        newUndoStack.removeAt(0);
      }
      // Emit the new state with an updated undo stack and cleared redo stack
      emit(newState.copyWith(undoStack: newUndoStack, redoStack: []));
    } else {
      // If the event is not undoable (like a drag update), capture a snapshot
      // of the pre-operation state so the "ended" event can push it to undo.
      _preOperationSnapshot ??= CanvasState.historic(
        nodes: Map<String, NodeInstance>.from(state.nodes),
        drawingObjects: Map<String, DrawingObject>.from(state.drawingObjects),
        viewportOffset: state.viewportOffset,
        viewportZoom: state.viewportZoom,
      );
      emit(
        newState.copyWith(
          undoStack: state.undoStack,
          redoStack: state.redoStack,
        ),
      );
    }
  }

  void _pushToUndoStack(
    CanvasEvent event,
    Emitter<CanvasState> emit,
    CanvasState currentState,
  ) {
    if (!event.isUndoable) return;

    // Use the pre-operation snapshot if available (captured before the first
    // non-undoable event like drag/resize/rotation updates). This ensures
    // undo restores the state BEFORE the operation, not after.
    final historicState = _preOperationSnapshot ?? CanvasState.historic(
      nodes: Map<String, NodeInstance>.from(currentState.nodes),
      drawingObjects: Map<String, DrawingObject>.from(currentState.drawingObjects),
      viewportOffset: currentState.viewportOffset,
      viewportZoom: currentState.viewportZoom,
    );
    _preOperationSnapshot = null;

    final newUndoStack = List<HistoryEntry>.from(currentState.undoStack)
      ..add((historicState, event));
    if (newUndoStack.length > _maxHistoryStack) {
      newUndoStack.removeAt(0);
    }
    emit(state.copyWith(undoStack: newUndoStack, redoStack: []));
  }

  void _onCanvasTransformed(CanvasTransformed event, Emitter<CanvasState> emit) {
    emit(state.copyWith(
      viewportZoom: event.zoom,
      viewportOffset: event.offset,
    ));
  }

  void _onCanvasPanned(CanvasPanned event, Emitter<CanvasState> emit) {
    emit(state.copyWith(viewportOffset: state.viewportOffset + event.delta));
  }

  void _onCanvasZoomed(CanvasZoomed event, Emitter<CanvasState> emit) {
    emit(state.copyWith(viewportZoom: event.zoom));
  }

  void _onNodeAdded(NodeAdded event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    newNodes[event.node.id] = event.node;
    emit(state.copyWith(nodes: newNodes));
  }

  void _onDrawingObjectAdded(
    DrawingObjectAdded event,
    Emitter<CanvasState> emit,
  ) {
    _pushToUndoStack(event, emit, state);
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    );
    newDrawingObjects[event.object.id] = event.object;
    emit(state.copyWith(drawingObjects: newDrawingObjects));
  }

  void _onObjectsRemoved(ObjectsRemoved event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes)
      ..removeWhere((key, _) => event.nodeIds.contains(key));
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    )..removeWhere((key, _) => event.drawingObjectIds.contains(key));
    emit(state.copyWith(nodes: newNodes, drawingObjects: newDrawingObjects));
  }

  void _onObjectsResizeEnded(
    ObjectsResizeEnded event,
    Emitter<CanvasState> emit,
  ) {
    // This event IS undoable. We push the current state to the undo stack.
    _pushToUndoStack(event, emit, state);
  }

  void _onObjectsRotationEnded(
      ObjectsRotationEnded event,
      Emitter<CanvasState> emit,
      ) {
    _pushToUndoStack(event, emit, state);
  }


  void _onDrawingObjectUpdated(
    DrawingObjectUpdated event,
    Emitter<CanvasState> emit,
  ) {
    // Capture pre-operation snapshot before the first update in a
    // drag/resize/rotation sequence so the "ended" event can undo to it.
    // Use Map.from to create defensive copies so mutations to the current
    // state's collections don't corrupt the snapshot.
    _preOperationSnapshot ??= CanvasState.historic(
      nodes: Map<String, NodeInstance>.from(state.nodes),
      drawingObjects: Map<String, DrawingObject>.from(state.drawingObjects),
      viewportOffset: state.viewportOffset,
      viewportZoom: state.viewportZoom,
    );
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    );
    newDrawingObjects[event.object.id] = event.object;
    emit(state.copyWith(drawingObjects: newDrawingObjects));
  }

  void _onNodeValueUpdated(NodeValueUpdated event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final node = newNodes[event.nodeId];
    if (node != null) {
      newNodes[event.nodeId] = node.copyWith(value: event.value);
      emit(state.copyWith(nodes: newNodes));
    }
  }

  void _onNodeHeadingUpdated(
    NodeHeadingUpdated event,
    Emitter<CanvasState> emit,
  ) {
    _pushToUndoStack(event, emit, state);
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final node = newNodes[event.nodeId];
    if (node != null) {
      newNodes[event.nodeId] = node.copyWith(heading: event.heading);
      emit(state.copyWith(nodes: newNodes));
    }
  }

  void _onNodeToggled(NodeToggled event, Emitter<CanvasState> emit) {
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final node = newNodes[event.nodeId];
    if (node != null) {
      _pushToUndoStack(event, emit, state);
      final oldState = node.state;
      newNodes[event.nodeId] = node.copyWith(
        state: NodeState(
          isSelected: oldState.isSelected,
          isCollapsed: !oldState.isCollapsed,
        ),
      );
      emit(state.copyWith(nodes: newNodes));
    }
  }

  void _onObjectsDragged(ObjectsDragged event, Emitter<CanvasState> emit) {
    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final newDrawingObjects = Map<String, DrawingObject>.from(
      state.drawingObjects,
    );

    // Compute snapped delta from the first selected object's anchor point.
    Offset effectiveDelta = event.delta;
    final firstId = event.objectIds.first;
    if (newNodes.containsKey(firstId)) {
      final node = newNodes[firstId]!;
      final currentPos = node.offset + event.delta;
      final snappedPos = snapOffset(currentPos);
      effectiveDelta = snappedPos - node.offset;
    } else if (newDrawingObjects.containsKey(firstId)) {
      final obj = newDrawingObjects[firstId]!;
      if (obj is ArrowObject) {
        final currentPos = obj.start + event.delta;
        final snappedPos = snapOffset(currentPos);
        effectiveDelta = snappedPos - obj.start;
      } else if (obj is LineObject) {
        final currentPos = obj.start + event.delta;
        final snappedPos = snapOffset(currentPos);
        effectiveDelta = snappedPos - obj.start;
      } else {
        final currentPos = obj.rect.topLeft + event.delta;
        final snappedPos = snapOffset(currentPos);
        effectiveDelta = snappedPos - obj.rect.topLeft;
      }
    }

    for (final id in event.objectIds) {
      if (newNodes.containsKey(id)) {
        final node = newNodes[id]!;
        newNodes[id] = node.copyWith(offset: node.offset + effectiveDelta);
      } else if (newDrawingObjects.containsKey(id)) {
        final object = newDrawingObjects[id]!;
        if (object is ArrowObject) {
          object.start += effectiveDelta;
          object.end += effectiveDelta;
          if (object.midPoint != null) {
            object.midPoint = object.midPoint! + effectiveDelta;
          }
        } else if (object is LineObject) {
          object.start += effectiveDelta;
          object.end += effectiveDelta;
          if (object.midPoint != null) {
            object.midPoint = object.midPoint! + effectiveDelta;
          }
        } else if (object is PencilStrokeObject) {
          object.points = object.points
              .map(
                (p) => PointVector(
                  p.x + effectiveDelta.dx,
                  p.y + effectiveDelta.dy,
                  p.pressure,
                ),
              )
              .toList();
        } else if (object is RectangleObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is CircleObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is FigureObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is TextObject) {
          object.rect = object.rect.shift(effectiveDelta);
        } else if (object is SvgObject) {
          object.rect = object.rect.shift(effectiveDelta);
        }

        newDrawingObjects[id] = object.copyWith();
      }
    }
    // We emit the new state BUT we pass the event, which is marked as NOT undoable.
    _emitWithHistory(
      state.copyWith(nodes: newNodes, drawingObjects: newDrawingObjects),
      event,
      emit,
    );
  }

  void _onObjectsDragEnded(ObjectsDragEnded event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);
  }

  void _onUndo(UndoRequested event, Emitter<CanvasState> emit) {
    if (state.undoStack.isEmpty) return;

    final newUndoStack = List<HistoryEntry>.from(state.undoStack);
    final (previousState, lastEvent) = newUndoStack.removeLast();

    final currentStateForRedo = CanvasState.historic(
      nodes: Map<String, NodeInstance>.from(state.nodes),
      drawingObjects: Map<String, DrawingObject>.from(state.drawingObjects),
      viewportOffset: state.viewportOffset,
      viewportZoom: state.viewportZoom,
    );

    final newRedoStack = List<HistoryEntry>.from(state.redoStack)
      ..add((currentStateForRedo, lastEvent));

    emit(
      previousState.copyWith(undoStack: newUndoStack, redoStack: newRedoStack, showGrid: state.showGrid),
    );
  }

  void _onRedo(RedoRequested event, Emitter<CanvasState> emit) {
    if (state.redoStack.isEmpty) return;

    final newRedoStack = List<HistoryEntry>.from(state.redoStack);
    final (nextState, nextEvent) = newRedoStack.removeLast();

    final currentStateForUndo = CanvasState.historic(
      nodes: Map<String, NodeInstance>.from(state.nodes),
      drawingObjects: Map<String, DrawingObject>.from(state.drawingObjects),
      viewportOffset: state.viewportOffset,
      viewportZoom: state.viewportZoom,
    );

    final newUndoStack = List<HistoryEntry>.from(state.undoStack)
      ..add((currentStateForUndo, nextEvent));

    emit(nextState.copyWith(undoStack: newUndoStack, redoStack: newRedoStack, showGrid: state.showGrid));
  }

  void _onNewProjectCreated(
    NewProjectCreated event,
    Emitter<CanvasState> emit,
  ) {
    emit(const CanvasState());
    showNodeEditorSnackbar('New project created.', SnackbarType.success);
  }

  void _onGridToggled(
    GridToggled event,
    Emitter<CanvasState> emit,
  ) {
    emit(state.copyWith(showGrid: !state.showGrid));
  }

  void _onProjectSaved(ProjectSaved event, Emitter<CanvasState> emit) {
    final jsonData = {
      'viewport': {
        'offset': [state.viewportOffset.dx, state.viewportOffset.dy],
        'zoom': state.viewportZoom,
      },
      'nodes': state.nodes.values.map((node) => node.toJson()).toList(),
      'drawingObjects': state.drawingObjects.values
          .map((obj) => obj.toJson())
          .toList(),
    };
    event.onSave(jsonData);
  }

  void _onProjectLoaded(ProjectLoaded event, Emitter<CanvasState> emit) {
    try {
      final viewportJson = event.data['viewport'] as Map<String, dynamic>;
      final offset = Offset(
        viewportJson['offset'][0],
        viewportJson['offset'][1],
      );
      final zoom = viewportJson['zoom'] as double;

      final nodesList = (event.data['nodes'] as List)
          .map((json) => NodeInstance.fromJson(json))
          .toList();
      final nodes = {for (var node in nodesList) node.id: node};

      final drawingObjectsList = (event.data['drawingObjects'] as List)
          .map((json) {
            // This logic can be moved to a factory in DrawingObject
            switch (json['type']) {
              case 'rectangle':
                return RectangleObject.fromJson(json);
              case 'circle':
                return CircleObject.fromJson(json);
              case 'arrow':
                return ArrowObject.fromJson(json);
              case 'line':
                return LineObject.fromJson(json);
              case 'pencil_stroke':
                return PencilStrokeObject.fromJson(json);
              case 'figure':
                return FigureObject.fromJson(json);
              case 'text':
                return TextObject.fromJson(json);
              default:
                return null;
            }
          })
          .whereType<DrawingObject>()
          .toList();
      final drawingObjects = {for (var obj in drawingObjectsList) obj.id: obj};

      emit(
        CanvasState(
          viewportOffset: offset,
          viewportZoom: zoom,
          nodes: nodes,
          drawingObjects: drawingObjects,
        ),
      );
    } catch (e, s) {
      throw Exception('Failed to load project: $e\n$s');
    }
  }

  void _onSelectionCut(SelectionCut event, Emitter<CanvasState> emit) {
    // This is an example of composing events. We don't need a separate handler.
    // The clipboard logic will be handled in the UI layer for now.
  }

  void _onSelectionPasted(
    SelectionPasted event,
    Emitter<CanvasState> emit,
  ) async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null || clipboardData.text == null) return;

    final newNodes = Map<String, NodeInstance>.from(state.nodes);
    final pasted = ClipboardService.preparePaste(
      clipboardData.text!,
      event.pastePosition,
    );
    if (pasted != null) {
      _pushToUndoStack(event, emit, state);
      for (var node in pasted) {
        newNodes[node.id] = node;
      }
      emit(state.copyWith(nodes: newNodes));
    }
  }

  void _onSelectionCopied(SelectionCopied e, Emitter<CanvasState> emit) {}

  void _onObjectDuplicatedWithConnection(
      ObjectDuplicatedWithConnection event, Emitter<CanvasState> emit) {
    _pushToUndoStack(event, emit, state);

    final sourceObject = state.drawingObjects[event.sourceObjectId];
    if (sourceObject == null ||
        !(sourceObject is RectangleObject || sourceObject is CircleObject)) {
      return;
    }

    final sourceRect = sourceObject.rect;
    // Gap between source and new object: at least 60% of the object's dimension, minimum 120px
    final double spacing;
    switch (event.direction) {
      case QuickActionDirection.top:
      case QuickActionDirection.bottom:
        spacing = max(sourceRect.height * 0.6, 120.0);
      case QuickActionDirection.left:
      case QuickActionDirection.right:
        spacing = max(sourceRect.width * 0.6, 120.0);
    }

    late Offset newRectTopLeft;
    late ObjectAttachment startAttachment;
    late ObjectAttachment endAttachment;

    switch (event.direction) {
      case QuickActionDirection.top:
        newRectTopLeft = sourceRect.topLeft - Offset(0, sourceRect.height + spacing);
        startAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(0.5, 0.0));
        endAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(0.5, 1.0));
        break;
      case QuickActionDirection.right:
        newRectTopLeft = sourceRect.topRight + Offset(spacing, 0);
        startAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(1.0, 0.5));
        endAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(0.0, 0.5));
        break;
      case QuickActionDirection.bottom:
        newRectTopLeft = sourceRect.bottomLeft + Offset(0, spacing);
        startAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(0.5, 1.0));
        endAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(0.5, 0.0));
        break;
      case QuickActionDirection.left:
        newRectTopLeft = sourceRect.topLeft - Offset(sourceRect.width + spacing, 0);
        startAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(0.0, 0.5));
        endAttachment = const ObjectAttachment(objectId: '', relativePosition: Offset(1.0, 0.5));
        break;
    }

    // Avoid overlapping with existing objects: push further if needed
    final existingRects = <Rect>[];
    for (final obj in state.drawingObjects.values) {
      if (obj is ArrowObject || obj is LineObject || obj is PencilStrokeObject) continue;
      existingRects.add(obj.rect);
    }
    var candidateRect = newRectTopLeft & sourceRect.size;
    const double pushStep = 40.0;
    final Offset pushDir;
    switch (event.direction) {
      case QuickActionDirection.top:    pushDir = const Offset(0, -1);
      case QuickActionDirection.right:  pushDir = const Offset(1, 0);
      case QuickActionDirection.bottom: pushDir = const Offset(0, 1);
      case QuickActionDirection.left:   pushDir = const Offset(-1, 0);
    }
    // Push until no overlap (max 20 iterations to avoid infinite loop)
    for (int i = 0; i < 20; i++) {
      final overlaps = existingRects.any((r) => r.overlaps(candidateRect.inflate(10)));
      if (!overlaps) break;
      newRectTopLeft += pushDir * pushStep;
      candidateRect = newRectTopLeft & sourceRect.size;
    }

    final DrawingObject newShape;
    final newId = const Uuid().v4();
    final newObjectRect = newRectTopLeft & sourceRect.size;

    if (sourceObject is RectangleObject) {
      newShape = RectangleObject(id: newId, rect: newObjectRect, lineStyle: sourceObject.lineStyle);
    } else if (sourceObject is CircleObject) {
      newShape = CircleObject(id: newId, rect: newObjectRect, lineStyle: sourceObject.lineStyle);
    } else {
      return;
    }

    final finalStartAttachment = startAttachment.copyWith(objectId: sourceObject.id);
    final finalEndAttachment = endAttachment.copyWith(objectId: newShape.id);

    // Compute actual attachment points on object edges
    final startRelPos = finalStartAttachment.relativePosition;
    final arrowStart = sourceRect.topLeft +
        Offset(sourceRect.width * startRelPos.dx, sourceRect.height * startRelPos.dy);
    final endRelPos = finalEndAttachment.relativePosition;
    final arrowEnd = newObjectRect.topLeft +
        Offset(newObjectRect.width * endRelPos.dx, newObjectRect.height * endRelPos.dy);

    // Collect obstacles (solid objects only, include connected objects for routing around)
    final obstacles = <Rect>[];
    for (final obj in state.drawingObjects.values) {
      if (obj is ArrowObject || obj is LineObject || obj is PencilStrokeObject) continue;
      obstacles.add(obj.rect);
    }
    obstacles.add(newObjectRect);

    final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final waypoints = OrthogonalRouter.route(
      start: arrowStart,
      end: arrowEnd,
      obstacles: obstacles,
      startObjectRect: sourceRect,
      endObjectRect: newObjectRect,
      devicePixelRatio: dpr,
      zoom: state.viewportZoom,
    );

    final newArrow = ArrowObject(
      id: const Uuid().v4(),
      start: arrowStart,
      end: arrowEnd,
      pathType: LinkPathType.orthogonal,
      startAttachment: finalStartAttachment,
      endAttachment: finalEndAttachment,
      waypoints: waypoints,
    );

    final newDrawingObjects = Map<String, DrawingObject>.from(state.drawingObjects)
      ..[newShape.id] = newShape
      ..[newArrow.id] = newArrow;

    emit(state.copyWith(drawingObjects: newDrawingObjects));
  }
}
