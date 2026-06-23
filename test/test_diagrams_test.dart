import 'package:nodeline/src/core/mermaid/mermaid_importer.dart';
import 'package:nodeline/src/core/mermaid/test_diagrams.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TestDiagrams.consciousness', () {
    late Map<String, dynamic> project;

    setUp(() {
      project = MermaidImporter.import(TestDiagrams.consciousness);
    });

    test('imports without throwing and produces drawing objects', () {
      expect(project['drawingObjects'], isA<List>());
      final objects = project['drawingObjects'] as List;
      expect(objects, isNotEmpty);
    });

    test('produces the expected node and edge counts', () {
      final objects = (project['drawingObjects'] as List)
          .cast<Map<String, dynamic>>();
      final nodeCount =
          objects.where((o) => o['type'] == 'rectangle').length;
      final edgeCount = objects.where((o) => o['type'] == 'arrow').length;

      // 36 distinct nodes and 45 edges in the source diagram.
      expect(nodeCount, 36, reason: 'rectangle nodes');
      expect(edgeCount, 45, reason: 'arrow edges');
    });

    test('every edge connects two existing nodes', () {
      final objects = (project['drawingObjects'] as List)
          .cast<Map<String, dynamic>>();
      final nodeIds = objects
          .where((o) => o['type'] == 'rectangle')
          .map((o) => o['id'] as String)
          .toSet();

      for (final arrow in objects.where((o) => o['type'] == 'arrow')) {
        final startId = arrow['startAttachment']?['objectId'] as String?;
        final endId = arrow['endAttachment']?['objectId'] as String?;
        expect(startId, isNotNull, reason: 'arrow has a start attachment');
        expect(endId, isNotNull, reason: 'arrow has an end attachment');
        expect(nodeIds, contains(startId));
        expect(nodeIds, contains(endId));
      }
    });
  });
}
