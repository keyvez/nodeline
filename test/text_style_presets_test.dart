import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/models/drawing_entities.dart';

/// The Docs-style text-style presets shown at the top of the font panel. Presets
/// are now global-relative: a scale factor off the global font size.
void main() {
  test('presets include the expected named styles', () {
    final labels = kTextStylePresets.map((p) => p.label).toList();
    expect(labels, containsAll(['Title', 'Heading 1', 'Heading 2', 'Body', 'Leaf node']));
  });

  test('scales descend from Title down to Caption', () {
    final scales = kTextStylePresets.map((p) => p.scale).toList();
    for (var i = 1; i < scales.length; i++) {
      expect(scales[i], lessThanOrEqualTo(scales[i - 1]),
          reason: '${kTextStylePresets[i].label} should not scale larger than the previous');
    }
  });

  test('Body == the global size (scale 1.0) so it round-trips with reset', () {
    final body = kTextStylePresets.firstWhere((p) => p.label == 'Body');
    expect(body.scale, 1.0);
    expect(body.sizeFor(36), 36);
  });

  test('presets resolve relative to the global size', () {
    final title = kTextStylePresets.firstWhere((p) => p.label == 'Title');
    final leaf = kTextStylePresets.firstWhere((p) => p.label == 'Leaf node');
    // Global Courier 36 → Title is bigger than 36, Leaf smaller, both derived.
    expect(title.sizeFor(36), greaterThan(36));
    expect(leaf.sizeFor(36), lessThan(36));
    // Doubling the global size doubles every preset's resolved size.
    expect(title.sizeFor(72), title.sizeFor(36) * 2);
  });
}
