import 'dart:async';

import 'package:nodeline/nodeline.dart';
import 'package:flutter/widgets.dart';

import 'flow_draw_controller_interface.dart';

/// A controller to programmatically interact with the flow_draw canvas.
///
/// This controller provides a clean API to access functionalities like changing tools,
/// performing undo/redo, adding objects, and listening to state changes from
/// outside the main `FlowDraw` widget.
///
/// ## Usage
///
/// 1. Create an instance of the controller.
/// ```dart
/// final controller = FlowDrawController();
/// ```
///
/// 2. Pass it to the `FlowDraw` widget.
/// ```dart
/// FlowDraw(
///   controller: controller,
///   child: FlowDrawCanvas(),
/// );
/// ```
///
/// 3. Use the controller's methods and streams.
/// ```dart
/// controller.setTool(EditorTool.square);
/// controller.undo();
///
/// controller.canvasStateStream.listen((state) {
///   print('Canvas updated! It now has ${state.nodes.length} nodes.');
/// });
/// ```
class FlowDrawController implements FlowDrawControllerInterface {
  CanvasBloc? _canvasBloc;
  SelectionBloc? _selectionBloc;
  ToolBloc? _toolBloc;

  bool _isInitialized = false;

  /// Initializes the controller with the BLoCs from the `FlowDraw` widget.
  /// This is intended for internal use by the library.
  void init(
    CanvasBloc canvasBloc,
    SelectionBloc selectionBloc,
    ToolBloc toolBloc,
  ) {
    _canvasBloc = canvasBloc;
    _selectionBloc = selectionBloc;
    _toolBloc = toolBloc;
    _isInitialized = true;
  }

  /// Throws an error if the controller has not been attached to an [FlowDraw] widget.
  void _assertIsInitialized() {
    assert(
      _isInitialized,
      'FlowDrawController is not attached to an FlowDraw widget. '
      'Please pass this controller to the `controller` property of an FlowDraw widget.',
    );
  }

  // --- State Getters and Streams ---

  /// Provides a stream of [CanvasState] updates.
  /// Listen to this to react to changes in nodes, drawing objects, or viewport.
  @override
  Stream<CanvasState> get canvasStateStream {
    _assertIsInitialized();
    return _canvasBloc!.stream;
  }

  /// Gets the current [CanvasState].
  @override
  CanvasState get canvasState {
    _assertIsInitialized();
    return _canvasBloc!.state;
  }

  /// Provides a stream of [SelectionState] updates.
  /// Listen to this to react to changes in object selection.
  @override
  Stream<SelectionState> get selectionStateStream {
    _assertIsInitialized();
    return _selectionBloc!.stream;
  }

  /// Gets the current [SelectionState].
  @override
  SelectionState get selectionState {
    _assertIsInitialized();
    return _selectionBloc!.state;
  }

  /// Provides a stream of [ToolState] updates.
  /// Listen to this to react to changes in the active tool.
  @override
  Stream<ToolState> get toolStateStream {
    _assertIsInitialized();
    return _toolBloc!.stream;
  }

  /// Gets the current [ToolState].
  @override
  ToolState get toolState {
    _assertIsInitialized();
    return _toolBloc!.state;
  }

  /// Gets the list of all [NodeInstance]s currently in the canvas.
  @override
  Map<String, NodeInstance> get nodes {
    _assertIsInitialized();
    return canvasState.nodes;
  }

  /// Gets the list of all [DrawingObject]s currently in the canvas.
  @override
  Map<String, DrawingObject> get drawingObjects {
    _assertIsInitialized();
    return canvasState.drawingObjects;
  }

  /// Gets the current viewport offset.
  @override
  Offset get viewportOffset {
    _assertIsInitialized();
    return canvasState.viewportOffset;
  }

  /// Gets the current viewport zoom level.
  @override
  double get viewportZoom {
    _assertIsInitialized();
    return canvasState.viewportZoom;
  }

  /// Gets the undo history stack.
  @override
  List<HistoryEntry> get undoStack {
    _assertIsInitialized();
    return canvasState.undoStack;
  }

  /// Gets the redo history stack.
  @override
  List<HistoryEntry> get redoStack {
    _assertIsInitialized();
    return canvasState.redoStack;
  }

  // --- Tool Methods ---

  /// Sets the active drawing tool.
  @override
  void setTool(EditorTool tool) {
    _assertIsInitialized();
    _toolBloc!.add(ToolSelected(tool));
  }

  // --- History Methods ---

  /// Reverts the last action.
  @override
  void undo() {
    _assertIsInitialized();
    _canvasBloc!.add(UndoRequested());
  }

  /// Re-applies the last undone action.
  @override
  void redo() {
    _assertIsInitialized();
    _canvasBloc!.add(RedoRequested());
  }

  /// Restores the canvas to the snapshot stored at [undoIndex] in the undo stack
  /// (0 = oldest). The current state is pushed first, so the jump is undoable.
  /// Backs the version-timeline "Restore" action.
  void restoreTo(int undoIndex) {
    _assertIsInitialized();
    _canvasBloc!.add(HistoryRestored(undoIndex));
  }

  // --- Object Manipulation Methods ---

  /// Adds a new [NodeInstance] to the canvas.
  @override
  void addNode(NodeInstance node) {
    _assertIsInitialized();
    _canvasBloc!.add(NodeAdded(node));
  }

  /// Adds a new [DrawingObject] (e.g., Rectangle, Circle) to the canvas.
  @override
  void addDrawingObject(DrawingObject object) {
    _assertIsInitialized();
    _canvasBloc!.add(DrawingObjectAdded(object));
  }

  /// Removes a set of objects from the canvas by their IDs.
  @override
  void removeObjects({
    Set<String> nodeIds = const {},
    Set<String> drawingObjectIds = const {},
  }) {
    _assertIsInitialized();
    _canvasBloc!.add(
      ObjectsRemoved(nodeIds: nodeIds, drawingObjectIds: drawingObjectIds),
    );
  }

  /// Removes all currently selected objects from the canvas.
  @override
  void removeSelectedObjects() {
    _assertIsInitialized();
    final selection = selectionState;
    removeObjects(
      nodeIds: selection.selectedNodeIds,
      drawingObjectIds: selection.selectedDrawingObjectIds,
    );
  }

  // --- Selection Methods ---

  /// Clears the current selection.
  @override
  void clearSelection() {
    _assertIsInitialized();
    _selectionBloc!.add(SelectionCleared());
  }

  /// Replaces the current selection with a new set of objects.
  @override
  void setSelection({
    Set<String> nodeIds = const {},
    Set<String> drawingObjectIds = const {},
  }) {
    _assertIsInitialized();
    _selectionBloc!.add(
      SelectionReplaced(nodeIds: nodeIds, drawingObjectIds: drawingObjectIds),
    );
  }

  // --- Viewport Methods ---

  /// Pans the canvas by the given [delta] offset.
  @override
  void pan(Offset delta) {
    _assertIsInitialized();
    _canvasBloc!.add(CanvasPanned(delta));
  }

  /// Zooms the canvas to a specific [newZoom] level.
  /// The zoom level is clamped between 0.1 and 10.0.
  @override
  void zoom(double newZoom) {
    _assertIsInitialized();
    _canvasBloc!.add(CanvasZoomed(newZoom.clamp(0.1, 10.0)));
  }

  /// Zooms in by a fixed factor.
  @override
  void zoomIn([double factor = 1.2]) {
    _assertIsInitialized();
    zoom(canvasState.viewportZoom * factor);
  }

  /// Zooms out by a fixed factor.
  @override
  void zoomOut([double factor = 1.2]) {
    _assertIsInitialized();
    zoom(canvasState.viewportZoom / factor);
  }

  /// Resets the canvas zoom to 1.0.
  @override
  void resetZoom() {
    _assertIsInitialized();
    zoom(1.0);
  }

  /// Resets the canvas pan to the center (Offset.zero).
  @override
  void centerView() {
    _assertIsInitialized();
    // To set the offset to zero, we need to pan by the negative of the current offset.
    _canvasBloc!.add(CanvasPanned(-canvasState.viewportOffset));
  }

  // --- Project Methods ---

  /// Clears the canvas to start a new project.
  @override
  void createNewProject() {
    _assertIsInitialized();
    _canvasBloc!.add(NewProjectCreated());
  }

  /// Loads a project from the given [data] map.
  @override
  void loadProject(Map<String, dynamic> data) {
    _assertIsInitialized();
    _canvasBloc!.add(ProjectLoaded(data));
  }

  /// Triggers a save action. The [onSave] callback will receive the project data.
  @override
  void saveProject(Function(Map<String, dynamic>) onSave) {
    _assertIsInitialized();
    _canvasBloc!.add(ProjectSaved(onSave: onSave));
  }

  // --- Mermaid Methods ---

  /// Exports the current canvas (or selected objects) as a Mermaid flowchart string.
  @override
  String exportMermaid({Set<String>? selectedIds}) {
    _assertIsInitialized();
    return MermaidExporter.export(
      canvasState.drawingObjects,
      selectedIds: selectedIds,
    );
  }

  /// Imports a Mermaid flowchart string, replacing the current canvas.
  @override
  void importMermaid(String mermaid) {
    _assertIsInitialized();
    final projectData = MermaidImporter.import(mermaid);
    _canvasBloc!.add(ProjectLoaded(projectData));
  }

  // --- View Settings ---

  /// Toggles grid visibility on/off.
  @override
  void toggleGrid() {
    _assertIsInitialized();
    _canvasBloc!.add(const GridToggled());
  }

  /// Runs the "Tidy" layered auto-layout: repositions boxes top-to-bottom to
  /// minimize edge crossings and fits the view to the result.
  @override
  void tidy() {
    _assertIsInitialized();
    _canvasBloc!.add(const AutoLayoutRequested());
  }

  /// Disposes of the controller's resources.
  /// Should be called when the controller is no longer needed.
  /// This is handled automatically by the `FlowDraw` widget.
  @override
  void dispose() {
    _canvasBloc = null;
    _selectionBloc = null;
    _toolBloc = null;
    _isInitialized = false;
  }
}
