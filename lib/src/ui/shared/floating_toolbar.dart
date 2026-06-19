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
  /// Called when the user requests crossing minimization.
  /// The [changeConnectionPoints] parameter controls whether port reassignment
  /// is allowed (true) or only waypoint re-routing (false).
  final ValueChanged<bool>? onMinimizeCrossings;

  /// The zoom level at which the single selected object was created.
  /// When non-null and != 1.0, a zoom badge is shown in the toolbar.
  final double? creationZoom;

  /// Called when the user taps the creation-zoom badge to jump to that zoom.
  final VoidCallback? onGoToCreationZoom;

  /// Whether any selected object carries text/font (controls the font picker).
  final bool hasFontTarget;

  /// The effective font family currently shown for the selection.
  final String currentFontFamily;

  /// The effective font size currently shown for the selection.
  final double currentFontSize;

  /// Whether the selection's font has been individually customized (controls
  /// whether the "Reset to default" action is offered).
  final bool fontCustomized;

  /// Called when the user picks a font family/size for the selection. Either
  /// argument may be null to leave that axis unchanged.
  final void Function(String? family, double? size)? onFontChanged;

  /// Called when the user resets the selection's font to the global default.
  final VoidCallback? onFontReset;

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
    this.onMinimizeCrossings,
    this.creationZoom,
    this.onGoToCreationZoom,
    this.hasFontTarget = false,
    this.currentFontFamily = kEditorDefaultFontFamily,
    this.currentFontSize = kEditorDefaultFontSize,
    this.fontCustomized = false,
    this.onFontChanged,
    this.onFontReset,
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
              if (hasFontTarget && onFontChanged != null) ...[
                const _ToolbarDivider(),
                _FontButton(
                  family: currentFontFamily,
                  size: currentFontSize,
                  customized: fontCustomized,
                  onChanged: onFontChanged!,
                  onReset: onFontReset,
                ),
              ],
              if (onMinimizeCrossings != null) ...[
                const _ToolbarDivider(),
                _MinimizeCrossingsButton(
                  onMinimize: onMinimizeCrossings!,
                ),
              ],
              if (creationZoom != null && selectedIds.length == 1) ...[
                const _ToolbarDivider(),
                _ZoomInfoButton(
                  zoom: creationZoom!,
                  onGoTo: onGoToCreationZoom,
                ),
              ],
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

/// Font picker for the selected shape(s): family choices, a size stepper, and
/// (when the selection has been customized) a "Reset to default" action.
class _FontButton extends StatelessWidget {
  final String family;
  final double size;
  final bool customized;
  final void Function(String? family, double? size) onChanged;
  final VoidCallback? onReset;

  const _FontButton({
    required this.family,
    required this.size,
    required this.customized,
    required this.onChanged,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) {
        return Tooltip(
          message: 'Font',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.text_fields, size: 18, color: Colors.white70),
                  const SizedBox(width: 2),
                  Text(
                    '${size.round()}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  const Icon(Icons.arrow_drop_down,
                      size: 14, color: Colors.white54),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        _FontMenuPanel(
          family: family,
          size: size,
          customized: customized,
          onChanged: onChanged,
          onReset: onReset,
        ),
      ],
    );
  }
}

/// The stateful body of the font menu — tracks the live size so repeated
/// stepper taps accumulate while the menu stays open.
class _FontMenuPanel extends StatefulWidget {
  final String family;
  final double size;
  final bool customized;
  final void Function(String? family, double? size) onChanged;
  final VoidCallback? onReset;

  const _FontMenuPanel({
    required this.family,
    required this.size,
    required this.customized,
    required this.onChanged,
    this.onReset,
  });

  @override
  State<_FontMenuPanel> createState() => _FontMenuPanelState();
}

class _FontMenuPanelState extends State<_FontMenuPanel> {
  late String _family = widget.family;
  late double _size = widget.size;

  static const double _minSize = 6;
  static const double _maxSize = 96;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in kEditorFontFamilies)
            InkWell(
              onTap: () {
                setState(() => _family = f);
                widget.onChanged(f, null);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      f == _family
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(f, style: TextStyle(fontSize: 13, fontFamily: f)),
                  ],
                ),
              ),
            ),
          const Divider(height: 12),
          Row(
            children: [
              const Text('Size', style: TextStyle(fontSize: 12)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.remove),
                onPressed: () {
                  setState(
                      () => _size = (_size - 1).clamp(_minSize, _maxSize));
                  widget.onChanged(null, _size);
                },
              ),
              SizedBox(
                width: 32,
                child: Text('${_size.round()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.add),
                onPressed: () {
                  setState(
                      () => _size = (_size + 1).clamp(_minSize, _maxSize));
                  widget.onChanged(null, _size);
                },
              ),
            ],
          ),
          if (widget.customized && widget.onReset != null) ...[
            const Divider(height: 12),
            InkWell(
              onTap: widget.onReset,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 16),
                    SizedBox(width: 8),
                    Text('Reset to default', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small badge showing the zoom level at which an object was created,
/// with a tap action to return to that zoom level.
class _ZoomInfoButton extends StatelessWidget {
  final double zoom;
  final VoidCallback? onGoTo;

  const _ZoomInfoButton({required this.zoom, this.onGoTo});

  String get _label {
    if (zoom >= 100) return '@${zoom.round()}x';
    if (zoom >= 10) return '@${zoom.toStringAsFixed(1)}x';
    return '@${zoom.toStringAsFixed(2)}x';
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Created at $_label — tap to go there',
      child: InkWell(
        onTap: onGoTo,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            _label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.6),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

/// A popup button that offers two crossing-minimization strategies.
class _MinimizeCrossingsButton extends StatelessWidget {
  final ValueChanged<bool> onMinimize;

  const _MinimizeCrossingsButton({required this.onMinimize});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Minimize Crossings',
      onSelected: onMinimize,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: true,
          child: Row(
            children: [
              Icon(Icons.route, size: 16),
              SizedBox(width: 8),
              Text('Reroute & change ports'),
            ],
          ),
        ),
        PopupMenuItem(
          value: false,
          child: Row(
            children: [
              Icon(Icons.alt_route, size: 16),
              SizedBox(width: 8),
              Text('Reroute only'),
            ],
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.device_hub, size: 18, color: Colors.white70),
      ),
    );
  }
}
