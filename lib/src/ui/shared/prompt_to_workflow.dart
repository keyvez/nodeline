import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/core/mermaid/mermaid_importer.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Converts simple flow text notation (e.g. "A -> B -> C") into valid
/// Mermaid flowchart syntax that can be parsed by [MermaidImporter].
///
/// Supports:
/// - Chain syntax: `A -> B -> C`
/// - Labelled arrows with `|label|`: `A ->|yes| B`
/// - Mixed chains and standalone edges per line
/// - Lines starting with `flowchart` are passed through as-is
///
/// Returns a Mermaid flowchart string with `flowchart TD` header.
String convertSimpleFlowToMermaid(String input) {
  final lines = input.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final mermaidLines = <String>['flowchart TD'];

  for (final line in lines) {
    // Skip comment lines
    if (line.startsWith('//') || line.startsWith('#') || line.startsWith('%%')) {
      continue;
    }
    // If it already looks like a mermaid header, skip it
    if (RegExp(r'^flowchart\s*(TD|TB|LR|BT|RL)?\s*$').hasMatch(line)) {
      continue;
    }

    // Split on -> to handle chains like A -> B -> C
    // Also handle ->|label| syntax
    final chainPattern = RegExp(r'\s*->\s*(?:\|([^|]*)\|\s*)?');
    final parts = line.split(chainPattern);
    final labels = chainPattern.allMatches(line).map((m) => m.group(1)).toList();

    // Clean up parts: trim and remove empty
    final cleanParts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (cleanParts.length >= 2) {
      // It's a chain: generate pairwise edges
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
      // Standalone node declaration
      final decl = _nodeDeclaration(cleanParts[0]);
      mermaidLines.add(decl);
    }
  }

  return mermaidLines.join('\n');
}

/// Creates a sanitized node ID from a label string.
/// Replaces spaces and special chars with underscores.
String _sanitizeNodeId(String label) {
  return label.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').replaceAll(RegExp(r'_+'), '_');
}

/// Returns a Mermaid node declaration like `NodeId["Label Text"]`.
/// If the label is already a simple identifier, returns it as-is.
String _nodeDeclaration(String rawLabel) {
  final trimmed = rawLabel.trim();
  // If already looks like a Mermaid node (has brackets etc.), pass through
  if (RegExp(r'^\w+\[').hasMatch(trimmed) ||
      RegExp(r'^\w+\(\(').hasMatch(trimmed) ||
      RegExp(r'^\w+\{').hasMatch(trimmed) ||
      RegExp(r'^\w+\(\[').hasMatch(trimmed)) {
    return trimmed;
  }
  final id = _sanitizeNodeId(trimmed);
  // If the label is a simple word (same as its ID), no brackets needed
  if (id == trimmed && RegExp(r'^\w+$').hasMatch(trimmed)) {
    return trimmed;
  }
  return '$id["$trimmed"]';
}

/// Detects whether the input text is already Mermaid syntax, simple flow text,
/// or ambiguous.
enum _InputFormat { mermaid, simpleFlow }

_InputFormat _detectFormat(String input) {
  final trimmed = input.trim();
  // If it starts with "flowchart" or contains Mermaid-specific syntax, treat as Mermaid
  if (trimmed.startsWith('flowchart') ||
      RegExp(r'^\s*graph\s+(TD|TB|LR|BT|RL)', multiLine: true).hasMatch(trimmed)) {
    return _InputFormat.mermaid;
  }
  // If it contains Mermaid node syntax like A["text"] or A(("text")), treat as Mermaid
  if (RegExp(r'\w+\["[^"]*"\]').hasMatch(trimmed) ||
      RegExp(r'\w+\(\("[^"]*"\)\)').hasMatch(trimmed)) {
    return _InputFormat.mermaid;
  }
  // Otherwise treat as simple flow text
  return _InputFormat.simpleFlow;
}

/// A toolbar button that opens a text-to-diagram prompt dialog.
///
/// Users can type either:
/// 1. Direct Mermaid syntax (auto-detected if it starts with `flowchart`)
/// 2. Simple flow text like `A -> B -> C` which gets converted to Mermaid
///
/// The parsed result is loaded into the canvas via [CanvasBloc].
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
///
/// This can be called from the toolbar button or via a keyboard shortcut.
void showPromptToWorkflowDialog(BuildContext context, CanvasBloc canvasBloc) {
  showPopover(
    context: context,
    alignment: Alignment.topCenter,
    builder: (popoverContext) {
      return ModalContainer(
        child: SizedBox(
          width: 420,
          child: _PromptToWorkflowContent(
            popoverContext: popoverContext,
            canvasBloc: canvasBloc,
          ),
        ),
      ).withPadding(top: 8);
    },
  );
}

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
  final _textController = TextEditingController();
  String? _errorMessage;
  bool _isProcessing = false;
  _InputFormat? _detectedFormat;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    setState(() {
      _errorMessage = null;
      if (text.trim().isNotEmpty) {
        _detectedFormat = _detectFormat(text);
      } else {
        _detectedFormat = null;
      }
    });
  }

  void _handleGenerate() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please enter some text to generate a diagram.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final format = _detectFormat(text);
      String mermaidText;

      if (format == _InputFormat.mermaid) {
        mermaidText = text;
      } else {
        mermaidText = convertSimpleFlowToMermaid(text);
      }

      final projectData = MermaidImporter.import(mermaidText);
      widget.canvasBloc.add(ProjectLoaded(projectData));
      closeOverlay(widget.popoverContext);
      showNodeEditorSnackbar('Diagram generated successfully', SnackbarType.success);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Failed to generate diagram: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 16),
            const Gap(8),
            Text(
              'Text to Diagram',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const Gap(8),
        Text(
          'Enter Mermaid syntax or simple flow text (e.g. "Start -> Process -> End")',
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
        ),
        const Gap(8),
        TextField(
          controller: _textController,
          placeholder: Text(
            'flowchart TD\n  A["Start"] --> B["Process"]\n  B --> C["End"]\n\nor simply:\n  Start -> Process -> End',
          ),
          maxLines: 10,
          autofocus: true,
          style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
          onChanged: _onTextChanged,
        ),
        if (_detectedFormat != null) ...[
          const Gap(4),
          Text(
            _detectedFormat == _InputFormat.mermaid
                ? 'Detected: Mermaid syntax'
                : 'Detected: Simple flow text (will convert to Mermaid)',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
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
                onPressed: _isProcessing ? null : _handleGenerate,
                child: Text(_isProcessing ? 'Generating...' : 'Generate'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
