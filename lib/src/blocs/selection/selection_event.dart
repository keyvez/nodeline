part of 'selection_bloc.dart';

sealed class SelectionEvent extends Equatable {
  const SelectionEvent();

  @override
  List<Object> get props => [];
}

/// Event to add a set of IDs to the current selection.
final class SelectionObjectsAdded extends SelectionEvent {
  final Set<String> nodeIds;
  final Set<String> drawingObjectIds;
  // We will add links back in a later phase

  const SelectionObjectsAdded({
    this.nodeIds = const {},
    this.drawingObjectIds = const {},
  });

  @override
  List<Object> get props => [nodeIds, drawingObjectIds];
}

/// Event to replace the current selection with a new set of IDs.
final class SelectionReplaced extends SelectionEvent {
  final Set<String> nodeIds;
  final Set<String> drawingObjectIds;

  const SelectionReplaced({
    this.nodeIds = const {},
    this.drawingObjectIds = const {},
  });

  @override
  List<Object> get props => [nodeIds, drawingObjectIds];
}


/// Event to clear the entire selection.
final class SelectionCleared extends SelectionEvent {}

/// Event to update which drawing object is currently hovered.
final class DrawingObjectHovered extends SelectionEvent {
  final String? drawingObjectId;

  const DrawingObjectHovered({this.drawingObjectId});

  @override
  List<Object> get props => [drawingObjectId ?? ''];
}