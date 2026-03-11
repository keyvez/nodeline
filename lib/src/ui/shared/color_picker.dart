import 'package:flutter/material.dart';

/// A compact color picker for stroke and fill colors.
///
/// Shows a grid of preset colors plus custom color input.
class ColorPicker extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final String label;

  const ColorPicker({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
    this.label = 'Color',
  });

  static const List<Color> presetColors = [
    Colors.white,
    Color(0xFFE0E0E0),
    Color(0xFF9E9E9E),
    Color(0xFF616161),
    Color(0xFF212121),
    Colors.red,
    Color(0xFFE91E63),
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: presetColors.map((color) {
            final isSelected = currentColor.value == color.value;
            return GestureDetector(
              onTap: () => onColorChanged(color),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.white24,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// A fill color picker variant that includes a "no fill" option.
class FillColorPicker extends StatelessWidget {
  final Color? currentColor;
  final ValueChanged<Color?> onColorChanged;

  const FillColorPicker({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Fill',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            // No fill option
            GestureDetector(
              onTap: () => onColorChanged(null),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: currentColor == null ? Colors.blue : Colors.white24,
                    width: currentColor == null ? 2 : 1,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.block, size: 14, color: Colors.white38),
                ),
              ),
            ),
            ...ColorPicker.presetColors.map((color) {
              final isSelected = currentColor?.value == color.value;
              return GestureDetector(
                onTap: () => onColorChanged(color),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.white24,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}

/// A stroke color picker widget.
class StrokeColorPicker extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;

  const StrokeColorPicker({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ColorPicker(
      currentColor: currentColor,
      onColorChanged: onColorChanged,
      label: 'Stroke',
    );
  }
}
