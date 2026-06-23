import 'package:nodeline/src/core/agent/tool_call.dart';
import 'package:nodeline/src/core/agent/tool_schemas.dart';

/// One entry in the conversation sent to the model.
///
/// The agent loop builds a transcript of these and replays it each round so the
/// model has full context. Roles:
/// - [AgentRole.user]: the human's instruction (and, after a tool round, the
///   tool results encoded as a synthetic user/tool turn by the provider).
/// - [AgentRole.model]: the model's own output (text and/or tool calls).
/// - [AgentRole.toolResults]: results of executing the model's tool calls.
enum AgentRole { user, model, toolResults }

class AgentMessage {
  final AgentRole role;

  /// Free text for user/model turns.
  final String? text;

  /// Tool calls the model wants to make (model turns only).
  final List<ToolCall> toolCalls;

  /// Results of executed tool calls (toolResults turns only).
  final List<ToolResult> toolResults;

  const AgentMessage({
    required this.role,
    this.text,
    this.toolCalls = const [],
    this.toolResults = const [],
  });

  factory AgentMessage.user(String text) =>
      AgentMessage(role: AgentRole.user, text: text);

  factory AgentMessage.model({String? text, List<ToolCall> toolCalls = const []}) =>
      AgentMessage(role: AgentRole.model, text: text, toolCalls: toolCalls);

  factory AgentMessage.results(List<ToolResult> results) =>
      AgentMessage(role: AgentRole.toolResults, toolResults: results);
}

/// What the model returned for one round: any text, plus any tool calls. When
/// [toolCalls] is empty the loop treats [text] as the final answer and stops.
class AgentResponse {
  final String? text;
  final List<ToolCall> toolCalls;

  const AgentResponse({this.text, this.toolCalls = const []});

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Abstraction over an LLM backend (Gemini first, then Claude/OpenAI). Kept
/// minimal so the agent loop can be unit-tested with a fake implementation and
/// no network.
abstract class LlmProvider {
  /// Human-readable name for UI/logging.
  String get name;

  /// Runs one turn: given the [systemPrompt], [tools], and the full [history],
  /// return the model's [AgentResponse]. Implementations make exactly one
  /// network round-trip per call; the loop calls this repeatedly.
  Future<AgentResponse> generate({
    required String systemPrompt,
    required List<ToolSchema> tools,
    required List<AgentMessage> history,
  });
}
