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
    if (object is ParallelogramObject) return 'Added Parallelogram';
    if (object is ForkJoinObject) return 'Added Fork/Join';
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

/// Begins an agent-turn transaction: captures a pre-turn snapshot and suppresses
/// per-event undo pushes so that the whole turn collapses into a single undo
/// entry. Pair with [AgentTurnCommitted]. Not undoable itself.
final class AgentTurnBegan extends CanvasEvent {
  const AgentTurnBegan() : super(isUndoable: false);

  @override
  String get description => 'Agent turn began';

  @override
  List<Object> get props => [];
}

/// Ends an agent-turn transaction, pushing ONE undo entry (the pre-turn
/// snapshot) labelled with [summary] — the agent's one-line description of what
/// the turn did. If no state changed during the turn, nothing is pushed.
final class AgentTurnCommitted extends CanvasEvent {
  final String summary;

  const AgentTurnCommitted(this.summary) : super(isUndoable: false);

  @override
  String get description => summary.isEmpty ? 'Canvas Mode edit' : summary;

  @override
  List<Object> get props => [summary];
}

/// Restores the canvas to the snapshot stored at [undoIndex] in the undo stack
/// (0 = oldest). The current state is pushed onto the undo stack first, so the
/// jump is itself undoable. Backs the version-timeline "Restore" action.
final class HistoryRestored extends CanvasEvent {
  final int undoIndex;

  const HistoryRestored(this.undoIndex) : super(isUndoable: false);

  @override
  String get description => 'Restored version';

  @override
  List<Object> get props => [undoIndex];
}

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

final class ObjectColorsChanged extends CanvasEvent {
  final Set<String> selectedIds;
  final Color? fillColor;
  final Color? strokeColor;
  final bool clearFill;
  final bool clearStroke;

  const ObjectColorsChanged(
    this.selectedIds, {
    this.fillColor,
    this.strokeColor,
    this.clearFill = false,
    this.clearStroke = false,
  }) : super(isUndoable: true);

  @override
  String get description => 'Changed object colors';

  @override
  List<Object> get props => [selectedIds, clearFill, clearStroke];
}

/// Changes the line (stroke) style of the selected shapes/edges — e.g. turning
/// a set of arrows dashed, or shape borders dotted. Applies to every object in
/// [selectedIds] that carries a [LineStyle] (rectangles, circles, diamonds,
/// parallelograms, fork/join bars, arrows, lines); others are left untouched.
/// Undoable as one step.
final class ObjectsLineStyleChanged extends CanvasEvent {
  final Set<String> selectedIds;
  final LineStyle lineStyle;

  const ObjectsLineStyleChanged(this.selectedIds, this.lineStyle)
      : super(isUndoable: true);

  @override
  String get description => 'Changed line style (${lineStyle.name})';

  @override
  List<Object> get props => [selectedIds, lineStyle];
}

/// Changes the global default font for shape text.
///
/// Updates [CanvasState.defaultFontFamily]/[defaultFontSize] and, by extension,
/// repaints every shape whose font has *not* been individually customized.
/// Customized shapes ([fontCustomized] true) are left untouched.
final class GlobalFontChanged extends CanvasEvent {
  /// New default font family, or null to leave it unchanged.
  final String? fontFamily;

  /// New default font size, or null to leave it unchanged.
  final double? fontSize;

  const GlobalFontChanged({this.fontFamily, this.fontSize})
      : super(isUndoable: true);

  @override
  String get description => 'Changed default font';

  @override
  List<Object> get props => [fontFamily ?? '', fontSize ?? 0];
}

/// Sets a per-shape font override on the selected shapes, marking each as
/// individually customized so global font changes no longer affect them.
final class ObjectFontChanged extends CanvasEvent {
  final Set<String> selectedIds;

  /// New font family for the selection, or null to keep each shape's current
  /// family (falling back to the global default when none).
  final String? fontFamily;

  /// New font size for the selection, or null to keep each shape's current size.
  final double? fontSize;

  const ObjectFontChanged(
    this.selectedIds, {
    this.fontFamily,
    this.fontSize,
  }) : super(isUndoable: true);

  @override
  String get description => 'Changed object font';

  @override
  List<Object> get props => [selectedIds, fontFamily ?? '', fontSize ?? 0];
}

/// Clears the per-shape font override on the selected shapes, so they follow
/// the global default font again.
final class ObjectFontReset extends CanvasEvent {
  final Set<String> selectedIds;

  const ObjectFontReset(this.selectedIds) : super(isUndoable: true);

  @override
  String get description => 'Reset object font to default';

  @override
  List<Object> get props => [selectedIds];
}

/// Resizes shapes so each box fits its text label exactly (grows tight boxes,
/// shrinks oversized ones), keeping each shape centered on its current center.
///
/// When [selectedIds] is non-empty only those shapes are fitted; otherwise
/// every text-bearing shape on the canvas is fitted. Undoable as one step.
///
/// [margin] is extra breathing room (in world px) added on every side around
/// the text, on top of the per-shape base padding. Defaults to
/// [kDefaultFitMargin].
final class NodesFittedToContent extends CanvasEvent {
  /// Shapes to fit. Empty means "fit all text-bearing shapes".
  final Set<String> selectedIds;

  /// Extra padding around the text on each side, in world pixels.
  final double margin;

  const NodesFittedToContent(
    this.selectedIds, {
    this.margin = kDefaultFitMargin,
  }) : super(isUndoable: true);

  @override
  String get description => 'Fit nodes to content';

  @override
  List<Object> get props => [selectedIds, margin];
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

/// Minimizes edge crossings among the selected arrows.
///
/// When [changeConnectionPoints] is true, the algorithm is free to reassign
/// which port on each endpoint the arrow connects to (top/right/bottom/left).
/// When false, only the routing (waypoints) is re-optimized while keeping
/// the same attachment relative positions.
final class CrossingsMinimized extends CanvasEvent {
  /// IDs of the arrows (and optionally shapes) to consider.
  final Set<String> selectedIds;

  /// Whether the algorithm may change which port an arrow connects to.
  final bool changeConnectionPoints;

  const CrossingsMinimized(
    this.selectedIds, {
    required this.changeConnectionPoints,
  }) : super(isUndoable: true);

  @override
  String get description => changeConnectionPoints
      ? 'Minimized crossings (with rerouting)'
      : 'Minimized crossings (routing only)';

  @override
  List<Object> get props => [selectedIds, changeConnectionPoints];
}

/// Repositions nodes to new top-left offsets computed by an auto-layout
/// (layered/Sugiyama). Undoable as a single step.
final class AutoLayoutApplied extends CanvasEvent {
  /// New top-left offset per node id.
  final Map<String, Offset> nodeOffsets;

  const AutoLayoutApplied(this.nodeOffsets);

  @override
  String get description => 'Auto-layout';

  @override
  List<Object> get props => [nodeOffsets];
}

/// Signals that the user requested a "Tidy" auto-layout. The actual layout is
/// computed in the data layer (it needs rendered node geometry), which listens
/// for this event; the bloc handler is a no-op. Not undoable itself — the
/// resulting [AutoLayoutApplied] carries the undo step.
final class AutoLayoutRequested extends CanvasEvent {
  const AutoLayoutRequested() : super(isUndoable: false);

  @override
  String get description => 'Tidy';

  @override
  List<Object> get props => [];
}

/// Signals that the user requested "lay selected nodes along the selected guide
/// shape". Like [AutoLayoutRequested], computed in the data layer (needs
/// rendered node geometry); the bloc just relays it. Not undoable itself — the
/// resulting [AutoLayoutApplied] carries the undo step.
final class LayoutAlongGuideRequested extends CanvasEvent {
  const LayoutAlongGuideRequested() : super(isUndoable: false);

  @override
  String get description => 'Lay along path';

  @override
  List<Object> get props => [];
}

/// Signals that the user requested "Swap" — exchange two selected nodes'
/// positions or two selected edges' endpoints. Like [AutoLayoutRequested],
/// computed in the data layer; the bloc just relays it. Not undoable itself —
/// the resulting position/endpoint change carries the undo step.
final class SwapRequested extends CanvasEvent {
  const SwapRequested() : super(isUndoable: false);

  @override
  String get description => 'Swap';

  @override
  List<Object> get props => [];
}

/// Attaches a review comment to an entity (or a bare canvas point).
///
/// Not undoable — comments are feedback layered over the drawing, not part of
/// the document edit history.
final class CommentAdded extends CanvasEvent {
  final EntityComment comment;

  const CommentAdded(this.comment) : super(isUndoable: false);

  @override
  String get description => 'Added comment';

  @override
  List<Object> get props => [comment];
}

/// Removes a comment by id.
final class CommentRemoved extends CanvasEvent {
  final String commentId;

  const CommentRemoved(this.commentId) : super(isUndoable: false);

  @override
  String get description => 'Removed comment';

  @override
  List<Object> get props => [commentId];
}

/// Toggles a comment's resolved flag.
final class CommentResolvedToggled extends CanvasEvent {
  final String commentId;

  const CommentResolvedToggled(this.commentId) : super(isUndoable: false);

  @override
  String get description => 'Toggled comment resolved';

  @override
  List<Object> get props => [commentId];
}