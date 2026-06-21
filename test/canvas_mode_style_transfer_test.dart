import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/blocs/selection/selection_bloc.dart';
import 'package:flow_draw/src/core/agent/tool_call.dart';
import 'package:flow_draw/src/core/agent/tool_dispatcher.dart';
import 'package:flow_draw/src/core/utils/guide_geometry.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Step 7: drawing-as-input (read_drawing) and style transfer
/// (apply_style_template), plus the shared GuideGeometry extraction.

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('GuideGeometry.polylineOf', () {
    test('pencil stroke returns its points, open', () {
      final stroke = PencilStrokeObject(
        id: 'p1',
        points: [
          PointVector(0, 0, 1),
          PointVector(10, 5, 1),
          PointVector(20, 0, 1),
        ],
      );
      final g = GuideGeometry.polylineOf(stroke);
      expect(g, isNotNull);
      expect(g!.$2, false); // open
      expect(g.$1, hasLength(3));
    });

    test('line returns endpoints, open', () {
      final line = LineObject(id: 'l1', start: Offset.zero, end: const Offset(100, 0));
      final g = GuideGeometry.polylineOf(line)!;
      expect(g.$1, [Offset.zero, const Offset(100, 0)]);
      expect(g.$2, false);
    });

    test('circle returns a closed sampled outline', () {
      final circle = CircleObject(id: 'c1', rect: const Rect.fromLTWH(0, 0, 100, 100));
      final g = GuideGeometry.polylineOf(circle)!;
      expect(g.$2, true); // closed
      expect(g.$1, hasLength(GuideGeometry.circleSegments));
    });

    test('arrow uses start/waypoints/end (no renderedPath dependency)', () {
      final arrow = ArrowObject(
        id: 'a1',
        start: Offset.zero,
        end: const Offset(100, 100),
        waypoints: [const Offset(100, 0)],
      );
      final g = GuideGeometry.polylineOf(arrow)!;
      expect(g.$1, [Offset.zero, const Offset(100, 0), const Offset(100, 100)]);
    });

    test('degenerate (zero-length) line is not a guide', () {
      final line = LineObject(id: 'l2', start: Offset.zero, end: Offset.zero);
      expect(GuideGeometry.polylineOf(line), isNull);
    });

    test('isStrongGuide excludes rectangles', () {
      expect(
        GuideGeometry.isStrongGuide(
            CircleObject(id: 'c', rect: const Rect.fromLTWH(0, 0, 10, 10))),
        true,
      );
      expect(
        GuideGeometry.isStrongGuide(
            RectangleObject(id: 'r', rect: const Rect.fromLTWH(0, 0, 10, 10))),
        false,
      );
    });
  });

  group('dispatcher: read_drawing', () {
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

    test('returns polyline, closed flag and bbox', () async {
      canvas.add(DrawingObjectAdded(
          CircleObject(id: 'g', rect: const Rect.fromLTWH(0, 0, 200, 100))));
      await _pump();

      final res = d.dispatch(ToolCall(name: 'read_drawing', args: {'id': 'g'}));
      expect(res.ok, true);
      expect(res.data!['closed'], true);
      expect(res.data!['type'], 'circle');
      expect((res.data!['points'] as List), isNotEmpty);
      final bbox = res.data!['bbox'] as Map;
      expect(bbox['width'], 200);
      expect(bbox['height'], 100);
    });

    test('downsamples long strokes', () async {
      canvas.add(DrawingObjectAdded(PencilStrokeObject(
        id: 'p',
        points: [for (var i = 0; i < 500; i++) PointVector(i.toDouble(), 0, 1)],
      )));
      await _pump();
      final res = d.dispatch(ToolCall(name: 'read_drawing', args: {'id': 'p'}));
      expect((res.data!['points'] as List).length, lessThanOrEqualTo(48));
      expect(res.data!['pointCount'], 500); // original count reported
    });

    test('errors on missing or non-guide objects', () async {
      final res = d.dispatch(ToolCall(name: 'read_drawing', args: {'id': 'ghost'}));
      expect(res.ok, false);
    });
  });

  group('dispatcher: apply_style_template', () {
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

    test('copies fill, stroke and line style from source to targets', () async {
      canvas
        ..add(DrawingObjectAdded(RectangleObject(
          id: 'src',
          rect: const Rect.fromLTWH(0, 0, 50, 50),
          fillColor: const Color(0xFF112233),
          strokeColor: const Color(0xFF445566),
          lineStyle: LineStyle.dashed,
        )))
        ..add(DrawingObjectAdded(
            RectangleObject(id: 't1', rect: const Rect.fromLTWH(60, 0, 50, 50))))
        ..add(DrawingObjectAdded(
            RectangleObject(id: 't2', rect: const Rect.fromLTWH(120, 0, 50, 50))));
      await _pump();

      final res = d.dispatch(ToolCall(name: 'apply_style_template', args: {
        'sourceIds': ['src'],
        'targetIds': ['t1', 't2'],
      }));
      await _pump();
      expect(res.ok, true);

      for (final id in ['t1', 't2']) {
        final t = canvas.state.drawingObjects[id] as RectangleObject;
        expect(t.fillColor, const Color(0xFF112233));
        expect(t.strokeColor, const Color(0xFF445566));
        expect(t.lineStyle, LineStyle.dashed);
      }
    });

    test('targets default to the current selection', () async {
      canvas
        ..add(DrawingObjectAdded(RectangleObject(
          id: 'src',
          rect: const Rect.fromLTWH(0, 0, 50, 50),
          fillColor: const Color(0xFFABCDEF),
        )))
        ..add(DrawingObjectAdded(
            RectangleObject(id: 't', rect: const Rect.fromLTWH(60, 0, 50, 50))));
      await _pump();
      selection.add(const SelectionReplaced(drawingObjectIds: {'t'}));
      await _pump();

      d.dispatch(ToolCall(name: 'apply_style_template', args: {
        'sourceIds': ['src'],
      }));
      await _pump();
      expect((canvas.state.drawingObjects['t'] as RectangleObject).fillColor,
          const Color(0xFFABCDEF));
    });

    test('errors when no sourceIds', () {
      final res = d.dispatch(ToolCall(name: 'apply_style_template', args: {
        'targetIds': ['t'],
      }));
      expect(res.ok, false);
    });
  });
}
