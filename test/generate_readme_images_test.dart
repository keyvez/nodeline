// Generates the README hero images by importing Mermaid diagrams through the
// SDK's own importer and rendering them with PngExporter. Run with:
//   flutter test test/generate_readme_images_test.dart
// Output: assets/readme/*.png
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/models/drawing_entities.dart'
    show drawingObjectFromJson, LinkPathType;
import 'package:nodeline/src/core/utils/orthogonal_router.dart';

Future<void> _render(String mermaid, String outPath, {double pixelRatio = 2.0}) async {
  // The PNG exporter renders label text verbatim and the importer parses line
  // by line, so collapse Mermaid's <br/> tags to a space (keeps each node on
  // one source line while dropping the literal tag from the rendered label).
  mermaid = mermaid.replaceAll(RegExp(r'<br\s*/?>'), ' ');
  final project = MermaidImporter.import(mermaid);
  final list = (project['drawingObjects'] as List)
      .map((j) => drawingObjectFromJson(j as Map<String, dynamic>))
      .whereType<DrawingObject>()
      .toList();
  final objects = {for (final o in list) o.id: o};
  expect(objects, isNotEmpty, reason: 'importer produced no objects for $outPath');

  // Route arrows orthogonally so the exported image matches the real app's
  // perpendicular routing (the importer marks arrows orthogonal but leaves
  // waypoints for the paint-time router; we run that router here).
  final obstacles = objects.values
      .where((o) => o is! ArrowObject && o is! LineObject)
      .map((o) => o.rect)
      .toList();
  final routed = <(Offset, Offset)>[];
  for (final o in objects.values) {
    if (o is ArrowObject && o.pathType == LinkPathType.orthogonal) {
      o.waypoints = OrthogonalRouter.route(
        start: o.start,
        end: o.end,
        obstacles: obstacles,
        existingSegments: routed,
      );
      final pts = [o.start, ...?o.waypoints, o.end];
      for (var i = 0; i < pts.length - 1; i++) {
        routed.add((pts[i], pts[i + 1]));
      }
    }
  }

  final png = await PngExporter.exportPng(objects, pixelRatio: pixelRatio);
  expect(png, isNotNull, reason: 'exporter returned null for $outPath');

  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!);
  // ignore: avoid_print
  print('wrote $outPath (${png.length} bytes, ${objects.length} objects)');
}

Future<void> _loadRealFont() async {
  // flutter test ships the "Ahem" font where every glyph is a solid box, so
  // text would render as bars. Register a real TTF under the family name the
  // exporter asks for ('sans-serif') so labels are legible.
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/Library/Fonts/Arial Unicode.ttf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final loader = FontLoader('sans-serif')
        ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      return;
    }
  }
  // ignore: avoid_print
  print('WARNING: no real font found; text may render as boxes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const basic = '''
flowchart TD
    A["Start"] --> B["Process Input"]
    B --> C{"Valid?"}
    C --> D["Save to Database"]
    C --> E["Show Error"]
    D --> F["Done"]
    E --> B
''';

  testWidgets('basic_ui.png', (tester) async {
    await tester.runAsync(() async {
      await _loadRealFont();
      await _render(basic, 'assets/readme/basic_ui.png');
    });
  });

  testWidgets('complex consciousness diagram', (tester) async {
    await tester.runAsync(() async {
      await _loadRealFont();
      await _render(TestDiagrams.consciousness, 'assets/readme/complex.png');
    });
  });
}
