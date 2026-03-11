part of 'canvas_bloc.dart';

enum QuickActionDirection { top, right, bottom, left }

sealed class CanvasEvent extends Equatable {
  final bool isUndoable;
  const CanvasEvent({this.isUndoable = true});

  String get description => 'Unknown Action';

  @override
  List<Object?> get props => [isUndoable];
}

final class CanvasTransformed extends CanvasEvent {
  final double zoom;
  final Offset offset;

  const CanvasTransformed({required this.zoom, required this.offset})
      : super(isUndoable: false);

  @override
  String get description => 'Transformed Canvas';

  @override
  List<Object> get props => [zoom, offset];
}

final class CanvasPanned extends CanvasEvent {
  final Offset delta;

  const CanvasPanned(this.delta);

  @override
  String get description => 'Panned Canvas';

  @override
  List<Object> get props => [delta];
}

final class CanvasZoomed extends CanvasEvent {
  final double zoom;

  const CanvasZoomed(this.zoom);

  @override
  String get description => 'Zoomed Canvas';

  @override
  List<Object> get props => [zoom];
}

// --- Object Manipulation Events ---
final class NodeAdded extends CanvasEvent {
  final NodeInstance node;

  const NodeAdded(this.node);

  @override
  String get description => 'Added Node "${node.heading ?? 'Untitled'}"';

  @override
  List<Object> get props => [node];
}

final class DrawingObjectAdded extends CanvasEvent {
  final DrawingObject object;

  const DrawingObjectAdded(this.object);

  @override
  String get description {
    if (object is RectangleObject) return 'Added Rectangle';
    if (object is CircleObject) return 'Added Circle';
    if (object is DiamondObject) return 'Added Diamond';
    if (object is ArrowObject) return 'Added Arrow';
    if (object is LineObject) return 'Added Line';
    if (object is TextObject) return 'Added Text';
    if (object is FigureObject) return 'Added Figure';
    if (object is PencilStrokeObject) return 'Added Drawing';
    return 'Added Object';
  }

  @override
  List<Object> get props => [object];
}

final class ObjectsRemoved extends CanvasEvent {
  final Set<String> nodeIds;
  final Set<String> drawingObjectIds;

  const ObjectsRemoved({required this.nodeIds, required this.drawingObjectIds});

  @override
  String get description {
    final count = nodeIds.length + drawingObjectIds.length;
    return 'Removed $count object(s)';
  }

  @override
  List<Object> get props => [nodeIds, drawingObjectIds];
}

final class ObjectsDragged extends CanvasEvent {
  final Set<String> objectIds;
  final Offset delta;

  const ObjectsDragged(this.objectIds, this.delta) : super(isUndoable: false);

  @override
  List<Object> get props => [objectIds, delta];
}

final class ObjectsDragEnded extends CanvasEvent {
  final Set<String> objectIds;
  // This event marks the end of a drag and IS undoable.
  const ObjectsDragEnded(this.objectIds) : super(isUndoable: true);

  @override
  String get description => 'Moved object(s)';

  @override
  List<Object> get props => [objectIds];
}

final class ObjectsNudged extends CanvasEvent {
  final Set<String> objectIds;
  final Offset delta;
  const ObjectsNudged(this.objectIds, this.delta) : super(isUndoable: true);

  @override
  String get description => 'Nudged object(s)';

  @override
  List<Object> get props => [objectIds, delta];
}

final class DrawingObjectUpdated extends CanvasEvent {
  final DrawingObject object;

  const DrawingObjectUpdated(this.object);

  @override
  List<Object> get props => [object];
}

final class ObjectsResizeEnded extends CanvasEvent {
  const ObjectsResizeEnded() : super(isUndoable: true);

  @override
  String get description => 'Resized object(s)';
}

final class ObjectsRotationEnded extends CanvasEvent {
  const ObjectsRotationEnded() : super(isUndoable: true);
  @override
  String get description => 'Rotated object(s)';
}

final class NodeValueUpdated extends CanvasEvent {
  final String nodeId;
  final String value;

  const NodeValueUpdated(this.nodeId, this.value);

  @override
  String get description => 'Updated node content: $nodeId';

  @override
  List<Object> get props => [nodeId];
}

final class NodeHeadingUpdated extends CanvasEvent {
  final String nodeId;
  final String heading;

  const NodeHeadingUpdated(this.nodeId, this.heading);

  @override
  String get description => 'Updated node heading: $nodeId';

  @override
  List<Object> get props => [nodeId];
}

final class NodeToggled extends CanvasEvent {
  final String nodeId;

  const NodeToggled(this.nodeId);

  @override
  String get description => 'Toggled node collapse: $nodeId';

  @override
  List<Object> get props => [nodeId];
}

// --- History Events ---
final class UndoRequested extends CanvasEvent {}

final class RedoRequested extends CanvasEvent {}

// --- Project Events ---
final class ProjectSaved extends CanvasEvent {
  final Function(Map<String, dynamic>) onSave;

  const ProjectSaved({required this.onSave});

  @override
  List<Object> get props => [onSave];
}

final class ProjectLoaded extends CanvasEvent {
  final Map<String, dynamic> data;

  const ProjectLoaded(this.data);

  @override
  List<Object> get props => [data];
}

final class NewProjectCreated extends CanvasEvent {}

final class GridToggled extends CanvasEvent {
  const GridToggled() : super(isUndoable: false);
}

// --- Clipboard Events ---
final class SelectionCopied extends CanvasEvent {}

final class SelectionCut extends CanvasEvent {}

final class SelectionPasted extends CanvasEvent {
  final Offset pastePosition;

  const SelectionPasted({required this.pastePosition});

  @override
  List<Object> get props => [pastePosition];
}

// --- Duplicate Event ---
final class SelectionDuplicated extends CanvasEvent {
  final Set<String> selectedDrawingObjectIds;

  const SelectionDuplicated(this.selectedDrawingObjectIds);

  @override
  String get description => 'Duplicated selection';

  @override
  List<Object> get props => [selectedDrawingObjectIds];
}

// --- Z-ordering Events ---
final class ObjectsBroughtForward extends CanvasEvent {
  final Set<String> selectedIds;

  const ObjectsBroughtForward(this.selectedIds);

  @override
  String get description => 'Brought forward';

  @override
  List<Object> get props => [selectedIds];
}

final class ObjectsSentBackward extends CanvasEvent {
  final Set<String> selectedIds;

  const ObjectsSentBackward(this.selectedIds);

  @override
  String get description => 'Sent backward';

  @override
  List<Object> get props => [selectedIds];
}

final class ObjectsBroughtToFront extends CanvasEvent {
  final Set<String> selectedIds;

  const ObjectsBroughtToFront(this.selectedIds);

  @override
  String get description => 'Brought to front';

  @override
  List<Object> get props => [selectedIds];
}

final class ObjectsSentToBack extends CanvasEvent {
  final Set<String> selectedIds;

  const ObjectsSentToBack(this.selectedIds);

  @override
  String get description => 'Sent to back';

  @override
  List<Object> get props => [selectedIds];
}

enum AlignmentType { left, centerH, right, top, centerV, bottom }

enum DistributionType { horizontal, vertical }

final class ObjectsAligned extends CanvasEvent {
  final Set<String> selectedIds;
  final AlignmentType alignmentType;

  const ObjectsAligned(this.selectedIds, this.alignmentType)
      : super(isUndoable: true);

  @override
  String get description => 'Aligned objects (${alignmentType.name})';

  @override
  List<Object> get props => [selectedIds, alignmentType];
}

final class ObjectsDistributed extends CanvasEvent {
  final Set<String> selectedIds;
  final DistributionType distributionType;

  const ObjectsDistributed(this.selectedIds, this.distributionType)
      : super(isUndoable: true);

  @override
  String get description => 'Distributed objects (${distributionType.name})';

  @override
  List<Object> get props => [selectedIds, distributionType];
}

final class ObjectDuplicatedWithConnection extends CanvasEvent {
  final String sourceObjectId;
  final QuickActionDirection direction;

  const ObjectDuplicatedWithConnection(this.sourceObjectId, this.direction);

  @override
  String get description => 'Created connected shape';

  @override
  List<Object> get props => [sourceObjectId, direction];
}