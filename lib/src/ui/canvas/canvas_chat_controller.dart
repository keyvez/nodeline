import 'dart:async';

import 'package:nodeline/src/core/agent/canvas_agent.dart';
import 'package:nodeline/src/core/agent/llm_provider.dart';
import 'package:nodeline/src/core/agent/tool_call.dart';
import 'package:flutter/foundation.dart';

/// A single line in the chat transcript as the panel renders it. This is a
/// flattened, display-oriented view of the agent's [AgentEvent] stream.
enum ChatLineKind { user, assistant, tool, error }

class ChatLine {
  final ChatLineKind kind;
  final String text;

  /// For tool lines: whether the tool succeeded (null for non-tool lines).
  final bool? toolOk;

  const ChatLine(this.kind, this.text, {this.toolOk});

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'text': text,
        if (toolOk != null) 'toolOk': toolOk,
      };

  factory ChatLine.fromJson(Map<String, dynamic> json) => ChatLine(
        ChatLineKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ChatLineKind.assistant,
        ),
        json['text'] as String? ?? '',
        toolOk: json['toolOk'] as bool?,
      );
}

/// Owns the chat transcript and the running [CanvasAgent], translating the
/// agent's event stream into a flat list of [ChatLine]s and exposing run state.
///
/// Separated from the widget so the conversation logic is unit-testable with a
/// fake provider (the widget just renders [lines] and calls [send]/[cancel]).
class CanvasChatController extends ChangeNotifier {
  final CanvasAgent agent;

  final List<ChatLine> _lines = [];
  StreamSubscription<AgentEvent>? _sub;
  bool _running = false;

  CanvasChatController({required this.agent});

  List<ChatLine> get lines => List.unmodifiable(_lines);
  bool get running => _running;

  /// Sends a user message and consumes the agent's event stream, appending lines
  /// as it goes. Returns when the run completes.
  Future<void> send(String message) async {
    final text = message.trim();
    if (text.isEmpty || _running) return;

    _lines.add(ChatLine(ChatLineKind.user, text));
    _running = true;
    notifyListeners();

    final completer = Completer<void>();
    _sub = agent.run(text).listen(
      _onEvent,
      onError: (Object e) {
        _lines.add(ChatLine(ChatLineKind.error, '$e'));
        _finish(completer);
      },
      onDone: () => _finish(completer),
    );
    return completer.future;
  }

  /// Requests cancellation of the in-flight run.
  void cancel() {
    if (!_running) return;
    agent.cancel();
  }

  void _onEvent(AgentEvent e) {
    switch (e) {
      case AgentText(:final text):
        _lines.add(ChatLine(ChatLineKind.assistant, text));
      case AgentToolStarted(:final call):
        _lines.add(ChatLine(ChatLineKind.tool, _describe(call), toolOk: null));
      case AgentToolFinished(:final call, :final result):
        // Replace the matching "started" placeholder with the finished line.
        final desc = '${_describe(call)} — ${result.summary}';
        final idx = _lines.lastIndexWhere(
            (l) => l.kind == ChatLineKind.tool && l.toolOk == null);
        final line = ChatLine(ChatLineKind.tool, desc, toolOk: result.ok);
        if (idx >= 0) {
          _lines[idx] = line;
        } else {
          _lines.add(line);
        }
      case AgentDone(:final cancelled, :final error):
        if (cancelled) {
          _lines.add(const ChatLine(ChatLineKind.error, 'Stopped.'));
        } else if (error != null) {
          _lines.add(ChatLine(ChatLineKind.error, error));
        }
    }
    notifyListeners();
  }

  void _finish(Completer<void> completer) {
    _running = false;
    _sub?.cancel();
    _sub = null;
    notifyListeners();
    if (!completer.isCompleted) completer.complete();
  }

  String _describe(ToolCall call) {
    final a = call.args;
    switch (call.name) {
      case 'select':
        final bits = [
          if (a['frame'] != null) 'frame "${a['frame']}"',
          if (a['kind'] != null) '${a['kind']}s',
          if (a['labelContains'] != null) 'matching "${a['labelContains']}"',
        ];
        return 'select ${bits.isEmpty ? 'all' : bits.join(' ')}';
      case 'color_objects':
        return 'color ${a['fill'] ?? a['stroke'] ?? ''}';
      case 'set_line_style':
        return 'set ${a['style']} line style';
      case 'create_nodes':
        return 'create ${(a['nodes'] as List?)?.length ?? 0} node(s)';
      case 'create_edges':
        return 'create ${(a['edges'] as List?)?.length ?? 0} edge(s)';
      default:
        return call.name;
    }
  }

  void reset() {
    _lines.clear();
    agent.clearHistory();
    notifyListeners();
  }

  /// Restores a saved transcript: shows the prior [lines] and seeds the agent's
  /// history with the user/assistant turns so context carries across reopen.
  /// Tool/error lines are display-only and not fed back to the model.
  void restore(List<ChatLine> lines) {
    _lines
      ..clear()
      ..addAll(lines);
    agent.seedHistory([
      for (final l in lines)
        if (l.kind == ChatLineKind.user)
          AgentMessage.user(l.text)
        else if (l.kind == ChatLineKind.assistant)
          AgentMessage.model(text: l.text),
    ]);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
