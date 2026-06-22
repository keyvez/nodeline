import 'dart:ui';
import 'package:flutter/material.dart'
    show
        TextStyle,
        TextSpan,
        TextSelection,
        TextEditingValue,
        FontWeight;
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/flow_draw.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/core/utils/svg_exporter.dart';
import 'package:flow_draw/src/ui/canvas/rich_text_editing_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('copyWith(clearFill) removes the fill (null != "keep")', () {
      final rect = RectangleObject(
        id: 'rect-6',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        fillColor: const Color(0xFFAABBCC),
      );
      // Plain copyWith without fillColor keeps it...
      expect((rect.copyWith() as RectangleObject).fillColor,
          const Color(0xFFAABBCC));
      // ...clearFill removes it.
      expect((rect.copyWith(clearFill: true) as RectangleObject).fillColor,
          isNull);
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

    test('handles graph LR, subgraphs, unquoted labels, dotted edges', () {
      const mermaid = '''
graph LR
    subgraph "Emotion"
        Bored[Bored / Restless]
        Sad[Sadness / Pain]
    end
    subgraph "Food"
        FoodBored[Crunchy snacks]
        FoodSad[Happy foods]
    end
    subgraph "Solution"
        SolBored[A fulfilling activity]
        SolSad[Talk with a friend]
    end
    Bored -->|May seek| FoodBored
    Bored -.->|Instead try| SolBored
    Sad -->|May seek| FoodSad
    Sad -.->|Instead try| SolSad
''';
      final result = MermaidImporter.import(mermaid);
      final objects = (result['drawingObjects'] as List).cast<Map>();
      final texts = objects.map((o) => o['text']).whereType<String>().toList();

      // Unquoted labels are preserved (not collapsed to node IDs).
      expect(texts, contains('Bored / Restless'));
      expect(texts, contains('Crunchy snacks'));
      expect(texts.contains('Bored'), isFalse);

      // Subgraph titles become container boxes.
      expect(texts, containsAll(<String>['Emotion', 'Food', 'Solution']));

      // All four edges parse, including the two dotted ones.
      final arrows = objects.where((o) => o['type'] == 'arrow').toList();
      expect(arrows.length, 4);
      expect(arrows.where((a) => a['lineStyle'] == 'dashed').length, 2);

      // Subgraph container boxes do not overlap one another.
      Rect rectOf(Map o) {
        final r = (o['rect'] as Map);
        return Rect.fromLTWH((r['left'] as num).toDouble(),
            (r['top'] as num).toDouble(),
            (r['width'] as num).toDouble(),
            (r['height'] as num).toDouble());
      }
      final boxes = objects
          .where((o) => o['type'] == 'rectangle' && o['lineStyle'] == 'dashed')
          .map(rectOf)
          .toList();
      expect(boxes.length, 3);
      for (int i = 0; i < boxes.length; i++) {
        for (int j = i + 1; j < boxes.length; j++) {
          expect(boxes[i].deflate(1).overlaps(boxes[j].deflate(1)), isFalse);
        }
      }
    });

    test('lays subgraph clusters out as ordered flow columns in LR', () {
      const mermaid = '''
graph LR
    subgraph "Emotion"
        Bored[Bored]
        Sad[Sadness]
    end
    subgraph "Food"
        FoodBored[Snacks]
        FoodSad[Comfort]
    end
    subgraph "Solution"
        SolBored[Hobby]
        SolSad[Journal]
    end
    Bored --> FoodBored
    Bored -.-> SolBored
    Sad --> FoodSad
    Sad -.-> SolSad
''';
      final result = MermaidImporter.import(mermaid);
      final objects = (result['drawingObjects'] as List).cast<Map>();

      // The three subgraph containers form left-to-right columns in the
      // order they're chained by edges: Emotion < Food < Solution.
      double leftOf(String title) {
        final box = objects.firstWhere((o) =>
            o['type'] == 'rectangle' &&
            o['lineStyle'] == 'dashed' &&
            o['text'] == title);
        return ((box['rect'] as Map)['left'] as num).toDouble();
      }
      final emo = leftOf('Emotion');
      final food = leftOf('Food');
      final sol = leftOf('Solution');
      expect(emo, lessThan(food));
      expect(food, lessThan(sol));

      // Edges flow forward into the food column: the food node is entered from
      // its left side (relativePosition.dx == 0.0), i.e. the arrow comes from
      // the emotion column on its left rather than wrapping around.
      Map nodeByText(String t) =>
          objects.firstWhere((o) => o['text'] == t);
      final boredId = nodeByText('Bored')['id'];
      final foodId = nodeByText('Snacks')['id'];
      final seek = objects.firstWhere((o) =>
          o['type'] == 'arrow' &&
          (o['startAttachment'] as Map?)?['objectId'] == boredId &&
          (o['endAttachment'] as Map?)?['objectId'] == foodId);
      final eRel = (seek['endAttachment'] as Map)['relativePosition'] as List;
      expect(eRel[0], 0.0); // enters left side of target

      // And the food node sits to the right of its emotion source, so the edge
      // genuinely runs left-to-right.
      Rect rOf(Map o) {
        final r = o['rect'] as Map;
        return Rect.fromLTWH((r['left'] as num).toDouble(),
            (r['top'] as num).toDouble(),
            (r['width'] as num).toDouble(),
            (r['height'] as num).toDouble());
      }
      expect(rOf(nodeByText('Snacks')).left,
          greaterThan(rOf(nodeByText('Bored')).right));
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

    test('ParallelogramObject supports fill and stroke colors', () {
      final para = ParallelogramObject(
        id: 'color-p1',
        rect: Rect.fromLTWH(0, 0, 120, 80),
        fillColor: const Color(0xFF112233),
        strokeColor: const Color(0xFF445566),
      );
      expect(para.fillColor, const Color(0xFF112233));
      expect(para.strokeColor, const Color(0xFF445566));

      final json = para.toJson();
      final restored = ParallelogramObject.fromJson(json);
      expect(restored.fillColor, const Color(0xFF112233));
      expect(restored.strokeColor, const Color(0xFF445566));
    });

    test('ForkJoinObject supports fill and stroke colors', () {
      final fj = ForkJoinObject(
        id: 'color-fj1',
        rect: Rect.fromLTWH(0, 0, 200, 10),
        fillColor: const Color(0xFFAABBCC),
        strokeColor: const Color(0xFFDDEEFF),
      );
      expect(fj.fillColor, const Color(0xFFAABBCC));

      final json = fj.toJson();
      final restored = ForkJoinObject.fromJson(json);
      expect(restored.fillColor, const Color(0xFFAABBCC));
      expect(restored.strokeColor, const Color(0xFFDDEEFF));
    });
  });

  group('EditorTool', () {
    test('parallelogram and forkJoin tools exist', () {
      expect(EditorTool.parallelogram, isNotNull);
      expect(EditorTool.forkJoin, isNotNull);
    });

    test('workflowTools contains new shape tools', () {
      expect(workflowTools.contains(EditorTool.parallelogram), true);
      expect(workflowTools.contains(EditorTool.forkJoin), true);
    });
  });

  group('SVG export colors', () {
    test('SVG exporter uses per-object fill/stroke colors', () {
      final objects = <String, DrawingObject>{
        'r1': RectangleObject(
          id: 'r1',
          rect: Rect.fromLTWH(0, 0, 100, 80),
          fillColor: const Color(0xFFFF0000),
          strokeColor: const Color(0xFF00FF00),
          text: 'Red Box',
        ),
      };
      // Just verify it doesn't crash and produces SVG
      final svg = SvgExporter.export(objects);
      expect(svg, contains('<svg'));
      expect(svg, contains('Red Box'));
      expect(svg, contains('#ff0000'));
      expect(svg, contains('#00ff00'));
    });
  });

  group('Font customization', () {
    test('fontCustomized defaults to false and round-trips', () {
      final original = RectangleObject(
        id: 'f1',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        text: 'Hi',
      );
      expect(original.fontCustomized, isFalse);
      // Not customized → flag omitted from JSON.
      expect(original.toJson().containsKey('fontCustomized'), isFalse);

      final customized = RectangleObject(
        id: 'f2',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        text: 'Hi',
        textStyle: const TextStyle(fontFamily: 'serif', fontSize: 24),
        fontCustomized: true,
      );
      final restored = RectangleObject.fromJson(customized.toJson());
      expect(restored.fontCustomized, isTrue);
      expect(restored.textStyle?.fontFamily, 'serif');
      expect(restored.textStyle?.fontSize, 24);
    });

    test('effectiveShapeTextStyle uses global default when not customized', () {
      final resolved = effectiveShapeTextStyle(
        style: const TextStyle(fontFamily: 'serif', fontSize: 99),
        customized: false,
        defaultFamily: 'monospace',
        defaultSize: 20,
      );
      // Non-customized: family/size come from the global default, ignoring the
      // stale per-shape style.
      expect(resolved.fontFamily, 'monospace');
      expect(resolved.fontSize, 20);
    });

    test('effectiveShapeTextStyle uses own style when customized', () {
      final resolved = effectiveShapeTextStyle(
        style: const TextStyle(fontFamily: 'serif', fontSize: 30),
        customized: true,
        defaultFamily: 'monospace',
        defaultSize: 20,
      );
      expect(resolved.fontFamily, 'serif');
      expect(resolved.fontSize, 30);
    });

    test('GlobalFontChanged updates defaults without touching customized shapes',
        () async {
      final bloc = CanvasBloc();
      final plain = RectangleObject(
        id: 'plain',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        text: 'A',
      );
      final fancy = RectangleObject(
        id: 'fancy',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        text: 'B',
        textStyle: const TextStyle(fontFamily: 'serif', fontSize: 40),
        fontCustomized: true,
      );
      bloc.emit(bloc.state.copyWith(
        drawingObjects: {'plain': plain, 'fancy': fancy},
      ));

      bloc.add(const GlobalFontChanged(fontFamily: 'monospace', fontSize: 22));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.defaultFontFamily, 'monospace');
      expect(bloc.state.defaultFontSize, 22);

      // The customized shape is untouched.
      final fancyAfter = bloc.state.drawingObjects['fancy'] as RectangleObject;
      expect(fancyAfter.fontCustomized, isTrue);
      expect(fancyAfter.textStyle?.fontFamily, 'serif');

      // The plain shape resolves to the new global default.
      final plainAfter = bloc.state.drawingObjects['plain'] as RectangleObject;
      final plainStyle = effectiveShapeTextStyle(
        style: plainAfter.textStyle,
        customized: plainAfter.fontCustomized,
        defaultFamily: bloc.state.defaultFontFamily,
        defaultSize: bloc.state.defaultFontSize,
      );
      expect(plainStyle.fontFamily, 'monospace');
      expect(plainStyle.fontSize, 22);
      await bloc.close();
    });

    test('ObjectFontChanged marks shape customized; ObjectFontReset clears it',
        () async {
      final bloc = CanvasBloc();
      final r = RectangleObject(
        id: 'r',
        rect: Rect.fromLTWH(0, 0, 100, 80),
        text: 'A',
      );
      bloc.emit(bloc.state.copyWith(drawingObjects: {'r': r}));

      bloc.add(const ObjectFontChanged({'r'}, fontFamily: 'serif', fontSize: 33));
      await Future<void>.delayed(Duration.zero);

      var after = bloc.state.drawingObjects['r'] as RectangleObject;
      expect(after.fontCustomized, isTrue);
      expect(after.textStyle?.fontFamily, 'serif');
      expect(after.textStyle?.fontSize, 33);

      bloc.add(const ObjectFontReset({'r'}));
      await Future<void>.delayed(Duration.zero);

      after = bloc.state.drawingObjects['r'] as RectangleObject;
      expect(after.fontCustomized, isFalse);
      await bloc.close();
    });

    test('ObjectFontChanged affects only the targeted shape, not others',
        () async {
      final bloc = CanvasBloc();
      final a = RectangleObject(
        id: 'a',
        rect: const Rect.fromLTWH(0, 0, 100, 80),
        text: 'A',
      );
      final b = RectangleObject(
        id: 'b',
        rect: const Rect.fromLTWH(0, 0, 100, 80),
        text: 'B',
      );
      bloc.emit(bloc.state.copyWith(drawingObjects: {'a': a, 'b': b}));

      // Change only 'a'.
      bloc.add(const ObjectFontChanged({'a'}, fontFamily: 'serif', fontSize: 40));
      await Future<void>.delayed(Duration.zero);

      final aAfter = bloc.state.drawingObjects['a'] as RectangleObject;
      final bAfter = bloc.state.drawingObjects['b'] as RectangleObject;
      expect(aAfter.fontCustomized, isTrue);
      expect(aAfter.textStyle?.fontFamily, 'serif');
      // 'b' is untouched: not customized, no per-shape style.
      expect(bAfter.fontCustomized, isFalse);
      expect(bAfter.textStyle, isNull);
      await bloc.close();
    });

    test('SVG export honors per-shape and global fonts', () {
      final objects = <String, DrawingObject>{
        'plain': RectangleObject(
          id: 'plain',
          rect: Rect.fromLTWH(0, 0, 100, 80),
          text: 'Plain',
        ),
        'fancy': RectangleObject(
          id: 'fancy',
          rect: Rect.fromLTWH(200, 0, 100, 80),
          text: 'Fancy',
          textStyle: const TextStyle(fontFamily: 'serif', fontSize: 28),
          fontCustomized: true,
        ),
      };
      final svg = SvgExporter.export(
        objects,
        defaultFontFamily: 'monospace',
        defaultFontSize: 18,
      );
      // Global default applied to the plain shape.
      expect(svg, contains('font-size="18.0"'));
      expect(svg, contains('font-family="monospace"'));
      // Per-shape override applied to the fancy shape.
      expect(svg, contains('font-size="28.0"'));
      expect(svg, contains('font-family="serif"'));
    });
  });

  group('Fit to content', () {
    test('shrinks an oversized box and keeps it centered', () async {
      final bloc = CanvasBloc();
      final huge = RectangleObject(
        id: 'r',
        rect: const Rect.fromLTWH(0, 0, 600, 400),
        text: 'Hi',
      );
      final center = huge.rect.center;
      bloc.emit(bloc.state.copyWith(drawingObjects: {'r': huge}));

      bloc.add(const NodesFittedToContent({}));
      await Future<void>.delayed(Duration.zero);

      final after = bloc.state.drawingObjects['r'] as RectangleObject;
      expect(after.rect.width, lessThan(600));
      expect(after.rect.height, lessThan(400));
      // Center preserved.
      expect(after.rect.center.dx, closeTo(center.dx, 0.01));
      expect(after.rect.center.dy, closeTo(center.dy, 0.01));
      await bloc.close();
    });

    test('grows a too-tight box to fit long text', () async {
      final bloc = CanvasBloc();
      final tight = RectangleObject(
        id: 'r',
        rect: const Rect.fromLTWH(0, 0, 20, 20),
        text: 'A reasonably long label that does not fit',
      );
      bloc.emit(bloc.state.copyWith(drawingObjects: {'r': tight}));

      bloc.add(const NodesFittedToContent({}));
      await Future<void>.delayed(Duration.zero);

      final after = bloc.state.drawingObjects['r'] as RectangleObject;
      expect(after.rect.width, greaterThan(20));
      await bloc.close();
    });

    test('empty selection fits all; non-empty fits only those', () async {
      final bloc = CanvasBloc();
      final a = RectangleObject(
        id: 'a',
        rect: const Rect.fromLTWH(0, 0, 500, 300),
        text: 'A',
      );
      final b = RectangleObject(
        id: 'b',
        rect: const Rect.fromLTWH(0, 0, 500, 300),
        text: 'B',
      );
      bloc.emit(bloc.state.copyWith(drawingObjects: {'a': a, 'b': b}));

      // Fit only 'a'.
      bloc.add(const NodesFittedToContent({'a'}));
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state.drawingObjects['a'] as RectangleObject).rect.width,
          lessThan(500));
      expect((bloc.state.drawingObjects['b'] as RectangleObject).rect.width,
          500);

      // Now fit all (empty set).
      bloc.add(const NodesFittedToContent({}));
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state.drawingObjects['b'] as RectangleObject).rect.width,
          lessThan(500));
      await bloc.close();
    });

    test('is a single undoable step', () async {
      final bloc = CanvasBloc();
      final r = RectangleObject(
        id: 'r',
        rect: const Rect.fromLTWH(0, 0, 500, 300),
        text: 'Hi',
      );
      bloc.emit(bloc.state.copyWith(drawingObjects: {'r': r}));

      bloc.add(const NodesFittedToContent({}));
      await Future<void>.delayed(Duration.zero);
      final fitted = bloc.state.drawingObjects['r'] as RectangleObject;
      expect(fitted.rect.width, lessThan(500));

      bloc.add(UndoRequested());
      await Future<void>.delayed(Duration.zero);
      final restored = bloc.state.drawingObjects['r'] as RectangleObject;
      expect(restored.rect.width, 500);
      expect(restored.rect.height, 300);
      await bloc.close();
    });

    test('shapes without text are left unchanged', () async {
      final bloc = CanvasBloc();
      final blank = RectangleObject(
        id: 'r',
        rect: const Rect.fromLTWH(0, 0, 500, 300),
      );
      bloc.emit(bloc.state.copyWith(drawingObjects: {'r': blank}));

      bloc.add(const NodesFittedToContent({}));
      await Future<void>.delayed(Duration.zero);

      final after = bloc.state.drawingObjects['r'] as RectangleObject;
      expect(after.rect.width, 500);
      expect(after.rect.height, 300);
      await bloc.close();
    });

    test('a larger margin produces a larger fitted box', () async {
      RectangleObject make() => RectangleObject(
            id: 'r',
            rect: const Rect.fromLTWH(0, 0, 20, 20),
            text: 'Label',
          );

      final small = CanvasBloc();
      small.emit(small.state.copyWith(drawingObjects: {'r': make()}));
      small.add(const NodesFittedToContent({}, margin: 0));
      await Future<void>.delayed(Duration.zero);
      final tight = (small.state.drawingObjects['r'] as RectangleObject).rect;

      final big = CanvasBloc();
      big.emit(big.state.copyWith(drawingObjects: {'r': make()}));
      big.add(const NodesFittedToContent({}, margin: 40));
      await Future<void>.delayed(Duration.zero);
      final loose = (big.state.drawingObjects['r'] as RectangleObject).rect;

      // margin=40 per side adds 80 to each dimension vs margin=0.
      expect(loose.width, closeTo(tight.width + 80, 0.01));
      expect(loose.height, closeTo(tight.height + 80, 0.01));
      await small.close();
      await big.close();
    });
  });

  group('Rich text (multiple styles per node)', () {
    test('TextRun JSON round-trips all attributes', () {
      const run = TextRun('Hi',
          fontFamily: 'serif',
          fontSize: 24,
          bold: true,
          italic: true,
          color: 0xFFFF0000);
      final restored = TextRun.fromJson(run.toJson());
      expect(restored, run);
    });

    test('a run with no overrides serializes lean', () {
      const run = TextRun('plain');
      expect(run.toJson().keys, ['text']);
      expect(run.hasOverrides, isFalse);
    });

    test('RectangleObject richText round-trips through JSON', () {
      final rect = RectangleObject(
        id: 'r1',
        rect: const Rect.fromLTWH(0, 0, 100, 40),
        text: 'AB',
        richText: const [
          TextRun('A', bold: true),
          TextRun('B', fontSize: 30, color: 0xFF00FF00),
        ],
      );
      final restored = RectangleObject.fromJson(rect.toJson());
      expect(restored.text, 'AB');
      expect(restored.richText, isNotNull);
      expect(restored.richText!.length, 2);
      expect(restored.richText![0].bold, isTrue);
      expect(restored.richText![1].fontSize, 30);
      expect(restored.richText![1].color, 0xFF00FF00);
    });

    test('normalizeRuns coalesces adjacent equal styles', () {
      final runs = normalizeRuns(const [
        TextRun('a', bold: true),
        TextRun('b', bold: true),
        TextRun('c'),
      ]);
      expect(runs.length, 2);
      expect(runs[0].text, 'ab');
      expect(runs[1].text, 'c');
    });

    test('buildShapeTextSpan: single inherited run returns a plain span', () {
      const base = TextStyle(fontSize: 16);
      final span = buildShapeTextSpan(
        text: 'hello',
        runs: const [TextRun('hello')],
        base: base,
      );
      expect(span.children, isNull);
      expect(span.text, 'hello');
    });

    test('buildShapeTextSpan: mixed runs produce styled children', () {
      const base = TextStyle(fontSize: 16, fontFamily: 'Courier');
      final span = buildShapeTextSpan(
        text: 'AB',
        runs: const [TextRun('A', bold: true), TextRun('B', fontSize: 30)],
        base: base,
      );
      expect(span.children, hasLength(2));
      final a = span.children![0] as TextSpan;
      final b = span.children![1] as TextSpan;
      expect(a.style!.fontWeight, FontWeight.bold);
      expect(b.style!.fontSize, 30);
      // Unspecified attributes inherit the base.
      expect(b.style!.fontFamily, 'Courier');
    });

    test('controller applies bold to a selection and exports runs', () {
      final c = RichTextEditingController(
        base: const TextStyle(fontSize: 16),
        runs: const [TextRun('hello world')],
      );
      // Select "hello".
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.applyToSelection(bold: const Attr.set(true));
      final runs = c.toRuns();
      expect(runs.first.text, 'hello');
      expect(runs.first.bold, isTrue);
      expect(runs.last.text, ' world');
      expect(runs.last.bold, isNull);
      c.dispose();
    });

    test('controller keeps runs aligned when text is inserted', () {
      final c = RichTextEditingController(
        base: const TextStyle(fontSize: 16),
        runs: const [TextRun('AB', bold: true)],
      );
      // Type "X" between A and B; it should inherit the left char's bold.
      c.value = const TextEditingValue(
        text: 'AXB',
        selection: TextSelection.collapsed(offset: 2),
      );
      final runs = c.toRuns();
      expect(runs.length, 1);
      expect(runs.first.text, 'AXB');
      expect(runs.first.bold, isTrue);
      c.dispose();
    });

    test('toolbar action still targets selection after focus collapses it', () {
      // Repro: user selects "hello", then clicks the font button — the editor
      // TextField loses focus and Flutter collapses the live selection. The
      // remembered ranged selection must still receive the style.
      final c = RichTextEditingController(
        base: const TextStyle(fontSize: 16),
        runs: const [TextRun('hello world')],
      );
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      // Simulate focus moving to the toolbar: selection collapses to a caret.
      c.selection = const TextSelection.collapsed(offset: 5);
      // Toolbar applies bold — should hit the remembered "hello" range.
      c.applyToSelection(bold: const Attr.set(true));
      final runs = c.toRuns();
      expect(runs.first.text, 'hello');
      expect(runs.first.bold, isTrue);
      expect(runs.last.text, ' world');
      expect(runs.last.bold, isNull);
      // The selection is re-asserted so the highlight persists.
      expect(c.selection.start, 0);
      expect(c.selection.end, 5);
      c.dispose();
    });

    test('selectionStyle reports mixed attributes as null', () {
      final c = RichTextEditingController(
        base: const TextStyle(fontSize: 16),
        runs: const [TextRun('A', bold: true), TextRun('B')],
      );
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
      expect(c.selectionStyle().bold, isNull); // mixed bold/non-bold
      c.dispose();
    });

    test('SVG export emits tspans for rich runs', () {
      final rect = RectangleObject(
        id: 'r1',
        rect: const Rect.fromLTWH(0, 0, 120, 40),
        text: 'AB',
        richText: const [
          TextRun('A', bold: true),
          TextRun('B', color: 0xFFFF0000),
        ],
      );
      final svg = SvgExporter.export({'r1': rect});
      expect(svg, contains('<tspan'));
      expect(svg, contains('font-weight="bold"'));
      expect(svg, contains('fill="#ff0000"'));
    });
  });
}
