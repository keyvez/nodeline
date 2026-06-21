/// A single tool invocation produced by the model (or by tests). The agent loop
/// in a later step parses provider-specific tool-call JSON into these; the
/// [ToolDispatcher] executes them against the canvas.
class ToolCall {
  /// Provider-assigned id for the call, echoed back in the [ToolResult] so the
  /// model can correlate results. Empty for hand-built calls in tests.
  final String id;

  /// The tool name, e.g. `select`, `color_objects`, `set_line_style`.
  final String name;

  /// The decoded JSON arguments object.
  final Map<String, dynamic> args;

  const ToolCall({this.id = '', required this.name, this.args = const {}});

  @override
  String toString() => 'ToolCall($name, $args)';
}

/// The outcome of executing a [ToolCall]. [summary] is a short human/model
/// readable line ("Selected 6 objects", "Unknown tool: foo") that the agent
/// loop feeds back to the model as the tool result. [data] carries any
/// structured payload a read tool returns (e.g. resolved ids, a guide polyline).
class ToolResult {
  final String callId;
  final bool ok;
  final String summary;
  final Map<String, dynamic>? data;

  const ToolResult({
    this.callId = '',
    required this.ok,
    required this.summary,
    this.data,
  });

  factory ToolResult.ok(String summary, {String callId = '', Map<String, dynamic>? data}) =>
      ToolResult(callId: callId, ok: true, summary: summary, data: data);

  factory ToolResult.error(String summary, {String callId = ''}) =>
      ToolResult(callId: callId, ok: false, summary: summary);

  @override
  String toString() => 'ToolResult(${ok ? 'ok' : 'error'}: $summary)';
}
