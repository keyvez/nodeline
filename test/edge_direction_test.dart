import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/blocs/selection/selection_bloc.dart';
import 'package:nodeline/src/core/agent/tool_call.dart';
import 'package:nodeline/src/core/agent/tool_dispatcher.dart';
import 'package:nodeline/src/core/utils/svg_exporter.dart';
import 'package:nodeline/src/models/drawing_entities.dart';

/// Directed ↔ undirected edges: ArrowObject.arrowHead, the bloc event, the
/// agent tool, and SVG export.

Future<void> _pump() => Future<void>.delayed(Duration.zero);

ArrowObject _arrow(String id, {ArrowHeadType head = ArrowHeadType.triangle}) =>
    ArrowObject(
      id: id,
      start: Offset.zero,
      end: const Offset(100, 0),
      arrowHead: head,
    );

void main() {
  test('arrowHead defaults to triangle and round-trips through JSON', () {
    expect(_arrow('a').arrowHead, ArrowHeadType.triangle);
    final undirected = _arrow('a', head: ArrowHeadType.none);
    final restored = ArrowObject.fromJson(undirected.toJson());
    expect(restored.arrowHead, ArrowHeadType.none);
    // Default triangle isn't serialized (kept compact) but restores correctly.
    expect(ArrowObject.fromJson(_arrow('a').toJson()).arrowHead,
        ArrowHeadType.triangle);
  });

  test('copyWith updates arrowHead and preserves it otherwise', () {
    final a = _arrow('a');
    expect((a.copyWith(arrowHead: ArrowHeadType.none) as ArrowObject).arrowHead,
        ArrowHeadType.none);
    // A copyWith that doesn't mention arrowHead keeps it.
    final colored = a.copyWith(strokeColor: const Color(0xFFFF0000)) as ArrowObject;
    expect(colored.arrowHead, ArrowHeadType.triangle);
  });

  test('ObjectsArrowHeadChanged makes an edge undirected (undoable)', () async {
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    bloc.add(DrawingObjectAdded(_arrow('a1')));
    await _pump();

    bloc.add(const ObjectsArrowHeadChanged({'a1'}, ArrowHeadType.none));
    await _pump();
    expect((bloc.state.drawingObjects['a1'] as ArrowObject).arrowHead,
        ArrowHeadType.none);

    bloc.add(UndoRequested());
    await _pump();
    expect((bloc.state.drawingObjects['a1'] as ArrowObject).arrowHead,
        ArrowHeadType.triangle);
  });

  test('set_edge_direction tool toggles directedness', () async {
    final canvas = CanvasBloc();
    final selection = SelectionBloc();
    addTearDown(canvas.close);
    addTearDown(selection.close);
    final d = ToolDispatcher(canvasBloc: canvas, selectionBloc: selection);

    canvas.add(DrawingObjectAdded(_arrow('a1')));
    await _pump();

    d.dispatch(ToolCall(name: 'set_edge_direction', args: {
      'ids': ['a1'],
      'directed': false,
    }));
    await _pump();
    expect((canvas.state.drawingObjects['a1'] as ArrowObject).arrowHead,
        ArrowHeadType.none);

    d.dispatch(ToolCall(name: 'set_edge_direction', args: {
      'ids': ['a1'],
      'directed': true,
    }));
    await _pump();
    expect((canvas.state.drawingObjects['a1'] as ArrowObject).arrowHead,
        ArrowHeadType.triangle);
  });

  test('SVG export omits the arrowhead for an undirected edge', () {
    final directed = SvgExporter.export({'a': _arrow('a')});
    final undirected =
        SvgExporter.export({'a': _arrow('a', head: ArrowHeadType.none)});
    // Directed edges emit a <polygon> arrowhead; undirected ones don't.
    expect(directed.contains('<polygon'), true);
    expect(undirected.contains('<polygon'), false);
  });
}
