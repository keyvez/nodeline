import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/core/agent/gemini_provider.dart';
import 'package:flow_draw/src/core/agent/llm_provider.dart';
import 'package:flow_draw/src/core/agent/tool_call.dart';
import 'package:flow_draw/src/core/agent/tool_schemas.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Step 3: verify the Gemini wire translation (request shape + response parse)
/// with a mocked HTTP client — no real API key, no network.

void main() {
  test('builds a generateContent request with tools and system instruction', () async {
    Map<String, dynamic>? sentBody;
    Uri? sentUri;

    final mock = MockClient((req) async {
      sentUri = req.url;
      sentBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'All set.'}
                ]
              }
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final provider = GeminiProvider(apiKey: 'TESTKEY', client: mock);
    final resp = await provider.generate(
      systemPrompt: 'be helpful',
      tools: canvasToolSchemas,
      history: [AgentMessage.user('hi')],
    );

    // URL carries model + key.
    expect(sentUri.toString(), contains('gemini-flash-lite-latest:generateContent'));
    expect(sentUri.toString(), contains('key=TESTKEY'));

    // System instruction + tools + a user content turn are present.
    expect(sentBody!['system_instruction'], isNotNull);
    final tools = sentBody!['tools'] as List;
    expect((tools.first as Map)['functionDeclarations'], isNotEmpty);
    final contents = sentBody!['contents'] as List;
    expect((contents.first as Map)['role'], 'user');

    // Plain text response, no tool calls.
    expect(resp.text, 'All set.');
    expect(resp.hasToolCalls, false);
  });

  test('parses functionCall parts into ToolCalls', () async {
    final mock = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'name': 'create_nodes',
                      'args': {
                        'nodes': [
                          {'label': 'A'}
                        ]
                      }
                    }
                  }
                ]
              }
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final provider = GeminiProvider(apiKey: 'k', client: mock);
    final resp = await provider.generate(
      systemPrompt: 's',
      tools: canvasToolSchemas,
      history: [AgentMessage.user('make node A')],
    );

    expect(resp.hasToolCalls, true);
    expect(resp.toolCalls.single.name, 'create_nodes');
    expect((resp.toolCalls.single.args['nodes'] as List).single['label'], 'A');
  });

  test('encodes tool results as functionResponse parts matched by name', () async {
    Map<String, dynamic>? sentBody;
    final mock = MockClient((req) async {
      sentBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ok'}
                ]
              }
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final provider = GeminiProvider(apiKey: 'k', client: mock);
    await provider.generate(
      systemPrompt: 's',
      tools: canvasToolSchemas,
      history: [
        AgentMessage.user('go'),
        const AgentMessage(role: AgentRole.model, toolCalls: [
          ToolCall(id: 'c1', name: 'get_selection'),
        ]),
        AgentMessage.results(const [
          ToolResult(callId: 'c1', ok: true, summary: '0 selected'),
        ]),
      ],
    );

    final contents = sentBody!['contents'] as List;
    final last = contents.last as Map;
    expect(last['role'], 'user');
    final fr = (last['parts'] as List).first as Map;
    expect((fr['functionResponse'] as Map)['name'], 'get_selection');
    expect(((fr['functionResponse'] as Map)['response'] as Map)['summary'], '0 selected');
  });

  test('surfaces HTTP errors as GeminiException', () async {
    final mock = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'API key not valid'}
        }),
        400,
        headers: {'content-type': 'application/json'},
      );
    });
    final provider = GeminiProvider(apiKey: 'bad', client: mock);
    expect(
      () => provider.generate(
        systemPrompt: 's',
        tools: canvasToolSchemas,
        history: [AgentMessage.user('x')],
      ),
      throwsA(isA<GeminiException>()),
    );
  });
}
