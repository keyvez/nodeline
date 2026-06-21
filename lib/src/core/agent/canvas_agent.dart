import 'dart:async';

import 'package:flow_draw/src/core/agent/llm_provider.dart';
import 'package:flow_draw/src/core/agent/tool_call.dart';
import 'package:flow_draw/src/core/agent/tool_dispatcher.dart';
import 'package:flow_draw/src/core/agent/tool_schemas.dart';

/// An event emitted by the agent as it works, for the chat panel to render a
/// live trace and for tests to assert on.
sealed class AgentEvent {
  const AgentEvent();
}

/// The model produced some assistant text (a thought or the final answer).
class AgentText extends AgentEvent {
  final String text;
  final bool isFinal;
  const AgentText(this.text, {this.isFinal = false});
}

/// A tool is about to run.
class AgentToolStarted extends AgentEvent {
  final ToolCall call;
  const AgentToolStarted(this.call);
}

/// A tool finished.
class AgentToolFinished extends AgentEvent {
  final ToolCall call;
  final ToolResult result;
  const AgentToolFinished(this.call, this.result);
}

/// The run ended (normally, by cancellation, or by error).
class AgentDone extends AgentEvent {
  final String? finalText;
  final bool cancelled;
  final String? error;
  const AgentDone({this.finalText, this.cancelled = false, this.error});
}

/// Drives the tool-use loop: prompt the [provider], execute any tool calls via
/// the [dispatcher], feed results back, repeat until the model stops asking for
/// tools (or [maxRounds] / cancellation is hit).
///
/// Provider-agnostic and side-effect-isolated: all canvas mutation goes through
/// the dispatcher, all model I/O through the provider. That makes it unit-
/// testable with a scripted fake provider and no network.
class CanvasAgent {
  final LlmProvider provider;
  final ToolDispatcher dispatcher;
  final String systemPrompt;
  final int maxRounds;

  /// The running transcript, preserved across [run] calls so a conversation
  /// accumulates context turn over turn.
  final List<AgentMessage> _history = [];

  bool _cancelled = false;

  CanvasAgent({
    required this.provider,
    required this.dispatcher,
    String? systemPrompt,
    this.maxRounds = 12,
  }) : systemPrompt = systemPrompt ?? defaultSystemPrompt;

  List<AgentMessage> get history => List.unmodifiable(_history);

  /// Requests cancellation of the in-flight run. The loop stops after the
  /// current provider/tool step completes.
  void cancel() => _cancelled = true;

  /// Sends one user message and runs the loop to completion, streaming
  /// [AgentEvent]s. Safe to await the returned stream's `last`/`toList`, or
  /// listen for live updates.
  Stream<AgentEvent> run(String userMessage) async* {
    _cancelled = false;
    _history.add(AgentMessage.user(userMessage));

    var round = 0;
    String? lastText;
    try {
      while (round < maxRounds) {
        if (_cancelled) {
          yield const AgentDone(cancelled: true);
          return;
        }
        round++;

        final AgentResponse resp;
        try {
          resp = await provider.generate(
            systemPrompt: systemPrompt,
            tools: canvasToolSchemas,
            history: _history,
          );
        } catch (e) {
          yield AgentDone(error: 'Model call failed: $e');
          return;
        }

        _history.add(AgentMessage.model(text: resp.text, toolCalls: resp.toolCalls));

        if (resp.text != null && resp.text!.trim().isNotEmpty) {
          lastText = resp.text;
          yield AgentText(resp.text!, isFinal: !resp.hasToolCalls);
        }

        if (!resp.hasToolCalls) {
          yield AgentDone(finalText: lastText);
          return;
        }

        // Execute every requested tool call, collecting results to feed back.
        final results = <ToolResult>[];
        for (final call in resp.toolCalls) {
          if (_cancelled) {
            yield const AgentDone(cancelled: true);
            return;
          }
          yield AgentToolStarted(call);
          final result = dispatcher.dispatch(call);
          results.add(result);
          yield AgentToolFinished(call, result);
        }
        _history.add(AgentMessage.results(results));
      }
      // Hit the round cap without a clean finish.
      yield AgentDone(
        finalText: lastText,
        error: 'Stopped after $maxRounds rounds',
      );
    } finally {
      _cancelled = false;
    }
  }

  /// Default system prompt for Canvas Mode. Describes the canvas, the referent
  /// model (selection / frames), and how to ground semantic requests.
  static const String defaultSystemPrompt = '''
You are the assistant inside a diagramming canvas. You build and edit diagrams by
calling tools — you never describe edits in prose, you make them.

The canvas holds nodes (rectangles, circles, diamonds, parallelograms,
fork/join bars), edges (arrows, lines), text, and frames (labelled containers
that group objects). Every object has a stable id.

Guidance:
- To act on existing objects, first `select` them (by frame, kind, or label), or
  pass explicit ids. Tools without ids act on the current selection.
- "These", "the selection", "the selected edges" refer to the current selection.
  Use `get_selection` if unsure what is selected.
- A frame is a container; "the nodes in the X frame" = select with frame:"X".
- For semantic color requests (e.g. "color these emotions by their cultural
  color"), reason about the right colors yourself and pass hex values.
- Prefer creating from scratch with `create_nodes` then `create_edges`,
  referencing nodes by their labels.
- Keep going until the request is fully satisfied, then give a one-line summary
  of what you did. Do not ask for confirmation for normal edits.
''';
}
