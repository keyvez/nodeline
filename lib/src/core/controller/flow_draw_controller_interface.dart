import 'dart:async';

import 'package:flow_draw/flow_draw.dart';
import 'package:flutter/widgets.dart';

abstract class FlowDrawControllerInterface {
  Stream<CanvasState> get canvasStateStream;

  CanvasState get canvasState;

  Stream<SelectionState> get selectionStateStream;

  SelectionState get selectionState;

  Stream<ToolState> get toolStateStream;

  ToolState get toolState;

  Map<String, NodeInstance> get nodes;

  Map<String, DrawingObject> get drawingObjects;

  Offset get viewportOffset;

  double get viewportZoom;

  List<HistoryEntry> get undoStack;

  List<HistoryEntry> get redoStack;

  // --- Tool Methods ---

  void setTool(EditorTool tool);

  // --- History Methods ---

  void undo();

  void redo();

  // --- Object Manipulation Methods ---

  void addNode(NodeInstance node);

  void addDrawingObject(DrawingObject object);

  void removeObjects({Set<String> nodeIds, Set<String> drawingObjectIds});

  void removeSelectedObjects();

  // --- Selection Methods ---

  void clearSelection();

  void setSelection({Set<String> nodeIds, Set<String> drawingObjectIds});

  // --- Viewport Methods ---

  void pan(Offset delta);

  void zoom(double newZoom);

  void zoomIn([double factor = 1.2]);

  void zoomOut([double factor = 1.2]);

  void resetZoom();

  void centerView();

  // --- Project Methods ---

  void createNewProject();

  void loadProject(Map<String, dynamic> data);

  void saveProject(Function(Map<String, dynamic>) onSave);

  // --- View Settings ---

  void toggleGrid();

  /// Runs the layered "Tidy" auto-layout (minimize crossings + fit view).
  void tidy();

  // --- Mermaid Methods ---

  String exportMermaid({Set<String>? selectedIds});

  void importMermaid(String mermaid);

  // --- Lifecycle ---

  void dispose();
}
