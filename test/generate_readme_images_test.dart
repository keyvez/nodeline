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
  // perpendicular routing. The importer marks arrows orthogonal but leaves
  // waypoints for the paint-time router, so we run that router here exactly the
  // way the render object does: snap each endpoint to its attached node's edge,
  // pass the source/target rects (which drive the perpendicular exit/entry
  // stubs) and exclude those two rects from the obstacle list.
  final routed = <(Offset, Offset)>[];
  for (final o in objects.values) {
    if (o is! ArrowObject || o.pathType != LinkPathType.orthogonal) continue;

    final startId = o.startAttachment?.objectId;
    final endId = o.endAttachment?.objectId;
    final startRect = startId != null ? objects[startId]?.rect : null;
    final endRect = endId != null ? objects[endId]?.rect : null;

    var start = startRect != null ? _snapToNearestEdge(o.start, startRect) : o.start;
    var end = endRect != null ? _snapToNearestEdge(o.end, endRect) : o.end;

    final obstacles = <Rect>[];
    for (final other in objects.values) {
      if (other.id == o.id) continue;
      if (other.id == startId || other.id == endId) continue;
      if (other is ArrowObject || other is LineObject) continue;
      obstacles.add(other.rect);
    }

    o.start = start;
    o.end = end;
    o.waypoints = OrthogonalRouter.route(
      start: start,
      end: end,
      obstacles: obstacles,
      startObjectRect: startRect,
      endObjectRect: endRect,
      existingSegments: routed,
    );
    final pts = [start, ...?o.waypoints, end];
    for (var i = 0; i < pts.length - 1; i++) {
      routed.add((pts[i], pts[i + 1]));
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

/// Mirrors the render object's snap: moves [point] onto the nearest edge of
/// [rect] so the router's stub leaves the box perpendicularly.
Offset _snapToNearestEdge(Offset point, Rect rect) {
  final distToLeft = (point.dx - rect.left).abs();
  final distToRight = (point.dx - rect.right).abs();
  final distToTop = (point.dy - rect.top).abs();
  final distToBottom = (point.dy - rect.bottom).abs();
  final minDist =
      [distToLeft, distToRight, distToTop, distToBottom].reduce((a, b) => a < b ? a : b);
  if (minDist == distToLeft) return Offset(rect.left, point.dy);
  if (minDist == distToRight) return Offset(rect.right, point.dy);
  if (minDist == distToTop) return Offset(point.dx, rect.top);
  return Offset(point.dx, rect.bottom);
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
