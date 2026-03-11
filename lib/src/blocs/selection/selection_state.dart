part of 'selection_bloc.dart';

class SelectionState extends Equatable {
  final Set<String> selectedNodeIds;
  final Set<String> selectedDrawingObjectIds;
  /// The id of the drawing object currently hovered by the pointer, or null.
  final String? hoveredDrawingObjectId;

  const SelectionState({
    this.selectedNodeIds = const {},
    this.selectedDrawingObjectIds = const {},
    this.hoveredDrawingObjectId,
  });

  SelectionState copyWith({
    Set<String>? selectedNodeIds,
    Set<String>? selectedDrawingObjectIds,
    String? hoveredDrawingObjectId,
    bool clearHoveredDrawingObjectId = false,
  }) {
    return SelectionState(
      selectedNodeIds: selectedNodeIds ?? this.selectedNodeIds,
      selectedDrawingObjectIds:
      selectedDrawingObjectIds ?? this.selectedDrawingObjectIds,
      hoveredDrawingObjectId: clearHoveredDrawingObjectId
          ? null
          : (hoveredDrawingObjectId ?? this.hoveredDrawingObjectId),
    );
  }

  @override
  List<Object?> get props => [selectedNodeIds, selectedDrawingObjectIds, hoveredDrawingObjectId];
}