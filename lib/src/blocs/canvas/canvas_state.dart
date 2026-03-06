part of 'canvas_bloc.dart';

typedef HistoryEntry = (CanvasState state, CanvasEvent event);

final class CanvasState extends Equatable {
  final Map<String, NodeInstance> nodes;
  final Map<String, DrawingObject> drawingObjects;
  final Offset viewportOffset;
  final double viewportZoom;
  final bool showGrid;

  // History stacks
  final List<HistoryEntry> undoStack;
  final List<HistoryEntry> redoStack;

  const CanvasState({
    this.nodes = const {},
    this.drawingObjects = const {},
    this.viewportOffset = Offset.zero,
    this.viewportZoom = 1.0,
    this.showGrid = true,
    this.undoStack = const [],
    this.redoStack = const [],
  });

  // A helper constructor to create a "historic" state without its own history stacks
  CanvasState.historic({
    required this.nodes,
    required this.drawingObjects,
    required this.viewportOffset,
    required this.viewportZoom,
    this.showGrid = true,
  }) : undoStack = [],
       redoStack = [];

  CanvasState copyWith({
    Map<String, NodeInstance>? nodes,
    Map<String, DrawingObject>? drawingObjects,
    Offset? viewportOffset,
    double? viewportZoom,
    bool? showGrid,
    List<HistoryEntry>? undoStack,
    List<HistoryEntry>? redoStack,
  }) {
    return CanvasState(
      nodes: nodes ?? this.nodes,
      drawingObjects: drawingObjects ?? this.drawingObjects,
      viewportOffset: viewportOffset ?? this.viewportOffset,
      viewportZoom: viewportZoom ?? this.viewportZoom,
      showGrid: showGrid ?? this.showGrid,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
    );
  }

  @override
  List<Object> get props => [
    nodes,
    drawingObjects,
    viewportOffset,
    viewportZoom,
    showGrid,
    undoStack,
    redoStack,
  ];
}
