import 'dart:convert';

import 'package:flow_draw/src/core/agent/llm_provider.dart';
import 'package:flow_draw/src/core/agent/tool_call.dart';
import 'package:flow_draw/src/core/agent/tool_schemas.dart';
import 'package:http/http.dart' as http;

/// Gemini implementation of [LlmProvider] using the `generateContent` REST API
/// with function calling. Chosen first because the free tier makes live testing
/// painless.
///
/// Endpoint:
///   POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}
/// Tools are sent as `tools: [{functionDeclarations: [...]}]`; the model replies
/// with `functionCall` parts, and we reply with `functionResponse` parts.
class GeminiProvider implements LlmProvider {
  final String apiKey;
  final String model;
  final http.Client _client;
  final Duration timeout;

  /// Default model. A rolling alias that tracks the latest Flash-Lite; override
  /// with a pinned id (e.g. "gemini-3.1-flash-lite") if the alias is rejected.
  static const String defaultModel = 'gemini-flash-lite-latest';

  GeminiProvider({
    required this.apiKey,
    this.model = defaultModel,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  @override
  String get name => 'Gemini ($model)';

  @override
  Future<AgentResponse> generate({
    required String systemPrompt,
    required List<ToolSchema> tools,
    required List<AgentMessage> history,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final body = <String, dynamic>{
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': _encodeHistory(history),
      'tools': [
        {'functionDeclarations': [for (final t in tools) t.toJson()]}
      ],
    };

    final resp = await _client
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(timeout);

    if (resp.statusCode != 200) {
      throw GeminiException(_extractError(resp.body, resp.statusCode));
    }
    return _parseResponse(resp.body);
  }

  /// Translates the transcript into Gemini `contents`.
  List<Map<String, dynamic>> _encodeHistory(List<AgentMessage> history) {
    final contents = <Map<String, dynamic>>[];
    for (final m in history) {
      switch (m.role) {
        case AgentRole.user:
          contents.add({
            'role': 'user',
            'parts': [
              {'text': m.text ?? ''}
            ],
          });
        case AgentRole.model:
          final parts = <Map<String, dynamic>>[];
          if (m.text != null && m.text!.isNotEmpty) {
            parts.add({'text': m.text});
          }
          for (final c in m.toolCalls) {
            parts.add({
              'functionCall': {'name': c.name, 'args': c.args}
            });
          }
          // Gemini requires at least one part.
          if (parts.isEmpty) parts.add({'text': ''});
          contents.add({'role': 'model', 'parts': parts});
        case AgentRole.toolResults:
          contents.add({
            'role': 'user',
            'parts': [
              for (final r in m.toolResults)
                {
                  'functionResponse': {
                    'name': _nameForResult(r, history),
                    'response': {
                      'ok': r.ok,
                      'summary': r.summary,
                      if (r.data != null) 'data': r.data,
                    },
                  }
                }
            ],
          });
      }
    }
    return contents;
  }

  /// Gemini matches functionResponse to functionCall by name. We carried the
  /// call id on the result but not the name, so recover it from the preceding
  /// model turn by position.
  String _nameForResult(ToolResult r, List<AgentMessage> history) {
    // Find the most recent model turn's tool calls and match by callId.
    for (var i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (m.role == AgentRole.model && m.toolCalls.isNotEmpty) {
        for (final c in m.toolCalls) {
          if (c.id == r.callId && c.id.isNotEmpty) return c.name;
        }
        // Fall back to positional match when ids are absent.
        return m.toolCalls.first.name;
      }
    }
    return 'unknown';
  }

  AgentResponse _parseResponse(String bodyStr) {
    final body = jsonDecode(bodyStr) as Map<String, dynamic>;
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return const AgentResponse(text: '');
    }
    final content = (candidates.first as Map)['content'] as Map?;
    final parts = (content?['parts'] as List?) ?? const [];

    final buffer = StringBuffer();
    final calls = <ToolCall>[];
    var callIndex = 0;
    for (final raw in parts) {
      final part = (raw as Map).cast<String, dynamic>();
      if (part['text'] != null) {
        buffer.write(part['text']);
      }
      final fc = part['functionCall'];
      if (fc is Map) {
        calls.add(ToolCall(
          id: 'gem_${callIndex++}',
          name: fc['name'] as String? ?? '',
          args: ((fc['args'] as Map?)?.cast<String, dynamic>()) ?? const {},
        ));
      }
    }
    final text = buffer.toString();
    return AgentResponse(text: text.isEmpty ? null : text, toolCalls: calls);
  }

  String _extractError(String bodyStr, int status) {
    try {
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final msg = (body['error'] as Map?)?['message'] as String?;
      if (msg != null) return 'Gemini HTTP $status: $msg';
    } catch (_) {}
    return 'Gemini HTTP $status';
  }

  void dispose() => _client.close();
}

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}
