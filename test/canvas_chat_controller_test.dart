import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/blocs/selection/selection_bloc.dart';
import 'package:nodeline/src/core/agent/canvas_agent.dart';
import 'package:nodeline/src/core/agent/llm_provider.dart';
import 'package:nodeline/src/core/agent/tool_call.dart';
import 'package:nodeline/src/core/agent/tool_dispatcher.dart';
import 'package:nodeline/src/core/agent/tool_schemas.dart';
import 'package:nodeline/src/ui/canvas/canvas_chat_controller.dart';

/// Step 4: the chat controller — the testable logic behind the panel widget.
/// Drives a real agent with a scripted fake provider over real BLoCs.

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

CanvasChatController _make(List<AgentResponse> script,
    {required CanvasBloc canvas, required SelectionBloc selection}) {
  final agent = CanvasAgent(
    provider: _FakeProvider(script),
    dispatcher: ToolDispatcher(canvasBloc: canvas, selectionBloc: selection),
  );
  return CanvasChatController(agent: agent);
}

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

  test('renders user, tool, and assistant lines in order', () async {
    final c = _make([
      const AgentResponse(toolCalls: [
        ToolCall(id: 'c1', name: 'create_nodes', args: {
          'nodes': [
            {'label': 'X'}
          ]
        }),
      ]),
      const AgentResponse(text: 'Created node X.'),
    ], canvas: canvas, selection: selection);
    addTearDown(c.dispose);

    await c.send('make X');

    final kinds = c.lines.map((l) => l.kind).toList();
    expect(kinds.first, ChatLineKind.user);
    expect(kinds.contains(ChatLineKind.tool), true);
    expect(kinds.last, ChatLineKind.assistant);
    // The tool line resolved to a success.
    final toolLine = c.lines.firstWhere((l) => l.kind == ChatLineKind.tool);
    expect(toolLine.toolOk, true);
  });

  test('running flips true during send and false after', () async {
    final c = _make([
      const AgentResponse(text: 'hi'),
    ], canvas: canvas, selection: selection);
    addTearDown(c.dispose);

    expect(c.running, false);
    final future = c.send('hello');
    // running becomes true synchronously after send is called
    expect(c.running, true);
    await future;
    expect(c.running, false);
  });

  test('ignores empty and concurrent sends', () async {
    final c = _make([
      const AgentResponse(text: 'one'),
    ], canvas: canvas, selection: selection);
    addTearDown(c.dispose);

    await c.send('   '); // empty -> ignored
    expect(c.lines, isEmpty);

    final f1 = c.send('first');
    await c.send('second while running'); // ignored: already running
    await f1;
    final userLines = c.lines.where((l) => l.kind == ChatLineKind.user).toList();
    expect(userLines, hasLength(1));
    expect(userLines.single.text, 'first');
  });

  test('reset clears the transcript and the agent history', () async {
    final c = _make([
      const AgentResponse(text: 'hi'),
    ], canvas: canvas, selection: selection);
    addTearDown(c.dispose);
    await c.send('hello');
    expect(c.lines, isNotEmpty);
    expect(c.agent.history, isNotEmpty);
    c.reset();
    expect(c.lines, isEmpty);
    expect(c.agent.history, isEmpty);
  });

  test('restore shows prior lines and seeds the agent history as turns', () {
    final c = _make([], canvas: canvas, selection: selection);
    addTearDown(c.dispose);

    c.restore(const [
      ChatLine(ChatLineKind.user, 'add a node'),
      ChatLine(ChatLineKind.tool, 'create 1 node — ok', toolOk: true),
      ChatLine(ChatLineKind.assistant, 'Added it.'),
    ]);

    // Display: all three lines restored.
    expect(c.lines, hasLength(3));
    // Agent context: only user + assistant turns carry forward (not tool lines).
    final roles = c.agent.history.map((m) => m.role).toList();
    expect(roles, [AgentRole.user, AgentRole.model]);
    expect(c.agent.history.first.text, 'add a node');
    expect(c.agent.history.last.text, 'Added it.');
  });

  test('ChatLine round-trips through JSON', () {
    const line = ChatLine(ChatLineKind.tool, 'create 2 edges', toolOk: false);
    final restored = ChatLine.fromJson(line.toJson());
    expect(restored.kind, ChatLineKind.tool);
    expect(restored.text, 'create 2 edges');
    expect(restored.toolOk, false);
  });

  test('notifies listeners as lines arrive', () async {
    final c = _make([
      const AgentResponse(text: 'hi'),
    ], canvas: canvas, selection: selection);
    addTearDown(c.dispose);
    var notifications = 0;
    c.addListener(() => notifications++);
    await c.send('hello');
    expect(notifications, greaterThan(0));
  });
}
