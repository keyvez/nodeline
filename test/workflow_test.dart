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

  group('ParallelogramObject', () {
    test('creates with required fields', () {
      final para = ParallelogramObject(
        id: 'para-1',
        rect: Rect.fromLTWH(0, 0, 120, 60),
      );
      expect(para.id, 'para-1');
      expect(para.rect.width, 120);
      expect(para.skewOffset, 20.0);
    });

    test('creates with text', () {
      final para = ParallelogramObject(
        id: 'para-2',
        rect: Rect.fromLTWH(0, 0, 120, 60),
        text: 'Input Data',
      );
      expect(para.text, 'Input Data');
    });

    test('path creates correct parallelogram shape', () {
      final para = ParallelogramObject(
        id: 'para-3',
        rect: Rect.fromLTWH(0, 0, 120, 60),
        skewOffset: 20,
      );
      final path = para.path;
      final bounds = path.getBounds();
      expect(bounds.width, closeTo(120, 1));
      expect(bounds.height, closeTo(60, 1));
    });

    test('toJson round-trips correctly', () {
      final original = ParallelogramObject(
        id: 'para-4',
        rect: Rect.fromLTWH(10, 20, 120, 60),
        text: 'Process',
        lineStyle: LineStyle.dashed,
        skewOffset: 25.0,
      );
      final json = original.toJson();
      expect(json['type'], 'parallelogram');
      expect(json['skewOffset'], 25.0);

      final restored = ParallelogramObject.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.rect, original.rect);
      expect(restored.text, original.text);
      expect(restored.lineStyle, LineStyle.dashed);
      expect(restored.skewOffset, 25.0);
    });

    test('copyWith preserves and overrides fields', () {
      final para = ParallelogramObject(
        id: 'para-5',
        rect: Rect.fromLTWH(0, 0, 120, 60),
        text: 'Original',
      );
      final copy = para.copyWith(isSelected: true);
      expect(copy.isSelected, true);
      expect(copy.id, 'para-5');
    });
  });

  group('ForkJoinObject', () {
    test('creates with required fields', () {
      final fork = ForkJoinObject(
        id: 'fork-1',
        rect: Rect.fromLTWH(0, 0, 200, 10),
      );
      expect(fork.id, 'fork-1');
      expect(fork.rect.width, 200);
      expect(fork.rect.height, 10);
    });

    test('toJson round-trips correctly', () {
      final original = ForkJoinObject(
        id: 'fork-2',
        rect: Rect.fromLTWH(50, 100, 200, 8),
        lineStyle: LineStyle.solid,
      );
      final json = original.toJson();
      expect(json['type'], 'fork_join');

      final restored = ForkJoinObject.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.rect, original.rect);
      expect(restored.lineStyle, LineStyle.solid);
    });

    test('copyWith preserves and overrides fields', () {
      final fork = ForkJoinObject(
        id: 'fork-3',
        rect: Rect.fromLTWH(0, 0, 200, 10),
      );
      final copy = fork.copyWith(isSelected: true);
      expect(copy.isSelected, true);
      expect(copy.id, 'fork-3');
    });
  });

  group('RectangleObject borderRadius', () {
    test('default borderRadius is 0', () {
      final rect = RectangleObject(
        id: 'rect-1',
        rect: Rect.fromLTWH(0, 0, 100, 80),
      );
      expect(rect.borderRadius, 0.0);
    });

    test('custom borderRadius is preserved', () {
      final rect = RectangleObject(
        id: 'rect-2',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        borderRadius: 12.0,
      );
      expect(rect.borderRadius, 12.0);
    });

    test('borderRadius round-trips through JSON', () {
      final original = RectangleObject(
        id: 'rect-3',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        borderRadius: 16.0,
        text: 'Rounded',
      );
      final json = original.toJson();
      expect(json['borderRadius'], 16.0);

      final restored = RectangleObject.fromJson(json);
      expect(restored.borderRadius, 16.0);
      expect(restored.text, 'Rounded');
    });

    test('borderRadius 0 is not included in JSON', () {
      final rect = RectangleObject(
        id: 'rect-4',
        rect: Rect.fromLTWH(0, 0, 100, 80),
      );
      final json = rect.toJson();
      expect(json.containsKey('borderRadius'), false);
    });

    test('copyWith can update borderRadius', () {
      final rect = RectangleObject(
        id: 'rect-5',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        borderRadius: 8.0,
      );
      final copy = rect.copyWith(borderRadius: 16.0);
      expect((copy as RectangleObject).borderRadius, 16.0);
    });
  });

  group('ConnectionPort', () {
    test('computes 4 cardinal ports for rect', () {
      final ports = ConnectionPort.portsForRect(
        Rect.fromLTWH(100, 100, 200, 100),
        'obj-1',
      );
      expect(ports.length, 4);
      expect(ports.any((p) => p.direction == PortDirection.top), true);
      expect(ports.any((p) => p.direction == PortDirection.right), true);
      expect(ports.any((p) => p.direction == PortDirection.bottom), true);
      expect(ports.any((p) => p.direction == PortDirection.left), true);
    });

    test('port positions are correct', () {
      final rect = Rect.fromLTWH(100, 100, 200, 100);
      final ports = ConnectionPort.portsForRect(rect, 'obj-2');

      final topPort = ports.firstWhere((p) => p.direction == PortDirection.top);
      expect(topPort.portPosition, Offset(200, 100)); // center x, top y

      final rightPort = ports.firstWhere((p) => p.direction == PortDirection.right);
      expect(rightPort.portPosition, Offset(300, 150)); // right x, center y

      final bottomPort = ports.firstWhere((p) => p.direction == PortDirection.bottom);
      expect(bottomPort.portPosition, Offset(200, 200)); // center x, bottom y

      final leftPort = ports.firstWhere((p) => p.direction == PortDirection.left);
      expect(leftPort.portPosition, Offset(100, 150)); // left x, center y
    });

    test('DrawingObject.getConnectionPorts returns ports', () {
      final rect = RectangleObject(
        id: 'rect-ports',
        rect: Rect.fromLTWH(0, 0, 100, 80),
      );
      final ports = rect.getConnectionPorts();
      expect(ports.length, 4);
      expect(ports.first.objectId, 'rect-ports');
    });
  });

  group('ArrowObject label', () {
    test('creates with label', () {
      final arrow = ArrowObject(
        id: 'arr-1',
        start: Offset(0, 0),
        end: Offset(100, 100),
        arrowLabel: 'Yes',
      );
      expect(arrow.arrowLabel, 'Yes');
    });

    test('label defaults to null', () {
      final arrow = ArrowObject(
        id: 'arr-2',
        start: Offset(0, 0),
        end: Offset(100, 100),
      );
      expect(arrow.arrowLabel, isNull);
    });

    test('label round-trips through JSON', () {
      final original = ArrowObject(
        id: 'arr-3',
        start: Offset(10, 20),
        end: Offset(110, 120),
        arrowLabel: 'Condition',
      );
      final json = original.toJson();
      final restored = ArrowObject.fromJson(json);
      expect(restored.arrowLabel, 'Condition');
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

    test('exports arrow labels in mermaid syntax', () {
      final objects = <String, DrawingObject>{
        'r1': RectangleObject(
          id: 'r1',
          rect: Rect.fromLTWH(0, 0, 100, 80),
          text: 'Start',
        ),
        'r2': RectangleObject(
          id: 'r2',
          rect: Rect.fromLTWH(200, 0, 100, 80),
          text: 'End',
        ),
        'a1': ArrowObject(
          id: 'a1',
          start: Offset(100, 40),
          end: Offset(200, 40),
          arrowLabel: 'yes',
          startAttachment: ObjectAttachment(
            objectId: 'r1',
            relativePosition: Offset(1.0, 0.5),
          ),
          endAttachment: ObjectAttachment(
            objectId: 'r2',
            relativePosition: Offset(0.0, 0.5),
          ),
        ),
      };
      final mermaid = MermaidExporter.export(objects);
      expect(mermaid, contains('yes'));
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

  group('MermaidExporter parallelogram', () {
    test('exports parallelogram as slash syntax', () {
      final objects = <String, DrawingObject>{
        'p1': ParallelogramObject(
          id: 'p1',
          rect: Rect.fromLTWH(0, 0, 120, 80),
          text: 'Input',
        ),
      };
      final mermaid = MermaidExporter.export(objects);
      expect(mermaid, contains('[/"Input"/]'));
    });

    test('exports forkJoin as stadium syntax', () {
      final objects = <String, DrawingObject>{
        'fj1': ForkJoinObject(
          id: 'fj1',
          rect: Rect.fromLTWH(0, 0, 200, 10),
        ),
      };
      final mermaid = MermaidExporter.export(objects);
      expect(mermaid, contains('(["'));
    });
  });

  group('MermaidImporter parallelogram', () {
    test('imports parallelogram from slash syntax', () {
      const mermaid = '''
flowchart TD
    A["Start"] --> B[/"Input"/]
    B --> C["End"]
''';
      final result = MermaidImporter.import(mermaid);
      final objects = result['drawingObjects'] as List;
      final types = objects.map((o) => o['type']).toList();
      expect(types, contains('parallelogram'));
      expect(types, contains('rectangle'));
    });
  });

  group('WorkflowValidator', () {
    test('validates basic workflow', () {
      final objects = <String, DrawingObject>{
        'start': RectangleObject(
          id: 'start',
          rect: Rect.fromLTWH(0, 0, 100, 80),
          text: 'Start',
        ),
        'end': RectangleObject(
          id: 'end',
          rect: Rect.fromLTWH(200, 0, 100, 80),
          text: 'End',
        ),
        'a1': ArrowObject(
          id: 'a1',
          start: Offset(100, 40),
          end: Offset(200, 40),
          startAttachment: ObjectAttachment(
            objectId: 'start',
            relativePosition: Offset(1.0, 0.5),
          ),
          endAttachment: ObjectAttachment(
            objectId: 'end',
            relativePosition: Offset(0.0, 0.5),
          ),
        ),
      };
      final result = WorkflowValidator.validateWorkflow(objects);
      expect(result.isValid, true);
    });
  });

  group('WorkflowTemplate', () {
    test('has available templates', () {
      final templates = WorkflowTemplate.templates;
      expect(templates, isNotEmpty);
    });

    test('templates have name and mermaid content', () {
      for (final t in WorkflowTemplate.templates) {
        expect(t.name, isNotEmpty);
        expect(t.mermaidDiagram, contains('flowchart'));
      }
    });
  });

  group('SnapGuide', () {
    test('AlignmentGuide finds horizontal alignment', () {
      final objects = <String, DrawingObject>{
        'ref': RectangleObject(
          id: 'ref',
          rect: Rect.fromLTWH(0, 100, 100, 50),
        ),
      };
      final movingRect = Rect.fromLTWH(200, 102, 100, 50);
      final guides = AlignmentGuide.findGuides(movingRect, objects, {});
      // Should find horizontal guide (top edges near: 102 vs 100)
      expect(guides.any((g) => g.axis == SnapGuideAxis.horizontal), true);
    });

    test('AlignmentGuide excludes specified IDs', () {
      final objects = <String, DrawingObject>{
        'self': RectangleObject(
          id: 'self',
          rect: Rect.fromLTWH(0, 100, 100, 50),
        ),
      };
      final movingRect = Rect.fromLTWH(0, 100, 100, 50);
      final guides = AlignmentGuide.findGuides(movingRect, objects, {'self'});
      expect(guides, isEmpty);
    });
  });

  group('Object fillColor and strokeColor', () {
    test('RectangleObject supports fill and stroke colors', () {
      final rect = RectangleObject(
        id: 'color-1',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        fillColor: const Color(0xFFFF0000),
        strokeColor: const Color(0xFF00FF00),
      );
      expect(rect.fillColor, const Color(0xFFFF0000));
      expect(rect.strokeColor, const Color(0xFF00FF00));
    });

    test('RectangleObject colors round-trip through JSON', () {
      final original = RectangleObject(
        id: 'color-2',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        fillColor: const Color(0xFF0000FF),
        strokeColor: const Color(0xFFFFFF00),
      );
      final json = original.toJson();
      expect(json['fillColor'], isNotNull);
      expect(json['strokeColor'], isNotNull);

      final restored = RectangleObject.fromJson(json);
      expect(restored.fillColor, const Color(0xFF0000FF));
      expect(restored.strokeColor, const Color(0xFFFFFF00));
    });

    test('CircleObject supports fill and stroke colors', () {
      final circle = CircleObject(
        id: 'color-3',
        rect: Rect.fromLTWH(0, 0, 100, 100),
        fillColor: const Color(0xFFFF00FF),
      );
      expect(circle.fillColor, const Color(0xFFFF00FF));
      expect(circle.strokeColor, isNull);
    });

    test('DiamondObject supports fill and stroke colors', () {
      final diamond = DiamondObject(
        id: 'color-4',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        fillColor: const Color(0xFF00FFFF),
        strokeColor: const Color(0xFFFF8800),
      );
      expect(diamond.fillColor, const Color(0xFF00FFFF));
      expect(diamond.strokeColor, const Color(0xFFFF8800));

      final json = diamond.toJson();
      final restored = DiamondObject.fromJson(json);
      expect(restored.fillColor, const Color(0xFF00FFFF));
      expect(restored.strokeColor, const Color(0xFFFF8800));
    });

    test('null colors are omitted from JSON', () {
      final rect = RectangleObject(
        id: 'color-5',
        rect: Rect.fromLTWH(0, 0, 100, 80),
      );
      final json = rect.toJson();
      expect(json.containsKey('fillColor'), false);
      expect(json.containsKey('strokeColor'), false);
    });

    test('copyWith can update colors', () {
      final rect = RectangleObject(
        id: 'color-6',
        rect: Rect.fromLTWH(0, 0, 100, 80),
      );
      final copy = rect.copyWith(
        fillColor: const Color(0xFFABCDEF),
      );
      expect((copy as RectangleObject).fillColor, const Color(0xFFABCDEF));
    });
  });
}
