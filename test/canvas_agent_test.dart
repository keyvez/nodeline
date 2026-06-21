import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/blocs/selection/selection_bloc.dart';
import 'package:flow_draw/src/core/agent/canvas_agent.dart';
import 'package:flow_draw/src/core/agent/llm_provider.dart';
import 'package:flow_draw/src/core/agent/tool_call.dart';
import 'package:flow_draw/src/core/agent/tool_dispatcher.dart';
import 'package:flow_draw/src/core/agent/tool_schemas.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';

/// Step 3: the agent loop. Driven by a scripted fake provider so the full
/// tool-use cycle (prompt → tool calls → dispatch → results → loop → final
/// text) is exercised against real BLoCs with no network.

Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// A provider that returns a pre-scripted [AgentResponse] per round, ignoring
/// the model logic. Records the histories it was given so tests can assert the
/// loop fed tool results back.
class FakeProvider implements LlmProvider {
  final List<AgentResponse> script;
  int _i = 0;
  final List<List<AgentMessage>> seenHistories = [];

  FakeProvider(this.script);

  @override
  String get name => 'Fake';

  @override
  Future<AgentResponse> generate({
    required String systemPrompt,
    required List<ToolSchema> tools,
    required List<AgentMessage> history,
  }) async {
    seenHistories.add(List.of(history));
    if (_i >= script.length) return const AgentResponse(text: 'done');
    return script[_i++];
  }
}

void main() {
  late CanvasBloc canvas;
  late SelectionBloc selection;
  late ToolDispatcher dispatcher;

  setUp(() {
    canvas = CanvasBloc();
    selection = SelectionBloc();
    dispatcher = ToolDispatcher(canvasBloc: canvas, selectionBloc: selection);
  });

  tearDown(() {
    canvas.close();
    selection.close();
  });

  test('single tool round then final text', () async {
    final provider = FakeProvider([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'create_nodes', args: {
          'nodes': [
            {'label': 'Hello'}
          ]
        }),
      ]),
      const AgentResponse(text: 'Created the node.'),
    ]);
    final agent = CanvasAgent(provider: provider, dispatcher: dispatcher);

    final events = await agent.run('make a node called Hello').toList();
    await _pump();

    expect(canvas.state.drawingObjects.values.whereType<RectangleObject>(), hasLength(1));
    expect(events.whereType<AgentToolFinished>(), hasLength(1));
    final done = events.whereType<AgentDone>().single;
    expect(done.finalText, 'Created the node.');
    expect(done.cancelled, false);
  });

  test('feeds tool results back into the next round', () async {
    final provider = FakeProvider([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'get_canvas_summary'),
      ]),
      const AgentResponse(text: 'ok'),
    ]);
    final agent = CanvasAgent(provider: provider, dispatcher: dispatcher);

    await agent.run('how many objects?').toList();

    // The 2nd provider call must have seen a toolResults turn appended.
    expect(provider.seenHistories.length, 2);
    final secondHistory = provider.seenHistories[1];
    expect(secondHistory.any((m) => m.role == AgentRole.toolResults), true);
  });

  test('multi-round: select then color the selection', () async {
    // Seed a node and put it in scope.
    canvas.add(DrawingObjectAdded(RectangleObject(
      id: 'joy',
      rect: const Rect.fromLTWH(0, 0, 80, 40),
      text: 'Joy',
    )));
    await _pump();

    final provider = FakeProvider([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'select', args: {'labelContains': 'joy'}),
      ]),
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c2', name: 'color_objects', args: {'fill': '#F2C94C'}),
      ]),
      const AgentResponse(text: 'Colored Joy gold.'),
    ]);
    final agent = CanvasAgent(provider: provider, dispatcher: dispatcher);

    await agent.run('color the joy node gold').toList();
    await _pump();

    expect(selection.state.selectedDrawingObjectIds, {'joy'});
    expect((canvas.state.drawingObjects['joy'] as RectangleObject).fillColor,
        const Color(0xFFF2C94C));
  });

  test('cancellation stops the loop', () async {
    final agent = CanvasAgent(
      provider: FakeProvider([
        const AgentResponse(toolCalls: [ToolCall(id: 'c1', name: 'get_selection')]),
        const AgentResponse(text: 'should not reach'),
      ]),
      dispatcher: dispatcher,
    );

    final events = <AgentEvent>[];
    await for (final e in agent.run('do something')) {
      events.add(e);
      if (e is AgentToolStarted) agent.cancel();
    }
    final done = events.whereType<AgentDone>().single;
    expect(done.cancelled, true);
  });

  test('round cap prevents an infinite tool loop', () async {
    // A provider that always asks for another tool call, never finishing.
    final neverEnds = _LoopingProvider();
    final agent = CanvasAgent(
      provider: neverEnds,
      dispatcher: dispatcher,
      maxRounds: 3,
    );

    final events = await agent.run('loop forever').toList();
    final done = events.whereType<AgentDone>().single;
    expect(done.error, contains('Stopped after 3 rounds'));
  });

  test('provider error is surfaced as AgentDone.error', () async {
    final agent = CanvasAgent(provider: _ThrowingProvider(), dispatcher: dispatcher);
    final events = await agent.run('go').toList();
    final done = events.whereType<AgentDone>().single;
    expect(done.error, contains('Model call failed'));
  });

  test('set_line_style end to end turns an edge dashed', () async {
    canvas.add(DrawingObjectAdded(ArrowObject(
      id: 'a1',
      start: Offset.zero,
      end: const Offset(50, 50),
    )));
    await _pump();

    final provider = FakeProvider([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'select', args: {'kind': 'edge'}),
      ]),
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c2', name: 'set_line_style', args: {'style': 'dashed'}),
      ]),
      const AgentResponse(text: 'Done.'),
    ]);
    final agent = CanvasAgent(provider: provider, dispatcher: dispatcher);
    await agent.run('make the edges dashed').toList();
    await _pump();

    expect((canvas.state.drawingObjects['a1'] as ArrowObject).lineStyle,
        LineStyle.dashed);
  });
}

class _LoopingProvider implements LlmProvider {
  @override
  String get name => 'Looping';
  @override
  Future<AgentResponse> generate({
    required String systemPrompt,
    required List<ToolSchema> tools,
    required List<AgentMessage> history,
  }) async =>
      const AgentResponse(toolCalls: [ToolCall(id: 'x', name: 'get_selection')]);
}

class _ThrowingProvider implements LlmProvider {
  @override
  String get name => 'Throwing';
  @override
  Future<AgentResponse> generate({
    required String systemPrompt,
    required List<ToolSchema> tools,
    required List<AgentMessage> history,
  }) async =>
      throw Exception('network down');
}
