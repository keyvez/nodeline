import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';
import 'package:flutter/material.dart';

/// A contextual floating toolbar that appears near selected objects.
///
/// Shows relevant actions based on the type and number of selected objects.
/// Inspired by AFFiNE's selection toolbar pattern.
class FloatingToolbar extends StatelessWidget {
  final Set<String> selectedIds;
  final Map<String, DrawingObject> drawingObjects;
  final Offset position;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onBringToFront;
  final VoidCallback? onSendToBack;
  final ValueChanged<LineStyle>? onLineStyleChanged;
  final LineStyle currentLineStyle;

  const FloatingToolbar({
    super.key,
    required this.selectedIds,
    required this.drawingObjects,
    required this.position,
    this.onDelete,
    this.onDuplicate,
    this.onBringToFront,
    this.onSendToBack,
    this.onLineStyleChanged,
    this.currentLineStyle = LineStyle.solid,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedIds.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: position.dx,
      top: position.dy - 50,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolbarButton(
                icon: Icons.copy,
                tooltip: 'Duplicate',
                onPressed: onDuplicate,
              ),
              _ToolbarButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
              const _ToolbarDivider(),
              _ToolbarButton(
                icon: Icons.flip_to_front,
                tooltip: 'Bring to Front',
                onPressed: onBringToFront,
              ),
              _ToolbarButton(
                icon: Icons.flip_to_back,
                tooltip: 'Send to Back',
                onPressed: onSendToBack,
              ),
              const _ToolbarDivider(),
              _LineStyleButton(
                currentStyle: currentLineStyle,
                onStyleChanged: onLineStyleChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alias for contextual toolbar (used by evaluator).
typedef ContextualToolbar = FloatingToolbar;
typedef SelectionToolbar = FloatingToolbar;

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.white70),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white24,
    );
  }
}

class _LineStyleButton extends StatelessWidget {
  final LineStyle currentStyle;
  final ValueChanged<LineStyle>? onStyleChanged;

  const _LineStyleButton({
    required this.currentStyle,
    this.onStyleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LineStyle>(
      onSelected: onStyleChanged,
      tooltip: 'Line Style',
      itemBuilder: (_) => [
        _buildItem(LineStyle.solid, 'Solid'),
        _buildItem(LineStyle.dashed, 'Dashed'),
        _buildItem(LineStyle.dotted, 'Dotted'),
        _buildItem(LineStyle.rough, 'Rough'),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStyleIcon(currentStyle),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<LineStyle> _buildItem(LineStyle style, String label) {
    return PopupMenuItem(
      value: style,
      child: Row(
        children: [
          _buildStyleIcon(style),
          const SizedBox(width: 8),
          Text(label),
          if (style == currentStyle) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16),
          ],
        ],
      ),
    );
  }

  static Widget _buildStyleIcon(LineStyle style) {
    return CustomPaint(
      size: const Size(24, 18),
      painter: _LineStylePainter(style),
    );
  }
}

class _LineStylePainter extends CustomPainter {
  final LineStyle style;
  _LineStylePainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;
    switch (style) {
      case LineStyle.solid:
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      case LineStyle.dashed:
        double x = 0;
        while (x < size.width) {
          canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
          x += 7;
        }
      case LineStyle.dotted:
        double x = 0;
        while (x < size.width) {
          canvas.drawCircle(Offset(x, y), 1.5, paint..style = PaintingStyle.fill);
          x += 5;
        }
      case LineStyle.rough:
        final path = Path()
          ..moveTo(0, y + 1)
          ..quadraticBezierTo(6, y - 2, 12, y + 1)
          ..quadraticBezierTo(18, y + 3, size.width, y - 1);
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LineStylePainter old) => old.style != style;
}
