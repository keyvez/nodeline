import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'selection_event.dart';
part 'selection_state.dart';

class SelectionBloc extends Bloc<SelectionEvent, SelectionState> {
  SelectionBloc() : super(const SelectionState()) {
    on<SelectionEvent>((event, emit) async {
      return (switch (event) {
        SelectionObjectsAdded e => _onSelectionObjectsAdded(e, emit),
        SelectionReplaced e => _onSelectionReplaced(e, emit),
        SelectionCleared e => _onSelectionCleared(e, emit),
        DrawingObjectHovered e => _onDrawingObjectHovered(e, emit),
      });
    });
  }

  void _onSelectionObjectsAdded(
      SelectionObjectsAdded event, Emitter<SelectionState> emit) {
    emit(state.copyWith(
      selectedNodeIds: {...state.selectedNodeIds, ...event.nodeIds},
      selectedDrawingObjectIds: {
        ...state.selectedDrawingObjectIds,
        ...event.drawingObjectIds
      },
    ));
  }

  void _onSelectionReplaced(
      SelectionReplaced event, Emitter<SelectionState> emit) {
    emit(state.copyWith(
      selectedNodeIds: event.nodeIds,
      selectedDrawingObjectIds: event.drawingObjectIds,
    ));
  }

  void _onSelectionCleared(
      SelectionCleared event, Emitter<SelectionState> emit) {
    emit(const SelectionState());
  }

  void _onDrawingObjectHovered(
      DrawingObjectHovered event, Emitter<SelectionState> emit) {
    if (state.hoveredDrawingObjectId == event.drawingObjectId) return;
    if (event.drawingObjectId == null) {
      emit(state.copyWith(clearHoveredDrawingObjectId: true));
    } else {
      emit(state.copyWith(hoveredDrawingObjectId: event.drawingObjectId));
    }
  }
}