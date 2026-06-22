import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/blocs/selection/selection_bloc.dart';
import 'package:flow_draw/src/core/agent/canvas_agent.dart';
import 'package:flow_draw/src/core/agent/gemini_provider.dart';
import 'package:flow_draw/src/core/agent/tool_dispatcher.dart';
import 'package:flow_draw/src/ui/canvas/canvas_chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefGeminiKey = 'canvas_mode_gemini_key';

/// A single transcript turn handed to [CanvasChatPanel.onSendTranscript], shaped
/// to match Flan's `sendChatLog` turns (`{role, text}` with role one of
/// 'user' | 'assistant' | 'tool' | 'error'). The package stays free of any Flan
/// dependency — the host app decides what to do with the turns.
typedef ChatTranscriptTurn = Map<String, String>;

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

  /// Called when the user taps "send transcript to agent". Receives the ordered
  /// transcript turns. Null hides the send-to-agent button. The host wires this
  /// to e.g. Flan's `sendChatLog`. Returns whether the send succeeded (for the
  /// toast); a void callback is also accepted.
  final bool Function(List<ChatTranscriptTurn> turns)? onSendTranscript;

  const CanvasChatPanel({
    super.key,
    this.width = 340,
    this.onClose,
    this.onSendTranscript,
  });

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
  bool _webSearch = true;

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
      provider: GeminiProvider(apiKey: _apiKey ?? '', enableWebSearch: _webSearch),
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
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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

  /// A compact header icon button that won't overflow the narrow panel.
  Widget _headerIcon(IconData icon, String tooltip, VoidCallback onPressed,
      {Color? color}) {
    return IconButton(
      icon: Icon(icon, size: 16, color: color ?? Colors.white54),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Text('Canvas Mode',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          _headerIcon(
            Icons.travel_explore,
            _webSearch ? 'Web search: on' : 'Web search: off',
            () {
              // Rebuild the agent so the new flag takes effect on the next turn.
              _chat?.dispose();
              _chat = null;
              setState(() => _webSearch = !_webSearch);
            },
            color: _webSearch ? Colors.purpleAccent : Colors.white38,
          ),
          _headerIcon(Icons.key, 'API key',
              () => setState(() => _showKeyEntry = !_showKeyEntry)),
          if (_hasLines) ...[
            _headerIcon(Icons.copy_all, 'Copy whole transcript', _copyTranscript),
            if (widget.onSendTranscript != null)
              _headerIcon(Icons.send, 'Send transcript to agent', _sendTranscript),
          ],
          if (_chat != null)
            _headerIcon(
                Icons.delete_outline, 'Clear chat', () => _chat?.reset()),
          if (widget.onClose != null)
            _headerIcon(Icons.close, 'Close', widget.onClose!),
        ],
      ),
    );
  }

  bool get _hasLines => (_chat?.lines.isNotEmpty ?? false);

  /// Maps a [ChatLineKind] to a transcript role string. Tool lines are folded
  /// into the assistant's actions.
  static String _roleOf(ChatLineKind k) => switch (k) {
        ChatLineKind.user => 'user',
        ChatLineKind.assistant => 'assistant',
        ChatLineKind.tool => 'tool',
        ChatLineKind.error => 'error',
      };

  List<ChatTranscriptTurn> _buildTurns() => [
        for (final l in (_chat?.lines ?? const <ChatLine>[]))
          {'role': _roleOf(l.kind), 'text': l.text},
      ];

  /// Plain-text rendering of the transcript for the clipboard.
  String _transcriptText() => [
        for (final l in (_chat?.lines ?? const <ChatLine>[]))
          '${_roleOf(l.kind)}: ${l.text}',
      ].join('\n\n');

  Future<void> _copyTranscript() async {
    await Clipboard.setData(ClipboardData(text: _transcriptText()));
    _toast('Transcript copied');
  }

  Future<void> _copyLine(ChatLine line) async {
    await Clipboard.setData(ClipboardData(text: line.text));
    _toast('Copied');
  }

  /// A small always-visible "Copy" button shown under a message, so copying is
  /// discoverable (long-press / right-click also work).
  Widget _copyAffordance(ChatLine line) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: InkWell(
        onTap: () => _copyLine(line),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy, size: 11, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(width: 3),
              Text('Copy',
                  style: TextStyle(
                      fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
        ),
      ),
    );
  }

  void _sendTranscript() {
    final send = widget.onSendTranscript;
    if (send == null) return;
    final ok = send(_buildTurns());
    _toast(ok ? 'Sent transcript to agent' : 'Agent not connected');
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
          child: GestureDetector(
            onLongPress: () => _copyLine(line),
            onSecondaryTap: () => _copyLine(line),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.only(left: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(line.text,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
                _copyAffordance(line),
              ],
            ),
          ),
        );
      case ChatLineKind.assistant:
        return GestureDetector(
          onLongPress: () => _copyLine(line),
          onSecondaryTap: () => _copyLine(line),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4, right: 16),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(line.text,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, height: 1.4)),
                _copyAffordance(line),
              ],
            ),
          ),
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
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                )
              : IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Send',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                    foregroundColor: Colors.white,
                  ),
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
