import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/blocs/selection/selection_bloc.dart';
import 'package:flow_draw/src/core/agent/canvas_agent.dart';
import 'package:flow_draw/src/core/agent/gemini_provider.dart';
import 'package:flow_draw/src/core/agent/tool_dispatcher.dart';
import 'package:flow_draw/src/ui/canvas/canvas_chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefGeminiKey = 'canvas_mode_gemini_key';

/// A docked chat side panel that drives Canvas Mode: type natural-language
/// directions, watch the agent create/edit the diagram live.
///
/// Self-contained — reads [CanvasBloc] and [SelectionBloc] from context (so it
/// can sit anywhere inside the `FlowDraw` subtree), owns its agent, and persists
/// the Gemini API key in SharedPreferences.
class CanvasChatPanel extends StatefulWidget {
  /// Panel width in logical pixels.
  final double width;

  /// Called when the user closes the panel (X). Null hides the close button.
  final VoidCallback? onClose;

  const CanvasChatPanel({super.key, this.width = 340, this.onClose});

  @override
  State<CanvasChatPanel> createState() => _CanvasChatPanelState();
}

class _CanvasChatPanelState extends State<CanvasChatPanel> {
  final _input = TextEditingController();
  final _keyInput = TextEditingController();
  final _scroll = ScrollController();

  CanvasChatController? _chat;
  String? _apiKey;
  bool _loadingKey = true;
  bool _showKeyEntry = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _apiKey = prefs.getString(_prefGeminiKey);
      _keyInput.text = _apiKey ?? '';
      _loadingKey = false;
      _showKeyEntry = _apiKey == null || _apiKey!.isEmpty;
    });
  }

  Future<void> _saveKey() async {
    final key = _keyInput.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefGeminiKey, key);
    // Force the agent to be rebuilt with the new key.
    _chat?.dispose();
    _chat = null;
    if (!mounted) return;
    setState(() {
      _apiKey = key;
      _showKeyEntry = key.isEmpty;
    });
  }

  /// Lazily builds the chat controller (and its agent) bound to the live blocs.
  CanvasChatController _chatController() {
    final existing = _chat;
    if (existing != null) return existing;
    final dispatcher = ToolDispatcher(
      canvasBloc: context.read<CanvasBloc>(),
      selectionBloc: context.read<SelectionBloc>(),
    );
    final agent = CanvasAgent(
      provider: GeminiProvider(apiKey: _apiKey ?? ''),
      dispatcher: dispatcher,
    );
    final chat = CanvasChatController(agent: agent)..addListener(_onChatChanged);
    _chat = chat;
    return chat;
  }

  void _onChatChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (_apiKey == null || _apiKey!.isEmpty) {
      setState(() => _showKeyEntry = true);
      return;
    }
    _input.clear();
    _chatController().send(text);
  }

  @override
  void dispose() {
    _chat?.dispose();
    _input.dispose();
    _keyInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            const Divider(height: 1),
            if (_showKeyEntry) _keyEntry() else Expanded(child: _transcript()),
            const Divider(height: 1),
            _selectionChip(),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Text('Canvas Mode',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.key, size: 16, color: Colors.white54),
            tooltip: 'API key',
            onPressed: () => setState(() => _showKeyEntry = !_showKeyEntry),
          ),
          if (_chat != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white54),
              tooltip: 'Clear chat',
              onPressed: () => _chat?.reset(),
            ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white54),
              tooltip: 'Close',
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _keyEntry() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Gemini API key',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _keyInput,
            obscureText: true,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _fieldDecoration('Paste your key (free at aistudio.google.com)'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                await _saveKey();
              },
              child: const Text('Save'),
            ),
          ),
          if (_loadingKey)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Loading…', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _transcript() {
    final lines = _chat?.lines ?? const <ChatLine>[];
    if (lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Describe or edit your diagram.\n\nTry: "create nodes for the 7 stages of grief and connect them in order", or select some edges and say "make these dashed".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (_, i) => _lineWidget(lines[i]),
    );
  }

  Widget _lineWidget(ChatLine line) {
    switch (line.kind) {
      case ChatLineKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8, left: 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(line.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        );
      case ChatLineKind.assistant:
        return Container(
          margin: const EdgeInsets.only(bottom: 8, right: 16),
          child: Text(line.text,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
        );
      case ChatLineKind.tool:
        final running = line.toolOk == null;
        final color = running
            ? Colors.white38
            : (line.toolOk! ? Colors.greenAccent.withValues(alpha: 0.7) : Colors.redAccent);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              running
                  ? const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : Icon(line.toolOk! ? Icons.check : Icons.error_outline, size: 12, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(line.text,
                    style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace')),
              ),
            ],
          ),
        );
      case ChatLineKind.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line.text,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        );
    }
  }

  Widget _selectionChip() {
    return BlocBuilder<SelectionBloc, SelectionState>(
      builder: (context, sel) {
        final n = sel.selectedDrawingObjectIds.length;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.white.withValues(alpha: 0.04),
          child: Text('$n object(s) selected — say "these" to act on them',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        );
      },
    );
  }

  Widget _composer() {
    final running = _chat?.running ?? false;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              enabled: !running,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: _fieldDecoration('Ask the canvas…'),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          running
              ? IconButton.filled(
                  onPressed: () => _chat?.cancel(),
                  icon: const Icon(Icons.stop, size: 18),
                  tooltip: 'Stop',
                )
              : IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Send',
                ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}
