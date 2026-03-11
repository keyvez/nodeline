import 'dart:ui';
import 'package:flutter/material.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';

void main() {
  group('DiamondObject', () {
    test('creates with required fields', () {
      final diamond = DiamondObject(
        id: 'test-1',
        rect: Rect.fromLTWH(0, 0, 100, 80),
      );
      expect(diamond.id, 'test-1');
      expect(diamond.rect.width, 100);
      expect(diamond.rect.height, 80);
      expect(diamond.text, isNull);
      expect(diamond.isEditing, false);
    });

    test('creates with text and style', () {
      final diamond = DiamondObject(
        id: 'test-2',
        rect: Rect.fromLTWH(10, 20, 120, 90),
        text: 'Decision',
        textStyle: TextStyle(fontSize: 14),
      );
      expect(diamond.text, 'Decision');
      expect(diamond.textStyle?.fontSize, 14);
    });

    test('path creates correct diamond shape', () {
      final diamond = DiamondObject(
        id: 'test-3',
        rect: Rect.fromLTWH(0, 0, 100, 80),
      );
      final path = diamond.path;
      // Path should have 4 points forming a diamond
      expect(path.getBounds().width, closeTo(100, 1));
      expect(path.getBounds().height, closeTo(80, 1));
    });

    test('toJson includes type diamond', () {
      final diamond = DiamondObject(
        id: 'test-4',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        text: 'Test',
      );
      final json = diamond.toJson();
      expect(json['type'], 'diamond');
      expect(json['text'], 'Test');
      expect(json['id'], 'test-4');
    });

    test('fromJson round-trips correctly', () {
      final original = DiamondObject(
        id: 'test-5',
        rect: Rect.fromLTWH(10, 20, 100, 80),
        text: 'Round Trip',
        lineStyle: LineStyle.dashed,
      );
      final json = original.toJson();
      final restored = DiamondObject.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.rect, original.rect);
      expect(restored.text, original.text);
      expect(restored.lineStyle, LineStyle.dashed);
    });

    test('copyWith preserves and overrides fields', () {
      final diamond = DiamondObject(
        id: 'test-6',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        text: 'Original',
        isEditing: true,
      );
      final copy = diamond.copyWith(isSelected: true, isEditing: false);
      expect(copy.isSelected, true);
      expect((copy as DiamondObject).isEditing, false);
      expect(copy.id, 'test-6');
    });
  });

  group('EditorTool', () {
    test('diamond tool exists in enum', () {
      expect(EditorTool.diamond, isNotNull);
      expect(EditorTool.values.contains(EditorTool.diamond), true);
    });
  });

  group('ArrowHeadType', () {
    test('has expected values', () {
      expect(ArrowHeadType.values.length, 5);
      expect(ArrowHeadType.none, isNotNull);
      expect(ArrowHeadType.triangle, isNotNull);
      expect(ArrowHeadType.diamond, isNotNull);
      expect(ArrowHeadType.dot, isNotNull);
      expect(ArrowHeadType.bar, isNotNull);
    });
  });

  group('workflowTools', () {
    test('contains expected workflow tools', () {
      expect(workflowTools.contains(EditorTool.arrow), true);
      expect(workflowTools.contains(EditorTool.square), true);
      expect(workflowTools.contains(EditorTool.diamond), true);
      expect(workflowTools.contains(EditorTool.arrowTopRight), true);
      expect(workflowTools.contains(EditorTool.text), true);
    });

    test('does not contain non-workflow tools', () {
      expect(workflowTools.contains(EditorTool.pencil), false);
      expect(workflowTools.contains(EditorTool.circle), false);
      expect(workflowTools.contains(EditorTool.line), false);
      expect(workflowTools.contains(EditorTool.figure), false);
    });
  });

  group('MermaidExporter', () {
    test('exports diamond as curly brace syntax', () {
      final objects = <String, DrawingObject>{
        'd1': DiamondObject(
          id: 'd1',
          rect: Rect.fromLTWH(0, 0, 100, 80),
          text: 'Approve?',
        ),
      };
      final mermaid = MermaidExporter.export(objects);
      expect(mermaid, contains('{'));
      expect(mermaid, contains('Approve?'));
    });

    test('exports diamond with connections', () {
      final objects = <String, DrawingObject>{
        'r1': RectangleObject(
          id: 'r1',
          rect: Rect.fromLTWH(0, 0, 100, 80),
          text: 'Start',
        ),
        'd1': DiamondObject(
          id: 'd1',
          rect: Rect.fromLTWH(200, 0, 100, 80),
          text: 'Check',
        ),
        'a1': ArrowObject(
          id: 'a1',
          start: Offset(100, 40),
          end: Offset(200, 40),
          startAttachment: ObjectAttachment(
            objectId: 'r1',
            relativePosition: Offset(1.0, 0.5),
          ),
          endAttachment: ObjectAttachment(
            objectId: 'd1',
            relativePosition: Offset(0.0, 0.5),
          ),
        ),
      };
      final mermaid = MermaidExporter.export(objects);
      expect(mermaid, contains('-->'));
      expect(mermaid, contains('Start'));
      expect(mermaid, contains('Check'));
    });
  });

  group('MermaidImporter', () {
    test('imports diamond from curly brace syntax', () {
      const mermaid = '''
flowchart TD
    A["Start"] --> B{"Decision"}
    B --> C["Yes"]
    B --> D["No"]
''';
      final result = MermaidImporter.import(mermaid);
      final objects = result['drawingObjects'] as List;
      final types = objects.map((o) => o['type']).toList();
      expect(types, contains('diamond'));
      expect(types, contains('rectangle'));
    });
  });
}
