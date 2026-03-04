import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';

part 'tool_event.dart';
part 'tool_state.dart';

class ToolBloc extends Bloc<ToolEvent, ToolState> {
  ToolBloc() : super(const ToolState()) {
    on<ToolEvent>((event, emit) async {
      return (switch (event) {
        ToolSelected e => _onToolSelected(e, emit),
        LineStyleSelected e => _onLineStyleSelected(e, emit),
      });
    });
  }

  void _onToolSelected(ToolSelected event, Emitter<ToolState> emit) {
    emit(ToolState(activeTool: event.tool, lineStyle: state.lineStyle));
  }

  void _onLineStyleSelected(LineStyleSelected event, Emitter<ToolState> emit) {
    emit(ToolState(activeTool: state.activeTool, lineStyle: event.lineStyle));
  }
}