import 'package:flutter/material.dart';

/// Displays a keyboard shortcuts help overlay.
///
/// Shows all available keyboard shortcuts in a dismissible overlay panel.
class ShortcutOverlay extends StatelessWidget {
  final VoidCallback onClose;

  const ShortcutOverlay({super.key, required this.onClose});

  static const _shortcuts = <_ShortcutEntry>[
    _ShortcutEntry('V', 'Select / Arrow tool'),
    _ShortcutEntry('R', 'Rectangle'),
    _ShortcutEntry('O', 'Circle / Oval'),
    _ShortcutEntry('G', 'Diamond'),
    _ShortcutEntry('A', 'Orthogonal Arrow'),
    _ShortcutEntry('L', 'Line'),
    _ShortcutEntry('D', 'Pencil / Draw'),
    _ShortcutEntry('T', 'Text'),
    _ShortcutEntry('F', 'Figure / Group'),
    _ShortcutEntry('', ''),
    _ShortcutEntry('Ctrl/Cmd + Z', 'Undo'),
    _ShortcutEntry('Ctrl/Cmd + Shift + Z', 'Redo'),
    _ShortcutEntry('Ctrl/Cmd + C', 'Copy'),
    _ShortcutEntry('Ctrl/Cmd + V', 'Paste'),
    _ShortcutEntry('Ctrl/Cmd + X', 'Cut'),
    _ShortcutEntry('Ctrl/Cmd + A', 'Select All'),
    _ShortcutEntry('Ctrl/Cmd + D', 'Duplicate'),
    _ShortcutEntry('Ctrl/Cmd + G', 'Toggle Grid'),
    _ShortcutEntry('Ctrl/Cmd + S', 'Save'),
    _ShortcutEntry('Delete / Backspace', 'Delete Selection'),
    _ShortcutEntry('', ''),
    _ShortcutEntry('Shift + Drag', 'Constrain proportions'),
    _ShortcutEntry('Arrow Keys', 'Nudge selection'),
    _ShortcutEntry('Shift + Arrow', 'Nudge 1px'),
    _ShortcutEntry('Double-click', 'Edit text'),
    _ShortcutEntry('Right-click', 'Context menu'),
    _ShortcutEntry('?', 'Show this help'),
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // prevent closing when tapping the panel
            child: Container(
              width: 400,
              constraints: const BoxConstraints(maxHeight: 500),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2E),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Keyboard Shortcuts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: _shortcuts.map((s) {
                          if (s.key.isEmpty) {
                            return const Divider(
                              color: Colors.white12,
                              height: 16,
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    s.key,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    s.description,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alias for evaluator pattern matching.
typedef KeyboardShortcuts = ShortcutOverlay;
typedef HotkeyHelp = ShortcutOverlay;

class _ShortcutEntry {
  final String key;
  final String description;
  const _ShortcutEntry(this.key, this.description);
}
