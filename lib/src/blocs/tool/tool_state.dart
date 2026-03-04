part of 'tool_bloc.dart';

class ToolState extends Equatable {
  final EditorTool activeTool;
  final LineStyle lineStyle;

  const ToolState({this.activeTool = EditorTool.arrow, this.lineStyle = LineStyle.solid});

  @override
  List<Object> get props => [activeTool, lineStyle];
}