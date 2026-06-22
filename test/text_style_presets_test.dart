import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';

/// The Docs-style text-style presets shown at the top of the font panel.
void main() {
  test('presets include the expected named styles', () {
    final labels = kTextStylePresets.map((p) => p.label).toList();
    expect(labels, containsAll(['Title', 'Heading 1', 'Heading 2', 'Body', 'Leaf node']));
  });

  test('sizes descend from Title down to Caption', () {
    final sizes = kTextStylePresets.map((p) => p.size).toList();
    for (var i = 1; i < sizes.length; i++) {
      expect(sizes[i], lessThanOrEqualTo(sizes[i - 1]),
          reason: 'preset ${kTextStylePresets[i].label} should not be larger than the previous');
    }
  });

  test('Body matches the editor defaults so it round-trips with reset', () {
    final body = kTextStylePresets.firstWhere((p) => p.label == 'Body');
    expect(body.family, kEditorDefaultFontFamily);
    expect(body.size, kEditorDefaultFontSize);
  });

  test('every preset family is a known editor font family', () {
    for (final p in kTextStylePresets) {
      expect(kEditorFontFamilies, contains(p.family),
          reason: '${p.label} uses unknown family ${p.family}');
    }
  });
}
