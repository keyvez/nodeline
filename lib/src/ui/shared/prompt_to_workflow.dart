import 'dart:convert';

import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/core/mermaid/mermaid_importer.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Mermaid conversion helpers (kept for direct mermaid/simple-flow input mode)
// ---------------------------------------------------------------------------

/// Converts simple flow text notation (e.g. "A -> B -> C") into valid
/// Mermaid flowchart syntax that can be parsed by [MermaidImporter].
String convertSimpleFlowToMermaid(String input) {
  final lines = input.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final mermaidLines = <String>['flowchart TD'];

  for (final line in lines) {
    if (line.startsWith('//') || line.startsWith('#') || line.startsWith('%%')) continue;
    if (RegExp(r'^flowchart\s*(TD|TB|LR|BT|RL)?\s*$').hasMatch(line)) continue;

    final chainPattern = RegExp(r'\s*->\s*(?:\|([^|]*)\|\s*)?');
    final parts = line.split(chainPattern);
    final labels = chainPattern.allMatches(line).map((m) => m.group(1)).toList();
    final cleanParts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (cleanParts.length >= 2) {
      for (int i = 0; i < cleanParts.length - 1; i++) {
        final label = (i < labels.length) ? labels[i] : null;
        final fromDecl = _nodeDeclaration(cleanParts[i]);
        final toDecl = _nodeDeclaration(cleanParts[i + 1]);
        if (label != null && label.isNotEmpty) {
          mermaidLines.add('$fromDecl -->|$label| $toDecl');
        } else {
          mermaidLines.add('$fromDecl --> $toDecl');
        }
      }
    } else if (cleanParts.length == 1) {
      mermaidLines.add(_nodeDeclaration(cleanParts[0]));
    }
  }

  return mermaidLines.join('\n');
}

String _sanitizeNodeId(String label) =>
    label.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').replaceAll(RegExp(r'_+'), '_');

String _nodeDeclaration(String rawLabel) {
  final trimmed = rawLabel.trim();
  if (RegExp(r'^\w+\[').hasMatch(trimmed) ||
      RegExp(r'^\w+\(\(').hasMatch(trimmed) ||
      RegExp(r'^\w+\{').hasMatch(trimmed) ||
      RegExp(r'^\w+\(\[').hasMatch(trimmed)) {
    return trimmed;
  }
  final id = _sanitizeNodeId(trimmed);
  if (id == trimmed && RegExp(r'^\w+$').hasMatch(trimmed)) return trimmed;
  return '$id["$trimmed"]';
}

// ---------------------------------------------------------------------------
// LLM provider model
// ---------------------------------------------------------------------------

enum LlmProvider { none, claude, openai }

extension LlmProviderLabel on LlmProvider {
  String get label => switch (this) {
        LlmProvider.none => 'No AI (Mermaid only)',
        LlmProvider.claude => 'Claude (Anthropic)',
        LlmProvider.openai => 'OpenAI',
      };
}

const _claudeApiKeyUrl = 'https://console.anthropic.com/settings/keys';
const _openaiApiKeyUrl = 'https://platform.openai.com/api-keys';

const _prefKeyProvider = 'llm_provider';
const _prefKeyClaudeKey = 'llm_claude_api_key';
const _prefKeyOpenaiKey = 'llm_openai_api_key';

const _systemPrompt = '''You are a diagram assistant. Convert the user's natural language description into valid Mermaid flowchart syntax.

Rules:
- Return ONLY the Mermaid code block, no explanation, no markdown fences.
- Start with "flowchart TD" (or LR/BT/RL if the description suggests it).
- Use descriptive node labels in quotes, e.g. A["Step name"].
- Use --> for arrows, and -->|label| for labelled arrows.
- Use diamond shapes {Decision?} for decisions/conditions.
- Use (( )) for start/end ovals if appropriate.

Example output:
flowchart TD
  A(("Start")) --> B["Receive Order"]
  B --> C{"In Stock?"}
  C -->|Yes| D["Ship Item"]
  C -->|No| E["Notify Customer"]
  D --> F(("End"))
  E --> F''';

// Pre-compiled regex used in _handleApply to detect Mermaid graph headers.
final _graphHeaderRe = RegExp(r'^\s*graph\s+(TD|TB|LR|BT|RL)', multiLine: true);

// ---------------------------------------------------------------------------
// Toolbar button
// ---------------------------------------------------------------------------

/// A toolbar button that opens the text-to-diagram prompt dialog.
class PromptToWorkflowButton extends StatelessWidget {
  const PromptToWorkflowButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GhostButton(
      density: ButtonDensity.compact,
      onPressed: () {
        final canvasBloc = context.read<CanvasBloc>();
        showPromptToWorkflowDialog(context, canvasBloc);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 16),
          const Gap(4),
          Text('Text to Diagram', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Shows the prompt-to-workflow dialog.
void showPromptToWorkflowDialog(BuildContext context, CanvasBloc canvasBloc) {
  showPopover(
    context: context,
    alignment: Alignment.topCenter,
    builder: (popoverContext) {
      return ModalContainer(
        child: SizedBox(
          width: 480,
          child: _PromptToWorkflowContent(
            popoverContext: popoverContext,
            canvasBloc: canvasBloc,
          ),
        ),
      ).withPadding(top: 8);
    },
  );
}

// ---------------------------------------------------------------------------
// Dialog content
// ---------------------------------------------------------------------------

class _PromptToWorkflowContent extends StatefulWidget {
  final BuildContext popoverContext;
  final CanvasBloc canvasBloc;

  const _PromptToWorkflowContent({
    required this.popoverContext,
    required this.canvasBloc,
  });

  @override
  State<_PromptToWorkflowContent> createState() => _PromptToWorkflowContentState();
}

class _PromptToWorkflowContentState extends State<_PromptToWorkflowContent> {
  final _promptController = TextEditingController();
  final _mermaidController = TextEditingController(
    text:
        'flowchart TD\n  A(("Start")) --> B["Process"]\n  B --> C{"Decision?"}\n  C -->|Yes| D["Action"]\n  C -->|No| E["Alternative"]\n  D --> F(("End"))\n  E --> F',
  );
  final _apiKeyController = TextEditingController();

  LlmProvider _provider = LlmProvider.none;
  String? _errorMessage;
  bool _isGenerating = false;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  String _keyForProvider(SharedPreferences prefs, LlmProvider p) => switch (p) {
        LlmProvider.claude => prefs.getString(_prefKeyClaudeKey) ?? '',
        LlmProvider.openai => prefs.getString(_prefKeyOpenaiKey) ?? '',
        LlmProvider.none => '',
      };

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final saved = prefs.getString(_prefKeyProvider);
      _provider = LlmProvider.values.firstWhere(
        (p) => p.name == saved,
        orElse: () => LlmProvider.none,
      );
      _apiKeyController.text = _keyForProvider(prefs, _provider);
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final trimmedKey = _apiKeyController.text.trim();
    await prefs.setString(_prefKeyProvider, _provider.name);
    switch (_provider) {
      case LlmProvider.claude:
        await prefs.setString(_prefKeyClaudeKey, trimmedKey);
      case LlmProvider.openai:
        await prefs.setString(_prefKeyOpenaiKey, trimmedKey);
      case LlmProvider.none:
        break;
    }
  }

  Future<void> _onProviderChanged(LlmProvider? p) async {
    if (p == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _provider = p;
      _apiKeyController.text = _keyForProvider(prefs, p);
      _showApiKey = false;
    });
  }

  Future<void> _handleGenerateWithAi() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _errorMessage = 'Enter a description to generate a diagram.');
      return;
    }
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _errorMessage = 'Enter an API key for ${_provider.label}.');
      return;
    }

    await _savePrefs();
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final mermaid = switch (_provider) {
        LlmProvider.claude => await _callClaude(prompt, apiKey),
        LlmProvider.openai => await _callOpenAi(prompt, apiKey),
        LlmProvider.none => throw StateError('No provider selected'),
      };
      if (mounted) setState(() => _mermaidController.text = mermaid);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'AI error: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _throwIfErrorResponse(http.Response response) {
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final msg = body['error']?['message'] as String? ?? 'HTTP ${response.statusCode}';
      throw Exception(msg);
    }
  }

  Future<String> _callClaude(String prompt, String apiKey) async {
    final response = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': 'claude-sonnet-4-6',
            'max_tokens': 1024,
            'system': _systemPrompt,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    _throwIfErrorResponse(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['content'] as List).first['text'] as String;
  }

  Future<String> _callOpenAi(String prompt, String apiKey) async {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': 'gpt-4o',
            'max_tokens': 1024,
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    _throwIfErrorResponse(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['choices'][0]['message']['content'] as String;
  }

  void _handleApply() {
    final text = _mermaidController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Mermaid text is empty.');
      return;
    }

    String mermaidText;
    if (text.startsWith('flowchart') || _graphHeaderRe.hasMatch(text)) {
      mermaidText = text;
    } else {
      mermaidText = convertSimpleFlowToMermaid(text);
    }

    try {
      final projectData = MermaidImporter.import(mermaidText);
      widget.canvasBloc.add(ProjectLoaded(projectData));
      closeOverlay(widget.popoverContext);
      showNodeEditorSnackbar('Diagram generated successfully', SnackbarType.success);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to parse Mermaid: $e');
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _mermaidController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 16),
            const Gap(8),
            Text(
              'Text to Diagram',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const Gap(12),

        // LLM Provider selector row
        Row(
          children: [
            Text('AI Model', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
            const Gap(8),
            Expanded(
              child: Select<LlmProvider>(
                value: _provider,
                onChanged: _onProviderChanged,
                itemBuilder: (context, value) => Text(value.label, style: TextStyle(fontSize: 12)),
                popup: SelectPopup(
                  items: SelectItemList(
                    children: LlmProvider.values
                        .map(
                          (p) => SelectItemButton(
                            value: p,
                            child: Text(p.label, style: TextStyle(fontSize: 12)),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        ),

        // API key row (shown when a provider is selected)
        if (_provider != LlmProvider.none) ...[
          const Gap(8),
          Row(
            children: [
              Text(
                _provider == LlmProvider.claude ? 'Anthropic Key' : 'OpenAI Key',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const Gap(8),
              Expanded(
                child: TextField(
                  controller: _apiKeyController,
                  obscureText: !_showApiKey,
                  placeholder: Text(
                    _provider == LlmProvider.claude ? 'sk-ant-...' : 'sk-...',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  onSubmitted: (_) => _handleGenerateWithAi(),
                ),
              ),
              const Gap(4),
              GhostButton(
                density: ButtonDensity.compact,
                onPressed: () => setState(() => _showApiKey = !_showApiKey),
                child: Icon(
                  _showApiKey ? Icons.visibility_off : Icons.visibility,
                  size: 14,
                ),
              ),
              const Gap(2),
              Tooltip(
                tooltip: (_) => TooltipContainer(
                  child: Text(
                    _provider == LlmProvider.claude
                        ? 'Get API key from Anthropic Console'
                        : 'Get API key from OpenAI Platform',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                child: GhostButton(
                  density: ButtonDensity.compact,
                  onPressed: () {
                    final url = _provider == LlmProvider.claude
                        ? _claudeApiKeyUrl
                        : _openaiApiKeyUrl;
                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  child: Icon(Icons.open_in_new, size: 14),
                ),
              ),
            ],
          ),

          const Gap(12),
          // Natural language input
          Text(
            'Describe your diagram',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const Gap(4),
          TextField(
            controller: _promptController,
            placeholder: Text(
              'e.g. "An e-commerce checkout flow with payment and shipping steps"',
              style: TextStyle(fontSize: 11),
            ),
            maxLines: 3,
            autofocus: true,
            style: TextStyle(fontSize: 12),
            onSubmitted: (_) => _handleGenerateWithAi(),
          ),
          const Gap(8),
          PrimaryButton(
            density: ButtonDensity.compact,
            onPressed: _isGenerating ? null : _handleGenerateWithAi,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isGenerating) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const Gap(6),
                  Text('Generating...'),
                ] else ...[
                  Icon(Icons.auto_awesome, size: 14),
                  const Gap(6),
                  Text('Generate with AI'),
                ],
              ],
            ),
          ),
          const Gap(12),
          Divider(),
          const Gap(8),
        ],

        // Mermaid text field
        Text(
          'Mermaid syntax',
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
        ),
        const Gap(4),
        TextField(
          controller: _mermaidController,
          maxLines: 10,
          autofocus: _provider == LlmProvider.none,
          style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),

        if (_errorMessage != null) ...[
          const Gap(8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: 11, color: Colors.red),
            ),
          ),
        ],

        const Gap(12),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                density: ButtonDensity.compact,
                onPressed: () => closeOverlay(widget.popoverContext),
                child: Text('Cancel'),
              ),
            ),
            const Gap(8),
            Expanded(
              child: PrimaryButton(
                density: ButtonDensity.compact,
                onPressed: _handleApply,
                child: Text('Apply Diagram'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
