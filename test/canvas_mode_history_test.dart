import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/blocs/selection/selection_bloc.dart';
import 'package:nodeline/src/core/agent/canvas_agent.dart';
import 'package:nodeline/src/core/agent/llm_provider.dart';
import 'package:nodeline/src/core/agent/tool_call.dart';
import 'package:nodeline/src/core/agent/tool_dispatcher.dart';
import 'package:nodeline/src/core/agent/tool_schemas.dart';
import 'package:nodeline/src/models/drawing_entities.dart';
import 'package:nodeline/src/models/styles.dart';

/// Step 5: versioning. An agent turn collapses into a single undo entry, undo
/// reverts the whole turn, entries are labelled, and HistoryRestored jumps to a
/// snapshot (itself undoable).

Future<void> _pump() => Future<void>.delayed(Duration.zero);

class _FakeProvider implements LlmProvider {
  final List<AgentResponse> script;
  int _i = 0;
  _FakeProvider(this.script);
  @override
  String get name => 'Fake';
  @override
  Future<AgentResponse> generate({
    required String systemPrompt,
    required List<ToolSchema> tools,
    required List<AgentMessage> history,
  }) async =>
      _i < script.length ? script[_i++] : const AgentResponse(text: 'done');
}

CanvasAgent _agent(List<AgentResponse> script, CanvasBloc canvas, SelectionBloc sel) =>
    CanvasAgent(
      provider: _FakeProvider(script),
      dispatcher: ToolDispatcher(canvasBloc: canvas, selectionBloc: sel),
    );

void main() {
  late CanvasBloc canvas;
  late SelectionBloc selection;

  setUp(() {
    canvas = CanvasBloc();
    selection = SelectionBloc();
  });
  tearDown(() {
    canvas.close();
    selection.close();
  });

  test('a multi-tool turn produces exactly one undo entry', () async {
    final agent = _agent([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'create_nodes', args: {
          'nodes': [
            {'label': 'A'},
            {'label': 'B'}
          ]
        }),
      ]),
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c2', name: 'create_edges', args: {
          'edges': [
            {'from': 'A', 'to': 'B'}
          ]
        }),
      ]),
      const AgentResponse(text: 'Created A→B.'),
    ], canvas, selection);

    await agent.run('make A and B connected').toList();
    await _pump();

    expect(canvas.state.drawingObjects, hasLength(3)); // 2 nodes + 1 edge
    expect(canvas.state.undoStack, hasLength(1));
    expect(canvas.state.undoStack.single.$2.description, 'Created A→B.');
  });

  test('undo reverts the whole agent turn at once', () async {
    final agent = _agent([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'create_nodes', args: {
          'nodes': [
            {'label': 'A'},
            {'label': 'B'},
            {'label': 'C'}
          ]
        }),
      ]),
      const AgentResponse(text: 'Made three nodes.'),
    ], canvas, selection);

    await agent.run('make three nodes').toList();
    await _pump();
    expect(canvas.state.drawingObjects, hasLength(3));

    canvas.add(UndoRequested());
    await _pump();
    expect(canvas.state.drawingObjects, isEmpty); // whole turn reverted
  });

  test('a turn that changes nothing pushes no history', () async {
    // Only a read tool then text — no mutation.
    final agent = _agent([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'get_canvas_summary'),
      ]),
      const AgentResponse(text: 'You have 0 objects.'),
    ], canvas, selection);

    await agent.run('how many objects?').toList();
    await _pump();
    expect(canvas.state.undoStack, isEmpty);
  });

  test('a pure question turn (no tools) opens no transaction', () async {
    final agent = _agent([
      const AgentResponse(text: 'Hello!'),
    ], canvas, selection);
    await agent.run('hi').toList();
    await _pump();
    expect(canvas.state.undoStack, isEmpty);
  });

  test('manual edits before/after a turn keep separate undo entries', () async {
    // Manual edit 1.
    canvas.add(DrawingObjectAdded(RectangleObject(
      id: 'm1',
      rect: const Rect.fromLTWH(0, 0, 50, 50),
    )));
    await _pump();
    expect(canvas.state.undoStack, hasLength(1));

    // Agent turn (one entry).
    final agent = _agent([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'create_nodes', args: {
          'nodes': [
            {'label': 'A'}
          ]
        }),
      ]),
      const AgentResponse(text: 'Added A.'),
    ], canvas, selection);
    await agent.run('add A').toList();
    await _pump();

    expect(canvas.state.undoStack, hasLength(2));
    expect(canvas.state.undoStack.last.$2.description, 'Added A.');
  });

  test('HistoryRestored jumps to a snapshot and is itself undoable', () async {
    // Turn 1: add A.
    await _agent([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'create_nodes', args: {
          'nodes': [
            {'label': 'A'}
          ]
        }),
      ]),
      const AgentResponse(text: 'Added A.'),
    ], canvas, selection)
        .run('add A')
        .toList();
    await _pump();

    // Turn 2: add B.
    await _agent([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c2', name: 'create_nodes', args: {
          'nodes': [
            {'label': 'B'}
          ]
        }),
      ]),
      const AgentResponse(text: 'Added B.'),
    ], canvas, selection)
        .run('add B')
        .toList();
    await _pump();

    expect(canvas.state.drawingObjects, hasLength(2));
    expect(canvas.state.undoStack, hasLength(2));

    // Restore to entry 0 (the snapshot BEFORE turn 1 = empty canvas).
    canvas.add(const HistoryRestored(0));
    await _pump();
    expect(canvas.state.drawingObjects, isEmpty);

    // The restore is itself undoable → undo brings back both nodes.
    canvas.add(UndoRequested());
    await _pump();
    expect(canvas.state.drawingObjects, hasLength(2));
  });

  test('set_line_style inside a turn is one undoable entry', () async {
    canvas.add(DrawingObjectAdded(ArrowObject(
      id: 'a1',
      start: Offset.zero,
      end: const Offset(50, 50),
    )));
    await _pump();
    final baseUndo = canvas.state.undoStack.length;

    final agent = _agent([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'select', args: {'kind': 'edge'}),
      ]),
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c2', name: 'set_line_style', args: {'style': 'dashed'}),
      ]),
      const AgentResponse(text: 'Dashed the edge.'),
    ], canvas, selection);
    await agent.run('make edges dashed').toList();
    await _pump();

    expect((canvas.state.drawingObjects['a1'] as ArrowObject).lineStyle,
        LineStyle.dashed);
    expect(canvas.state.undoStack.length, baseUndo + 1);

    canvas.add(UndoRequested());
    await _pump();
    expect((canvas.state.drawingObjects['a1'] as ArrowObject).lineStyle,
        LineStyle.solid);
  });
}
