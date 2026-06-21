import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/blocs/selection/selection_bloc.dart';
import 'package:flow_draw/src/core/agent/tool_call.dart';
import 'package:flow_draw/src/core/agent/tool_dispatcher.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';

/// Step 2: the tool dispatch layer. Each tool is exercised against real BLoCs,
/// asserting on the resulting canvas/selection state — no LLM involved.

/// Lets the BLoC event loop drain after adding events.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late CanvasBloc canvas;
  late SelectionBloc selection;
  late ToolDispatcher d;

  setUp(() {
    canvas = CanvasBloc();
    selection = SelectionBloc();
    d = ToolDispatcher(canvasBloc: canvas, selectionBloc: selection);
  });

  tearDown(() {
    canvas.close();
    selection.close();
  });

  RectangleObject rect(String id, {String? text, Rect? r}) => RectangleObject(
        id: id,
        rect: r ?? const Rect.fromLTWH(0, 0, 100, 80),
        text: text,
      );

  group('create_nodes', () {
    test('creates nodes of the requested shapes', () async {
      final res = d.dispatch(ToolCall(name: 'create_nodes', args: {
        'nodes': [
          {'label': 'Start', 'shape': 'circle'},
          {'label': 'Decide', 'shape': 'diamond'},
          {'label': 'Box'},
        ],
      }));
      await _pump();
      expect(res.ok, true);
      final objs = canvas.state.drawingObjects.values.toList();
      expect(objs.whereType<CircleObject>(), hasLength(1));
      expect(objs.whereType<DiamondObject>(), hasLength(1));
      expect(objs.whereType<RectangleObject>(), hasLength(1));
      // Returns a label->id map for follow-up edge creation.
      expect((res.data!['labelToId'] as Map).keys, containsAll(['Start', 'Decide', 'Box']));
    });

    test('applies fill color when provided as hex', () async {
      d.dispatch(ToolCall(name: 'create_nodes', args: {
        'nodes': [
          {'label': 'Red', 'fill': '#C1272D'},
        ],
      }));
      await _pump();
      final node = canvas.state.drawingObjects.values.whereType<RectangleObject>().first;
      expect(node.fillColor, const Color(0xFFC1272D));
    });
  });

  group('create_edges', () {
    test('connects nodes referenced by label, attaching to both ends', () async {
      d.dispatch(ToolCall(name: 'create_nodes', args: {
        'nodes': [
          {'label': 'A'},
          {'label': 'B'},
        ],
      }));
      await _pump();

      final res = d.dispatch(ToolCall(name: 'create_edges', args: {
        'edges': [
          {'from': 'A', 'to': 'B', 'label': 'go', 'style': 'dashed'},
        ],
      }));
      await _pump();
      expect(res.ok, true);
      final arrows = canvas.state.drawingObjects.values.whereType<ArrowObject>().toList();
      expect(arrows, hasLength(1));
      expect(arrows.first.startAttachment, isNotNull);
      expect(arrows.first.endAttachment, isNotNull);
      expect(arrows.first.arrowLabel, 'go');
      expect(arrows.first.lineStyle, LineStyle.dashed);
    });

    test('reports unresolved endpoints rather than crashing', () async {
      final res = d.dispatch(ToolCall(name: 'create_edges', args: {
        'edges': [
          {'from': 'Ghost', 'to': 'Phantom'},
        ],
      }));
      await _pump();
      expect(res.ok, false);
      expect(res.summary, anyOf(contains('unresolved'), contains('resolve')));
    });
  });

  group('select', () {
    test('selects by kind and pushes to the selection bloc', () async {
      canvas
        ..add(DrawingObjectAdded(rect('r1')))
        ..add(DrawingObjectAdded(ArrowObject(
            id: 'a1', start: Offset.zero, end: const Offset(50, 50))));
      await _pump();

      final res = d.dispatch(ToolCall(name: 'select', args: {'kind': 'edge'}));
      await _pump();
      expect(res.ok, true);
      expect(selection.state.selectedDrawingObjectIds, {'a1'});
    });

    test('selects nodes in a named frame', () async {
      canvas
        ..add(DrawingObjectAdded(FigureObject(
          id: 'f1',
          rect: const Rect.fromLTWH(0, 0, 1000, 1000),
          label: 'Emotions',
          childrenIds: const {'joy'},
        )))
        ..add(DrawingObjectAdded(
            rect('joy', text: 'Joy', r: const Rect.fromLTWH(10, 10, 50, 50))));
      await _pump();

      d.dispatch(ToolCall(name: 'select', args: {
        'frame': 'Emotions',
        'kind': 'node',
        'spatialFallback': false,
      }));
      await _pump();
      expect(selection.state.selectedDrawingObjectIds, {'joy'});
    });
  });

  group('color_objects + set_line_style operate on the current selection', () {
    test('color_objects with no ids uses the selection', () async {
      canvas.add(DrawingObjectAdded(rect('r1')));
      await _pump();
      selection.add(const SelectionReplaced(drawingObjectIds: {'r1'}));
      await _pump();

      final res = d.dispatch(ToolCall(name: 'color_objects', args: {'fill': '#00FF00'}));
      await _pump();
      expect(res.ok, true);
      expect((canvas.state.drawingObjects['r1'] as RectangleObject).fillColor,
          const Color(0xFF00FF00));
    });

    test('set_line_style turns selected edges dashed', () async {
      canvas.add(DrawingObjectAdded(ArrowObject(
          id: 'a1', start: Offset.zero, end: const Offset(50, 50))));
      await _pump();
      selection.add(const SelectionReplaced(drawingObjectIds: {'a1'}));
      await _pump();

      d.dispatch(ToolCall(name: 'set_line_style', args: {'style': 'dashed'}));
      await _pump();
      expect((canvas.state.drawingObjects['a1'] as ArrowObject).lineStyle,
          LineStyle.dashed);
    });

    test('set_line_style rejects an unknown style', () async {
      final res = d.dispatch(
          ToolCall(name: 'set_line_style', args: {'ids': ['x'], 'style': 'zigzag'}));
      expect(res.ok, false);
      expect(res.summary, contains('Unknown line style'));
    });
  });

  group('delete_objects', () {
    test('removes objects by id', () async {
      canvas.add(DrawingObjectAdded(rect('r1')));
      await _pump();
      d.dispatch(ToolCall(name: 'delete_objects', args: {'ids': ['r1']}));
      await _pump();
      expect(canvas.state.drawingObjects.containsKey('r1'), false);
    });
  });

  group('read tools', () {
    test('get_selection returns ids, types and labels', () async {
      canvas.add(DrawingObjectAdded(rect('r1', text: 'Hello')));
      await _pump();
      selection.add(const SelectionReplaced(drawingObjectIds: {'r1'}));
      await _pump();

      final res = d.dispatch(ToolCall(name: 'get_selection'));
      final sel = res.data!['selection'] as List;
      expect(sel, hasLength(1));
      expect((sel.first as Map)['label'], 'Hello');
      expect((sel.first as Map)['type'], 'rectangle');
    });

    test('get_canvas_summary counts objects by type', () async {
      canvas
        ..add(DrawingObjectAdded(rect('r1')))
        ..add(DrawingObjectAdded(rect('r2')))
        ..add(DrawingObjectAdded(ArrowObject(
            id: 'a1', start: Offset.zero, end: const Offset(10, 10))));
      await _pump();
      final res = d.dispatch(ToolCall(name: 'get_canvas_summary'));
      final counts = res.data!['counts'] as Map;
      expect(counts['rectangle'], 2);
      expect(counts['arrow'], 1);
    });
  });

  group('robustness', () {
    test('unknown tool returns an error result, not a throw', () {
      final res = d.dispatch(ToolCall(name: 'frobnicate'));
      expect(res.ok, false);
      expect(res.summary, contains('Unknown tool'));
    });

    test('color_objects with no target and empty selection errors cleanly', () {
      final res = d.dispatch(ToolCall(name: 'color_objects', args: {'fill': '#fff'}));
      expect(res.ok, false);
    });
  });
}
